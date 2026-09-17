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

public with sharing class BulkBillingSyncController {
	@AuraEnabled
    public static String startBatchSync(Date startDate,
                                        Date endDate,
                                        List<String> locations) {

        System.debug('===== LWC Batch Start =====');
        System.debug('Start Date: ' + startDate);
        System.debug('End Date: ' + endDate);
        System.debug('Locations: ' + locations);
	
		// Convert Date → DateTime
        Datetime startDateTime;
        Datetime endDateTime;
                                            
        if(startDate != null){
            startDateTime = Datetime.newInstance(startDate, Time.newInstance(0,0,0,0));
        }

        if(endDate != null){
            endDateTime = Datetime.newInstance(endDate, Time.newInstance(23,59,59,999));
        }

        // Validation
        if(startDateTime != null && endDateTime != null && startDateTime > endDateTime){
            throw new AuraHandledException('Start Date cannot be greater than End Date');
        }

        BillingSyncBatch batch =
        new BillingSyncBatch(startDateTime, endDateTime, locations);

        Id batchId = Database.executeBatch(batch, 1);

        System.debug('Batch Job Id: ' + batchId);

        return 'Mass Sync Started! The system is processing ALL pending records in the background. ' + 
               'Because we are processing 5 record at a time to ensure safety, this may take a while. ' +
               'You can close this tab and check back later.'; //Job Id: ' + batchId;
    }
}