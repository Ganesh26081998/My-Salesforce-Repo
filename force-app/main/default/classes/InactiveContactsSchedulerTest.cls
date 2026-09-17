@isTest
private class InactiveContactsSchedulerTest {

    @isTest
    static void testSchedulerExecutes() {
        Test.startTest();
            InactiveContactsScheduler scheduler = new InactiveContactsScheduler();
            scheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Scheduler executed without errors');
    }


    @isTest
    static void testSchedulerCanBeScheduled() {
        String cronExp = '0 0 7 * * ?';
        String jobName = 'Test Inactive Contacts Job';

        Test.startTest();
            String jobId = System.schedule(jobName, cronExp, new InactiveContactsScheduler());
        Test.stopTest();
        
        CronTrigger ct = [
            SELECT Id, CronExpression, State, CronJobDetail.Name
            FROM   CronTrigger
            WHERE  Id = :jobId
        ];

        System.assertNotEquals(null, ct, 'Scheduled job should exist');
        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression should match');
        System.assertEquals(jobName, ct.CronJobDetail.Name, 'Job name should match');
    }

    @isTest
    static void testSchedulerTriggersBatch() {        
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User owner = new User(
            FirstName        = 'Sched',
            LastName         = 'Tester',
            Email            = 'schedtester@testorg.com',
            Username         = 'schedtester_inactive@testorg.com',
            Alias            = 'scht',
            TimeZoneSidKey   = 'America/Los_Angeles',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey= 'en_US',
            ProfileId        = stdProfile.Id
        );
        insert owner;

        System.runAs(owner) {
            Account acc = new Account(Name = 'Scheduler Test Account', OwnerId = owner.Id);
            insert acc;
            insert new Contact(FirstName = 'Sched', LastName = 'Contact', AccountId = acc.Id);
        }

        Test.startTest();
            String jobId = System.schedule(
                'Test Scheduler Triggers Batch',
                '0 0 7 * * ?',
                new InactiveContactsScheduler()
            );
        Test.stopTest();

        CronTrigger ct = [SELECT Id, State FROM CronTrigger WHERE Id = :jobId];
        System.assertNotEquals(null, ct.Id, 'Job should be scheduled');
    }


    @isTest
    static void testAbortAndRescheduleJob() {
        String cronExp = '0 0 7 * * ?';
        String jobName = 'Test Abort Reschedule Job';

        Test.startTest();            
            String firstJobId = System.schedule(jobName, cronExp, new InactiveContactsScheduler());
            
            System.abortJob(firstJobId);
            
            String secondJobId = System.schedule(jobName, cronExp, new InactiveContactsScheduler());
        Test.stopTest();

        CronTrigger ct = [
            SELECT Id FROM CronTrigger WHERE Id = :secondJobId
        ];
        System.assertNotEquals(null, ct, 'Rescheduled job should exist');
        System.assertNotEquals(firstJobId, secondJobId, 'New job Id should differ from aborted job');
    }
}