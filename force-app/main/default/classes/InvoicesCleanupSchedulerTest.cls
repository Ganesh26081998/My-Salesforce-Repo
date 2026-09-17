@IsTest
private class InvoicesCleanupSchedulerTest {
   
    @IsTest
    static void testSchedulerExecution() {

        Test.startTest();

        String cronExp = '0 0 0 1 1 ? 2099';

        System.schedule(
            'Test Invoices Cleanup Scheduler',
            cronExp,
            new InvoicesCleanupScheduler()
        );

        Test.stopTest();
        
        CronTrigger ct = [
            SELECT Id,
                   CronJobDetail.Name,
                   State
            FROM CronTrigger
            WHERE CronJobDetail.Name =
                'Test Invoices Cleanup Scheduler'
            LIMIT 1
        ];

        System.assertEquals(
            'WAITING',
            ct.State
        );
    }
}