@IsTest
private class ContentDocumentTriggerTest {

    @IsTest
    static void testBeforeDelete() {
        
        WellSky_Custom_Setting__c cs = new WellSky_Custom_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Name = 'Bypass',
            Run_Triggers__c = true
        );
        insert cs;

        // Create Account
        Account acc = new Account(
            LastName = 'Test Client',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Prospect')
                .getRecordTypeId()
        );
        insert acc;

        // Create Assessment
        SecondaryAssessment__c assessment = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Caregiver Assessment',
            PDF_Generated__c = true
        );
        insert assessment;

        // Create File
        ContentVersion cv = new ContentVersion(
            Title = 'Test PDF',
            PathOnClient = 'Test.pdf',
            VersionData = Blob.valueOf('Dummy PDF'),
            IsMajorVersion = true
        );
        insert cv;

        // Get ContentDocument Id
        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        // Link File to Assessment
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = assessment.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        Test.startTest();

        delete [
            SELECT Id
            FROM ContentDocument
            WHERE Id = :cv.ContentDocumentId
        ];

        Test.stopTest();

        assessment = [
            SELECT PDF_Generated__c
            FROM SecondaryAssessment__c
            WHERE Id = :assessment.Id
        ];

        System.assertEquals(
            false,
            assessment.PDF_Generated__c,
            'PDF_Generated__c should be false after deleting the PDF.'
        );
    }
}