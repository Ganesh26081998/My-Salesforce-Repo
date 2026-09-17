@IsTest
private class MedicationControllerTest {

    @TestSetup
    static void setupData() {

        Account acc = new Account(
            LastName = 'Test Patient',
            RecordTypeId = Schema.SObjectType.Account
                .getRecordTypeInfosByName()
                .get('Prospect')
                .getRecordTypeId()
        );
        insert acc;

        Medication m = new Medication(
            Name = 'Test Medication'
        );
        insert m;

        MedicationStatement ms = new MedicationStatement(
            PatientId                     = acc.Id,
            Client_Instruction__c        = 'After Food',
            Comments__c                  = 'Test Comments',
            DosageQuantityType__c        = 'Tablet',
            DosageQuantityDenominator__c = 2,
            DosageQuantityNumerator__c   = 1,
            MedicationId                 = m.Id
        );
        insert ms;

        PatientMedicationDosage pmd =
            new PatientMedicationDosage(
                ParentRecordId             = ms.Id,
                PatientInstruction      = 'Morning',
                Comments                       = 'PMD Comments',
                DosageQuantityType         = 'Capsule',
                DosageQuantityDenominator  = 5,
                DosageQuantityNumerator    = 2
            );
        insert pmd;

        Account accForCs = [SELECT Id FROM Account LIMIT 1];

        WellSky_Custom_Setting__c cs =
            WellSky_Custom_Setting__c.getInstance(UserInfo.getUserId());

        if (cs == null) {
            cs = new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getUserId()
            );
        }

        // Store as JSON map keyed by accountId, matching the current format
        Map<String, Object> colMap = new Map<String, Object>();
        colMap.put(
            (String) accForCs.Id,
            'MS.Client_Instruction__c,' +
            'MS.Comments__c,' +
            'MS.DosageQuantityType__c,' +
            'MS.DosageQuantityDenominator__c,' +
            'MS.DosageQuantityNumerator__c'
        );
        cs.Columns_On_Medication__c = JSON.serialize(colMap);

        upsert cs;
    }

    @IsTest
    static void testConstructor() {

        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Test.setCurrentPage(
            Page.MedicationPrintPage
        );

        ApexPages.currentPage()
            .getParameters()
            .put('recordId', acc.Id);

        Test.startTest();

        MedicationController controller =
            new MedicationController();

        Test.stopTest();

        System.assertNotEquals(
            null,
            controller.medications
        );

        System.assertEquals(
            1,
            controller.medications.size()
        );

        System.assertEquals(
            'Test Medication',
            controller.medications[0].medicationName
        );
    }

    @IsTest
    static void testGetAvailableFields() {

        Test.startTest();

        List<MedicationController.FieldOption> result =
            MedicationController.getAvailableFields();

        Test.stopTest();

        System.assert(
            result.size() > 0
        );
    }

    @IsTest
    static void testSaveSelectedFields() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<String> fields = new List<String>{
            'MedicationStatement.Route_CSB__c',
            'MedicationStatement.Comments__c'
        };

        Test.startTest();

        MedicationController.saveSelectedFields(fields, acc.Id);

        Test.stopTest();

        WellSky_Custom_Setting__c cs =
            WellSky_Custom_Setting__c.getInstance(UserInfo.getUserId());

        System.assertNotEquals(
            null,
            cs.Columns_On_Medication__c
        );

        // Verify the saved value is a JSON map containing the account's entry
        Map<String, Object> colMap =
            (Map<String, Object>) JSON.deserializeUntyped(cs.Columns_On_Medication__c);

        System.assert(
            colMap.containsKey((String) acc.Id),
            'Expected saved columns to be keyed by accountId'
        );
    }

    @IsTest
    static void testGetMedicationData() {

        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Test.startTest();

        MedicationController.MedicationResponse response =
            MedicationController.getMedicationData(acc.Id, 'CreatedDate', 'desc');

        Test.stopTest();

        System.assertNotEquals(
            null,
            response
        );

        System.assertEquals(
            1,
            response.records.size()
        );        
    }

    @IsTest
    static void testGetMedicationDataWithInvalidSort() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // Invalid sortBy should fall back to CreatedDate without throwing
        MedicationController.MedicationResponse response =
            MedicationController.getMedicationData(acc.Id, 'invalid_field__c', 'desc');
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(1, response.records.size());
    }

    @IsTest
    static void testGetMedicationDataWithInvalidSortDir() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // Invalid sortDir should fall back to DESC without throwing
        MedicationController.MedicationResponse response =
            MedicationController.getMedicationData(acc.Id, 'CreatedDate', 'INVALID');
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(1, response.records.size());
    }

    @IsTest
    static void testSaveSelectedFieldsAndReload() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<String> fields = new List<String>{
            'MedicationStatement.Comments__c'
        };

        Test.startTest();

        MedicationController.saveSelectedFields(fields, acc.Id);

        // Reload data after save — should reflect newly saved fields
        MedicationController.MedicationResponse response =
            MedicationController.getMedicationData(acc.Id, 'CreatedDate', 'desc');

        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(1, response.records.size());
        System.assertEquals(1, response.selectedFields.size());
    }

    @IsTest
    static void testLegacyFlatStringMigration() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Simulate a legacy flat string (pre-JSON-map format)
        WellSky_Custom_Setting__c cs =
            WellSky_Custom_Setting__c.getInstance(UserInfo.getUserId());

        if (cs == null) {
            cs = new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getUserId()
            );
        }

        cs.Columns_On_Medication__c = 'MS.Comments__c,MS.DosageQuantityType__c';
        upsert cs;

        Test.startTest();

        MedicationController.MedicationResponse response =
            MedicationController.getMedicationData(acc.Id, 'CreatedDate', 'desc');

        Test.stopTest();

        // Legacy format should still resolve without throwing
        System.assertNotEquals(null, response);
        System.assertEquals(1, response.records.size());
    }
}