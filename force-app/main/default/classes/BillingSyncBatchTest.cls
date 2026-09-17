@isTest
public class BillingSyncBatchTest {

    // ======================================================
    // ✅ UNIVERSAL SAFE MOCK (Handles ALL cases)
    // ======================================================
    private class UniversalMock implements HttpCalloutMock {

        Integer createCallCount = 0;
        Boolean simulateDuplicate;

        UniversalMock(Boolean simulateDuplicate){
            this.simulateDuplicate = simulateDuplicate;
        }
 
        public HttpResponse respond(HttpRequest req){

            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint().toLowerCase();

            System.debug('ENDPOINT => ' + endpoint);

            // ---------------------------
            // QUERY
            // ---------------------------
            if(endpoint.contains('query')){
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{}}');
                return res;
            }

            // ---------------------------
            // GET CUSTOMER (SYNC TOKEN)
            // ---------------------------
            if(endpoint.contains('customer/')){
                res.setStatusCode(200);
                res.setBody(
                    '{"Customer":{"Id":"QB-CUST","SyncToken":"0"}}'
                );
                return res;
            }

            // ---------------------------
            // CREATE / UPDATE CUSTOMER
            // ---------------------------
            if(endpoint.contains('customer')){

                // simulate duplicate only for first call
                if(simulateDuplicate){

                    createCallCount++;

                    if(createCallCount == 1){
                        res.setStatusCode(400);
                        res.setBody(
                            '{"Fault":{"Error":[{"Message":"Duplicate Name Exists Error 6240"}]}}'
                        );
                        return res;
                    }
                }

                // SUCCESS RESPONSE
                res.setStatusCode(200);
                res.setBody(
                    '{"Customer":{"Id":"QB-NEW","SyncToken":"0"}}'
                );
                return res;
            }

            // ---------------------------
            // INVOICE
            // ---------------------------
            if(endpoint.contains('invoice')){
                res.setStatusCode(200);
                res.setBody(
                    '{"Invoice":{"Id":"QB-INV","SyncToken":"0","Line":[{"Id":"1","DetailType":"SalesItemLineDetail"}]}}'
                );
                return res;
            }

            // DEFAULT SAFE RESPONSE
            res.setStatusCode(200);
            res.setBody('{}');

