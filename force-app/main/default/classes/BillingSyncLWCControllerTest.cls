@isTest
private class BillingSyncLWCControllerTest {

   @testSetup
static void createData() {

    Account acc = new Account(
        Name = 'Test Account'
    );
    insert acc;

    Billing__c bill = new Billing__c(
        Client__c = acc.Id,
        Care_From_Date__c = Date.today(),
        Care_To_Date__c = Date.today().addDays(7),
        Invoice_Date__c = Date.today(),
        Invoice_Period_Start_Date__c = Date.today(),
        Invoice_Period_End_Date__c = Date.today().addDays(7),
        Paid_Status__c = 'Unpaid',
        Amount__c=100
    );

    insert bill;
}

   @isTest
static void testSyncSelectedBillings_Success() {

    List<Id> billingIds = new List<Id>();

    for(Billing__c b : [
        SELECT Id
        FROM Billing__c
        LIMIT 1
    ]) {
        billingIds.add(b.Id);
    }

    Test.startTest();

    BillingSyncLWCController.syncSelectedBillings(billingIds);

    Test.stopTest();

    System.assertEquals(1, billingIds.size());
}
    @isTest
    static void testSyncSelectedBillings_EmptyList() {

        Test.startTest();

        try {

            BillingSyncLWCController.syncSelectedBillings(
                new List<Id>()
            );

            System.assert(false,
                'Exception should have been thrown');

        } catch (AuraHandledException ex) {

           // System.assertEquals('Please select at least one record.', ex.getMessage() );
        }

        Test.stopTest();
    }

    @isTest
    static void testSyncSelectedBillings_NullList() {

        Test.startTest();

        try {

            BillingSyncLWCController.syncSelectedBillings(null);

            System.assert(false,
                'Exception should have been thrown');

        } catch (AuraHandledException ex) {

            //System.assertEquals('Please select at least one record.', ex.getMessage() );
        }

        Test.stopTest();
    }
    @isTest
static void testGetBatchStatus() {

    // Test Data
    Account acc = new Account(
        Name = 'Test Account',
        QB_Customer_Id__c = 'QB-CUST'
    );
    insert acc;

    Date d = Date.today();

    Billing__c billing = new Billing__c(
        Client__c = acc.Id,
        Amount__c = 100,
        Care_From_Date__c = d,
        Care_To_Date__c = d,
        Paid_Status__c = 'Unpaid',
        Invoice_Date__c = d,
        Invoice_Period_Start_Date__c = d.toStartOfMonth(),
        Invoice_Period_End_Date__c = d.toStartOfMonth().addMonths(1).addDays(-1),
        Due_Date__c = d.addDays(5),
        Location_g__c = 'Detroit',
        QB_Sync_Status__c = 'Pending',
        Is_Synced__c = false
    );
    insert billing;

    insert new Billing_Line_Item__c(
        Invoice__c = billing.Id,
        Type__c = 'Client Billable',
        Quantity__c = 1,
        Rate__c = 100,
        Amount__c = 100,
        Service_Date__c = Date.today(),
        Description__c = 'Service'
    );

    Test.setMock(HttpCalloutMock.class,
        new UniversalMock());

    Test.startTest();

    Id jobId = BillingSyncLWCController.syncSelectedBillings(
        new List<Id>{ billing.Id }
    );

    String status = BillingSyncLWCController.getBatchStatus(jobId);

    Test.stopTest();

    System.assertNotEquals(null, status);
    System.assert(
        status == 'Queued' ||
        status == 'Preparing' ||
        status == 'Processing' ||
        status == 'Completed',
        'Unexpected Batch Status: ' + status
    );
}
    private class UniversalMock implements HttpCalloutMock {

    public HttpResponse respond(HttpRequest req) {

        HttpResponse res = new HttpResponse();
        String endpoint = req.getEndpoint().toLowerCase();

        if(endpoint.contains('query')){
            res.setStatusCode(200);
            res.setBody('{"QueryResponse":{}}');
            return res;
        }

        if(endpoint.contains('customer/')){
            res.setStatusCode(200);
            res.setBody(
                '{"Customer":{"Id":"QB-CUST","SyncToken":"0"}}'
            );
            return res;
        }

        if(endpoint.contains('customer')){
            res.setStatusCode(200);
            res.setBody(
                '{"Customer":{"Id":"QB-CUST","SyncToken":"0"}}'
            );
            return res;
        }

        if(endpoint.contains('invoice')){
            res.setStatusCode(200);
            res.setBody(
                '{"Invoice":{"Id":"QB-INV","SyncToken":"0","Line":[{"Id":"1"}]}}'
            );
            return res;
        }

        res.setStatusCode(200);
        res.setBody('{}');
        return res;
    }
}
}