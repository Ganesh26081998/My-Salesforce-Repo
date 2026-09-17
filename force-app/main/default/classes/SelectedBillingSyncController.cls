/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : SelectedBillingSyncController
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : It captures the specific records you checkmark on a Salesforce List View 
                and passes them to the background batch job so you can manually sync multiple selected records at once.
----------------------------------------------------------------------------
*/

public class SelectedBillingSyncController {

    // Skips executeBatch when running in test context
    @TestVisible
    private static Boolean skipBatchForTest = false;

    private ApexPages.StandardSetController standardController;

    public SelectedBillingSyncController(ApexPages.StandardSetController ssc) {
        this.standardController = ssc;
    }

    public PageReference runSync() {
        List<Billing__c> selectedRecords =
            (List<Billing__c>) standardController.getSelected();

        if (!selectedRecords.isEmpty()) {
            List<Id> ids = new List<Id>();
            for (Billing__c b : selectedRecords) {
                ids.add(b.Id);
            }
            // Skip actual batch execution during unit tests
            if (!skipBatchForTest) {
                Database.executeBatch(new BillingSyncBatch(ids), 50);
            }
        }

        return standardController.cancel();
    }
}