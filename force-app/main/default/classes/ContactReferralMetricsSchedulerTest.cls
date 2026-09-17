@IsTest
private class ContactReferralMetricsSchedulerTest {

    @IsTest
    static void testSchedulerExecution() {

        Test.startTest();

        // Schedule the job
        String cronExp = '0 0 0 1 1 ? 2099';

        String jobId = System.schedule(
            'Test Contact Referral Metrics Scheduler',
            cronExp,
            new ContactReferralMetricsScheduler()
        );

        Test.stopTest();

        // Verify the scheduled job was created
        CronTrigger ct = [
            SELECT Id, CronJobDetail.Name, State
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals(
            'Test Contact Referral Metrics Scheduler',
            ct.CronJobDetail.Name
        );
    }
}