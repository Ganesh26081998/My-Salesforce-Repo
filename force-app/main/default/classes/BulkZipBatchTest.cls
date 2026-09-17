@IsTest
private class BulkZipBatchTest {

    // ---------------------------------------------------------------------
    // Test Data Helpers
    // ---------------------------------------------------------------------

    private static Bulk_Zip_Job__c createJob() {

        Bulk_Zip_Job__c job = new Bulk_Zip_Job__c(
            Status__c = 'Processing'
        );

        insert job;

        return job;
    }

    private static ContentVersion createContentVersion() {

        ContentVersion cv = new ContentVersion(
            Title        = 'Test File',
            PathOnClient = 'TestFile.pdf',
            VersionData  = Blob.valueOf('Test Content')
        );

        insert cv;

        return [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
    }

    // ---------------------------------------------------------------------
    // TEST 1 : Successful Batch Execution
    // ---------------------------------------------------------------------

    @IsTest
    static void testBatchSuccess() {

        Bulk_Zip_Job__c job = createJob();

        ContentVersion cv1 = createContentVersion();
        ContentVersion cv2 = createContentVersion();

        Test.startTest();

        BulkZipBatch batch = new BulkZipBatch(
            job.Id,
            new List<Id>{ cv1.Id, cv2.Id },
            String.valueOf(Date.today()),
            String.valueOf(Date.today()),
            'Standard Invoice'
        );

        Database.executeBatch(batch, 50);

        Test.stopTest();

        Bulk_Zip_Job__c updatedJob = [
            SELECT Status__c, Error_Message__c
            FROM Bulk_Zip_Job__c
            WHERE Id = :job.Id
        ];

        System.assertEquals(
            'Completed',
            updatedJob.Status__c
        );

        System.assertNotEquals(
            null,
            updatedJob.Error_Message__c
        );

        System.assert(
            updatedJob.Error_Message__c.contains(
                '/sfc/servlet.shepherd/version/download/'
            )
        );
    }

    // ---------------------------------------------------------------------
    // TEST 2 : Empty ContentVersion Id List
    // ---------------------------------------------------------------------

    @IsTest
    static void testBatchNoContentVersions() {

        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        BulkZipBatch batch = new BulkZipBatch(
            job.Id,
            new List<Id>(),
            String.valueOf(Date.today()),
            String.valueOf(Date.today()),
            'Standard Invoice'
        );

        Database.executeBatch(batch, 50);

        Test.stopTest();

        Bulk_Zip_Job__c updatedJob = [
            SELECT Status__c, Error_Message__c
            FROM Bulk_Zip_Job__c
            WHERE Id = :job.Id
        ];

        System.assertEquals(
            'Failed',
            updatedJob.Status__c
        );

        System.assertEquals(
            'No ContentVersion Ids were collected.',
            updatedJob.Error_Message__c
        );
    }

    // ---------------------------------------------------------------------
    // TEST 3 : Null ContentVersion List
    // ---------------------------------------------------------------------

    @IsTest
    static void testBatchNullContentVersionList() {

        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        BulkZipBatch batch = new BulkZipBatch(
            job.Id,
            null,
            String.valueOf(Date.today()),
            String.valueOf(Date.today()),
            'Standard Invoice'
        );

        Database.executeBatch(batch, 50);

        Test.stopTest();

        Bulk_Zip_Job__c updatedJob = [
            SELECT Status__c
            FROM Bulk_Zip_Job__c
            WHERE Id = :job.Id
        ];

        System.assertEquals(
            'Failed',
            updatedJob.Status__c
        );
    }

    // ---------------------------------------------------------------------
    // TEST 4 : Duplicate ContentVersion Ids
    // Ensures Set<Id> removes duplicates safely
    // ---------------------------------------------------------------------

    @IsTest
    static void testBatchDuplicateIds() {

        Bulk_Zip_Job__c job = createJob();

        ContentVersion cv = createContentVersion();

        Test.startTest();

        BulkZipBatch batch = new BulkZipBatch(
            job.Id,
            new List<Id>{ cv.Id, cv.Id, cv.Id },
            String.valueOf(Date.today()),
            String.valueOf(Date.today()),
            'Standard Invoice'
        );

        Database.executeBatch(batch, 50);

        Test.stopTest();

        Bulk_Zip_Job__c updatedJob = [
            SELECT Status__c, Error_Message__c
            FROM Bulk_Zip_Job__c
            WHERE Id = :job.Id
        ];

        System.assertEquals(
            'Completed',
            updatedJob.Status__c
        );

        System.assertNotEquals(
            null,
            updatedJob.Error_Message__c
        );
    }
}