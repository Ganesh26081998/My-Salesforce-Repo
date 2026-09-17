@isTest
public class DataSyncQueableTest {
    
    @isTest
    static void testExecuteWithoutContinuation() {
        Data_Sync_Job__c job = new Data_Sync_Job__c();
        job.Status__c = 'Pending';
        job.External_System__c = 'TestSystem';
        job.Retry_Attempts__c = null;

        Test.startTest();
        
        DataSyncQueable queueableJob = new DataSyncQueable(false);
        System.enqueueJob(queueableJob);
        
        Test.stopTest();

    }

    @isTest
    static void testExecuteWithExistingJob() {
        Data_Sync_Job__c existingJob = new Data_Sync_Job__c();
        existingJob.Status__c = 'Retry';
        insert existingJob;

        AsyncApexJob job = new AsyncApexJob();


        Test.startTest();
        
        DataSyncQueable queueableJob = new DataSyncQueable(false);
        System.enqueueJob(queueableJob);
        
        Test.stopTest();

        existingJob = [SELECT Status__c FROM Data_Sync_Job__c WHERE Id = :existingJob.Id];
    }

    @isTest
    static void testExecuteWithError() {
        Data_Sync_Job__c job = new Data_Sync_Job__c();
        job.Status__c = 'Pending';
        job.External_System__c = 'TestSystem';

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGeneratorError());
        
        DataSyncQueable queueableJob = new DataSyncQueable(false);
        System.enqueueJob(queueableJob);
        
        Test.stopTest();

    }

    public class MockHttpResponseGeneratorError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(500); 
            return res;
        }
    }

}