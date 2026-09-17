@IsTest
private class OutboundReferralPDFControllerTest {


    private static Account createBusinessAccount() {

        Account acc = new Account(
            Name = 'Test Business'
        );

        insert acc;
        return acc;
    }

    private static Account createPatientAccount() {

        Id personRtId;

        Map<String, Schema.RecordTypeInfo> rtMap =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName();

        if (rtMap.containsKey('PersonAccount')) {
            personRtId =
                rtMap.get('PersonAccount').getRecordTypeId();
        }

        Account patient;

        if (personRtId != null) {

            patient = new Account(
                RecordTypeId = personRtId,
                FirstName = 'John',
                LastName = 'Doe',
                PersonEmail = 'john@test.com'
            );

        } else {

            patient = new Account(
                Name = 'Patient Account'
            );
        }

        insert patient;

        return patient;
    }


    private static Referral__c createReferral(
        Id businessId,
        Id patientId,
        Id rtId
    ) {

        Referral__c ref = new Referral__c(
            Name = 'Test Referral',
            RecordTypeId = rtId,
            Business_Account__c = businessId,
            Patient__c = patientId,
            Referral_Type__c = 'Home Care Agency',
            Business_Email__c = 'business@test.com',
            Additional_Email_Addresses__c =
                'a@test.com,b@test.com',
            Role__c = 'Attorney',

            // VALID BASE64 IMAGE
            Reason_for_Referral__c =
                '<div style="color:red;">' +
                '<script>alert(1)</script>' +
                '<img src="data:image/png;base64,' +
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="' +
                '"/>' +
                '<p>Referral Reason</p>' +
                '</div>'
        );

        insert ref;

        return ref;
    }


    @IsTest
    static void testControllerWithReferral() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        Referral__c ref =
            createReferral(
                business.Id,
                patient.Id,
                referralRtId
            );

        
        if (patient.PersonContactId != null) {

            List<Contact> conList = [
                SELECT Id
                FROM Contact
                WHERE Id = :patient.PersonContactId
                LIMIT 1
            ];

            if (!conList.isEmpty()) {

                AccountContactRelation acr =
                    new AccountContactRelation(
                        AccountId = patient.Id,
                        ContactId = conList[0].Id,
                        Roles = 'Emergency Contact',
                        IsActive = true
                    );

                insert acr;
            }
        }

        ApexPages.StandardController sc =
            new ApexPages.StandardController(ref);

        Test.startTest();

        OutboundReferralPDFController controller =
            new OutboundReferralPDFController(sc);

        String formatted =
            controller.formattedReason;

        Test.stopTest();

        
        System.assertNotEquals(
            null,
            controller.referral
        );

        System.assert(
            formatted.contains('Referral Reason')
        );

       
    }


    @IsTest
    static void testControllerWithoutReferralId() {

        Referral__c dummyRef = new Referral__c();

        ApexPages.StandardController sc =
            new ApexPages.StandardController(dummyRef);

        Test.startTest();

        OutboundReferralPDFController controller =
            new OutboundReferralPDFController(sc);

        Test.stopTest();

        System.assertNotEquals(
            null,
            controller.referral
        );

        System.assertEquals(
            0,
            controller.relatedContacts.size()
        );
    }


    @IsTest
    static void testFormattedReasonBlank() {

        Account business = createBusinessAccount();
        Account patient = createPatientAccount();

        Id referralRtId =
            Schema.SObjectType.Referral__c
                .getRecordTypeInfosByName()
                .values()[0]
                .getRecordTypeId();

        Referral__c ref = new Referral__c(
            Name = 'Blank Reason Referral',
            RecordTypeId = referralRtId,
            Business_Account__c = business.Id,
            Patient__c = patient.Id
        );

        insert ref;

        ApexPages.StandardController sc =
            new ApexPages.StandardController(ref);

        Test.startTest();

        OutboundReferralPDFController controller =
            new OutboundReferralPDFController(sc);

        String formatted =
            controller.formattedReason;

        Test.stopTest();

        System.assertEquals('', formatted);
    }
}