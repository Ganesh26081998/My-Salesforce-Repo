@IsTest
private class ClientAccountTeamControllerTest {

    private static User createTestUser(String uniqueName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        String safeAlias = uniqueName.length() > 5 ? uniqueName.substring(0, 5) : uniqueName;

        User u = new User(
            FirstName = 'Test',
            LastName = uniqueName,
            Alias = safeAlias,
            Email = uniqueName + '@test.com',
            Username = uniqueName + DateTime.now().getTime() + '@test.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert u;
        return u;
    }

    @IsTest
    static void testGetClientUsers() {

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        User internalUser = createTestUser('internalUser');

        Client_User_Detail__c internalRecord = new Client_User_Detail__c(
            Client__c = acc.Id,
            User__c = internalUser.Id,
            Role__c = 'Primary Care Manager',
            Marketing_Attribution__c = 'Yes'
        );

        Client_User_Detail__c externalRecord = new Client_User_Detail__c(
            Client__c = acc.Id,
            External_User_Name__c = 'External User',
            External_User_Email__c = 'external@test.com',
            External_User_Phone__c = '9999999999',
            Role__c = 'Secondary Care Manager',
            Marketing_Attribution__c = 'No'
        );

        insert new List<Client_User_Detail__c>{ internalRecord, externalRecord };

        Test.startTest();
        List<List<Client_User_Detail__c>> result =
            ClientAccountTeamController.getClientUsers(acc.Id);
        Test.stopTest();

        System.assertEquals(2, result.size());
        System.assertEquals(1, result[0].size());
        System.assertEquals(1, result[1].size());
    }

    @IsTest
    static void testSearchInternalUsers() {

        createTestUser('searchUser');

        Test.startTest();
        List<User> users =
            ClientAccountTeamController.searchInternalUsers('Test');
        Test.stopTest();

        System.assert(users.size() > 0);
    }

    @IsTest
    static void testSaveClientUser_InternalCreate() {

        Account acc = new Account(Name = 'Internal Create');
        insert acc;

        User u = createTestUser('internalCreate');

        Test.startTest();
        ClientAccountTeamController.saveClientUser(
            acc.Id,
            u.Id,
            null,
            null,
            null,
            'Primary Care Manager',
            'Yes',
            null
        );
        Test.stopTest();

        List<Client_User_Detail__c> records = [
            SELECT Id, User__c
            FROM Client_User_Detail__c
            WHERE Client__c = :acc.Id
        ];

        System.assertEquals(1, records.size());
        System.assertEquals(u.Id, records[0].User__c);
    }

    @IsTest
    static void testSaveClientUser_ExternalCreate() {

        Account acc = new Account(Name = 'External Create');
        insert acc;

        Test.startTest();
        ClientAccountTeamController.saveClientUser(
            acc.Id,
            null,
            'External User',
            'external@test.com',
            '8888888888',
            'Secondary Care Manager',
            'No',
            null
        );
        Test.stopTest();

        List<Client_User_Detail__c> records = [
            SELECT Id, External_User_Name__c
            FROM Client_User_Detail__c
            WHERE Client__c = :acc.Id
        ];

        System.assertEquals(1, records.size());
        System.assertEquals('External User', records[0].External_User_Name__c);
    }

    @IsTest
    static void testSaveClientUser_Update() {

        Account acc = new Account(Name = 'Update Account');
        insert acc;

        User u = createTestUser('updateUser');

        Client_User_Detail__c record = new Client_User_Detail__c(
            Client__c = acc.Id,
            User__c = u.Id,
            Role__c = 'Primary Care Manager',
            Marketing_Attribution__c = 'Yes'
        );
        insert record;

        Test.startTest();
        ClientAccountTeamController.saveClientUser(
            acc.Id,
            u.Id,
            null,
            null,
            null,
            'Secondary Care Manager',
            'No',
            record.Id
        );
        Test.stopTest();

        Client_User_Detail__c updated = [
            SELECT Role__c, Marketing_Attribution__c
            FROM Client_User_Detail__c
            WHERE Id = :record.Id
        ];

        System.assertEquals('Secondary Care Manager', updated.Role__c);
        System.assertEquals('No', updated.Marketing_Attribution__c);
    }

    @IsTest
    static void testDuplicateInternalUserException() {

        Account acc = new Account(Name = 'Duplicate Test');
        insert acc;

        User u = createTestUser('duplicateUser');

        Client_User_Detail__c existing = new Client_User_Detail__c(
            Client__c = acc.Id,
            User__c = u.Id,
            Role__c = 'Primary Care Manager',
            Marketing_Attribution__c = 'Yes'
        );
        insert existing;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ClientAccountTeamController.saveClientUser(
                acc.Id,
                u.Id,
                null,
                null,
                null,
                'Primary Care Manager',
                'Yes',
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
           
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testSaveClientUser_ClientIdNullException() {

        Test.startTest();
        try {
            ClientAccountTeamController.saveClientUser(
                null,
                null,
                null,
                null,
                null,
                'Primary Care Manager',
                'Yes',
                null
            );
            System.assert(false, 'Expected exception not thrown');
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveClientUser_NoUserException() {

        Account acc = new Account(Name = 'No User');
        insert acc;

        Test.startTest();
        try {
            ClientAccountTeamController.saveClientUser(
                acc.Id,
                null,
                '',
                '',
                '',
                'Primary Care Manager',
                'Yes',
                null
            );
            System.assert(false, 'Expected exception not thrown');
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testDeleteClientUser() {

        Account acc = new Account(Name = 'Delete Account');
        insert acc;

        Client_User_Detail__c record = new Client_User_Detail__c(
            Client__c = acc.Id,
            External_User_Name__c = 'Delete Me',
            Role__c = 'Secondary Care Manager',
            Marketing_Attribution__c = 'No'
        );
        insert record;

        Test.startTest();
        ClientAccountTeamController.deleteClientUser(record.Id);
        Test.stopTest();

        Integer countRecords = [
            SELECT COUNT()
            FROM Client_User_Detail__c
            WHERE Id = :record.Id
        ];

        System.assertEquals(0, countRecords);
    }

    @IsTest
    static void testDeleteClientUser_NullIdException() {

        Test.startTest();
        try {
            ClientAccountTeamController.deleteClientUser(null);
            System.assert(false, 'Expected exception not thrown');
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }
}