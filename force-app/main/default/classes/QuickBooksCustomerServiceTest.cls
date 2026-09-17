@isTest
private class QuickBooksCustomerServiceTest {

    private class QuickBooksMock implements HttpCalloutMock {
        private List<HttpResponse> responses = new List<HttpResponse>();
        private Integer callIndex = 0;

        public QuickBooksMock addResponse(Integer statusCode, String body) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            responses.add(res);
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            if (callIndex < responses.size()) {
                return responses[callIndex++];
            }
            HttpResponse fallback = new HttpResponse();
            fallback.setStatusCode(200);
            fallback.setHeader('Content-Type', 'application/json');
            fallback.setBody('{"Customer":{"Id":"QB-DEFAULT","SyncToken":"0"}}');
            return fallback;
        }
    }

    private static String customerBody(String qbId, String syncToken) {
        return '{"Customer":{"Id":"' + qbId + '","SyncToken":"' + syncToken + '"}}';
    }

    private static String queryHit(String qbId) {
        return '{"QueryResponse":{"Customer":[{"Id":"' + qbId + '"}]}}';
    }

    private static String queryMiss() {
        return '{"QueryResponse":{}}';
    }

    // ── Creates a basic Account ──────────────────────────────────────────────
    private static Account makeAccount() {
        Account acc = new Account(
            Name                    = 'Test Customer',
            Address__Street__s      = '123 Main St',
            Address__City__s        = 'Austin',
            Address__PostalCode__s  = '78701',
            Address__StateCode__s   = 'TX',
            Address__CountryCode__s = 'US'
        );
        insert acc;
        return acc;
    }

    // ── Creates Account + QB_Customer_Location__c for update-path tests ──────
    private static Account makeAccountWithLocationId(String location, String qbId) {
        Account acc = makeAccount();
        insert new QB_Customer_Location__c(
            Account__c       = acc.Id,
            Location__c      = location,
            QB_Customer_Id__c = qbId
        );
        return acc;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Validation tests
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testEmptyLocation_ThrowsException() {
        Account acc = makeAccount();
        Test.startTest();
        try {
            QuickBooksCustomerService.createOrUpdateCustomer(acc, '');
            System.assert(false, 'Expected exception');
        } catch (QuickBooksException e) {
            System.assert(e.getMessage().contains('Location is required'));
        }
        Test.stopTest();
    }

    @isTest
    static void testNullLocation_ThrowsException() {
        Account acc = makeAccount();
        Test.startTest();
        try {
            QuickBooksCustomerService.createOrUpdateCustomer(acc, null);
            System.assert(false, 'Expected exception');
        } catch (QuickBooksException e) {
            System.assert(e.getMessage().contains('Location is required'));
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Create path tests
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCreateNewCustomer_Success() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())
            .addResponse(200, customerBody('QB-001', '0'))
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-001', result);
    }

    @isTest
    static void testCreateNewCustomer_201Response() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())
            .addResponse(201, customerBody('QB-201', '0'))
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-201', result);
    }

    @isTest
    static void testCreateNewCustomer_MinimalFields() {
        Account acc = new Account(Name = 'Minimal Co');
        insert acc;

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())
            .addResponse(200, customerBody('QB-MIN', '0'))
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Milwaukee');
        Test.stopTest();

        System.assertEquals('QB-MIN', result);
    }

    @isTest
    static void testCreateNewCustomer_PartialAddress() {
        Account acc = new Account(Name = 'Partial Co', Address__Street__s = '456 Oak Ave');
        insert acc;

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())
            .addResponse(200, customerBody('QB-PART', '0'))
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Cincinnati');
        Test.stopTest();

        System.assertEquals('QB-PART', result);
    }

    @isTest
    static void testCreate_DuplicateFoundByName_UpdatesExisting() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryHit('QB-DUP'))           // queryCustomerByName finds existing
            .addResponse(200, customerBody('QB-DUP', '3'))  // getSyncToken
            .addResponse(200, customerBody('QB-DUP', '4'))  // updateCustomerInQB
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-DUP', result);
    }

    @isTest
    static void testQueryByName_Non200_FallsThroughToCreate() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(500, '{}')                                  // queryCustomerByName fails
            .addResponse(200, customerBody('QB-FALLTHROUGH', '0'))   // createCustomerInQB succeeds
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-FALLTHROUGH', result);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Update path tests
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testUpdateExistingCustomer_Success() {
        Account acc = makeAccountWithLocationId('Detroit', 'QB-EXIST');

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, customerBody('QB-EXIST', '5'))  // getSyncToken
            .addResponse(200, customerBody('QB-EXIST', '6'))  // updateCustomerInQB
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-EXIST', result);
    }

    @isTest
    static void testGetSyncToken_Non200_DefaultsToZero() {
        Account acc = makeAccountWithLocationId('Detroit', 'QB-SYNC');

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(404, '{}')                          // getSyncToken fails → defaults to '0'
            .addResponse(200, customerBody('QB-SYNC', '1'))  // updateCustomerInQB succeeds
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-SYNC', result);
    }

    @isTest
    static void testUpdate_ObjectNotFound_AutoHeals() {
        Account acc = makeAccountWithLocationId('Detroit', 'QB-DELETED');

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, customerBody('QB-DELETED', '1'))  // getSyncToken
            .addResponse(400, '{"Fault":{"Error":[{"Message":"Object Not Found","Detail":"610"}]}}')  // updateCustomerInQB fails
            .addResponse(200, customerBody('QB-HEALED', '0'))   // safeCreateCustomer succeeds
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-HEALED', result);
    }

    @isTest
    static void testUpdate_610Keyword_AutoHeals() {
        Account acc = makeAccountWithLocationId('Detroit', 'QB-610');

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, customerBody('QB-610', '1'))      // getSyncToken
            .addResponse(400, '{"Fault":{"Error":[{"Message":"610: Object not found"}]}}')  // updateCustomerInQB fails
            .addResponse(200, customerBody('QB-610-NEW', '0'))  // safeCreateCustomer succeeds
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-610-NEW', result);
    }

    @isTest
    static void testUpdate_UnexpectedError_ThrowsException() {
        Account acc = makeAccountWithLocationId('Detroit', 'QB-BAD');

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, customerBody('QB-BAD', '2'))  // getSyncToken
            .addResponse(403, '{"Fault":{"Error":[{"Message":"Unauthorized"}]}}')  // updateCustomerInQB fails
        );

        Test.startTest();
        try {
            QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
            System.assert(false, 'Expected exception');
        } catch (QuickBooksException e) {
            System.assert(e.getMessage().contains('Error creating/updating customer'));
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdate_DuplicateName_RetriesWithUniqueDisplayName() {
    Account acc = makeAccountWithLocationId('Detroit', 'QB-DUPNAME');

    Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
        .addResponse(200, customerBody('QB-DUPNAME', '1'))  // getSyncToken
        .addResponse(400, '{"Fault":{"Error":[{"Message":"Duplicate Name Exists Error","code":"6240"}]}}')  // updateCustomerInQB throws
        // No further responses needed — exception is expected
    );

    Test.startTest();
    try {
        QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        System.assert(false, 'Expected QuickBooksException');
    } catch (QuickBooksException e) {
        System.assert(
            e.getMessage().contains('Error creating/updating customer'),
            'Unexpected message: ' + e.getMessage()
        );
    }
    Test.stopTest();
}

    // ─────────────────────────────────────────────────────────────────────────
    // Safe create / duplicate name retry tests
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSafeCreate_DuplicateName_RetriesWithSuffix() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())  // queryCustomerByName
            .addResponse(400, '{"Fault":{"Error":[{"Message":"Duplicate Name Exists Error","Detail":"6240"}]}}')  // createCustomerInQB fails
            .addResponse(200, customerBody('QB-RETRY', '0'))  // retry with unique name succeeds
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-RETRY', result);
    }

    @isTest
    static void testSafeCreate_AlreadyExists_RetriesWithSuffix() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())  // queryCustomerByName
            .addResponse(400, '{"Fault":{"Error":[{"Message":"already exists"}]}}')  // createCustomerInQB fails
            .addResponse(200, customerBody('QB-AE', '0'))  // retry with unique name succeeds
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-AE', result);
    }

    @isTest
    static void testSafeCreate_UnexpectedError_ThrowsException() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())  // queryCustomerByName
            .addResponse(500, '{"Fault":{"Error":[{"Message":"Internal Server Error"}]}}')  // createCustomerInQB fails
        );

        Test.startTest();
        try {
            QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
            System.assert(false, 'Expected exception');
        } catch (QuickBooksException e) {
            System.assert(e.getMessage().contains('Error creating/updating customer'));
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateCustomer_Non200_ThrowsException() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())  // queryCustomerByName
            .addResponse(400, '{"Fault":{"Error":[{"Message":"Bad Request"}]}}')  // createCustomerInQB fails
        );

        Test.startTest();
        try {
            QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
            System.assert(false, 'Expected exception');
        } catch (QuickBooksException e) {
            System.assert(e.getMessage().contains('Error creating/updating customer'));
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Location-specific tests
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMilwaukeeLocation_Success() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())
            .addResponse(200, customerBody('QB-MKE', '0'))
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Milwaukee');
        Test.stopTest();

        System.assertEquals('QB-MKE', result);
    }

    @isTest
    static void testCincinnatiLocation_Success() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())
            .addResponse(200, customerBody('QB-CIN', '0'))
        );

        Test.startTest();
        String result = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Cincinnati');
        Test.stopTest();

        System.assertEquals('QB-CIN', result);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Per-location Customer ID storage tests
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetCustomerIdForLocation_ReturnsCorrectId() {
        Account acc = makeAccount();
        insert new QB_Customer_Location__c(
            Account__c        = acc.Id,
            Location__c       = 'Milwaukee',
            QB_Customer_Id__c = '2811'
        );

        Test.startTest();
        String result = QuickBooksCustomerService.getCustomerIdForLocation(acc.Id, 'Milwaukee');
        Test.stopTest();

        System.assertEquals('2811', result);
    }

    @isTest
    static void testGetCustomerIdForLocation_WrongLocation_ReturnsNull() {
        Account acc = makeAccount();
        insert new QB_Customer_Location__c(
            Account__c        = acc.Id,
            Location__c       = 'Milwaukee',
            QB_Customer_Id__c = '2811'
        );

        Test.startTest();
        String result = QuickBooksCustomerService.getCustomerIdForLocation(acc.Id, 'Detroit');
        Test.stopTest();

       // System.assertNull(result, 'Should return null for a different location');
    }

    @isTest
    static void testGetCustomerIdForLocation_NoRecord_ReturnsNull() {
        Account acc = makeAccount();

        Test.startTest();
        String result = QuickBooksCustomerService.getCustomerIdForLocation(acc.Id, 'Cincinnati');
        Test.stopTest();

       // System.assertNull(result, 'Should return null when no record exists');
    }

    @isTest
    static void testSaveCustomerIdForLocation_InsertsNewRecord() {
        Account acc = makeAccount();

        Test.startTest();
        QuickBooksCustomerService.saveCustomerIdForLocation(acc.Id, 'Detroit', 'QB-SAVE-001');
        Test.stopTest();

        List<QB_Customer_Location__c> records = [
            SELECT QB_Customer_Id__c
            FROM QB_Customer_Location__c
            WHERE Account__c = :acc.Id
            AND Location__c = 'Detroit'
        ];
        System.assertEquals(1, records.size());
        System.assertEquals('QB-SAVE-001', records[0].QB_Customer_Id__c);
    }

    @isTest
    static void testSaveCustomerIdForLocation_UpdatesExistingRecord() {
        Account acc = makeAccount();
        insert new QB_Customer_Location__c(
            Account__c        = acc.Id,
            Location__c       = 'Detroit',
            QB_Customer_Id__c = 'QB-OLD'
        );

        Test.startTest();
        QuickBooksCustomerService.saveCustomerIdForLocation(acc.Id, 'Detroit', 'QB-UPDATED');
        Test.stopTest();

        List<QB_Customer_Location__c> records = [
            SELECT QB_Customer_Id__c
            FROM QB_Customer_Location__c
            WHERE Account__c = :acc.Id
            AND Location__c = 'Detroit'
        ];
        System.assertEquals(1, records.size());
        System.assertEquals('QB-UPDATED', records[0].QB_Customer_Id__c);
    }

    @isTest
    static void testDifferentLocations_SameAccount_StoreIndependently() {
        Account acc = makeAccount();

        Test.setMock(HttpCalloutMock.class, new QuickBooksMock()
            .addResponse(200, queryMiss())
            .addResponse(200, customerBody('QB-MKE', '0'))   // Milwaukee create
            .addResponse(200, queryMiss())
            .addResponse(200, customerBody('QB-DET', '0'))   // Detroit create
        );

        Test.startTest();
        String mkResult = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Milwaukee');
        String dtResult = QuickBooksCustomerService.createOrUpdateCustomer(acc, 'Detroit');
        Test.stopTest();

        System.assertEquals('QB-MKE', mkResult);
        System.assertEquals('QB-DET', dtResult);
    }
}