/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : BulkZipBatch
CreatedOn      : 07-5-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This batch class is used to collect ContentVersion records
                 for generated invoice PDF files and prepare a combined bulk
                 download URL for ZIP processing. It updates the bulk job
                 status and stores the generated download link for UI access.
----------------------------------------------------------------------------
*/
global class BulkZipBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Id jobRecordId;
    private String fromDateStr;
    private String toDateStr;
    private String invoiceType;

    private List<Id> cvIds;
    private Set<Id> allCVIds;

    private String batchError;

    global BulkZipBatch(
        Id       jobRecordId,
        List<Id> cvIds,
        String   fromDateStr,
        String   toDateStr,
        String   invoiceType
    ) {
        this.jobRecordId = jobRecordId;
        this.fromDateStr = fromDateStr;
        this.toDateStr   = toDateStr;
        this.invoiceType = invoiceType;
        this.allCVIds    = new Set<Id>();
        this.cvIds = cvIds != null ? cvIds : new List<Id>();      
    }

    // -------------------------------------------------------------------------
    global Database.QueryLocator start(Database.BatchableContext bc) {
         return Database.getQueryLocator([
            SELECT Id
            FROM ContentVersion
            WHERE Id IN :cvIds
        ]);
    }

    // -------------------------------------------------------------------------
    // No blobs loaded here — just collecting Ids into stateful list.
    // Safe to use a large scope since nothing heavy is happening.
    // -------------------------------------------------------------------------
    global void execute(Database.BatchableContext bc, List<SObject> records) {
        try {
            for (SObject record : records) {
                allCVIds.add((Id) record.get('Id'));
            }
        } catch (Exception ex) {
            batchError = ex.getMessage() + '\n' + ex.getStackTraceString();
        }
    }

    // -------------------------------------------------------------------------
    // finish() - build the servlet URL and store it on the job record.
    // No blobs. Just string concatenation.
    // -------------------------------------------------------------------------
    global void finish(Database.BatchableContext bc) {
        if (String.isNotBlank(batchError)) {
            markJobFailed(batchError);
            return;
        }

        if (allCVIds.isEmpty()) {
            markJobFailed('No ContentVersion Ids were collected.');
            return;
        }

        // Build: /sfc/servlet.shepherd/version/download/ID1/ID2/ID3?
        List<String> idStrings = new List<String>();

        for (Id cvId : allCVIds) {
            idStrings.add(String.valueOf(cvId));
        }

        String idPath = String.join(idStrings, '/');

        String downloadUrl = '/sfc/servlet.shepherd/version/download/' + idPath + '?';        

        update new Bulk_Zip_Job__c(
            Id               = jobRecordId,
            Status__c        = 'Completed',
            Error_Message__c = downloadUrl   // LWC reads this as the download URL
        );
        
    }    

    // -------------------------------------------------------------------------
    private void markJobFailed(String errorMsg) {
        try {
            update new Bulk_Zip_Job__c(
                Id               = jobRecordId,
                Status__c        = 'Failed',
                Error_Message__c = errorMsg
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,'markJobFailed: ' + e.getMessage());
        }
    }
}