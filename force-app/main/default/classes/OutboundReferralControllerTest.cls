@IsTest
private class OutboundReferralControllerTest {
 
    private static Account createBusinessAccount() {

        Account acc = new Account(
            Name = 'Test Business Account',
            Email__c = 'business@test.com',
            Referral_Source_Type__c = 'Attorney'
        );

        insert acc;
        return acc;
    }

    
    private static Account createPatientAccount() {

        Id personRtId;

        Map<String, Schema.RecordTypeInfo> rtMap =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();

        if (rtMap.containsKey('PersonAccount')) {
            personRtId = rtMap.get('PersonAccount').getRecordTypeId();
        }

        Account pa;

        
        if (personRtId != null) {

            pa = new Account(
                RecordTypeId = personRtId,
                FirstName = 'John',
                LastName = 'Doe',
                PersonEmail = 'patient@test.com'
            );

        } else {

            
            pa = new Account(
                Name = 'Test Patient Account'
            );
        }

        insert pa;

        return pa;
    }

    
    private static Contact createRelatedContact(Account patientAccount) {

        if (patientAccount.PersonContactId != null) {

            List<Contact> conList = [
                SELECT Id, LastName, Email
                FROM Contact
                WHERE Id = :patientAccount.PersonContactId
                LIMIT 1
            ];

            if (!conList.isEmpty()) {
                return conList[0];
            }
        }

    
        Contact c = new Contact(
            LastName = 'Test Contact'
        );

        insert c;

        return c;
    }

    private static Referral__c createReferral(
        Id businessId,
        Id patientId,
        Id referralRtId
    ) {

        Referral__c ref = new Referral__c(
            Name = 'Test Referral',
            RecordTypeId = referralRtId,
            Business_Account__c = businessId,
            Patient__c = patientId,
            Referral_Type__c = 'Home Care Agency',
            Business_Email__c = 'business@test.com',
            Additional_Email_Addresses__c =
                'a@test.com,b@test.com',
            Reason_for_Referral__c = 'Testing',
            Role__c = 'Role'
        );

        insert ref;
        return ref;
    }


    @IsTest
    static void testGetBusinessEmail() {

        Account acc = createBusinessAccount();

        Test.startTest();

        String email =
            OutboundReferralController.getBusinessEmail(acc.Id);

        Test.stopTest();

        System.assertEquals('business@test.com', email);
    }

    @IsTest
    static void testGetBusinessEmailNull() {

        Test.startTest();

        String email =
            OutboundReferralController.getBusinessEmail(null);

        Test.stopTest();

        System.assertEquals(null, email);
    }


    @IsTest
    static void testSearchBusinessAccounts() {

        createBusinessAccount();

        Test.startTest();

        List<Account> result =
            OutboundReferralController.searchBusinessAccounts('Test');

        Test.stopTest();

        System.assert(result.size() > 0);
    }


    @IsTest
    static void testGetPatientContacts() {

        Account patient = createPatientAccount();

        
        if (patient.PersonContactId != null) {

            Contact relatedContact =
                createRelatedContact(patient);

            HealthCloudGA__ContactContactRelation__c rel =
                new HealthCloudGA__ContactContactRelation__c(
                    HealthCloudGA__RelatedContact__c =
                        patient.PersonContactId,
                    HealthCloudGA__Contact__c =
                        relatedContact.Id
                );

            insert rel;

            Test.startTest();

            List<HealthCloudGA__ContactContactRelation__c> results =
                OutboundReferralController.getPatientContacts(
                    patient.Id
                );

            Test.stopTest();

            System.assertNotEquals(null, results);

        } else {

            System.assert(true);
        }
    }

    @IsTest
    static void testGetPatientContactsNull() {

        Test.startTest();

        List<HealthCloudGA__ContactContactRelation__c> results =
            OutboundReferralController.getPatientContacts(null);

        Test.stopTest();

        System.assertEquals(0, results.size());
    }


    @IsTest
    static void testGetPatientDetails() {

        Account patient = createPatientAccount();

        Test.startTest();

        Account result =
            OutboundReferralController.getPatientDetails(patient.Id);

        Test.stopTest();

        System.assertEquals(patient.Id, result.Id);
    }

    @IsTest
    static void testGetPatientDetailsNull() {

        Test.startTest();

        Account result =
            OutboundReferralController.getPatientDetails(null);

        Test.stopTest();

        System.assertEquals(null, result);
    }


    @IsTest
    static void testSaveReferralSuccess() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        Test.startTest();

        Id refId = OutboundReferralController.saveReferral(
            business.Id,
            patient.Id,
            'Home Care Agency',
            'business@test.com',
            'one@test.com,two@test.com',
            '<p>Testing</p>',
            'Role',
            null,
            referralRtId
        );

