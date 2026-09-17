@isTest
private class PatientNotesTriggerTest {

    @testSetup
    static void setupData() {
        TriggerControlUtil.reset();

        try {
            WellSky_Custom_Setting__c s = WellSky_Custom_Setting__c.getOrgDefaults();
            if (s == null) {
                s = new WellSky_Custom_Setting__c();
            }
            upsert s;
        } catch (Exception e) {
            // ignore
        }
    }

    static testMethod void testPatientNotesTriggerContexts() {

        TriggerControlUtil.reset();
        
         Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();

        // Create Account
        Account acct = new Account(LastName = 'Test Account', RecordTypeId = prospectRtId);
        insert acct;

        // Insert note
        Patient_Notes__c note = new Patient_Notes__c(
            Name = 'Test Note Insert',
            Account__c = acct.Id
        );
        insert note;

        // Second note for undelete test
        Patient_Notes__c note2 = new Patient_Notes__c(
            Name = 'To Undelete',
            Account__c = acct.Id
        );
        insert note2;

        // SINGLE startTest/stopTest block
        Test.startTest();

        // UPDATE
        note.Name = 'Updated Note';
        update note;

        // DELETE
        delete note;

        // DELETE + UNDELETE
        delete note2;

        Patient_Notes__c deletedNote = [
            SELECT Id
            FROM Patient_Notes__c
            WHERE Id = :note2.Id
            ALL ROWS
        ];

        undelete deletedNote;

        Test.stopTest();

        // Assertions

        // note should be deleted
        Integer deletedCount = [
            SELECT COUNT()
            FROM Patient_Notes__c
            WHERE Id = :note.Id
        ];
        System.assertEquals(0, deletedCount);

        // note2 should be restored
        Patient_Notes__c undeletedAfter = [
            SELECT Id, IsDeleted
            FROM Patient_Notes__c
            WHERE Id = :note2.Id
        ];

        System.assertEquals(false, undeletedAfter.IsDeleted);

        TriggerControlUtil.reset();
    }
}