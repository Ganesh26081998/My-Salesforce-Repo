@IsTest
public class EventBillingControllerTest {

    @TestSetup
    static void setupData() {
        List<Event> events = new List<Event>();
        for (Integer i = 0; i < 5; i++) {
            Event e = new Event(
                Subject      = 'Test Event ' + i,
                StartDateTime = System.now().addDays(-i),
                EndDateTime   = System.now().addDays(-i).addHours(1),
                Status__c     = 'Completed'
            );
            events.add(e);
        }
        insert events;
    }

    // Test runJob() - normal execution with date range
    @IsTest
    static void testRunJob() {
        Date startDate = Date.today().addDays(-10);
        Date endDate   = Date.today();

        Test.startTest();
        String result = EventBillingController.runJob(startDate, endDate);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Job ID should be returned');
        System.assertNotEquals('ALREADY_RUNNING', result, 'Job should not be already running');
    }

    // Test runJob() with null dates
    @IsTest
    static void testRunJobWithNullDates() {
        Test.startTest();
        String result = EventBillingController.runJob(null, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Job ID should be returned even with null dates');
        System.assertNotEquals('ALREADY_RUNNING', result);
    }

    // Test runJob() when already running (covers isJobRunning = TRUE)
    @IsTest
    static void testRunJobAlreadyRunning() {
        Test.startTest();
        // Enqueue one job first so isJobRunning() returns true
        System.enqueueJob(new EventBillingQueueable());
        // Call runJob() while a job is still queued
        String result = EventBillingController.runJob(Date.today().addDays(-5), Date.today());
        Test.stopTest();

        System.assertEquals('ALREADY_RUNNING', result, 'Should detect duplicate job');
    }

    // Test getJobStatus() with a valid job ID
    @IsTest
    static void testGetJobStatus() {
        Test.startTest();
        Id jobId = System.enqueueJob(new EventBillingQueueable());
        Test.stopTest();

        EventBillingController.JobStatusWrapper wrap =
            EventBillingController.getJobStatus(jobId);

        System.assertNotEquals(null, wrap,            'Wrapper should not be null');
        System.assertNotEquals(null, wrap.status,     'Status should not be null');
        System.assertNotEquals(null, wrap.createdDate,'CreatedDate should not be null');
    }

    // Test getJobStatus() with null — should return null safely
    @IsTest
    static void testGetJobStatusNull() {
        EventBillingController.JobStatusWrapper wrap =
            EventBillingController.getJobStatus(null);

        System.assertEquals(null, wrap, 'Null jobId should return null wrapper');
    }

    // Test getPendingBillingEvents() without date filters
    @IsTest
    static void testGetPendingBillingEventsNoFilter() {
        Test.startTest();
        List<Event> result = EventBillingController.getPendingBillingEvents(10, 0, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result list should not be null');
    }

    // Test getPendingBillingEvents() with date filters
    @IsTest
    static void testGetPendingBillingEventsWithDates() {
        Date startDate = Date.today().addDays(-10);
        Date endDate   = Date.today();

        Test.startTest();
        List<Event> result = EventBillingController.getPendingBillingEvents(
            10, 0, startDate, endDate
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result list should not be null');
    }

    // Test getPendingBillingEvents() with only startDate
    @IsTest
    static void testGetPendingBillingEventsOnlyStartDate() {
        Test.startTest();
        List<Event> result = EventBillingController.getPendingBillingEvents(
            10, 0, Date.today().addDays(-5), null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result list should not be null');
    }

    // Test getPendingBillingEvents() with only endDate
    @IsTest
    static void testGetPendingBillingEventsOnlyEndDate() {
        Test.startTest();
        List<Event> result = EventBillingController.getPendingBillingEvents(
            10, 0, null, Date.today()
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result list should not be null');
    }
}