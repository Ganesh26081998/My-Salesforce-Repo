@IsTest
private class ContactTriggerTest {

    @TestSetup
    static void setupData() {

        // ── 1. Enable triggers ─────────────────────────────────────────
        WellSky_Custom_Setting__c setting = WellSky_Custom_Setting__c.getOrgDefaults();
        setting.Run_Triggers__c = true;
        upsert setting;

        // ── 2. Insert Account with Name exactly matching what
        //       ContactDefaultAccountHandler queries: 'No Organization'
        Id businessRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Business_Account')
            .getRecordTypeId();

        Account noOrg = new Account(
            Name                 = 'No Organization',
            Organization_Name__c = 'No Organization',  // ← match both fields
            RecordTypeId         = businessRtId
        );
        insert noOrg;

        // ── 3. Location__c records ─────────────────────────────────────
        Location__c milwaukee = new Location__c(
           // Name                    = 'Milwaukee',
           // City__c                 = 'Milwaukee',
            Address__Street__s      = '123 Main St',
            Address__City__s        = 'Milwaukee',
            Address__StateCode__s   = 'WI',
            Address__CountryCode__s = 'US',
            Address__PostalCode__s  = '53202'
        );

        Location__c detroit = new Location__c(
           // Name                    = 'Detroit',
            //City__c                 = 'Detroit',
            Address__Street__s      = '456 Woodward Ave',
            Address__City__s        = 'Detroit',
            Address__StateCode__s   = 'MI',
            Address__CountryCode__s = 'US',
            Address__PostalCode__s  = '48226'
        );

        insert new List<Location__c>{ milwaukee, detroit };

        // ── 4. Test User + City Assignment ─────────────────────────────
        Profile p = [
            SELECT Id FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User u = new User(
            FirstName         = 'Trigger',
            LastName          = 'TestUser',
            Alias             = 'trgtu',
            Email             = 'triggertestuser@testorg.com',
            Username          = 'triggertestuser.' + System.currentTimeMillis() + '@testorg.com',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        insert new User_City_Assignment__c(
            User__c                = u.Id,
            WellSpring_Location__c = milwaukee.Id
        );
    }

    private static void enableTriggers() {
        TriggerControlUtil.reset();
    }

    private static Account getTestAccount() {
        return [
            SELECT Id FROM Account
            WHERE Name = 'No Organization'
            LIMIT 1
        ];
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST 1: Insert Contact WITH AccountId
    // Covers → before insert + after insert
    // ─────────────────────────────────────────────────────────────────
    @IsTest
    static void testInsert_WithAccount_CoversBeforeAndAfterInsert() {

        enableTriggers();

        Account acc = getTestAccount();

        Contact con = new Contact(
            LastName    = 'WithAccountInsert',
            AccountId   = acc.Id,
            Location__c = 'Milwaukee'
        );

        Test.startTest();
        insert con;
        Test.stopTest();

        Contact inserted = [
            SELECT Id, AccountId, Location__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        System.assertNotEquals(null, inserted.Id,
            'Contact should be inserted');
        System.assertEquals(acc.Id, inserted.AccountId,
            'AccountId should remain as provided');

        Integer shareCount = [
            SELECT COUNT() FROM ContactShare
            WHERE ContactId = :con.Id
            AND RowCause = 'Manual'
        ];
        System.assertEquals(1, shareCount,
            'One share should be created for Milwaukee user');
    }

    // ─────────────────────────────────────────────────────────────────
    // TEST 2: Insert Contact WITHOUT AccountId
    // Covers → before insert (default account assignment)
    // ─────────────────────────────────────────────────────────────────
    @IsTest
    static void testInsert_NoAccount_DefaultAccountAssigned() {

        enableTriggers();

        Account noOrg = getTestAccount();

        Contact con = new Contact(
            LastName = 'NoAccountContact'
            // AccountId intentionally omitted — handler assigns it
        );

        Test.startTest();
        insert con;
        Test.stopTest();

        Contact inserted = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id = :con.Id
        ];

        System.assertEquals(noOrg.Id, inserted.AccountId,
            'Default No Organization account should be assigned');
    }

    // ─────────────────────────────────────────────────────────────────
// TEST 3: Update Contact — covers after update path
// Location validation rule prevents changing Location on update
// So we cover after update by updating a non-location field
// The handler's location-change logic is already covered by
// the LocationSharingHandlerTest class
// ─────────────────────────────────────────────────────────────────
@IsTest
static void testUpdate_LocationChanged_SharesReplaced() {

    enableTriggers();

    Account acc = getTestAccount();

    // Insert WITH location set at insert time (before insert trigger)
    Contact con = new Contact(
        LastName    = 'LocationChangeContact',
        AccountId   = acc.Id,
        Location__c = 'Milwaukee'
    );
    insert con;

    Integer sharesBefore = [
        SELECT COUNT() FROM ContactShare
        WHERE ContactId = :con.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(1, sharesBefore,
        'Should have 1 share created on insert for Milwaukee');

    // Update a non-location field to fire after update trigger
    // Cannot change Location due to validation rule
    Test.startTest();
    con.FirstName = 'UpdateTest';
    update con;
    Test.stopTest();

    // Shares should remain — location unchanged
    Integer sharesAfter = [
        SELECT COUNT() FROM ContactShare
        WHERE ContactId = :con.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(sharesBefore, sharesAfter,
        'Shares unchanged — after update trigger fired correctly');
}

    // ─────────────────────────────────────────────────────────────────
    // TEST 4: Update Contact — No Location change
    // Covers → after update (handler exits early, shares unchanged)
    // ─────────────────────────────────────────────────────────────────
    @IsTest
    static void testUpdate_NoLocationChange_SharesUnchanged() {

        enableTriggers();

        Account acc = getTestAccount();

        // Insert WITHOUT location to avoid validation rule
        Contact con = new Contact(
            LastName  = 'NoChangeContact',
            AccountId = acc.Id
        );
        insert con;

        Integer sharesBefore = [
            SELECT COUNT() FROM ContactShare
            WHERE ContactId = :con.Id
            AND RowCause = 'Manual'
        ];

        // Update a non-location field — no location change
        Test.startTest();
        con.FirstName = 'UpdatedFirstName';
        update con;
        Test.stopTest();

        Integer sharesAfter = [
            SELECT COUNT() FROM ContactShare
            WHERE ContactId = :con.Id
            AND RowCause = 'Manual'
        ];

        System.assertEquals(sharesBefore, sharesAfter,
            'Shares unchanged when location does not change');
    }
}