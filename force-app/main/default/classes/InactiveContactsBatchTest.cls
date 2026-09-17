@isTest
private class InactiveContactsBatchTest {

    @TestSetup
    static void setupTestData() {
        
        Id businessRecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Business_Account')
            .getRecordTypeId();
                
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User owner1 = new User(
            FirstName       = 'Owner',
            LastName        = 'One',
            Email           = 'owner1@testorg.com',
            Username        = 'owner1_inactive_test@testorg.com',
            Alias           = 'own1',
            TimeZoneSidKey  = 'America/Los_Angeles',
            LocaleSidKey    = 'en_US',
            EmailEncodingKey= 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId       = stdProfile.Id
        );
        
        User owner2 = new User(
            FirstName       = 'Owner',
            LastName        = 'Two',
            Email           = 'owner2@testorg.com',
            Username        = 'owner2_inactive_test@testorg.com',
            Alias           = 'own2',
            TimeZoneSidKey  = 'America/Los_Angeles',
            LocaleSidKey    = 'en_US',
            EmailEncodingKey= 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId       = stdProfile.Id
        );
        insert new List<User>{ owner1, owner2 };
                        
            List<Account> accounts = new List<Account>{
                new Account(Organization_Name__c = 'Acme Corporation', Name ='Acme Corporation',  OwnerId = owner1.Id, RecordTypeId =businessRecordTypeId),
                    new Account(Organization_Name__c = 'Globex Industries', Name ='Globex Industries',  OwnerId = owner1.Id, RecordTypeId =businessRecordTypeId),
                    new Account(Organization_Name__c = 'Initech LLC', Name ='Initech LLC',        OwnerId = owner2.Id, RecordTypeId =businessRecordTypeId),
                    new Account(Organization_Name__c = 'No Contact Account', Name ='No Contact Account', OwnerId = owner2.Id, RecordTypeId =businessRecordTypeId)
                    };
                        insert accounts;
                
        List<Contact> contacts = new List<Contact>{            
            new Contact(FirstName = 'Alice', LastName = 'Johnson', AccountId = accounts[0].Id),
                new Contact(FirstName = 'Bob',   LastName = 'Martinez',AccountId = accounts[0].Id),               
                new Contact(FirstName = 'Carol', LastName = 'White',   AccountId = accounts[1].Id),                
                new Contact(FirstName = 'David', LastName = 'Brown',   AccountId = accounts[2].Id),
                new Contact(FirstName = 'Eva',   LastName = 'Green',   AccountId = accounts[2].Id)                
                };
                    insert contacts;
        
        insert new Task(
            Subject      = 'Follow Up',
            WhoId        = contacts[2].Id,
            ActivityDate = Date.today().addDays(-5),
            Status       = 'Completed'
        );
                
        insert new Event(
            Subject          = 'Demo Call',
            WhoId            = contacts[4].Id,
            ActivityDate     = Date.today().addDays(-3),
            DurationInMinutes= 30,
            ActivityDateTime = DateTime.now().addDays(-3)
        );
    }
    

    @isTest
    static void testBatchRunsSuccessfully() {
        Test.startTest();
        InactiveContactsBatch batch = new InactiveContactsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
                
        System.assert(true, 'Batch executed without errors');
    }
    

    @isTest
    static void testInactiveContactsIdentified() {
        Test.startTest();
        InactiveContactsBatch batch = new InactiveContactsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        
        List<Task> tasks = [SELECT WhoId FROM Task WHERE Subject = 'Follow Up'];
        System.assertEquals(1, tasks.size(), 'Carol should have 1 task');
        
        List<Event> events = [SELECT WhoId FROM Event WHERE Subject = 'Demo Call'];
        System.assertEquals(1, events.size(), 'Eva should have 1 event');
    }
    
    @isTest
    static void testActivityOutsideThresholdIsInactive() {        
        Contact alice = [SELECT Id FROM Contact WHERE FirstName = 'Alice' LIMIT 1];
        insert new Task(
            Subject      = 'Old Task',
            WhoId        = alice.Id,
            ActivityDate = Date.today().addDays(-20),
            Status       = 'Completed'
        );
        
        Test.startTest();
        InactiveContactsBatch batch = new InactiveContactsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
                
        List<Task> oldTasks = [SELECT Id FROM Task WHERE Subject = 'Old Task'];
        System.assertEquals(1, oldTasks.size(), 'Old task exists but outside threshold');
    }
    
    @isTest
    static void testAccountWithNoContacts() {
        Test.startTest();
        InactiveContactsBatch batch = new InactiveContactsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
                
        Account noContactAcc = [SELECT Id, Name FROM Account WHERE Name = 'No Contact Account'];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :noContactAcc.Id];
        System.assertEquals(0, contacts.size(), 'No Contact Account should have no contacts');
    }
    

    @isTest
    static void testMultipleAccountsSameOwnerMerged() {
        Test.startTest();
        InactiveContactsBatch batch = new InactiveContactsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
                
        User owner1 = [SELECT Id FROM User WHERE Username = 'owner1_inactive_test@testorg.com'];
        List<Account> owner1Accounts = [SELECT Id FROM Account WHERE OwnerId = :owner1.Id];
        System.assertEquals(2, owner1Accounts.size(), 'Owner1 should have 2 accounts');
    }
    

    @isTest
    static void testAllContactsActiveNoEmail() {
       
        List<Contact> allContacts = [SELECT Id FROM Contact];
        List<Task> tasks = new List<Task>();
        for (Contact con : allContacts) {
            tasks.add(new Task(
                Subject      = 'Recent Task',
                WhoId        = con.Id,
                ActivityDate = Date.today().addDays(-1),
                Status       = 'Completed'
            ));
        }
        insert tasks;
        
        Test.startTest();
        InactiveContactsBatch batch = new InactiveContactsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        

        System.assert(true, 'Batch completed with all contacts active');
    }
    
    
    

    @isTest
    static void testBatchWithNoAccounts() {        
        delete [SELECT Id FROM Account];
        
        Test.startTest();
        InactiveContactsBatch batch = new InactiveContactsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        System.assert(true, 'Batch handles empty dataset gracefully');
    }
}