/*public with sharing class BillingSyncLWCController {

    @AuraEnabled
    public static void syncSelectedBillings(List<Id> billingIds) {

        if (billingIds == null || billingIds.isEmpty()) {
            throw new AuraHandledException(
                'Please select at least one record.'
            );
        }

        Database.executeBatch(
            new BillingSyncBatch(billingIds),
            30
        );
    }
}*/
public with sharing class BillingSyncLWCController {

    @AuraEnabled
    public static Id syncSelectedBillings(List<Id> billingIds) {

        if (billingIds == null || billingIds.isEmpty()) {
            throw new AuraHandledException(
                'Please select at least one record.'
            );
        }

        Id jobId = Database.executeBatch(
            new BillingSyncBatch(billingIds),
            1
        );

        return jobId;
    }

    @AuraEnabled(cacheable=false)
    public static String getBatchStatus(Id jobId){

        AsyncApexJob job = [
            SELECT Status
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        return job.Status;
    }
}