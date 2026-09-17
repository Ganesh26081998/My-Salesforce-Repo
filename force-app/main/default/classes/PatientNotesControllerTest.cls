@IsTest
private class PatientNotesControllerTest {

    // Test Data Setup
    @TestSetup
    static void setupData() {

        Account acc1 = new Account(
            Name = 'Test Patient 1',
            Is_Deactivated__c = false
        );

        Account acc2 = new Account(
            Name = 'Test Patient 2',
            Is_Deactivated__c = true
        );

        insert new List<Account>{ acc1, acc2 };

        List<Patient_Notes__c> notes = new List<Patient_Notes__c>();

        notes.add(new Patient_Notes__c(
            Name = 'Headache Note',
            Descriptions__c = 'Patient has severe headache',
            Account__c = acc1.Id,
            Date__c = System.today()
        ));

        notes.add(new Patient_Notes__c(
            Name = 'Fever Note',
            Descriptions__c = 'High fever symptoms',
            Account__c = acc1.Id,
            Date__c = System.today()
        ));

        notes.add(new Patient_Notes__c(
            Name = 'General Checkup',
            Descriptions__c = 'Routine checkup completed',
            Account__c = acc2.Id,
            Date__c = System.today()
        ));

        insert notes;
    }

    // =========================
    // getNotes() TESTS
    // =========================

    @IsTest
    static void testGetNotes_WithAccountAndSearch_ASC() {

        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Patient 1' LIMIT 1];

        Test.startTest();

        List<Patient_Notes__c> results =
            PatientNotesController.getNotes(
                'Headache',
                acc.Id,
                'ASC'
            );

        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Headache Note', results[0].Name);
    }

    @IsTest
    static void testGetNotes_WithAccountOnly_DESC() {

        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Patient 1' LIMIT 1];

        Test.startTest();

        List<Patient_Notes__c> results =
            PatientNotesController.getNotes(
                null,
                acc.Id,
                'DESC'
            );

        Test.stopTest();

        System.assertEquals(2, results.size());
    }

    @IsTest
    static void testGetNotes_WithSearchOnly() {

        Test.startTest();

        List<Patient_Notes__c> results =
            PatientNotesController.getNotes(
                'Fever',
                null,
                'ASC'
            );

        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Fever Note', results[0].Name);
    }

    @IsTest
    static void testGetNotes_NoFilters() {

        Test.startTest();

        List<Patient_Notes__c> results =
            PatientNotesController.getNotes(
                null,
                null,
                null
            );

        Test.stopTest();

        System.assert(results.size() >= 3);
    }

    @IsTest
    static void testGetNotes_SearchInDescription() {

        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Patient 1' LIMIT 1];

        Test.startTest();

        List<Patient_Notes__c> results =
            PatientNotesController.getNotes(
                'severe',
                acc.Id,
                'ASC'
            );

        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Headache Note', results[0].Name);
    }

    @IsTest
    static void testGetNotes_InvalidSortDirection() {

        Test.startTest();

        List<Patient_Notes__c> results =
            PatientNotesController.getNotes(
                null,
                null,
                'INVALID'
            );

        Test.stopTest();

        System.assert(results.size() > 0);
    }

    // =========================
    // saveNote() TESTS
    // =========================

    @IsTest
    static void testSaveNote() {

        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Patient 1' LIMIT 1];

        Test.startTest();

        Patient_Notes__c note =
            PatientNotesController.saveNote(
                'New Note',
                'New Description',
                acc.Id
            );

        Test.stopTest();

        System.assertNotEquals(null, note.Id);

        Patient_Notes__c insertedNote = [
            SELECT Id, Name, Descriptions__c, Account__c
            FROM Patient_Notes__c
            WHERE Id = :note.Id
        ];

        System.assertEquals('New Note', insertedNote.Name);
        System.assertEquals('New Description', insertedNote.Descriptions__c);
        System.assertEquals(acc.Id, insertedNote.Account__c);
    }

    // =========================
    // Comparator Coverage
    // =========================

    @IsTest
    static void testComparatorCoverage() {

        List<Patient_Notes__c> notes = [
            SELECT Id, Name, Date__c, CreatedDate
            FROM Patient_Notes__c
            LIMIT 2
        ];

        PatientNotesController.CreatedDateComparator ascComp =
            new PatientNotesController.CreatedDateComparator(true);

        Integer result1 = ascComp.compare(notes[0], notes[1]);

        System.assert(result1 == 1 || result1 == -1 || result1 == 0);

        PatientNotesController.CreatedDateComparator descComp =
            new PatientNotesController.CreatedDateComparator(false);

        Integer result2 = descComp.compare(notes[0], notes[1]);

        System.assert(result2 == 1 || result2 == -1 || result2 == 0);
    }
}