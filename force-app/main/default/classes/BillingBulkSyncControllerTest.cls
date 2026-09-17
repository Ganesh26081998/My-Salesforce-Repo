@isTest
public class BillingBulkSyncControllerTest {

    // ---------- Utility: Create dummy records ----------
    private static List<Account> createAccounts() {
        List<Account> accList = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accList.add(new Account(Name = 'Test Account ' + i));
        }
        insert accList;
        return accList;
    }

    // ---------- Test: syncSelected ----------
    @isTest
    static void testSyncSelected() {

        List<Account> accList = createAccounts();

        // Create StandardSetController
        ApexPages.StandardSetController ssc =
            new ApexPages.StandardSetController(accList);

        BillingBulkSyncController controller =
            new BillingBulkSyncController(ssc);

        Test.startTest();

        PageReference result = controller.syncSelected();

        Test.stopTest(); // 🔥 executes batch

        // Assertions
        System.assertEquals(true, controller.isProcessed, 'Should be processed');
        System.assert(controller.message.contains('Mass Sync Started'), 'Message should be set');
        System.assertEquals(null, result, 'Return should be null');
    }

    // ---------- Test: backToList ----------
    @isTest
    static void testBackToList() {

        List<Account> accList = createAccounts();

        ApexPages.StandardSetController ssc =
            new ApexPages.StandardSetController(accList);

        BillingBulkSyncController controller =
            new BillingBulkSyncController(ssc);

        Test.startTest();

        PageReference result = controller.backToList();

        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, result, 'Cancel should return a PageReference');
    }
}