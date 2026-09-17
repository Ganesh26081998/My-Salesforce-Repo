@isTest
public class BillingSyncControllerTest {

    // ================================================================
    // TEST DATA FACTORY
    // ================================================================

    private static Account createTestAccount() {
        Account acc = new Account(
            Name                = 'Test Account',
            City_Prospect__c    = 'Austin',
            Postal_Code__c      = '78701',
            QB_Customer_Id__c   = null
        );
        insert acc;
        return acc;
    }

    private static Billing__c createTestBilling(Id accountId, String location, Boolean isSynced) {
        Billing__c billing = new Billing__c(
            Location_g__c                = 'Detroit',
            Client__c                    = accountId,
            Care_From_Date__c            = Date.today(),
            Care_To_Date__c              = Date.today().addDays(1),
            Invoice_Date__c              = Date.today(),
            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c   = Date.today().addDays(7),
            Paid_Status__c               = 'Paid',
            Amount__c                    = 500.00,
            QB_Sync_Status__c            = 'Pending',
            Is_Synced__c                 = false
        );
        insert billing;

        if (isSynced) {
            billing.Is_Synced__c      = true;
            billing.QB_Sync_Status__c = 'Synced';
            update billing;
        }

        return billing;
    }

    // ★ NEW: Creates a non-Caregiver line item so the invoice service doesn't throw
    private static void createTestLineItem(Id billingId) {
        Billing_Line_Item__c li = new Billing_Line_Item__c(
            Invoice__c      = billingId,
            Description__c  = 'Test Service',
            Quantity__c     = 1,
            Rate__c         = 100.00,
            Amount__c       = 100.00,
            Type__c         = 'Client Billable',   // anything except 'Caregiver Billable'
            Service_Date__c = Date.today().addDays(-1)
        );
        insert li;
    }

    // ================================================================
    // MOCK: QuickBooks HTTP Callout
    // ================================================================

    private class QBMultiCallMock implements HttpCalloutMock {
        private List<HTTPResponse> responses = new List<HTTPResponse>();
        private Integer callIndex = 0;

        public void addResponse(Integer statusCode, String body) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setHeader('Content-Type', 'application/json');
            responses.add(res);
        }

