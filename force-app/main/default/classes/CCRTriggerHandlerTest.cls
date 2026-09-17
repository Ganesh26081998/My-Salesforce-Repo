@IsTest
public class CCRTriggerHandlerTest {

    // =========================================================
    // HELPERS
    // =========================================================

    private static void enableTriggers() {

        WellSky_Custom_Setting__c existing =
            WellSky_Custom_Setting__c.getOrgDefaults();

        if (existing == null || existing.Id == null) {

            insert new WellSky_Custom_Setting__c(
                SetupOwnerId    = UserInfo.getOrganizationId(),
                Run_Triggers__c = true
            );

        } else {

            existing.Run_Triggers__c = true;
            update existing;
        }

        // Reset static cache
        TriggerControlUtil.reset();
    }

    private static Id getBusinessContactRtId() {

        return Schema.SObjectType.Contact
            .getRecordTypeInfosByDeveloperName()
            .get('IndustriesBusiness')
            .getRecordTypeId();
    }

    private static Id getInboundReferralRtId() {

        return Schema.SObjectType.Referral__c
            .getRecordTypeInfosByDeveloperName()
            .get('Inbound')
            .getRecordTypeId();
    }

    private static Id getPersonAccountRtId() {

        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
    }

    private static Id getBusinessAccountRtId() {

        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Business_Account')
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
                Name                              = nameVal,
                HealthCloudGA__InverseRole__c     = inverseName,
                HealthCloudGA__CreateInverseRole__c = false,
                RecordTypeId                      = getReciprocalRoleRtId()
            );

        insert roleRec;

        return roleRec;
    }

    private static Account createBusinessAccount(String uniqueVal) {

        Account acc = new Account(
            Name                 = 'Business ' + uniqueVal,
            Organization_Name__c = 'ORG_' + uniqueVal,
            RecordTypeId         = getBusinessAccountRtId()
        );

        insert acc;

        return acc;
    }

    private static Contact createBusinessContact(
        Account acc,
        String uniqueVal
    ) {

        Contact con = new Contact(
            LastName     = 'BUSCON' + uniqueVal,
            AccountId    = acc.Id,
            RecordTypeId = getBusinessContactRtId()
        );

        insert con;

        return con;
    }

    private static Account createPersonAccount(String uniqueVal) {

        Account pa = new Account(
            FirstName    = 'Patient',
            LastName     = uniqueVal,
            PersonEmail  = uniqueVal + '@test.com',
            RecordTypeId = getPersonAccountRtId()
        );

        insert pa;

        return pa;
    }

    private static Contact getPersonContact(Id personAccId) {

        return [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :personAccId
            LIMIT 1
        ];
    }

    // =========================================================
    // TEST 1 — POSITIVE
    // Referral SHOULD delete
    // =========================================================

    @IsTest
    static void testHandleAfterDelete() {

        enableTriggers();

        // ─────────────────────────────────────────────────────
        // Test Data
        // ─────────────────────────────────────────────────────

        HealthCloudGA__ReciprocalRole__c roleRec =
            createRole('Daughter', 'Mother');

        Account businessAcc =
            createBusinessAccount('POSITIVETEST');

        Contact businessContact =
            createBusinessContact(
                businessAcc,
                'POSITIVETEST'
            );

        Account patientAcc =
            createPersonAccount('POSITIVETEST');

        Contact patientContact =
            getPersonContact(patientAcc.Id);

        // Referral
        Referral__c ref = new Referral__c(
            Name              = 'ReferralPositive',
            RecordTypeId      = getInboundReferralRtId(),
            Contact_Lookup__c = businessContact.Id,
            Patient__c        = patientAcc.Id
        );

        insert ref;

        // CCR
        HealthCloudGA__ContactContactRelation__c ccr =
            new HealthCloudGA__ContactContactRelation__c(
                HealthCloudGA__Contact__c        = businessContact.Id,
                HealthCloudGA__RelatedContact__c = patientContact.Id,
                HealthCloudGA__Role__c           = roleRec.Id,
                Is_Referral__c                   = true
            );

        insert ccr;

        List<HealthCloudGA__ContactContactRelation__c> oldList =
            new List<HealthCloudGA__ContactContactRelation__c>{ ccr };

        // ─────────────────────────────────────────────────────
        // Execute
        // ─────────────────────────────────────────────────────

        Test.startTest();

        CCRTriggerHandler.handleAfterDelete(oldList);

        Test.stopTest();

        // ─────────────────────────────────────────────────────
        // Assert
        // ─────────────────────────────────────────────────────

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Referral__c
                WHERE Id = :ref.Id
            ],
            'Referral should be deleted'
        );
    }

    // =========================================================
    // TEST 2 — NEGATIVE
    // Referral should NOT delete
    // =========================================================

    @IsTest
    static void testHandleAfterDelete_NoDelete() {

        enableTriggers();

        // ─────────────────────────────────────────────────────
        // Test Data
        // ─────────────────────────────────────────────────────

        HealthCloudGA__ReciprocalRole__c roleRec =
            createRole('Brother', 'Sister');

        Account businessAcc =
            createBusinessAccount('NEGATIVETEST');

        Contact businessContact =
            createBusinessContact(
                businessAcc,
                'NEGATIVETEST'
            );

        Account patientAcc =
            createPersonAccount('NEGATIVETEST');

        Contact patientContact =
            getPersonContact(patientAcc.Id);

        // Referral
        Referral__c ref = new Referral__c(
            Name              = 'Referral Negative',
            RecordTypeId      = getInboundReferralRtId(),
            Contact_Lookup__c = businessContact.Id,
            Patient__c        = patientAcc.Id
        );

        insert ref;

        // CCR
        HealthCloudGA__ContactContactRelation__c ccr =
            new HealthCloudGA__ContactContactRelation__c(
                HealthCloudGA__Contact__c        = businessContact.Id,
                HealthCloudGA__RelatedContact__c = patientContact.Id,
                HealthCloudGA__Role__c           = roleRec.Id,
                Is_Referral__c                   = false
            );

        insert ccr;

        List<HealthCloudGA__ContactContactRelation__c> oldList =
            new List<HealthCloudGA__ContactContactRelation__c>{ ccr };

        // ─────────────────────────────────────────────────────
        // Execute
        // ─────────────────────────────────────────────────────

        Test.startTest();

        CCRTriggerHandler.handleAfterDelete(oldList);

        Test.stopTest();

        // ─────────────────────────────────────────────────────
        // Assert
        // ─────────────────────────────────────────────────────

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Referral__c
                WHERE Id = :ref.Id
            ],
            'Referral should NOT be deleted'
        );
    }
}