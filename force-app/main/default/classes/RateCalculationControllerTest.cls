@IsTest
public class RateCalculationControllerTest {

    // =====================================================
    // COMMON DATA
    // =====================================================
    public static Event createTestEvent() {

        // Person Account RT
        Id personRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByName()
            .get('Person Account')
            .getRecordTypeId();

        // Account
        Account acc = new Account(
            FirstName = 'Test',
            LastName = 'Patient',
            PersonEmail = 'test@test.com',
            RecordTypeId = personRtId,
            Location_g__c = 'Milwaukee'
        );
        insert acc;

        // Event
        Event evt = new Event(
            Subject = 'Test Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),
            WhatId = acc.Id
        );
        insert evt;

        return evt;
    }

    // =====================================================
    // TEST UPDATE PATIENT LOCATION
    // =====================================================
    @IsTest
    static void testUpdatePatientLocation() {

        Event evt = createTestEvent();

        Test.startTest();

        RateCalculationController.updatePatientLocation(
            evt.Id,
            'Milwaukee'
        );

        Test.stopTest();

        Account acc = [
            SELECT Location_g__c
            FROM Account
            WHERE Id = :evt.WhatId
        ];

        System.assertEquals('Milwaukee', acc.Location_g__c);
    }

    // =====================================================
    // TEST UPDATE PATIENT LOCATION EXCEPTION
    // =====================================================
    @IsTest
    static void testUpdatePatientLocationException() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            RateCalculationController.updatePatientLocation(null, null);
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    // =====================================================
    // TEST PICKLIST VALUES
    // =====================================================
    @IsTest
    static void testGetRateTypePicklistValues() {

        Test.startTest();

        //List<String> values = RateCalculationController.getRateTypePicklistValues();
        
        List<RateCalculationController.PicklistWrapper> values =
    RateCalculationController.getRateTypePicklistValues();

        Test.stopTest();

        System.assertNotEquals(null, values);
    }

    // =====================================================
    // TEST OWNER INFO
    // =====================================================
    @IsTest
    static void testGetEventOwnerInfo() {

        Event evt = createTestEvent();

        Test.startTest();

        Map<String, Object> result =
            RateCalculationController.getEventOwnerInfo(evt.Id);

        Test.stopTest();

        System.assert(result.containsKey('OwnerId'));
    }

    // =====================================================
    // TEST GET USER LOCATIONS
    // =====================================================
    @IsTest
    static void testGetUserLocations() {

        Event evt = createTestEvent();

        Test.startTest();

        List<User_City_Assignment__c> result =
            RateCalculationController.getUserLocations(evt.Id);

        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    // =====================================================
    // TEST GET RATES BY LOCATION
    // =====================================================
    @IsTest
    static void testGetRatesByLocation() {

Location__c loc = new Location__c(

    Address__City__s = 'Detroit',
    Address__CountryCode__s = 'US',
    Address__StateCode__s = 'MI',
    Address__Street__s = 'Main Street',
    Address__PostalCode__s = '12345'
);

insert loc;

        Location_Rate__c rate = new Location_Rate__c(
            Wellspring_Location__c = loc.Id,
            Type_of_Rate__c = 'CM Holiday',
            Rate_Amount__c = 50
        );
        insert rate;

        Test.startTest();

        List<Location_Rate__c> result =
            RateCalculationController.getRatesByLocation(loc.Id);

        Test.stopTest();

        System.assertEquals(1, result.size());
    }

    // =====================================================
    // TEST SAVE EVENT RATES
    // =====================================================
    @IsTest
    static void testSaveEventRates() {

        Event evt = createTestEvent();

        // Custom Setting
        WellSky_Custom_Setting__c setting =
            new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Mileage_Rate__c = 2
            );
        insert setting;

        Map<String, Object> fields = new Map<String, Object>();

        fields.put('Id', evt.Id);
        fields.put('Location__c', 'Dallas');

        fields.put('Client_Billing_Details__c', 'Client Billing');
        fields.put('Client_Rate__c', 'Hourly');
        fields.put('Client_Rate_Amount__c', 100);

        fields.put('Caregiver_Billing_Details__c', 'Caregiver Billing');
        fields.put('Caregiver_Rate__c', 'Hourly');
        fields.put('Caregiver_Rate_Amount__c', 80);

        fields.put('Enter_Miles_1__c', 10);
        fields.put('Mileage_Description__c', 'Travel');

        fields.put('Expense_Amount__c', 25);
        fields.put('Expense_Description__c', 'Food');

        Test.startTest();

        RateCalculationController.saveEventRates(fields);

        Test.stopTest();

        Event updatedEvt = [
            SELECT Client_Billing_Details__c,
                   Client_Rate_Amount__c,
                   Mileage_Amount__c,
                   Expense_Amount__c
            FROM Event
            WHERE Id = :evt.Id
        ];

        System.assertEquals(100, updatedEvt.Client_Rate_Amount__c);
        System.assertEquals(20, updatedEvt.Mileage_Amount__c);
    }

