@isTest
private class WellSpringHospitalizationControllerTest {
    @isTest
    static void getHospitalizations_returnsEmptyListWhenAccountIdIsNull() {
        Test.startTest();
        List<Hospitalization__c> results =
            WellSpringHospitalizationController.getHospitalizations(null);
        Test.stopTest();

        System.assertNotEquals(null, results, 'The controller should return a list instance.');
        System.assertEquals(0, results.size(), 'A null account Id should return no hospitalizations.');
    }

    @isTest
    static void getHospitalizations_returnsOnlyMatchingAccountRecordsInNewestFirstOrder() {
        Account patientAccount = new Account(Name = 'Patient Account');
        Account otherAccount = new Account(Name = 'Other Account');
        insert new List<Account>{ patientAccount, otherAccount };

        Hospitalization__c olderHospitalization = new Hospitalization__c(
            Account__c = patientAccount.Id,
            Hospitalization_Status__c = 'Closed - Discharged',
            Admission_Type__c = 'Elective',
            Admission_Date__c = Date.today().addDays(-12),
            Hospital_Name__c = 'First Hospital',
            Primary_diagnosis__c = 'UTI',
            Discharge_Date__c = Date.today().addDays(-8),
            Role_during_hospitalization__c = 'Supporting discharge planning',
            Reason_for_admission__c = 'Planned procedure',
            Current_Hospitalization__c = false
        );
        Hospitalization__c newerHospitalization = new Hospitalization__c(
            Account__c = patientAccount.Id,
            Hospitalization_Status__c = 'Open - Hospitalized',
            Admission_Type__c = 'Emergency',
            Admission_Date__c = Date.today().addDays(-2),
            Hospital_Name__c = 'Second Hospital',
            Primary_diagnosis__c = 'Stroke',
            Role_during_hospitalization__c = 'Navigation/advocacy through hospitalization',
            Reason_for_admission__c = 'Emergency intake',
            Current_Hospitalization__c = true
        );
        Hospitalization__c unrelatedHospitalization = new Hospitalization__c(
            Account__c = otherAccount.Id,
            Hospitalization_Status__c = 'Open - Hospitalized',
            Admission_Type__c = 'Observation',
            Admission_Date__c = Date.today().addDays(-1),
            Hospital_Name__c = 'Other Hospital',
            Primary_diagnosis__c = 'Fall',
            Role_during_hospitalization__c = 'Supporting transition home',
            Reason_for_admission__c = 'Observation stay',
            Current_Hospitalization__c = true
        );
        insert new List<Hospitalization__c>{
            olderHospitalization,
            newerHospitalization,
            unrelatedHospitalization
        };

        Test.setCreatedDate(olderHospitalization.Id, Datetime.newInstance(2024, 1, 10, 8, 0, 0));
        Test.setCreatedDate(newerHospitalization.Id, Datetime.newInstance(2024, 2, 10, 8, 0, 0));
        Test.setCreatedDate(unrelatedHospitalization.Id, Datetime.newInstance(2024, 3, 10, 8, 0, 0));

        Test.startTest();
        List<Hospitalization__c> results =
            WellSpringHospitalizationController.getHospitalizations(patientAccount.Id);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Only hospitalizations for the requested account should be returned.');
        System.assertEquals(newerHospitalization.Id, results[0].Id, 'Newest hospitalization should be first.');
        System.assertEquals(olderHospitalization.Id, results[1].Id, 'Older hospitalization should be second.');
        System.assertEquals(patientAccount.Id, results[0].Account__c);
        System.assertEquals(patientAccount.Id, results[1].Account__c);
        System.assertEquals('Second Hospital', results[0].Hospital_Name__c);
        System.assertEquals('First Hospital', results[1].Hospital_Name__c);
        System.assertEquals(true, results[0].Current_Hospitalization__c);
        System.assertEquals(false, results[1].Current_Hospitalization__c);
    }

    @isTest
    static void deleteHospitalization_deletesRequestedRecord() {
        Account patientAccount = new Account(Name = 'Patient Account');
        insert patientAccount;

        Hospitalization__c hospitalization = new Hospitalization__c(
            Account__c = patientAccount.Id,
            Hospitalization_Status__c = 'Open - Hospitalized',
            Admission_Type__c = 'Emergency',
            Admission_Date__c = Date.today(),
            Hospital_Name__c = 'Delete Test Hospital',
            Primary_diagnosis__c = 'Pneumonia',
            Reason_for_admission__c = 'Emergency intake',
            Current_Hospitalization__c = true
        );
        insert hospitalization;

        Test.startTest();
        WellSpringHospitalizationController.deleteHospitalization(hospitalization.Id);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Hospitalization__c WHERE Id = :hospitalization.Id],
            'The hospitalization record should be deleted.'
        );
    }

    @isTest
    static void deleteHospitalization_throwsForNullId() {
        Boolean didThrow = false;

        try {
            Test.startTest();
            WellSpringHospitalizationController.deleteHospitalization(null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            Test.stopTest();
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'A null Id should throw an AuraHandledException.');
    }
}