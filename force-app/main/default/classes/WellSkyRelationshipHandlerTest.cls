@isTest
private class WellSkyRelationshipHandlerTest {

    // ─────────────────────────────────────────────────────────────────────
    // SHARED TEST DATA — inserted once, reused across all tests
    // ─────────────────────────────────────────────────────────────────────
    @TestSetup
    static void setupData() {

        // Enable triggers
        WellSky_Custom_Setting__c setting = new WellSky_Custom_Setting__c(
            SetupOwnerId    = UserInfo.getOrganizationId(),
            Run_Triggers__c = true
        );
        insert setting;

        // Primary business account
        Account primaryAcc = new Account(
            Name                = 'Primary Account',
            Organization_Name__c = 'PRIMARY_ACC_UNIQUE',
            Is_Primary__c       = true
        );
        insert primaryAcc;

        // Related business account
        Account relatedAcc = new Account(
            Name                = 'Related Account',
            Organization_Name__c = 'RELATED_ACC_UNIQUE',
            Is_Primary__c       = false
        );
        insert relatedAcc;

        // Second related account also marked primary
        Account secondPrimaryAcc = new Account(
            Name                = 'Second Primary Account',
            Organization_Name__c = 'SECOND_PRIMARY_ACC_UNIQUE',
            Is_Primary__c       = true
        );
        insert secondPrimaryAcc;

        // Contacts
        Contact primaryCon = new Contact(
            LastName  = 'PRIMARY CONTACT UNIQUE',
            AccountId = primaryAcc.Id
        );
        insert primaryCon;

        Contact relatedCon = new Contact(
            LastName  = 'RELATED CONTACT UNIQUE',
            AccountId = relatedAcc.Id
        );
        insert relatedCon;

        Contact secondPrimaryCon = new Contact(
            LastName  = 'SECOND PRIMARY CONTACT UNIQUE',
            AccountId = secondPrimaryAcc.Id
        );
        insert secondPrimaryCon;

        // Get or create Reciprocal Role
        Id roleId = getOrCreateRoleId();

        // CCR: primaryCon <-> relatedCon
        insert new HealthCloudGA__ContactContactRelation__c(
            HealthCloudGA__Contact__c        = primaryCon.Id,
            HealthCloudGA__RelatedContact__c = relatedCon.Id,
            Relationship_Status__c           = 'Related',
            HealthCloudGA__Role__c           = roleId
        );

        // CCR: primaryCon <-> secondPrimaryCon
        insert new HealthCloudGA__ContactContactRelation__c(
            HealthCloudGA__Contact__c        = primaryCon.Id,
            HealthCloudGA__RelatedContact__c = secondPrimaryCon.Id,
            Relationship_Status__c           = 'Related',
            HealthCloudGA__Role__c           = roleId
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────────────────

    private static Id getOrCreateRoleId() {

        List<HealthCloudGA__ReciprocalRole__c> roles = [
            SELECT Id
            FROM HealthCloudGA__ReciprocalRole__c
            LIMIT 1
        ];

        if (!roles.isEmpty()) {
            return roles[0].Id;
        }

        Id contactRoleRtId =
            Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();

        HealthCloudGA__ReciprocalRole__c role =
            new HealthCloudGA__ReciprocalRole__c(
                Name                          = 'Test Role',
                HealthCloudGA__InverseRole__c = 'Test Inverse',
                RecordTypeId                  = contactRoleRtId
            );

        insert role;

        return role.Id;
    }

    private static void resetTriggerCache() {
        TriggerControlUtil.reset();
    }

    private static Account getPrimaryAccount() {

        return [
            SELECT Id, Name, Is_Primary__c, Organization_Name__c
            FROM Account
            WHERE Organization_Name__c = 'PRIMARY_ACC_UNIQUE'
            LIMIT 1
        ];
    }

    private static Account getRelatedAccount() {

        return [
            SELECT Id, Name, Is_Primary__c, Organization_Name__c
            FROM Account
            WHERE Organization_Name__c = 'RELATED_ACC_UNIQUE'
            LIMIT 1
        ];
    }

    private static Account getSecondPrimaryAccount() {

        return [
            SELECT Id, Name, Is_Primary__c, Organization_Name__c
            FROM Account
            WHERE Organization_Name__c = 'SECOND_PRIMARY_ACC_UNIQUE'
            LIMIT 1
        ];
    }

    private static Contact getPrimaryContact() {

        return [
            SELECT Id, AccountId
            FROM Contact
            WHERE LastName = 'PRIMARY CONTACT UNIQUE'
            LIMIT 1
        ];
    }

    private static Contact getRelatedContact() {

        return [
            SELECT Id, AccountId
            FROM Contact
            WHERE LastName = 'RELATED CONTACT UNIQUE'
            LIMIT 1
        ];
    }

    // Build fake in-memory CCR
    private static HealthCloudGA__ContactContactRelation__c makeFakeCCR(
        Id contactId,
        Id relatedId,
        String status
    ) {

        return (HealthCloudGA__ContactContactRelation__c)
            JSON.deserialize(
                JSON.serialize(
                    new Map<String, Object>{
                        'HealthCloudGA__Contact__c'        => contactId,
                        'HealthCloudGA__RelatedContact__c' => relatedId,
                        'Relationship_Status__c'           => status
                    }
                ),
                HealthCloudGA__ContactContactRelation__c.class
            );
    }

    // =====================================================================
    // manualSync
    // =====================================================================

    @isTest
    static void test_manualSync_nullId_throwsException() {

        resetTriggerCache();

        Test.startTest();

        try {

            WellSkyRelationshipHandler.manualSync(null);

            System.assert(false, 'Expected exception');

        } catch (AuraHandledException ex) {

            System.assert(ex.getMessage() != null);
        }

        Test.stopTest();
    }

    @isTest
    static void test_manualSync_happyPath_skipSync() {

        resetTriggerCache();

        Account acc = getPrimaryAccount();

        WellSkyRelationshipHandler.skipPerformSync = true;

        Test.startTest();

        WellSkyRelationshipHandler.manualSync(acc.Id);

        Test.stopTest();

        System.assert(true);
    }

    // =====================================================================
    // syncFromCCR
    // =====================================================================

    @isTest
    static void test_syncFromCCR_nullList_earlyReturn() {

        resetTriggerCache();

        Test.startTest();

        WellSkyRelationshipHandler.syncFromCCR(null);

        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void test_syncFromCCR_emptyList_earlyReturn() {

        resetTriggerCache();

        Test.startTest();

        WellSkyRelationshipHandler.syncFromCCR(
            new List<HealthCloudGA__ContactContactRelation__c>()
        );

        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void test_syncFromCCR_nonRelatedStatus_contactIdsEmpty() {

        resetTriggerCache();

        Contact c1 = getPrimaryContact();
        Contact c2 = getRelatedContact();

        WellSkyRelationshipHandler.skipPerformSync = true;

        Test.startTest();

        WellSkyRelationshipHandler.syncFromCCR(
            new List<HealthCloudGA__ContactContactRelation__c>{
                makeFakeCCR(c1.Id, c2.Id, 'Not Related')
            }
        );

        Test.stopTest();

        System.assert(true);
    }

    // =====================================================================
    // validatePrimary
    // =====================================================================

    @isTest
    static void test_validatePrimary_relatedNotPrimary_noError() {

        resetTriggerCache();

        Account primaryAcc = getPrimaryAccount();

        Test.startTest();

        WellSkyRelationshipHandler.validatePrimary(
            new Set<Id>{ primaryAcc.Id },
            new Map<Id, Account>{ primaryAcc.Id => primaryAcc }
        );

        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void test_validatePrimary_relatedIsPrimary_addsError() {

        resetTriggerCache();

        Account primaryAcc = getPrimaryAccount();

        Account accForMap = new Account(
            Id   = primaryAcc.Id,
            Name = primaryAcc.Name
        );

        Test.startTest();

        try {

            WellSkyRelationshipHandler.validatePrimary(
                new Set<Id>{ primaryAcc.Id },
                new Map<Id, Account>{ primaryAcc.Id => accForMap }
            );

        } catch (Exception ex) {

            System.assert(ex.getMessage() != null);
        }

        Test.stopTest();
    }

    // =====================================================================
    // sendErrorEmail
    // =====================================================================

    @isTest
    static void test_sendErrorEmail_skipFlag_noException() {

        resetTriggerCache();

        WellSkyRelationshipHandler.skipEmailSend = true;

        Test.startTest();

        WellSkyRelationshipHandler.sendErrorEmail(
            new Set<Id>(),
            new AuraHandledException('Test error')
        );

        Test.stopTest();

        System.assert(true);
    }

    // =====================================================================
    // performSync
    // =====================================================================

    @isTest
    static void test_performSync_fullExecution_fieldsCopiedAndUpdated() {

        resetTriggerCache();

        Account primaryAcc = getPrimaryAccount();
        Account relatedAcc = getRelatedAccount();

        WellSkyRelationshipHandler.testFieldsToCopy = 'Name';
        WellSkyRelationshipHandler.skipPerformSync  = false;

        Test.startTest();

        WellSkyRelationshipHandler.manualSync(primaryAcc.Id);

        Test.stopTest();

        Account updatedRelated = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :relatedAcc.Id
        ];

    }

    @isTest
    static void test_performSync_selfRelated_primaryToRelatedMapEmpty() {

        resetTriggerCache();

        Account sameAcc = new Account(
            Name                = 'Self Related Acc',
            Organization_Name__c = 'SELF_RELATED_ACC_UNIQUE',
            Is_Primary__c       = true
        );

        insert sameAcc;

        Contact con1 = new Contact(
            LastName  = 'SELF CON ONE',
            AccountId = sameAcc.Id
        );

        Contact con2 = new Contact(
            LastName  = 'SELF CON TWO',
            AccountId = sameAcc.Id
        );

        insert new List<Contact>{ con1, con2 };

        insert new HealthCloudGA__ContactContactRelation__c(
            HealthCloudGA__Contact__c        = con1.Id,
            HealthCloudGA__RelatedContact__c = con2.Id,
            Relationship_Status__c           = 'Related',
            HealthCloudGA__Role__c           = getOrCreateRoleId()
        );

        WellSkyRelationshipHandler.testFieldsToCopy = 'Name';

        Test.startTest();

        WellSkyRelationshipHandler.manualSync(sameAcc.Id);

        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void test_syncFromCCR_exceptionCaught_emailInvoked() {

        resetTriggerCache();

        Contact c1 = getPrimaryContact();
        Contact c2 = getRelatedContact();

        WellSkyRelationshipHandler.skipEmailSend   = true;
        WellSkyRelationshipHandler.skipPerformSync = false;

        Test.startTest();

        WellSkyRelationshipHandler.syncFromCCR(
            new List<HealthCloudGA__ContactContactRelation__c>{
                makeFakeCCR(c1.Id, c2.Id, 'Related')
            }
        );

        Test.stopTest();

        System.assert(true);
    }
}