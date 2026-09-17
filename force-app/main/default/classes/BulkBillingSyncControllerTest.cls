@IsTest
public class BulkBillingSyncControllerTest {

    // ================= MOCK =================
    private class SimpleMock implements HttpCalloutMock {
        Integer code;
        String body;

        SimpleMock(Integer c, String b) {
            code = c;
            body = b;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody(body);
            return res;
        }
    }

    // ================= TEST METHODS =================

    // 🔥 1. FULL SUCCESS (both dates + locations)
    @isTest
    static void testBulkSync_Success_AllInputs() {

        Test.setMock(HttpCalloutMock.class, new SimpleMock(200, '{}'));

        Date startDate = Date.today().addDays(-2);
        Date endDate = Date.today();

        Test.startTest();
        String res = BulkBillingSyncController.startBatchSync(
            startDate,
            endDate,
            new List<String>{'Detroit'}
        );
        Test.stopTest();

        System.assertNotEquals(null, res);
        System.assert(res.contains('Mass Sync Started'));
    }


    // 🔥 2. ONLY START DATE
    @isTest
    static void testBulkSync_OnlyStartDate() {

        Test.startTest();
        String res = BulkBillingSyncController.startBatchSync(
            Date.today(),
            null,
            new List<String>{'Detroit'}
        );
        Test.stopTest();

        System.assert(res.contains('Mass Sync Started'));
    }


    // 🔥 3. ONLY END DATE
    @isTest
    static void testBulkSync_OnlyEndDate() {

        Test.startTest();
        String res = BulkBillingSyncController.startBatchSync(
            null,
            Date.today(),
            new List<String>{'Detroit'}
        );
        Test.stopTest();

        System.assert(res.contains('Mass Sync Started'));
    }


    // 🔥 4. BOTH DATES NULL
    @isTest
    static void testBulkSync_NoDates() {

        Test.startTest();
        String res = BulkBillingSyncController.startBatchSync(
            null,
            null,
            new List<String>{'Detroit'}
        );
        Test.stopTest();

        System.assert(res.contains('Mass Sync Started'));
    }


    // 🔥 5. VALIDATION FAILURE
    @isTest
    static void testBulkSync_InvalidDateRange() {

        Date startDate = Date.today();
        Date endDate = Date.today().addDays(-1);

        try {
            BulkBillingSyncController.startBatchSync(
                startDate,
                endDate,
                new List<String>{'Detroit'}
            );
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
         //   System.assert(e.getMessage().contains('Start Date cannot be greater'));
        }
    }


    // 🔥 6. EMPTY LOCATION LIST
    @isTest
    static void testBulkSync_EmptyLocations() {

        Test.startTest();
        String res = BulkBillingSyncController.startBatchSync(
            Date.today().addDays(-1),
            Date.today(),
            new List<String>()
        );
        Test.stopTest();

        System.assert(res.contains('Mass Sync Started'));
    }


    // 🔥 7. NULL LOCATION LIST (extra edge case)
    @isTest
    static void testBulkSync_NullLocations() {

        Test.startTest();
        String res = BulkBillingSyncController.startBatchSync(
            Date.today().addDays(-1),
            Date.today(),
            null
        );
        Test.stopTest();

        System.assert(res.contains('Mass Sync Started'));
    }
}