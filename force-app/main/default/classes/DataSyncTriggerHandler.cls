public with sharing class DataSyncTriggerHandler {
    public void onAfterInsert(List<Data_Sync_Job__c> newRecords, Map<Id, Data_Sync_Job__c> newRecordsMap) {
        // if any records are inserted with Status__c = 'Pending' then start the DataSyncQueable job.
        boolean startJob = false;
        for (Data_Sync_Job__c newRecord : newRecords) {
            if (newRecord.Status__c == 'Pending') {
                startJob = true;
                break;
            }
        }
        
        if (startJob){
            DataSyncQueable job = new DataSyncQueable(false);
            System.enqueueJob(job);
        }
    }
    public void onAfterUpdate(List<Data_Sync_Job__c> newRecords, List<Data_Sync_Job__c> oldRecords, Map<Id, Data_Sync_Job__c> newRecordsMap, Map<Id, Data_Sync_Job__c> oldRecordsMap) {
        
        // if any records just became 'Pending' then start the DataSyncQueable job.
        boolean startJob = false;
        for (Data_Sync_Job__c newRecord : newRecords) {
            if (newRecord.Status__c == 'Pending') {
                Data_Sync_Job__c oldRecord = oldRecordsMap.get(newRecord.Id);
                if (oldRecord.Status__c != 'Pending') {
                    startJob = true;
                    break;
                }
            }
        }
        if (startJob){
            DataSyncQueable job = new DataSyncQueable(false);
            System.enqueueJob(job);
        }
        
    }
}