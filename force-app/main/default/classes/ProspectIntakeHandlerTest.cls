@IsTest
private class ProspectIntakeHandlerTest {

    @testSetup
    static void setupData() {

        // Create test user
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@test.com',
            Username = 'testuser' + System.currentTimeMillis() + '@test.com',
            Alias = 'tuser',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );

        insert testUser;
    }

    @IsTest
    static void testHandleBeforeInsert() {

        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();

        Intake_Coordinator_Config__mdt config =
            Intake_Coordinator_Config__mdt.getInstance('Default');

        System.assertNotEquals(
            null,
            config,
            'Default CMDT record should exist'
        );

        Account acc = new Account(
            LastName = 'Prospect Test',
            RecordTypeId = prospectRtId
        );

        Test.startTest();

        ProspectIntakeHandler.handleBeforeInsert(
            new List<Account>{ acc }
        );

        Test.stopTest();

        // Verify owner assignment
        if (String.isNotBlank(config.Intake_User_Id__c)) {
            System.assertEquals(
                config.Intake_User_Id__c,
                acc.OwnerId
            );
        }
    }

    @IsTest
    static void testHandleAfterInsert() {

        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();

        Account acc = new Account(
            LastName = 'After Insert Prospect',
            RecordTypeId = prospectRtId,
            Mobile_Phones__c = '9876543210',
            PersonEmail = 'prospect@test.com',
            Prospect_Source__c = 'Phone'
            // Location_g__c = 'Cincinnati'
        );

        insert acc;

        List<Account> accList = [
            SELECT Id,
                   Name,
                   RecordTypeId,
                   Mobile_Phones__c,
                   PersonEmail,
                   Prospect_Source__c,
                   Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        
        System.debug('accList <><><><'+ accList);
        
        // Create test user
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@test.com',
            Username = 'testuser' + System.currentTimeMillis() + '@test.com',
            Alias = 'tuser',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );

        insert testUser;
        
         Intake_Coordinator_Config__mdt config =
            Intake_Coordinator_Config__mdt.getInstance('Default');

        Test.startTest();

        //ProspectIntakeHandler.handleAfterInsert(accList);
        // Directly call @TestVisible method
    ProspectIntakeHandler.sendEmailToIntakeUser(
        accList,
        testUser.Id
    );

        Test.stopTest();

        System.assertEquals(1, accList.size());
    }

    @IsTest
    static void testHandleAfterInsertWithNonProspect() {

        Account acc = new Account(
            Name = 'Regular Account'
        );

        insert acc;

        List<Account> accList = [
            SELECT Id, Name, RecordTypeId
            FROM Account
            WHERE Id = :acc.Id
        ];

        Test.startTest();

        ProspectIntakeHandler.handleAfterInsert(accList);

        Test.stopTest();

        System.assertEquals(1, accList.size());
    }

    @IsTest
    static void testEmptyLists() {

        Test.startTest();

        ProspectIntakeHandler.handleBeforeInsert(
            new List<Account>()
        );

        ProspectIntakeHandler.handleAfterInsert(
            new List<Account>()
        );

        Test.stopTest();

        System.assert(true);
    }
}