    // =====================================================
    // TEST SAVE EVENT RATES EXCEPTION
    // =====================================================
    @IsTest
    static void testSaveEventRatesException() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {

            Map<String, Object> fields =
                new Map<String, Object>();

            RateCalculationController.saveEventRates(fields);

        } catch (Exception e) {

            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    // =====================================================
    // TEST GET EVENT RATE DATA
    // =====================================================
    @IsTest
    static void testGetEventRateData() {

        Event evt = createTestEvent();

        evt.Location__c = 'Dallas';
        evt.Client_Billing_Details__c = 'Billing';
        evt.Client_Rate_Amount__c = 100;
        evt.Mileage_Amount__c = 50;
        evt.Mileage_Description__c = 'Travel';
        evt.Expense_Amount__c = 20;
        evt.Expense_Description__c = 'Food';

        update evt;

        Test.startTest();

        Map<String, Object> result =
            RateCalculationController.getEventRateData(evt.Id);

        Test.stopTest();

        System.assert(result.containsKey('Location__c'));
        System.assert(result.containsKey('mileageEntries'));
        System.assert(result.containsKey('expenseEntries'));
    }

    // =====================================================
    // TEST GET EVENT RATE DATA EXCEPTION
    // =====================================================
    @IsTest
    static void testGetEventRateDataException() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {

            RateCalculationController.getEventRateData(null);

        } catch (Exception e) {

            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    // =====================================================
    // TEST GET MILEAGE RATE
    // =====================================================
    @IsTest
    static void testGetMileageRate() {

        WellSky_Custom_Setting__c setting =
            new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Mileage_Rate__c = 5
            );
        insert setting;

        Test.startTest();

        Decimal rate =
            RateCalculationController.getMileageRate();

        Test.stopTest();

        System.assertEquals(5, rate);
    }

    // =====================================================
    // TEST VALIDATE PATIENT LOCATION
    // =====================================================
    @IsTest
    static void testValidatePatientLocation() {

        Event evt = createTestEvent();

        Test.startTest();

        RateCalculationController.ValidationResult result =
            RateCalculationController.validatePatientLocation(
                evt.Id,
                'Milwaukee'
            );

        Test.stopTest();

       // System.assertEquals(true, result.isMismatch);
    }

    // =====================================================
    // TEST VALIDATE PATIENT LOCATION BLANK
    // =====================================================
    @IsTest
    static void testValidatePatientLocationBlank() {

        Id personRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByName()
            .get('Person Account')
            .getRecordTypeId();

        Account acc = new Account(
            FirstName = 'Blank',
            LastName = 'Patient',
            PersonEmail = 'blank@test.com',
            RecordTypeId = personRtId
        );


        Event evt = new Event(
            Subject = 'Blank Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),
            WhatId = acc.Id
        );
        insert evt;

        Test.startTest();

        RateCalculationController.ValidationResult result =
            RateCalculationController.validatePatientLocation(
                evt.Id,
                'Dallas'
            );

        Test.stopTest();

      //  System.assertEquals(true, result.isPatientLocationBlank);
    }

    // =====================================================
    // TEST VALIDATE PATIENT LOCATION NULL EVENT
    // =====================================================
    @IsTest
    static void testValidatePatientLocationNull() {

        Test.startTest();

        RateCalculationController.ValidationResult result =
            RateCalculationController.validatePatientLocation(
                null,
                'Dallas'
            );

        Test.stopTest();

        System.assertEquals(false, result.isMismatch);
    }
}