        public HTTPResponse respond(HTTPRequest req) {
            if (callIndex < responses.size()) {
                return responses[callIndex++];
            }
            return responses[responses.size() - 1];
        }
    }

    // ================================================================
    // RESPONSE BODY HELPERS
    // ================================================================

    private static String customerQueryEmptyBody() {
        return '{"QueryResponse":{}}';
    }

    private static String customerCreateBody(String customerId) {
        return '{"Customer":{"Id":"' + customerId + '","SyncToken":"0","DisplayName":"Test Account"}}';
    }

    private static String customerGetBody(String customerId) {
        return '{"Customer":{"Id":"' + customerId + '","SyncToken":"1"}}';
    }

    // Invoice response must include a Line array so processResponse() doesn't fail
    private static String invoiceCreateBody(String invoiceId) {
        return '{"Invoice":{"Id":"' + invoiceId + '","SyncToken":"0","Line":[{"Id":"1","DetailType":"SalesItemLineDetail"}]}}';
    }

    // ================================================================
    // Callout sequence for NEW customer path:
    //   1. queryCustomerByName  → GET  /query
    //   2. createCustomerInQB   → POST /customer
    //   3. createInvoiceInQB    → POST /invoice
    // ================================================================

    // ================================================================
    // TEST 1: Already-synced billing record returns early
    // ================================================================
    @isTest
    static void testAlreadySyncedBilling() {
        Account acc     = createTestAccount();
        Billing__c bill = createTestBilling(acc.Id, 'Detroit', true);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        System.assert(result.contains('Already Synced'), 'Expected Already Synced, got: ' + result);
    }

    // ================================================================
    // TEST 2: Missing location → fails gracefully
    // ================================================================
    @isTest
    static void testMissingLocation() {
        Account acc = createTestAccount();
        Billing__c bill = new Billing__c(
            Client__c                    = acc.Id,
            Care_From_Date__c            = Date.today(),
            Care_To_Date__c              = Date.today().addDays(1),
            Invoice_Date__c              = Date.today(),
            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c   = Date.today().addDays(7),
            Paid_Status__c               = 'Paid',
            Amount__c                    = 500.00,
            QB_Sync_Status__c            = 'Pending',
            Is_Synced__c                 = false
        );
        insert bill;

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        Billing__c updated = [SELECT QB_Sync_Status__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertEquals('Failed', updated.QB_Sync_Status__c);
        System.assert(result.startsWith('Error'), 'Expected error, got: ' + result);
    }

    // ================================================================
    // TEST 3: No QB credential configured for location
    // ================================================================
    @isTest
    static void testNoCredentialForLocation() {
        Account acc     = createTestAccount();
        Billing__c bill = createTestBilling(acc.Id, 'UnknownLocation_XYZ', false);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        Billing__c updated = [SELECT QB_Sync_Status__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertEquals('Failed', updated.QB_Sync_Status__c);
    }

    // ================================================================
    // TEST 4: Happy path — new customer + new invoice
    // Sequence: query(1) → createCustomer(2) → createInvoice(3)
    // ================================================================
    @isTest
    static void testSuccessfulSyncNewCustomerNewInvoice() {
        Account acc     = createTestAccount();
        Billing__c bill = createTestBilling(acc.Id, 'Detroit', false);
        createTestLineItem(bill.Id); // ★ required so invoice service doesn't throw

        QBMultiCallMock mock = new QBMultiCallMock();
        mock.addResponse(200, customerQueryEmptyBody());          // 1. query by name
        mock.addResponse(200, customerCreateBody('QB-CUST-001')); // 2. create customer
        mock.addResponse(200, invoiceCreateBody('QB-INV-001'));   // 3. create invoice

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        System.assert(result.contains('Success'), 'Expected Success, got: ' + result);

        Billing__c updated = [SELECT QB_Sync_Status__c, Is_Synced__c, QB_Invoice_Id__c, Synced_Date__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertEquals('Synced', updated.QB_Sync_Status__c);
        System.assertEquals(true, updated.Is_Synced__c);
        System.assertEquals('QB-INV-001', updated.QB_Invoice_Id__c);
        System.assertNotEquals(null, updated.Synced_Date__c);

        Account updatedAcc = [SELECT QB_Customer_Id__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('QB-CUST-001', updatedAcc.QB_Customer_Id__c);
    }

    // ================================================================
    // TEST 5: Existing QB Customer ID → update path
    // Sequence: getSyncToken(1) → updateCustomer(2) → createInvoice(3)
    // ================================================================
    @isTest
    static void testSuccessfulSyncExistingCustomer() {
        Account acc = createTestAccount();
        acc.QB_Customer_Id__c = 'EXISTING-QB-CUST';
        update acc;

        Billing__c bill = createTestBilling(acc.Id, 'Detroit', false);
        createTestLineItem(bill.Id); // ★ required

        QBMultiCallMock mock = new QBMultiCallMock();
        mock.addResponse(200, customerGetBody('EXISTING-QB-CUST')); // 1. getSyncToken
        mock.addResponse(200, customerCreateBody('EXISTING-QB-CUST')); // 2. update customer
        mock.addResponse(200, invoiceCreateBody('QB-INV-002'));      // 3. create invoice

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        System.assert(result.contains('Success'), 'Expected Success, got: ' + result);

        Billing__c updated = [SELECT QB_Sync_Status__c, Is_Synced__c, QB_Invoice_Id__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertEquals('Synced', updated.QB_Sync_Status__c);
        System.assertEquals(true, updated.Is_Synced__c);

        Account updatedAcc = [SELECT QB_Customer_Id__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('EXISTING-QB-CUST', updatedAcc.QB_Customer_Id__c);
    }

    // ================================================================
    // TEST 6: Duplicate name → auto-heal
    // Sequence: query(1) → createCustomer 400(2) → createCustomer retry(3) → createInvoice(4)
    // ================================================================
    @isTest
    static void testDuplicateNameAutoHeal() {
        Account acc     = createTestAccount();
        Billing__c bill = createTestBilling(acc.Id, 'Detroit', false);
        createTestLineItem(bill.Id); // ★ required

        QBMultiCallMock mock = new QBMultiCallMock();
        mock.addResponse(200, customerQueryEmptyBody());
        mock.addResponse(400, '{"Fault":{"Error":[{"Message":"Duplicate Name Exists Error","code":"6240"}]}}');
        mock.addResponse(200, customerCreateBody('QB-CUST-HEALED'));
        mock.addResponse(200, invoiceCreateBody('QB-INV-003'));

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        Billing__c updated = [SELECT QB_Sync_Status__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertNotEquals(null, updated.QB_Sync_Status__c);
    }

    // ================================================================
    // TEST 7: Object Not Found → auto-heal
    // Sequence: getSyncToken(1) → update 400(2) → query(3) → createCustomer(4) → createInvoice(5)
    // ================================================================
    @isTest
    static void testObjectNotFoundAutoHeal() {
        Account acc = createTestAccount();
        acc.QB_Customer_Id__c = 'DELETED-QB-CUST';
        update acc;

        Billing__c bill = createTestBilling(acc.Id, 'Detroit', false);
        createTestLineItem(bill.Id); // ★ required

        QBMultiCallMock mock = new QBMultiCallMock();
        mock.addResponse(200, customerGetBody('DELETED-QB-CUST'));
        mock.addResponse(400, '{"Fault":{"Error":[{"Message":"Object Not Found","code":"610"}]}}');
        mock.addResponse(200, customerQueryEmptyBody());
        mock.addResponse(200, customerCreateBody('QB-CUST-NEW'));
        mock.addResponse(200, invoiceCreateBody('QB-INV-004'));

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        Billing__c updated = [SELECT QB_Sync_Status__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertNotEquals(null, updated.QB_Sync_Status__c);
    }

    // ================================================================
    // TEST 8: QB API 500 → failure recorded
    // ================================================================
    @isTest
    static void testQBApiServerError() {
        Account acc     = createTestAccount();
        Billing__c bill = createTestBilling(acc.Id, 'Detroit', false);
        // No line item needed — fails at customer step before invoice

        QBMultiCallMock mock = new QBMultiCallMock();
        mock.addResponse(200, customerQueryEmptyBody());
        mock.addResponse(500, '{"Fault":{"Error":[{"Message":"Internal Server Error"}]}}');

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        System.assert(result.startsWith('Error'), 'Expected error, got: ' + result);
        Billing__c updated = [SELECT QB_Sync_Status__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertEquals('Failed', updated.QB_Sync_Status__c);
    }

    // ================================================================
    // TEST 9: Customer found by name → ID reused
    // Sequence: query found(1) → getSyncToken(2) → updateCustomer(3) → createInvoice(4)
    // ================================================================
    @isTest
    static void testExistingCustomerFoundByName() {
        Account acc     = createTestAccount();
        Billing__c bill = createTestBilling(acc.Id, 'Detroit', false);
        createTestLineItem(bill.Id); // ★ required

        String existingQbId   = 'QB-FOUND-BY-NAME';
        String queryFoundBody = '{"QueryResponse":{"Customer":[{"Id":"' + existingQbId + '"}]}}';

        QBMultiCallMock mock = new QBMultiCallMock();
        mock.addResponse(200, queryFoundBody);                       // 1. query → found
        mock.addResponse(200, customerGetBody(existingQbId));        // 2. getSyncToken
        mock.addResponse(200, customerCreateBody(existingQbId));     // 3. update customer
        mock.addResponse(200, invoiceCreateBody('QB-INV-005'));      // 4. create invoice

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        System.assert(result.contains('Success'), 'Expected Success, got: ' + result);

        Billing__c updated = [SELECT QB_Sync_Status__c, Is_Synced__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertEquals('Synced', updated.QB_Sync_Status__c);
        System.assertEquals(true, updated.Is_Synced__c);
    }

    // ================================================================
    // TEST 10: No line items → fails with no valid line items error
    // ================================================================
    @isTest
    static void testNoLineItemsFails() {
        Account acc     = createTestAccount();
        Billing__c bill = createTestBilling(acc.Id, 'Detroit', false);
        // Intentionally no line items inserted

        QBMultiCallMock mock = new QBMultiCallMock();
        mock.addResponse(200, customerQueryEmptyBody());
        mock.addResponse(200, customerCreateBody('QB-CUST-NLI'));

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        System.assert(result.startsWith('Error'), 'Expected error for no line items, got: ' + result);
        Billing__c updated = [SELECT QB_Sync_Status__c FROM Billing__c WHERE Id = :bill.Id];
        System.assertEquals('Failed', updated.QB_Sync_Status__c);
    }

    // ================================================================
    // TEST 11: Caregiver-only line items → same no-valid-lines failure
    // ================================================================
    @isTest
    static void testCaregiverOnlyLineItemsFails() {
        Account acc     = createTestAccount();
        Billing__c bill = createTestBilling(acc.Id, 'Detroit', false);

        Billing_Line_Item__c li = new Billing_Line_Item__c(
            Invoice__c     = bill.Id,
            Description__c = 'Caregiver Pay',
            Quantity__c    = 1,
            Rate__c        = 200.00,
            Amount__c      = 200.00,
            Type__c        = 'Caregiver Billable',  // filtered out by service
            Service_Date__c = Date.today().addDays(-1)
        );
        insert li;

        QBMultiCallMock mock = new QBMultiCallMock();
        mock.addResponse(200, customerQueryEmptyBody());
        mock.addResponse(200, customerCreateBody('QB-CUST-CG'));

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BillingSyncController.syncBillingToQB(bill.Id);
        Test.stopTest();

        System.assert(result.startsWith('Error'), 'Expected error for caregiver-only lines, got: ' + result);
    }

    // ================================================================
    // TEST 12: QB Credential helper — getCredentialNameForLocation
    // ================================================================
    @isTest
    static void testCredentialManagerGetName() {
        Test.startTest();
        String name = QuickBooksCredentialManager.getCredentialNameForLocation('Detroit');
        Test.stopTest();
        System.assertEquals('QuickBooksSalesforce_Detroit', name);
    }

    // ================================================================
    // TEST 13: QB Credential helper — empty location throws exception
    // ================================================================
    @isTest
    static void testCredentialManagerEmptyLocationThrows() {
        Test.startTest();
        try {
            QuickBooksCredentialManager.getCredentialNameForLocation('');
            System.assert(false, 'Expected exception not thrown');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Location cannot be empty'));
        }
        Test.stopTest();
    }

    // ================================================================
    // TEST 14: isLocationCredentialConfigured returns non-null
    // ================================================================
    @isTest
    static void testIsLocationCredentialConfigured() {
        Test.startTest();
        Boolean result = QuickBooksCredentialManager.isLocationCredentialConfigured('Detroit');
        Test.stopTest();
        System.assertNotEquals(null, result);
    }
}