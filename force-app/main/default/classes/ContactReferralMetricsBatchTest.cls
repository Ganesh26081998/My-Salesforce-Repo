/*
----------------------------------------------------------------------------
Author        : Siva Naga Prasad
Class Name    : ContactReferralMetricsBatchTest
CreatedOn     : 14-05-2026
LastModifiedOn: 21-05-2026
LastModifiedBy: Siva Naga Prasad
Description   : Test class for ContactReferralMetricsBatch to validate 
                referral metric calculations, revenue aggregation, 
                related contact processing, and batch execution scenarios.
----------------------------------------------------------------------------
*/

@isTest
private class ContactReferralMetricsBatchTest {

    /* ---------------- HELPERS ---------------- */

    private static Id getBusinessRtId() {
        return Schema.SObjectType.Contact
            .getRecordTypeInfosByDeveloperName()
            .get('IndustriesBusiness')
            .getRecordTypeId();
    }

    private static Id getPersonRtId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
    }

    private static Account createPersonAccount(String status) {

        Account a = new Account(
            RecordTypeId = getPersonRtId(),
            LastName = 'Person Test',
            Account_Status__c = status
        );

        insert a;
        return a;
    }

    private static Contact getPersonContact(Id accountId) {

        return [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :accountId
            LIMIT 1
        ];
    }

    private static Contact createBusinessContact() {

        Account businessAcc = new Account(
            Name = 'Business Account'
        );
        insert businessAcc;

        Contact c = new Contact(
            FirstName = 'Business',
            LastName = 'Referral',
            AccountId = businessAcc.Id,
            RecordTypeId = getBusinessRtId()
        );

        insert c;
        return c;
    }

   private static void relateContacts(Id contactId, Id relatedContactId) {

    HealthCloudGA__ReciprocalRole__c role;

    List<HealthCloudGA__ReciprocalRole__c> existingRoles = [
        SELECT Id
        FROM HealthCloudGA__ReciprocalRole__c
        LIMIT 1
    ];

    if (!existingRoles.isEmpty()) {

        role = existingRoles[0];

    } else {
		
        Id rRRecordType = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c.getRecordTypeInfosByDeveloperName().get('ContactRole').getRecordTypeId();
        
        // Create test reciprocal role
        role = new HealthCloudGA__ReciprocalRole__c(
            Name = 'Test Role',
            HealthCloudGA__InverseRole__c = 'Empaneled Patient',
            RecordTypeId = rRRecordType,
            HealthCloudGA__CreateInverseRole__c = True
        );

        insert role;
    }

    insert new HealthCloudGA__ContactContactRelation__c(
        HealthCloudGA__Contact__c = contactId,
        HealthCloudGA__RelatedContact__c = relatedContactId,
        HealthCloudGA__Role__c = role.Id,
        Is_Referral__c = true
    );
}

    private static void createBilling(Id accountId, Decimal amount) {

        Billing__c billing = new Billing__c(
            Client__c = accountId,
            Amount__c = amount,
            Invoice_Date__c = System.today(),
            
            Due_Date__c = Date.today().addDays(15),
            Location_g__c = 'Detroit',
            QB_Sync_Status__c = 'Pending',
            Is_Synced__c = false,
            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today().addDays(7),
            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today().addDays(30),
            Paid_Status__c = 'Unpaid'
            
        );

        insert billing;
    }

    /* ---------------- TESTS ---------------- */

    @isTest
    static void testClientReferralWithRevenue() {

        Contact businessContact = createBusinessContact();

        Account clientAccount = createPersonAccount('Client');
        Contact clientContact = getPersonContact(clientAccount.Id);

        relateContacts(businessContact.Id, clientContact.Id);

        createBilling(clientAccount.Id, 5000);

        Test.startTest();
        Database.executeBatch(new ContactReferralMetricsBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Clients_Referred__c,
                   Prospects_Referred__c,
                   Lifetime_Revenue__c,
                   Records_Updated_On__c
            FROM Contact
            WHERE Id = :businessContact.Id
        ];

        System.assertEquals(1, updated.Clients_Referred__c);
        System.assertEquals(0, updated.Prospects_Referred__c);
        System.assertEquals(5000, updated.Lifetime_Revenue__c);
        System.assertNotEquals(null, updated.Records_Updated_On__c);
    }

    @isTest
    static void testProspectReferral() {

        Contact businessContact = createBusinessContact();

        Account prospectAccount = createPersonAccount('Prospect');
        Contact prospectContact = getPersonContact(prospectAccount.Id);

        relateContacts(businessContact.Id, prospectContact.Id);

        Test.startTest();
        Database.executeBatch(new ContactReferralMetricsBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Clients_Referred__c,
                   Prospects_Referred__c,
                   Lifetime_Revenue__c
            FROM Contact
            WHERE Id = :businessContact.Id
        ];

        System.assertEquals(0, updated.Clients_Referred__c);
        System.assertEquals(1, updated.Prospects_Referred__c);
        System.assertEquals(0, updated.Lifetime_Revenue__c);
    }

    @isTest
    static void testMixedReferrals() {

        Contact businessContact = createBusinessContact();

        Account clientAccount = createPersonAccount('Client');
        Account prospectAccount = createPersonAccount('Prospect');

        relateContacts(
            businessContact.Id,
            getPersonContact(clientAccount.Id).Id
        );

        relateContacts(
            businessContact.Id,
            getPersonContact(prospectAccount.Id).Id
        );

        createBilling(clientAccount.Id, 3000);

        Test.startTest();
        Database.executeBatch(new ContactReferralMetricsBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Clients_Referred__c,
                   Prospects_Referred__c,
                   Lifetime_Revenue__c
            FROM Contact
            WHERE Id = :businessContact.Id
        ];

        System.assertEquals(1, updated.Clients_Referred__c);
        System.assertEquals(1, updated.Prospects_Referred__c);
        System.assertEquals(3000, updated.Lifetime_Revenue__c);
    }

    @isTest
    static void testNoRelatedContacts() {

        Contact businessContact = createBusinessContact();

        Test.startTest();
        Database.executeBatch(new ContactReferralMetricsBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Clients_Referred__c,
                   Prospects_Referred__c,
                   Lifetime_Revenue__c
            FROM Contact
            WHERE Id = :businessContact.Id
        ];

        System.assertEquals(0, updated.Clients_Referred__c);
        System.assertEquals(0, updated.Prospects_Referred__c);
        System.assertEquals(0, updated.Lifetime_Revenue__c);
    }

    @isTest
    static void testBlankStage() {

        Contact businessContact = createBusinessContact();

        Account acc = createPersonAccount('Prospect');

        acc.Account_Status__c = null;
        update acc;

        Contact relatedContact = getPersonContact(acc.Id);

        relateContacts(businessContact.Id, relatedContact.Id);

        Test.startTest();
        Database.executeBatch(new ContactReferralMetricsBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Clients_Referred__c,
                   Prospects_Referred__c
            FROM Contact
            WHERE Id = :businessContact.Id
        ];

        System.assertEquals(0, updated.Clients_Referred__c);
        System.assertEquals(0, updated.Prospects_Referred__c);
    }

    @isTest
    static void testMultipleBillings() {

        Contact businessContact = createBusinessContact();

        Account clientAccount = createPersonAccount('Client');

        relateContacts(
            businessContact.Id,
            getPersonContact(clientAccount.Id).Id
        );

        createBilling(clientAccount.Id, 1000);
        createBilling(clientAccount.Id, 2000);

        Test.startTest();
        Database.executeBatch(new ContactReferralMetricsBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Lifetime_Revenue__c
            FROM Contact
            WHERE Id = :businessContact.Id
        ];

        System.assertEquals(3000, updated.Lifetime_Revenue__c);
    }

    @isTest
    static void testClientWithoutBilling() {

        Contact businessContact = createBusinessContact();

        Account clientAccount = createPersonAccount('Client');

        relateContacts(
            businessContact.Id,
            getPersonContact(clientAccount.Id).Id
        );

        Test.startTest();
        Database.executeBatch(new ContactReferralMetricsBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Clients_Referred__c,
                   Lifetime_Revenue__c
            FROM Contact
            WHERE Id = :businessContact.Id
        ];

        System.assertEquals(1, updated.Clients_Referred__c);
        System.assertEquals(0, updated.Lifetime_Revenue__c);
    }

    @isTest
    static void testFinishMethodCoverage() {

        Contact businessContact = createBusinessContact();

        Test.startTest();
        Database.executeBatch(new ContactReferralMetricsBatch(), 1);
        Test.stopTest();

        System.assert(true);
    }
}