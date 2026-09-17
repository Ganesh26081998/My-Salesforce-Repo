/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : BillingBulkSyncController
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : it is the "bridge" that connects a screen (like a Lightning Web Component or a custom button) 
			    to your background Apex code.
----------------------------------------------------------------------------
*/

public class BillingBulkSyncController {
    
    private ApexPages.StandardSetController standardController;
    public Boolean isProcessed {get; set;}
    public String message {get; set;}
    
    public BillingBulkSyncController(ApexPages.StandardSetController standardController) {
        this.standardController = standardController;
        this.isProcessed = false;
    }

    public PageReference syncSelected() {
        // We ignore the checkbox selection. We simply run the Batch for ALL pending records.
        
        // Execute Batch with Scope Size = 1
        // This means: "Process 100,000 records, but do them 1 at a time."
        BillingSyncBatch batchJob = new BillingSyncBatch();
        Database.executeBatch(batchJob, 1); 	

        isProcessed = true;
        message = 'Mass Sync Started! The system is processing ALL pending records in the background. ' + 
                  'Because we are processing 1 record at a time to ensure safety, this may take a while. ' +
                  'You can close this tab and check back later.';
        
        return null;
    }
    
    public PageReference backToList() {
        return standardController.cancel();
    }
}