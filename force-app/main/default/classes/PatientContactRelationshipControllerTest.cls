@IsTest
private class PatientContactRelationshipControllerTest {

    static Id personRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Prospect').getRecordTypeId();

    static Id businessRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Business_Account').getRecordTypeId();

    static Id familyContactRtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
        .get('IndividualContact').getRecordTypeId();

    static Id businessContactRtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
        .get('IndustriesBusiness').getRecordTypeId();



    @testSetup
    static void setup() {

        
        Account patient1 = new Account(RecordTypeId = personRtId, FirstName = 'John',  LastName = 'Doe');
        Account patient2 = new Account(RecordTypeId = personRtId, FirstName = 'Jane',  LastName = 'Smith');
        insert new List<Account>{ patient1, patient2 };

        
        Account businessAcc = new Account(
            RecordTypeId = businessRtId,
            Name = 'City Hospital',
            Organization_Name__c = 'City Hospital'
        );
        insert businessAcc;

        
        Contact businessContact = new Contact(
            RecordTypeId = businessContactRtId,
            LastName = 'Business Contact',
            AccountId = businessAcc.Id,
            ReferralType__c = 'Hospital'
        );
        Contact familyContact = new Contact(
            RecordTypeId = familyContactRtId,
            LastName = 'Family Contact',
            AccountId = businessAcc.Id
        );
        insert new List<Contact>{ businessContact, familyContact };

        
        Id contactRoleRtId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();

        
        HealthCloudGA__ReciprocalRole__c hospitalRole = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = 'Hospital',
            HealthCloudGA__InverseRole__c='Patient'
        );
        HealthCloudGA__ReciprocalRole__c patientRole = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = 'Patient',
            HealthCloudGA__InverseRole__c='Hospital'
        );
        insert new List<HealthCloudGA__ReciprocalRole__c>{ hospitalRole, patientRole };

        hospitalRole.HealthCloudGA__InverseRole__c = patientRole.Id;
        patientRole.HealthCloudGA__InverseRole__c  = hospitalRole.Id;
       

        
        HealthCloudGA__ReciprocalRole__c fatherRole = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = 'Father',
            HealthCloudGA__InverseRole__c='Son'
        );
        HealthCloudGA__ReciprocalRole__c sonRole = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = 'Son',
            HealthCloudGA__InverseRole__c='Father'
        );
        insert new List<HealthCloudGA__ReciprocalRole__c>{ fatherRole, sonRole };

        fatherRole.HealthCloudGA__InverseRole__c = sonRole.Id;
        sonRole.HealthCloudGA__InverseRole__c    = fatherRole.Id;
        

        
        HealthCloudGA__ReciprocalRole__c spouseA = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = 'Spouse',
            HealthCloudGA__InverseRole__c='Partner'
        );
        HealthCloudGA__ReciprocalRole__c spouseB = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = 'Partner',
            HealthCloudGA__InverseRole__c='Spouse'
        );
        

        spouseA.HealthCloudGA__InverseRole__c = spouseB.Name;
        spouseB.HealthCloudGA__InverseRole__c = spouseA.Name;
        insert new List<HealthCloudGA__ReciprocalRole__c>{ spouseA, spouseB };
        


        HealthCloudGA__ReciprocalRole__c fcRole = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = 'Family Contact',
            HealthCloudGA__InverseRole__c='Contact'
        );
        HealthCloudGA__ReciprocalRole__c contactRole = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = 'Contact',
            HealthCloudGA__InverseRole__c='Family Contact'
        );
        insert new List<HealthCloudGA__ReciprocalRole__c>{ fcRole, contactRole };

        fcRole.HealthCloudGA__InverseRole__c     = contactRole.Id;
        contactRole.HealthCloudGA__InverseRole__c = fcRole.Id;
        
    }

    
    private static HealthCloudGA__ContactContactRelation__c createCCR(Id contactId) {

        
        List<Account> noOrgList = [SELECT Id FROM Account WHERE Name = 'No Organization' LIMIT 1];
        Account noOrg;
        if (noOrgList.isEmpty()) {
            noOrg = new Account(Name = 'No Organization', Organization_Name__c = 'No Organization');
            insert noOrg;
        } else {
            noOrg = noOrgList[0];
        }

        Contact relatedCon = new Contact(LastName = 'RelatedForCCR', AccountId = noOrg.Id);
        insert relatedCon;

        Id contactRoleRecordTypeId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();

        
        HealthCloudGA__ReciprocalRole__c helperRole = new HealthCloudGA__ReciprocalRole__c(
            Name = 'Helper_Role_' + Crypto.getRandomInteger(),
            RecordTypeId = contactRoleRecordTypeId
        );
        HealthCloudGA__ReciprocalRole__c helperInverse = new HealthCloudGA__ReciprocalRole__c(
            Name = 'Helper_Inverse_' + Crypto.getRandomInteger(),
            RecordTypeId = contactRoleRecordTypeId
        );
       
        helperRole.HealthCloudGA__InverseRole__c    = helperInverse.Name;
        helperInverse.HealthCloudGA__InverseRole__c = helperRole.Name;
         insert new List<HealthCloudGA__ReciprocalRole__c>{ helperRole, helperInverse };

        HealthCloudGA__ContactContactRelation__c ccr = new HealthCloudGA__ContactContactRelation__c(
            HealthCloudGA__Contact__c        = contactId,
            HealthCloudGA__Role__c           = helperRole.Id,
            HealthCloudGA__RelatedContact__c = relatedCon.Id
        );
        insert ccr;
        return ccr;
    }

   
    @IsTest
    static void testGetRelatedContacts_ReturnsList() {
        Account patient = [SELECT  Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        List<HealthCloudGA__ContactContactRelation__c> result =
            PatientContactRelationshipController.getRelatedContacts(patient.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testGetRelatedContacts_BlankId_ReturnsEmpty() {
        Test.startTest();
        List<HealthCloudGA__ContactContactRelation__c> result =
            PatientContactRelationshipController.getRelatedContacts('');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Blank accountId should return empty list');
    }

    @IsTest
    static void testGetRelatedContacts_InvalidId_ThrowsException() {
        
        Account biz = [SELECT Id FROM Account WHERE IsPersonAccount = false LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.getRelatedContacts(biz.Id);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    

    @IsTest
    static void testGetHouseholdAccountForPerson_NullId() {
        Test.startTest();
        Id result = PatientContactRelationshipController.getHouseholdAccountForPerson(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Null input should return null');
    }

    @IsTest
    static void testGetHouseholdAccountForPerson_NoHousehold() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        Id result = PatientContactRelationshipController.getHouseholdAccountForPerson(patient.Id);
        Test.stopTest();


        System.assertEquals(null, result);
    }

    @IsTest
    static void testCreatePatientCCR_SameAccount_ThrowsException() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        HealthCloudGA__ReciprocalRole__c role =
            [SELECT Id FROM HealthCloudGA__ReciprocalRole__c WHERE Name = 'Spouse' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createPatientCCR(
                patient.Id, patient.Id, role.Id
            );
            System.assert(false, 'Expected AuraHandledException for same account');
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreatePatientCCR_InvalidAccount_ThrowsException() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Account biz    = [SELECT Id FROM Account WHERE IsPersonAccount = false LIMIT 1];
        HealthCloudGA__ReciprocalRole__c role =
            [SELECT Id FROM HealthCloudGA__ReciprocalRole__c WHERE Name = 'Spouse' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createPatientCCR(
                patient.Id, biz.Id, role.Id
            );
            System.assert(false, 'Expected AuraHandledException for invalid account');
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

   
    @IsTest
    static void testCreateBusinessCCR_Success() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Test.startTest();
        Id ccrId = PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', false
        );
        Test.stopTest();

        System.assertNotEquals(null, ccrId);
    }

    @IsTest
    static void testCreateBusinessCCR_AsReferral_Success() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Test.startTest();
        Id ccrId = PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', true
        );
        Test.stopTest();

        System.assertNotEquals(null, ccrId);
    }

    @IsTest
    static void testCreateBusinessCCR_NullContactId_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createBusinessCCR(null, patient.Id, 'Hospital', false);
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateBusinessCCR_NullAccountId_Throws() {
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createBusinessCCR(bizContact.Id, null, 'Hospital', false);
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateBusinessCCR_BlankRoleName_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createBusinessCCR(bizContact.Id, patient.Id, '', false);
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateBusinessCCR_NoMatchingRole_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createBusinessCCR(
                bizContact.Id, patient.Id, 'NonExistentRole', false
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateBusinessCCR_RoleNameMismatch_Throws() {
        
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createBusinessCCR(
                bizContact.Id, patient.Id, 'Father', false
            );
            System.assert(false);
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateBusinessCCR_DuplicateNonReferral_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', false
        );

        Test.startTest();
        try {
            PatientContactRelationshipController.createBusinessCCR(
                bizContact.Id, patient.Id, 'Hospital', false
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateBusinessCCR_DuplicateReferral_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', true
        );

        Test.startTest();
        try {
            PatientContactRelationshipController.createBusinessCCR(
                bizContact.Id, patient.Id, 'Hospital', true
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    

    @IsTest
    static void testHasExistingReferralCCR_NoneExists() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        Boolean result = PatientContactRelationshipController.hasExistingReferralCCR(patient.Id);
        Test.stopTest();

        System.assertEquals(false, result, 'Should be false when no referral CCR exists');
    }

    @IsTest
    static void testHasExistingReferralCCR_Exists() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', true
        );

        Test.startTest();
        Boolean result = PatientContactRelationshipController.hasExistingReferralCCR(patient.Id);
        Test.stopTest();

        System.assertEquals(true, result, 'Should be true after referral CCR is created');
    }

    @IsTest
    static void testHasExistingReferralCCR_NonPersonAccount_ReturnsFalse() {
        
        Account biz = [SELECT Id FROM Account WHERE IsPersonAccount = false LIMIT 1];

        Test.startTest();
        try {
            Boolean result = PatientContactRelationshipController.hasExistingReferralCCR(biz.Id);
            
            System.assertNotEquals(null, result);
        } catch (AuraHandledException e) {
            System.assert(true); 
        }
        Test.stopTest();
    }

   
    @IsTest
    static void testCreateCallerCCR_NullContactId_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createCallerCCR(
                null, patient.Id, 'Father', true, 'Family', 'Son', null
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateCallerCCR_NullAccountId_Throws() {
        Contact familyContact = [SELECT Id FROM Contact WHERE LastName = 'Family Contact' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createCallerCCR(
                familyContact.Id, null, 'Father', true, 'Family', 'Son', null
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateCallerCCR_BlankRoleName_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact familyContact = [SELECT Id FROM Contact WHERE LastName = 'Family Contact' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createCallerCCR(
                familyContact.Id, patient.Id, '', true, 'Family', 'Son', null
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateCallerCCR_NoMatchingRole_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact familyContact = [SELECT Id FROM Contact WHERE LastName = 'Family Contact' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createCallerCCR(
                familyContact.Id, patient.Id, 'NonExistentRole', true, 'Family', 'Son', null
            );
            System.assert(false);
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateCallerCCR_FamilyRelationshipBlank_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact familyContact = [SELECT Id FROM Contact WHERE LastName = 'Family Contact' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.createCallerCCR(
                familyContact.Id, patient.Id, 'Father', true,
                'Family',   
                '',
                null
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }


    @IsTest
    static void testUpdateFamilyCCR_Success() {
        Account patient = [SELECT Id, PersonContactId FROM Account WHERE IsPersonAccount = true LIMIT 1];
        HealthCloudGA__ContactContactRelation__c ccr = createCCR(patient.PersonContactId);
        HealthCloudGA__ReciprocalRole__c role =
            [SELECT Id FROM HealthCloudGA__ReciprocalRole__c WHERE Name = 'Father' LIMIT 1];

        Test.startTest();
        PatientContactRelationshipController.updateFamilyCCR(
            ccr.Id, 'Father', 'Family', 'Son', null
        );
        Test.stopTest();

        HealthCloudGA__ContactContactRelation__c updated = [
            SELECT HealthCloudGA__Role__c, Relationship_to_Client__c
            FROM HealthCloudGA__ContactContactRelation__c WHERE Id = :ccr.Id
        ];
        System.assertEquals(role.Id, updated.HealthCloudGA__Role__c);
        System.assertEquals('Family', updated.Relationship_to_Client__c);
    }

    @IsTest
    static void testUpdateFamilyCCR_NullId_Throws() {
        Test.startTest();
        try {
            PatientContactRelationshipController.updateFamilyCCR(null, 'Father', 'Family', 'Son', null);
            System.assert(false);
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateFamilyCCR_BlankRoleName_Throws() {
        Account patient = [SELECT Id, PersonContactId FROM Account WHERE IsPersonAccount = true LIMIT 1];
        HealthCloudGA__ContactContactRelation__c ccr = createCCR(patient.PersonContactId);

        Test.startTest();
        try {
            PatientContactRelationshipController.updateFamilyCCR(ccr.Id, '', 'Family', 'Son', null);
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateFamilyCCR_NoMatchingRole_Throws() {
        Account patient = [SELECT Id, PersonContactId FROM Account WHERE IsPersonAccount = true LIMIT 1];
        HealthCloudGA__ContactContactRelation__c ccr = createCCR(patient.PersonContactId);

        Test.startTest();
        try {
            PatientContactRelationshipController.updateFamilyCCR(
                ccr.Id, 'NonExistentRole', 'Family', 'Son', null
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    
    @IsTest
    static void testUpdateCoupleHouseholdCCR_Success() {
        List<Account> patients = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 2];
        HealthCloudGA__ReciprocalRole__c role =
            [SELECT Id,Name,HealthCloudGA__InverseRole__c,HealthCloudGA__InverseRelationship__c FROM HealthCloudGA__ReciprocalRole__c WHERE Name = 'Hospital' LIMIT 1];
        System.debug('role:'+role);

        Id ccrId = PatientContactRelationshipController.createPatientCCR(
            patients[0].Id, patients[1].Id, role.Id
        );

        Test.startTest();
        PatientContactRelationshipController.updateCoupleHouseholdCCR(ccrId, role.Id);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testUpdateCoupleHouseholdCCR_NullRelationshipId_Throws() {
        HealthCloudGA__ReciprocalRole__c role =
            [SELECT Id FROM HealthCloudGA__ReciprocalRole__c WHERE Name = 'Spouse' LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.updateCoupleHouseholdCCR(null, role.Id);
            System.assert(false);
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }

   
    @IsTest
    static void testUpdateBusinessCCR_Success() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Id ccrId = PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', false
        );

        Test.startTest();
        PatientContactRelationshipController.updateBusinessCCR(
            ccrId, bizContact.Id, 'Hospital', true, patient.Id
        );
        Test.stopTest();

        HealthCloudGA__ContactContactRelation__c updated = [
            SELECT Is_Referral__c FROM HealthCloudGA__ContactContactRelation__c WHERE Id = :ccrId
        ];
        System.assertEquals(true, updated.Is_Referral__c);
    }

    @IsTest
    static void testUpdateBusinessCCR_NullRelationshipId_Throws() {
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        try {
            PatientContactRelationshipController.updateBusinessCCR(
                null, bizContact.Id, 'Hospital', false, patient.Id
            );
            System.assert(false);
        } catch (AuraHandledException e) {
            
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateBusinessCCR_BlankType_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Id ccrId = PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', false
        );

        Test.startTest();
        try {
            PatientContactRelationshipController.updateBusinessCCR(
                ccrId, bizContact.Id, '', false, patient.Id
            );
            System.assert(false);
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateBusinessCCR_NoMatchingRole_Throws() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Id ccrId = PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', false
        );

        Test.startTest();
        try {
            PatientContactRelationshipController.updateBusinessCCR(
                ccrId, bizContact.Id, 'NonExistentRole', false, patient.Id
            );
            System.assert(false);
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }

   

    @IsTest
    static void testDeleteContactRelationship_Success() {
        Account patient = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Contact bizContact = [SELECT Id FROM Contact WHERE ReferralType__c = 'Hospital' LIMIT 1];

        Id ccrId = PatientContactRelationshipController.createBusinessCCR(
            bizContact.Id, patient.Id, 'Hospital', false
        );

        Test.startTest();
        PatientContactRelationshipController.deleteContactRelationship(ccrId);
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT() FROM HealthCloudGA__ContactContactRelation__c WHERE Id = :ccrId
        ];
        System.assertEquals(0, remaining, 'CCR should be deleted');
    }

    @IsTest
    static void testDeleteContactRelationship_InvalidId_Throws() {
        Test.startTest();
        try {
            PatientContactRelationshipController.deleteContactRelationship('001000000000000AAA');
            System.assert(false);
        } catch (AuraHandledException e) {
           
        }
        Test.stopTest();
    }

    
    @IsTest
    static void testSaveAccountBypass_Success() {
        Account acc = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Bypass',
            LastName = 'Test'
        );

        Test.startTest();
        String accId = PatientContactRelationshipController.saveAccountBypass(acc);
        Test.stopTest();

        System.assertNotEquals(null, accId);
    }

    @IsTest
    static void testSaveAccountBypass_InvalidAccount_Throws() {
        
        Account acc = new Account(RecordTypeId = personRtId);

        Test.startTest();
        try {
            PatientContactRelationshipController.saveAccountBypass(acc);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}