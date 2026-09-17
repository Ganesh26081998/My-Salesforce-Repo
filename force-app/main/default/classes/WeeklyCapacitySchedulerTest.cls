@isTest
public class WeeklyCapacitySchedulerTest {

    @isTest
    static void testSchedulerExecution() {

        // Step 1: Create test user (Care Manager)
        User u = new User(
		FirstName = 'Test',
		LastName = 'User',
		Email = 'testuser@test.com',
		Username = 'testuser' + System.currentTimeMillis() + '@test.com',
		Alias = 'tuser',
		TimeZoneSidKey = 'Asia/Kolkata',
		LocaleSidKey = 'en_US',
		EmailEncodingKey = 'UTF-8',
		ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
		LanguageLocaleKey = 'en_US'
	);
	insert u;

        // Step 2: Create test Event (required for batch)
        Event e = new Event(
            Subject = 'Test Event',
            StartDateTime = System.now().addHours(1),
            EndDateTime = System.now().addHours(2),
            Care_Manager__c = u.Id
        );
        insert e;

        // Step 3: Schedule the job
        String cronExp = '0 0 0 1 1 ? 2050'; // future date

        Test.startTest();

        System.schedule('Test Weekly Capacity Scheduler', cronExp, new WeeklyCapacityScheduler());

        Test.stopTest();

        // Step 4: Validate job created
        List<CronTrigger> jobs = [
            SELECT Id, CronExpression, State 
            FROM CronTrigger 
            WHERE CronJobDetail.Name = 'Test Weekly Capacity Scheduler'
        ];

        System.assert(jobs.size() > 0, 'Scheduler job should be created');
    }
}