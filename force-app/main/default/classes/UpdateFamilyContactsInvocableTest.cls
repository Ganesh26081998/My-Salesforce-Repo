@IsTest
private class UpdateFamilyContactsInvocableTest {

    //=========================================================
    // Helpers
    //=========================================================

    private static Id getPersonAccountRtId() {

        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
    }

    private static Id getReciprocalRoleRtId() {

        return Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();
    }

    private static HealthCloudGA__ReciprocalRole__c createRole(
        String nameVal,
        String inverseName
    ) {

        HealthCloudGA__ReciprocalRole__c roleRec =
            new HealthCloudGA__ReciprocalRole__c(
                Name = nameVal,
                HealthCloudGA__InverseRole__c = inverseName,
                HealthCloudGA__CreateInverseRole__c = false,
                RecordTypeId = getReciprocalRoleRtId()
            );

        insert roleRec;

        return roleRec;
    }

    private static Account createPersonAccount(String uniqueVal) {

        Account pa = new Account(
            FirstName = 'Anthony',
            LastName = uniqueVal,
            PersonEmail = uniqueVal + '@test.com',
            RecordTypeId = getPersonAccountRtId(),
            Account_Status__c = 'Prospect',
            Account_Statusp__c = 'Active'
        );

        insert pa;

        return pa;
    }

    private static Contact getPersonContact(Id personAccId) {

        return [
            SELECT Id
            FROM Contact
            WHERE AccountId = :personAccId
            LIMIT 1
        ];
    }

    //=========================================================
    // Positive Test
    //=========================================================

    @IsTest
    static void testUpdateFamilyContacts() {

        Account personAcc = createPersonAccount('Patient1');

        Contact patientContact = getPersonContact(personAcc.Id);

        Contact familyContact = new Contact(
            LastName = 'Family Contact'
        );
        insert familyContact;

        HealthCloudGA__ReciprocalRole__c roleRec =
            createRole('Daughter', 'Mother');

        HealthCloudGA__ContactContactRelation__c relation =
            new HealthCloudGA__ContactContactRelation__c(
                HealthCloudGA__Contact__c = patientContact.Id,
                HealthCloudGA__RelatedContact__c = familyContact.Id,
                HealthCloudGA__Role__c = roleRec.Id,
                HealthCloudGA__Active__c = true,
                Type__c = 'Family Contact'
            );

        insert relation;

        UpdateFamilyContactsInvocable.Request req =
            new UpdateFamilyContactsInvocable.Request();

        req.accountId = personAcc.Id;

        Test.startTest();

        UpdateFamilyContactsInvocable.updateFamilyContacts(
            new List<UpdateFamilyContactsInvocable.Request>{req}
        );

        Test.stopTest();

        familyContact = [
            SELECT
                Account_Stage_in_Contact__c,
                Account_Status_in_Contact__c
            FROM Contact
            WHERE Id = :familyContact.Id
        ];

        Account updatedAccount = [
            SELECT
                Account_Status__c,
                Account_Statusp__c
            FROM Account
            WHERE Id = :personAcc.Id
        ];

        System.assertEquals(
            updatedAccount.Account_Status__c,
            familyContact.Account_Stage_in_Contact__c
        );

        System.assertEquals(
            updatedAccount.Account_Statusp__c,
            familyContact.Account_Status_in_Contact__c
        );
    }

    //=========================================================
    // Empty Request List
    //=========================================================

    @IsTest
    static void testEmptyRequestList() {

        Test.startTest();

        UpdateFamilyContactsInvocable.updateFamilyContacts(
            new List<UpdateFamilyContactsInvocable.Request>()
        );

        Test.stopTest();

        System.assert(true);
    }

    //=========================================================
    // Null Account Id
    //=========================================================

    @IsTest
    static void testNullAccountId() {

        UpdateFamilyContactsInvocable.Request req =
            new UpdateFamilyContactsInvocable.Request();

        req.accountId = null;

        Test.startTest();

        UpdateFamilyContactsInvocable.updateFamilyContacts(
            new List<UpdateFamilyContactsInvocable.Request>{req}
        );

        Test.stopTest();

        System.assert(true);
    }

    //=========================================================
    // No Family Relationship
    //=========================================================

    @IsTest
    static void testNoRelationship() {

        Account personAcc = createPersonAccount('Patient2');

        UpdateFamilyContactsInvocable.Request req =
            new UpdateFamilyContactsInvocable.Request();

        req.accountId = personAcc.Id;

        Test.startTest();

        UpdateFamilyContactsInvocable.updateFamilyContacts(
            new List<UpdateFamilyContactsInvocable.Request>{req}
        );

        Test.stopTest();

        System.assert(true);
    }
}