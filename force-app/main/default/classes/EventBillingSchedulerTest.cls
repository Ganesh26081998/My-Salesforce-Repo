@IsTest
private class EventBillingSchedulerTest {

    // ---------------------------------------------------------------------
    // Test : Scheduler Execution
    // ---------------------------------------------------------------------
    @IsTest
    static void testSchedulerExecution() {

        Test.startTest();

        String cronExp = '0 0 0 1 1 ? 2099';

        System.schedule(
            'Test Event Billing Scheduler',
            cronExp,
            new EventBillingScheduler()
        );

        Test.stopTest();

        CronTrigger ct = [
            SELECT Id,
                   CronJobDetail.Name,
                   State
            FROM CronTrigger
            WHERE CronJobDetail.Name =
                'Test Event Billing Scheduler'
            LIMIT 1
        ];

        System.assertEquals(
            'WAITING',
            ct.State
        );
    }
}