@IsTest
public class EventBillingQueueableTest {

    
    @IsTest
    static void testQueueableExecution() {
        Test.startTest();
        Id jobId = System.enqueueJob(new EventBillingQueueable());
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, JobType
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        System.assertEquals('Queueable', job.JobType);
        System.assert(
            job.Status == 'Completed' || job.Status == 'Processing',
            'Job should be processed'
        );
    }

    
    @IsTest
    static void testQueueableWithDateRange() {
        Date startDate = Date.newInstance(2024, 1, 1);
        Date endDate   = Date.newInstance(2024, 3, 31);

        Test.startTest();
        Id jobId = System.enqueueJob(new EventBillingQueueable(startDate, endDate));
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, JobType
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        System.assertEquals('Queueable', job.JobType);
        System.assert(
            job.Status == 'Completed' || job.Status == 'Processing',
            'Job with date range should be processed'
        );
    }

    
    @IsTest
    static void testQueueableWithNullDates() {
        Test.startTest();
        Id jobId = System.enqueueJob(new EventBillingQueueable(null, null));
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, JobType
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        System.assertEquals('Queueable', job.JobType);
        System.assert(
            job.Status == 'Completed' || job.Status == 'Processing',
            'Job with null dates should be processed'
        );
    }
}