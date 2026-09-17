@isTest
private class ScheduledAccountMetricsTest {

    @isTest
    static void testSchedulableExecution() {
        // 1. Define a Cron expression for midnight execution
        String cronExp = '0 0 0 * * ?';

        Test.startTest();
        
        // 2. Schedule the job using System.schedule
        String jobId = System.schedule(
            'Test Nightly Metrics Sync Job', 
            cronExp, 
            new ScheduledAccountMetrics()
        );
        
        // Get the CronTrigger metadata record to verify it is scheduled correctly
        CronTrigger triggerRecord = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime 
            FROM CronTrigger 
            WHERE Id = :jobId
        ];
        
        System.assertEquals(cronExp, triggerRecord.CronExpression, 'The CRON expression does not match.');
        System.assertEquals(0, triggerRecord.TimesTriggered, 'Job fired prematurely.');

        Test.stopTest(); // Forces the asynchronous scheduled action to fire immediately

        // 3. Verify that the inner Batch Job was placed into the Apex execution queue
        AsyncApexJob[] batchJobs = [
            SELECT Id, JobType, Status, ApexClass.Name 
            FROM AsyncApexJob 
            WHERE JobType = 'BatchApex' AND ApexClass.Name = 'BusinessAccountMetricsBatch'
        ];

        System.assert(batchJobs.size() > 0, 'The BusinessAccountMetricsBatch job was not initiated by the schedule class.');
        System.assertEquals('Queued', batchJobs[0].Status, 'The batch job status is incorrect.');
    }
}