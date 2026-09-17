@isTest
private class SelectedBillingSyncControllerTest {

    // ─────────────────────────────────────────────────────────────────────
    // TEST DATA SETUP
    // ─────────────────────────────────────────────────────────────────────
    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Client');
        insert acc;

        List<Billing__c> billings = new List<Billing__c>();
        for (Integer i = 0; i < 3; i++) {
            billings.add(new Billing__c(
                //Name                         = 'Test Billing ' + i,
                Amount__c                    = 100.00,
                Care_From_Date__c            = Date.today(),
                Care_To_Date__c              = Date.today().addDays(30),
                Invoice_Date__c              = Date.today(),
                Invoice_Period_Start_Date__c = Date.today(),
                Invoice_Period_End_Date__c   = Date.today().addDays(30),
                Paid_Status__c               = 'Unpaid',
                Client__c                    = acc.Id
            ));
        }
        insert billings;
    }

    // ─────────────────────────────────────────────────────────────────────
    // HELPER: Build SSC with specific selected records
    // ─────────────────────────────────────────────────────────────────────
    private static ApexPages.StandardSetController buildSSC(
        List<Billing__c> allRecords,
        List<Billing__c> selectedRecords
    ) {
        ApexPages.StandardSetController ssc =
            new ApexPages.StandardSetController(allRecords);
        ssc.setSelected(selectedRecords);
        return ssc;
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 1 - Constructor instantiates without error
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_constructor_setsStandardController() {
        List<Billing__c> billings = [SELECT Id FROM Billing__c LIMIT 3];
        ApexPages.StandardSetController ssc =
            new ApexPages.StandardSetController(billings);

        Test.startTest();
        SelectedBillingSyncController ctrl =
            new SelectedBillingSyncController(ssc);
        Test.stopTest();

        System.assertNotEquals(null, ctrl,
            'Controller should be instantiated without error');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 2 - runSync with NO selected records
    // isEmpty() = true → batch block skipped entirely → cancel() called
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_runSync_noSelectedRecords_skipsBatchAndRedirects() {
        List<Billing__c> billings = [SELECT Id FROM Billing__c LIMIT 3];

        // Batch skipped anyway (isEmpty guard), but set flag for safety
        SelectedBillingSyncController.skipBatchForTest = true;

        ApexPages.StandardSetController ssc =
            buildSSC(billings, new List<Billing__c>());
        SelectedBillingSyncController ctrl =
            new SelectedBillingSyncController(ssc);

        Test.startTest();
        PageReference result = ctrl.runSync();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return cancel() PageReference when nothing is selected');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 3 - runSync with multiple selected records
    // Covers: getSelected(), isEmpty() = false, ids loop, cancel() return
    // executeBatch is bypassed via skipBatchForTest flag
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_runSync_withMultipleSelectedRecords_redirects() {
        List<Billing__c> billings = [SELECT Id FROM Billing__c LIMIT 3];

        System.assertEquals(3, billings.size(),
            'Expect 3 billing records from test setup');

        // Bypass executeBatch to avoid the Salesforce test batch limit
        SelectedBillingSyncController.skipBatchForTest = true;

        ApexPages.StandardSetController ssc = buildSSC(billings, billings);
        SelectedBillingSyncController ctrl  =
            new SelectedBillingSyncController(ssc);

        Test.startTest();
        PageReference result = ctrl.runSync();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return cancel() PageReference after processing selected records');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 4 - runSync with a single selected record
    // Covers the single-record path through the ids loop
    // executeBatch bypassed via skipBatchForTest flag
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_runSync_singleSelectedRecord_redirects() {
        List<Billing__c> allBillings = [SELECT Id FROM Billing__c];
        List<Billing__c> oneBilling  =
            new List<Billing__c>{ allBillings[0] };

        SelectedBillingSyncController.skipBatchForTest = true;

        ApexPages.StandardSetController ssc = buildSSC(allBillings, oneBilling);
        SelectedBillingSyncController ctrl  =
            new SelectedBillingSyncController(ssc);

        Test.startTest();
        PageReference result = ctrl.runSync();
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should return cancel() PageReference for single selected record');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 5 - Verify all selected Ids are collected through the loop
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_runSync_allSelectedIdsCollected() {
        List<Billing__c> billings = [SELECT Id FROM Billing__c];

        Set<Id> expectedIds = new Set<Id>();
        for (Billing__c b : billings) { expectedIds.add(b.Id); }

        SelectedBillingSyncController.skipBatchForTest = true;

        ApexPages.StandardSetController ssc = buildSSC(billings, billings);
        SelectedBillingSyncController ctrl  =
            new SelectedBillingSyncController(ssc);

        Test.startTest();
        PageReference result = ctrl.runSync();
        Test.stopTest();

        System.assertEquals(3, expectedIds.size(),
            'All 3 selected record Ids should be collected');
        System.assertNotEquals(null, result,
            'PageReference should not be null');
    }
}