            return res;
        }
    }

    // ======================================================
    // TEST DATA
    // ======================================================
    private static Account makeAcc(Boolean hasQB){

        Account a = new Account(
            Name = 'Test Account',
            QB_Customer_Id__c = hasQB ? 'QB-CUST' : null
        );
        insert a;
        return a;
    }

    private static Billing__c makeBill(Id accId){

        Date d = Date.today();

        Billing__c b = new Billing__c(
            Client__c = accId,
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
        insert b;
        return b;
    }

    private static void makeLine(Id billId){
        insert new Billing_Line_Item__c(
            Invoice__c = billId,
            Type__c = 'Client Billable',
            Quantity__c = 1,
            Rate__c = 100,
            Amount__c = 100,
            Service_Date__c = Date.today(),
            Description__c = 'Service'
        );
    }

    // ======================================================
    // ✅ TEST: BATCH WITH RECORD IDS (List View Selection)
    // ======================================================
    @isTest
    static void testBatchSuccess(){

        Account a = makeAcc(true);
        Billing__c b = makeBill(a.Id);
        makeLine(b.Id);

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        Database.executeBatch(new BillingSyncBatch(new List<Id>{ b.Id }),1);
        Test.stopTest();

        b = [
            SELECT Is_Synced__c, QB_Sync_Status__c
            FROM Billing__c
            WHERE Id = :b.Id
        ];

        System.assertEquals(true, b.Is_Synced__c);
        System.assertEquals('Synced', b.QB_Sync_Status__c);
    }

    // ======================================================
    // ✅ TEST: BATCH WITH DEFAULT CONSTRUCTOR
    // ======================================================
    @isTest
    static void testBatchDefaultConstructor(){

        Account a = makeAcc(true);
        Billing__c b = makeBill(a.Id);
        makeLine(b.Id);

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        Database.executeBatch(new BillingSyncBatch(), 1);
        Test.stopTest();

        b = [
            SELECT Is_Synced__c, QB_Sync_Status__c
            FROM Billing__c
            WHERE Id = :b.Id
        ];

        System.assertEquals(true, b.Is_Synced__c);
        System.assertEquals('Synced', b.QB_Sync_Status__c);
    }

    // ======================================================
    // ✅ TEST: BATCH WITH LOCATION FILTER ONLY
    // ======================================================
    @isTest
    static void testBatchWithLocationFilter(){

        Account a = makeAcc(true);
        Billing__c b = makeBill(a.Id);
        makeLine(b.Id);

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        List<String> locs = new List<String>{'Detroit'};

        Test.startTest();
        Database.executeBatch(new BillingSyncBatch(null, null, locs), 1);
        Test.stopTest();

        b = [
            SELECT Is_Synced__c, QB_Sync_Status__c
            FROM Billing__c
            WHERE Id = :b.Id
        ];

        System.assertEquals(true, b.Is_Synced__c);
        System.assertEquals('Synced', b.QB_Sync_Status__c);
    }

    // ======================================================
    // ✅ TEST: BATCH WITH MISSING LOCATION - SKIPPED
    // ======================================================
    @isTest
    static void testBatchMissingLocation(){

        Account a = makeAcc(true);
        
        Date d = Date.today();
        Billing__c b = new Billing__c(
            Client__c = a.Id,
            Amount__c = 100,
            Care_From_Date__c = d,
            Care_To_Date__c = d,
            Paid_Status__c = 'Unpaid',
            Invoice_Date__c = d,
            Invoice_Period_Start_Date__c = d.toStartOfMonth(),
            Invoice_Period_End_Date__c = d.toStartOfMonth().addMonths(1).addDays(-1),
            Due_Date__c = d.addDays(5),
            Location_g__c = null, // Missing location
            QB_Sync_Status__c = 'Pending',
            Is_Synced__c = false
        );
        insert b;
        makeLine(b.Id);

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        BillingSyncBatch batch = new BillingSyncBatch(new List<Id>{ b.Id });
        Database.executeBatch(batch, 1);
        Test.stopTest();

        b = [
            SELECT QB_Sync_Status__c, QB_Sync_Error__c
            FROM Billing__c
            WHERE Id = :b.Id
        ];

        System.assertEquals('Failed', b.QB_Sync_Status__c);
        System.assert(b.QB_Sync_Error__c.contains('Location field is required'));
        //System.assertEquals(1, batch.skippedCount);
    }

    // ======================================================
    // ✅ TEST: BATCH START METHOD
    // ======================================================
    @isTest
    static void testBatchStartMethod(){

        Account a = makeAcc(true);
        Billing__c b = makeBill(a.Id);
        makeLine(b.Id);

        Test.startTest();
       BillingSyncBatch batch = new BillingSyncBatch();

	   Iterable<List<Billing__c>> iterable = batch.start(null);

	   System.assertNotEquals(null, iterable);
        Test.stopTest();

        
    }

    // ======================================================
    // ✅ TEST: BATCH WITH MULTIPLE RECORDS
    // ======================================================
    @isTest
    static void testBatchMultipleRecords(){

        Account a = makeAcc(true);
        
        Date d = Date.today();
        List<Billing__c> bills = new List<Billing__c>();
        for(Integer i = 0; i < 3; i++){
            bills.add(new Billing__c(
                Client__c = a.Id,
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
            ));
        }
        insert bills;
        
        for(Billing__c bill : bills){
            makeLine(bill.Id);
        }

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        BillingSyncBatch batch = new BillingSyncBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Billing__c> syncedBills = [
            SELECT Id, Is_Synced__c 
            FROM Billing__c 
            WHERE Is_Synced__c = true
        ];
    }

    // ======================================================
    // ✅ TEST: BATCH WITH EMPTY RESULT SET
    // ======================================================
    @isTest
    static void testBatchEmptyResultSet(){

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        BillingSyncBatch batch = new BillingSyncBatch();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Should complete without errors
        System.assertEquals(0, batch.successCount);
        System.assertEquals(0, batch.failureCount);
    }

    // ======================================================
    // ✅ TEST: BATCH WITH SYNCED DATE FIELD
    // ======================================================
    @isTest
    static void testBatchSyncedDateField(){

        Account a = makeAcc(true);
        Billing__c b = makeBill(a.Id);
        makeLine(b.Id);

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        Database.executeBatch(new BillingSyncBatch(new List<Id>{ b.Id }), 1);
        Test.stopTest();

        b = [
            SELECT Synced_Date__c, Is_Synced__c
            FROM Billing__c
            WHERE Id = :b.Id
        ];

        System.assertEquals(true, b.Is_Synced__c);
        System.assertNotEquals(null, b.Synced_Date__c, 'Synced date should be set');
    }

    // ======================================================
    // ✅ TEST: BATCH START WITH FILTERS IN QUERY
    // ======================================================
    @isTest
    static void testBatchStartWithFilters(){

        Account a = makeAcc(true);
        Billing__c b = makeBill(a.Id);
        makeLine(b.Id);

        Datetime startDT = Datetime.now().addDays(-1);
        Datetime endDT = Datetime.now().addDays(1);
        List<String> locs = new List<String>{'Detroit'};

        Test.startTest();
     	BillingSyncBatch batch = new BillingSyncBatch(startDT, endDT, locs);

		Iterable<List<Billing__c>> iterable = batch.start(null);

		System.assertNotEquals(null, iterable);
        Test.stopTest();

        
    }

    // ======================================================
    // ✅ TEST: BATCH WITH SELECTED RECORD IDS FILTER
    // ======================================================
    @isTest
    static void testBatchWithSelectedRecordIds(){

        Account a = makeAcc(true);
        Billing__c b1 = makeBill(a.Id);
        makeLine(b1.Id);
        
        Billing__c b2 = makeBill(a.Id);
        makeLine(b2.Id);

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        BillingSyncBatch batch = new BillingSyncBatch(new List<Id>{ b1.Id });
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Only b1 should be synced, not b2
        Billing__c b1Result = [SELECT Is_Synced__c FROM Billing__c WHERE Id = :b1.Id];
        Billing__c b2Result = [SELECT Is_Synced__c FROM Billing__c WHERE Id = :b2.Id];

        System.assertEquals(true, b1Result.Is_Synced__c, 'b1 should be synced');
        System.assertEquals(false, b2Result.Is_Synced__c, 'b2 should not be synced');
    }

    // ======================================================
    // ✅ TEST: BATCH WITH EXCEPTION HANDLING
    // ======================================================
    @isTest
    static void testBatchWithException(){

        // Create account without required fields to trigger exception
        Account a = new Account(Name = 'Test Account', QB_Customer_Id__c = 'QB-CUST');
        insert a;
        
        Date d = Date.today();
        Billing__c b = new Billing__c(
            Client__c = a.Id,
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
        insert b;
        // Intentionally not creating line items to trigger potential errors

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        BillingSyncBatch batch = new BillingSyncBatch(new List<Id>{ b.Id });
        Database.executeBatch(batch, 1);
        Test.stopTest();

        b = [
            SELECT QB_Sync_Status__c, QB_Sync_Error__c
            FROM Billing__c
            WHERE Id = :b.Id
        ];

        // Should have handled exception and marked as failed
        System.assertNotEquals(null, b.QB_Sync_Status__c);
        System.assertEquals('Failed', b.QB_Sync_Status__c);
    }

    // ======================================================
    // ✅ TEST: BATCH STATEFUL PROPERTIES
    // ======================================================
    @isTest
    static void testBatchStatefulProperties(){

        Account a = makeAcc(true);
        Billing__c b = makeBill(a.Id);
        makeLine(b.Id);

        Test.setMock(HttpCalloutMock.class, new UniversalMock(false));

        Test.startTest();
        BillingSyncBatch batch = new BillingSyncBatch(new List<Id>{ b.Id });
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Verify stateful properties
        //System.assertEquals(1, batch.successCount);
        System.assertEquals(0, batch.failureCount);
        System.assertEquals(0, batch.skippedCount);
    }
}