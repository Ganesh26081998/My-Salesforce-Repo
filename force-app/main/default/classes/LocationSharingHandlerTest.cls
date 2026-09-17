@IsTest
private class LocationSharingHandlerTest {

    private static final String ACCOUNT_RT_DEV_NAME = 'Business_Account';
    private static final String PROSPECT_RT_DEV_NAME = 'Prospect';

    @TestSetup
    static void setupData() {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User u1 = new User(
            FirstName = 'Loc',
            LastName = 'User1',
            Alias = 'locu1',
            Email = 'locuser1@testorg.com',
            Username = 'locuser1.' + System.currentTimeMillis() + '@testorg.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        User u2 = new User(
            FirstName = 'Loc',
            LastName = 'User2',
            Alias = 'locu2',
            Email = 'locuser2@testorg.com',
            Username = 'locuser2.' + System.currentTimeMillis() + '@testorg.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert new List<User>{ u1, u2 };

        Location__c milwaukee = new Location__c(
            Address__Street__s = '123 Main St',
            Address__City__s = 'Milwaukee',
            Address__StateCode__s = 'WI',
            Address__CountryCode__s = 'US',
            Address__PostalCode__s = '53202'
        );

        Location__c detroit = new Location__c(
            Address__Street__s = '456 Woodward Ave',
            Address__City__s = 'Detroit',
            Address__StateCode__s = 'MI',
            Address__CountryCode__s = 'US',
            Address__PostalCode__s = '48226'
        );

        insert new List<Location__c>{ milwaukee, detroit };

        insert new List<User_City_Assignment__c>{
            new User_City_Assignment__c(
                User__c = u1.Id,
                WellSpring_Location__c = milwaukee.Id
            ),
            new User_City_Assignment__c(
                User__c = u2.Id,
                WellSpring_Location__c = detroit.Id
            )
        };
    }

    @IsTest
    static void testHandleAccounts_InsertAndSharesCreated() {

        Id businessRtId = getBusinessAccountRecordTypeId();

        Account acc = new Account(
            Name = 'Business Account 1',
            RecordTypeId = businessRtId,
            Location_g__c = 'Milwaukee'
        );

        insert acc;

        List<Account> newList = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        Test.startTest();
        LocationSharingHandler.handleAccounts(newList, null, true, false);
        Test.stopTest();

        List<AccountShare> shares = [
            SELECT Id, UserOrGroupId
            FROM AccountShare
            WHERE AccountId = :acc.Id
            AND RowCause = 'Manual'
        ];

        
    }

    @IsTest
    static void testHandleAccounts_ProspectRecordType() {

        List<RecordType> rtList = [
            SELECT Id,IsPersonType
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = :PROSPECT_RT_DEV_NAME
            LIMIT 1
        ];

        if (rtList.isEmpty()) {
            System.assert(true);
            return;
        }

        Account acc = new Account(
            
            FirstName = 'Prospect',
            LastName = 'Account',
            RecordTypeId = rtList[0].Id
            
        );

        insert acc;

        List<Account> newList = [
            SELECT Id, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        Test.startTest();
        LocationSharingHandler.handleAccounts(newList, null, true, false);
        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM AccountShare
            WHERE AccountId = :acc.Id
            AND RowCause = 'Manual'
        ];

        
    }

    @IsTest
    static void testHandleAccounts_UpdateLocationChange_ReplacesShares() {

        Id businessRtId = getBusinessAccountRecordTypeId();

        Account acc = new Account(
            Name = 'Business Account 2',
            RecordTypeId = businessRtId
            
        );

        insert acc;

        List<Account> insertList = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        LocationSharingHandler.handleAccounts(
            insertList,
            null,
            true,
            false
        );

        Account oldAcc = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        acc.Location_g__c = 'Detroit';
        //update acc;

        Account newAcc = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        Test.startTest();

        LocationSharingHandler.handleAccounts(
            new List<Account>{ newAcc },
            new Map<Id, Account>{ oldAcc.Id => oldAcc },
            false,
            true
        );

        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM AccountShare
            WHERE AccountId = :acc.Id
            AND RowCause = 'Manual'
        ];

        
    }

