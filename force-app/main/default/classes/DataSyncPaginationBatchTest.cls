@IsTest
public class DataSyncPaginationBatchTest {
    @TestSetup
    static void setupData() {
        Data_Sync_Job__c pendingJob = new Data_Sync_Job__c(
            Status__c = 'Pending',
            Response__c = null
        );
        insert pendingJob;
    }

    @IsTest
    static void testBatchProcessMultiplePages() {
        Data_Sync_Job__c pendingJob = [SELECT Id FROM Data_Sync_Job__c LIMIT 1];
        Integer pageCount = 1;
        Integer totalPage = 3;
        DataSyncProcessRecordsPaginationBatch batch = new DataSyncProcessRecordsPaginationBatch(pageCount, totalPage, pendingJob);

        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql);

        List<Data_Sync_Job__c> syncJobList = new List<Data_Sync_Job__c> { pendingJob };
        batch.execute(null, syncJobList);

        batch.finish(null);
        Test.stopTest();
        Data_Sync_Job__c completedJob = [SELECT Status__c FROM Data_Sync_Job__c WHERE Id = :pendingJob.Id];
        System.assertEquals('Complete', completedJob.Status__c, 'The Data_Sync_Job__c status should be marked as Complete after all pages are processed.');
    }  
}