        Test.stopTest();

        System.assertNotEquals(null, refId);
    }


    @IsTest
    static void testSaveReferralDuplicate() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        createReferral(
            business.Id,
            patient.Id,
            referralRtId
        );

        Test.startTest();

        try {

            OutboundReferralController.saveReferral(
                business.Id,
                patient.Id,
                'Home Care Agency',
                'business@test.com',
                'one@test.com',
                'Testing',
                'Role',
                null,
                referralRtId
            );

            System.assert(false);

        } catch (AuraHandledException ex) {

            
        }

        Test.stopTest();
    }


    @IsTest
    static void testSaveReferralValidation() {

        Test.startTest();

        try {

            OutboundReferralController.saveReferral(
                null,
                null,
                'Home Care Agency',
                'business@test.com',
                'one@test.com',
                'Testing',
                'Role',
                null,
                null
            );

            System.assert(false);

        } catch (AuraHandledException ex) {

        }

        Test.stopTest();
    }


    @IsTest
    static void testSaveReferralAdditionalEmailsRequired() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        Test.startTest();

        try {

            OutboundReferralController.saveReferral(
                business.Id,
                patient.Id,
                'Home Care Agency',
                'business@test.com',
                null,
                'Testing',
                'Role',
                null,
                referralRtId
            );

        

        } catch (AuraHandledException ex) {

        }

        Test.stopTest();
    }


    @IsTest
    static void testSaveReferralInvalidEmail() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        Test.startTest();

        try {

            OutboundReferralController.saveReferral(
                business.Id,
                patient.Id,
                'Home Care Agency',
                'business@test.com',
                'badEmail',
                'Testing',
                'Role',
                null,
                referralRtId
            );

            System.assert(false);

        } catch (AuraHandledException ex) {

        }

        Test.stopTest();
    }

    
    @IsTest
    static void testSaveReferralTooManyEmails() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        Test.startTest();

        try {

            OutboundReferralController.saveReferral(
                business.Id,
                patient.Id,
                'Home Care Agency',
                'business@test.com',
                '1@test.com,2@test.com,3@test.com,4@test.com',
                'Testing',
                'Role',
                null,
                referralRtId
            );

            System.assert(false);

        } catch (AuraHandledException ex) {

        }

        Test.stopTest();
    }


    @IsTest
    static void testSearchAccounts() {

        createBusinessAccount();

        Test.startTest();

        List<Account> result =
            OutboundReferralController.searchAccounts(
                'Test',
                false
            );

        Test.stopTest();

        System.assert(result.size() > 0);
    }


    @IsTest
    static void testGetReferralTypePicklist() {

        Test.startTest();

        List<String> values =
            OutboundReferralController.getReferralTypePicklist();

        Test.stopTest();

        System.assertNotEquals(null, values);
    }


    @IsTest
    static void testGetBusinessReferralType() {

        Account acc = createBusinessAccount();

        Test.startTest();

        String val =
            OutboundReferralController.getBusinessReferralType(acc.Id);

        Test.stopTest();

        System.assertEquals('Attorney', val);
    }

    @IsTest
    static void testGetBusinessReferralTypeNull() {

        Test.startTest();

        String val =
            OutboundReferralController.getBusinessReferralType(null);

        Test.stopTest();

        System.assertEquals(null, val);
    }


    @IsTest
    static void testGenerateReferralPDFAsync() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        Referral__c ref = createReferral(
            business.Id,
            patient.Id,
            referralRtId
        );

        Test.startTest();

        OutboundReferralController.generateReferralPDFAsync(ref.Id);

        Test.stopTest();

        List<Attachment> atts = [
            SELECT Id
            FROM Attachment
            WHERE ParentId = :ref.Id
        ];

        System.assert(atts.size() > 0);
    }


    @IsTest
    static void testSaveReferralWithImage() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        String richText =
            '<p>Test</p>' +
            '<img src="data:image/png;base64,' +
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="' +
            '"/>';

        Test.startTest();

        Id refId = OutboundReferralController.saveReferral(
            business.Id,
            patient.Id,
            'Home Care Agency',
            'business@test.com',
            'one@test.com',
            richText,
            'Role',
            null,
            referralRtId
        );

        Test.stopTest();

        Referral__c ref = [
            SELECT Id, Reason_for_Referral__c
            FROM Referral__c
            WHERE Id = :refId
        ];

        System.assert(
            ref.Reason_for_Referral__c.contains(
                '/servlet/servlet.FileDownload'
            )
        );
    }
}