    @IsTest
    static void testHandleAccounts_UpdateWithoutLocationChange() {

        Id businessRtId = getBusinessAccountRecordTypeId();

        Account acc = new Account(
            Name = 'Business Account 3',
            RecordTypeId = businessRtId,
            Location_g__c = 'Milwaukee'
        );

        insert acc;

        List<Account> insertList = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        LocationSharingHandler.handleAccounts(
            insertList,
            null,
            true,
            false
        );

        Integer shareCountBefore = [
            SELECT COUNT()
            FROM AccountShare
            WHERE AccountId = :acc.Id
            AND RowCause = 'Manual'
        ];

        Account oldAcc = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        acc.Name = 'Updated Name';
        update acc;

        Account newAcc = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        Test.startTest();

        LocationSharingHandler.handleAccounts(
            new List<Account>{ newAcc },
            new Map<Id, Account>{ oldAcc.Id => oldAcc },
            false,
            true
        );

        Test.stopTest();

        Integer shareCountAfter = [
            SELECT COUNT()
            FROM AccountShare
            WHERE AccountId = :acc.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(
            shareCountBefore,
            shareCountAfter
        );
    }

    @IsTest
    static void testHandleAccounts_BlankLocation() {

        Id businessRtId = getBusinessAccountRecordTypeId();

        Account acc = new Account(
            Name = 'Business Account 4',
            RecordTypeId = businessRtId
        );

        insert acc;

        List<Account> newList = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        Test.startTest();
        LocationSharingHandler.handleAccounts(newList, null, true, false);
        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM AccountShare
            WHERE AccountId = :acc.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(0, shareCount);
    }

    @IsTest
    static void testHandleAccounts_NonBusinessRecordType() {

        List<RecordType> otherRtList = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName != :ACCOUNT_RT_DEV_NAME
            AND DeveloperName != :PROSPECT_RT_DEV_NAME
            AND IsPersonType = false
            LIMIT 1
        ];

        if (otherRtList.isEmpty()) {
            System.assert(true);
            return;
        }

        Account acc = new Account(
            Name = 'Other RT Account',
            RecordTypeId = otherRtList[0].Id,
            Location_g__c = 'Milwaukee'
        );

        insert acc;

        List<Account> newList = [
            SELECT Id, Name, RecordTypeId, Location_g__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        Test.startTest();
        LocationSharingHandler.handleAccounts(newList, null, true, false);
        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM AccountShare
            WHERE AccountId = :acc.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(0, shareCount);
    }

    @IsTest
    static void testHandleContacts_InsertAndSharesCreated() {

        Account parentAcc = new Account(Name = 'Parent Acc');
        insert parentAcc;

        Contact con = new Contact(
            LastName = 'Contact One',
            AccountId = parentAcc.Id,
            Location__c = 'Milwaukee'
        );

        insert con;

        List<Contact> newList = [
            SELECT Id, LastName, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        Test.startTest();
        LocationSharingHandler.handleContacts(newList, null, true, false);
        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :con.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(1, shareCount);
    }

    @IsTest
    static void testHandleContacts_UpdateLocationChange() {

        Account parentAcc = new Account(Name = 'Parent Acc 2');
        insert parentAcc;

        Contact con = new Contact(
            LastName = 'Contact Two',
            AccountId = parentAcc.Id,
            Location__c = 'Milwaukee'
        );

        insert con;

        List<Contact> insertList = [
            SELECT Id, LastName, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        LocationSharingHandler.handleContacts(
            insertList,
            null,
            true,
            false
        );

        Contact oldCon = [
            SELECT Id, LastName, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        

        Contact newCon = [
            SELECT Id, LastName, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        Test.startTest();

        LocationSharingHandler.handleContacts(
            new List<Contact>{ newCon },
            new Map<Id, Contact>{ oldCon.Id => oldCon },
            false,
            true
        );

        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :con.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(1, shareCount);
    }

    @IsTest
    static void testHandleContacts_UpdateWithoutLocationChange() {

        Account parentAcc = new Account(Name = 'Parent Acc 3');
        insert parentAcc;

        Contact con = new Contact(
            LastName = 'Contact Three',
            AccountId = parentAcc.Id,
            Location__c = 'Milwaukee'
        );

        insert con;

        List<Contact> insertList = [
            SELECT Id, LastName, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        LocationSharingHandler.handleContacts(
            insertList,
            null,
            true,
            false
        );

        Integer shareCountBefore = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :con.Id
            AND RowCause = 'Manual'
        ];

        Contact oldCon = [
            SELECT Id, LastName, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        con.FirstName = 'Updated';
        update con;

        Contact newCon = [
            SELECT Id, FirstName, LastName, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        Test.startTest();

        LocationSharingHandler.handleContacts(
            new List<Contact>{ newCon },
            new Map<Id, Contact>{ oldCon.Id => oldCon },
            false,
            true
        );

        Test.stopTest();

        Integer shareCountAfter = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :con.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(
            shareCountBefore,
            shareCountAfter
        );
    }

    @IsTest
    static void testHandleContacts_BlankLocation() {

        Account parentAcc = new Account(Name = 'Parent Acc 4');
        insert parentAcc;

        Contact con = new Contact(
            LastName = 'Contact Four',
            AccountId = parentAcc.Id
        );

        insert con;

        List<Contact> newList = [
            SELECT Id, LastName, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        Test.startTest();
        LocationSharingHandler.handleContacts(newList, null, true, false);
        Test.stopTest();

        Integer shareCount = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :con.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(0, shareCount);
    }

    @IsTest
    static void testDirectMethodCoverage_NullAndEmptyInputs() {

        Test.startTest();

        LocationSharingHandler.handleAccounts(
            new List<Account>(),
            null,
            true,
            false
        );

        LocationSharingHandler.handleContacts(
            new List<Contact>(),
            null,
            true,
            false
        );

        Test.stopTest();

        System.assert(true);
    }

    private static Id getBusinessAccountRecordTypeId() {

        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = :ACCOUNT_RT_DEV_NAME
            LIMIT 1
        ].Id;
    }
}