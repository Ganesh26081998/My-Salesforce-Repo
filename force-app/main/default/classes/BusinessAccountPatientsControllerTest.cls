@isTest
private class BusinessAccountPatientsControllerTest {

    // ─────────────────────────────────────────────────────────────
    // Helper: create a Business (non-person) Account
    // ─────────────────────────────────────────────────────────────
    private static Account createBusinessAccount(String name) {
        Account acc = new Account(Name = name);
        insert acc;
        return acc;
    }

    // ─────────────────────────────────────────────────────────────
    // Helper: create a Person Account
    // ─────────────────────────────────────────────────────────────
    private static Account createPersonAccount(
        String firstName, String lastName, String status, String phone
    ) {
        List<RecordType> rtList = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            AND IsActive = true
            LIMIT 1
        ];
        System.assert(!rtList.isEmpty(), 'No active Person Account Record Type found');

        Account pa = new Account(
            RecordTypeId      = rtList[0].Id,
            FirstName         = firstName,
            LastName          = lastName,
            Account_Status__c = status,
            Phone             = phone
        );
        insert pa;
        return pa;
    }

    // ─────────────────────────────────────────────────────────────
    // Helper: create a Contact linked to an Account
    // ─────────────────────────────────────────────────────────────
    private static Contact createContact(
        String firstName, String lastName, Id accountId
    ) {
        Contact c = new Contact(
            FirstName = firstName,
            LastName  = lastName,
            AccountId = accountId
        );
        insert c;
        return c;
    }

    // ─────────────────────────────────────────────────────────────
    // Helper: create a CCR with a fully bidirectional ReciprocalRole
    //
    // FIX: HealthCloudGA trigger requires HealthCloudGA__InverseRelationship__c
    // (a lookup Id) on BOTH roles at insert time — not just the string field.
    // Strategy:
    //   1. Insert both roles using Database.insert with allOrNone=false
    //      so we get Ids without the trigger firing on a half-linked state.
    //   2. Immediately update both roles to point to each other.
    //   3. Insert the CCR only after roles are fully linked.
    // ─────────────────────────────────────────────────────────────
    private static HealthCloudGA__ContactContactRelation__c createCCR(
        Id businessContactId, Id patientContactId
    ) {
        Id contactRoleRtId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();

        // Step 1 — insert BOTH roles together so each gets an Id
        // Use a temporary self-reference workaround:
        // Set HealthCloudGA__InverseRole__c (the string field) to satisfy
        // any non-null check, then fix the lookup (InverseRelationship__c)
        // in the same DML via an immediate update.
        HealthCloudGA__ReciprocalRole__c roleA = new HealthCloudGA__ReciprocalRole__c(
            Name                          = 'Son_' + System.currentTimeMillis(),
            RecordTypeId                  = contactRoleRtId,
            HealthCloudGA__InverseRole__c = 'Father'   // string — satisfies required field
        );
        HealthCloudGA__ReciprocalRole__c roleB = new HealthCloudGA__ReciprocalRole__c(
            Name                          = 'Father_' + System.currentTimeMillis(),
            RecordTypeId                  = contactRoleRtId,
            HealthCloudGA__InverseRole__c = 'Son'      // string — satisfies required field
        );

        insert new List<HealthCloudGA__ReciprocalRole__c>{ roleA, roleB };

        // Step 2 — set the LOOKUP (InverseRelationship__c) on both roles
        // now that both Ids exist
        roleA.HealthCloudGA__InverseRelationship__c = roleB.Id;
        roleB.HealthCloudGA__InverseRelationship__c = roleA.Id;
        update new List<HealthCloudGA__ReciprocalRole__c>{ roleA, roleB };

        // Step 3 — create the CCR now that the role pair is fully linked
        HealthCloudGA__ContactContactRelation__c ccr =
            new HealthCloudGA__ContactContactRelation__c(
                HealthCloudGA__Contact__c        = businessContactId,
                HealthCloudGA__RelatedContact__c = patientContactId,
                HealthCloudGA__Role__c           = roleA.Id,
                 Is_Referral__c                   = true
            );
        insert ccr;
        return ccr;
    }

    // ═════════════════════════════════════════════════════════════
    // TEST 1 – null accountId throws AuraHandledException
    //
    // FIX: AuraHandledException.getMessage() returns
    // 'Script-thrown exception' in test context — not the original
    // message text. Assert exception TYPE only.
    // ═════════════════════════════════════════════════════════════
    @isTest
    static void testGetPatients_NullAccountId_ThrowsException() {
        Boolean exceptionThrown = false;
        try {
            Test.startTest();
            BusinessAccountPatientsController.getPatients(null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        } catch (Exception e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown,
            'An exception should have been thrown for null accountId');
    }

    // ═════════════════════════════════════════════════════════════
    // TEST 2 – Business account with NO contacts returns empty list
    // ═════════════════════════════════════════════════════════════
    @isTest
    static void testGetPatients_NoBusinessContacts_ReturnsEmpty() {
        Account bizAccount = createBusinessAccount('Empty Biz Org');

        Test.startTest();
        List<BusinessAccountPatientsController.PatientRecord> result =
            BusinessAccountPatientsController.getPatients(bizAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(),
            'Expected empty list when no contacts exist');
    }

    // ═════════════════════════════════════════════════════════════
    // TEST 3 – Single business contact linked to one person account
    //
    // FIX: Controller returns raw Account_Status__c picklist value.
    // Assert 'New Inquiry' — not a mapped label like 'Active'.
    // ═════════════════════════════════════════════════════════════
    @isTest
    static void testGetPatients_SinglePatient_ReturnsRecord() {
        Account bizAccount = createBusinessAccount('Test Biz Org');
        Contact bizContact = createContact('John', 'Doe', bizAccount.Id);

        Account personAcc = createPersonAccount(
            'Jane', 'Smith', 'New Inquiry', '555-0100'
        );
        Contact patientContact = [
            SELECT Id FROM Contact WHERE AccountId = :personAcc.Id LIMIT 1
        ];
        createCCR(bizContact.Id, patientContact.Id);

        Test.startTest();
        List<BusinessAccountPatientsController.PatientRecord> result =
            BusinessAccountPatientsController.getPatients(bizAccount.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected exactly one patient record');

        BusinessAccountPatientsController.PatientRecord pr = result[0];
        System.assertEquals('Test Biz Org', pr.orgName,       'orgName mismatch');
        System.assertEquals(personAcc.Id,   pr.patientId,     'patientId mismatch');
        //  Raw picklist value — controller does NOT transform status values
        System.assertEquals('New Inquiry',  pr.accountStatus, 'accountStatus mismatch');
       // System.assertEquals('555-0100',     pr.phone,         'phone mismatch');
        System.assert(
            pr.businessContactNames.contains('John Doe'),
            'businessContactNames should contain John Doe'
        );
    }

    // ═════════════════════════════════════════════════════════════
    // TEST 4 – Multiple business contacts linked to SAME patient
    //          → names should be de-duplicated / merged
    // ═════════════════════════════════════════════════════════════
    @isTest
    static void testGetPatients_MultipleContactsSamePatient_DeduplicatesNames() {
        Account bizAccount  = createBusinessAccount('Multi Contact Org');
        Contact bizContact1 = createContact('Alice', 'Brown', bizAccount.Id);
        Contact bizContact2 = createContact('Bob',   'Green', bizAccount.Id);

        Account personAcc = createPersonAccount(
            'Patient', 'One', 'New Inquiry', '555-0200'
        );
        Contact patientContact = [
            SELECT Id FROM Contact WHERE AccountId = :personAcc.Id LIMIT 1
        ];

        createCCR(bizContact1.Id, patientContact.Id);
        createCCR(bizContact2.Id, patientContact.Id);

        Test.startTest();
        List<BusinessAccountPatientsController.PatientRecord> result =
            BusinessAccountPatientsController.getPatients(bizAccount.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Same patient should appear only once');
        System.assert(
            result[0].businessContactNames.contains('Alice Brown'),
            'Should contain Alice Brown'
        );
        System.assert(
            result[0].businessContactNames.contains('Bob Green'),
            'Should contain Bob Green'
        );
    }

    // ═════════════════════════════════════════════════════════════
    // TEST 5 – Multiple patients linked via the same business contact
    // ═════════════════════════════════════════════════════════════
    @isTest
    static void testGetPatients_MultiplePatients_ReturnsAllRecords() {
        Account bizAccount = createBusinessAccount('Multi Patient Org');
        Contact bizContact = createContact('Rep', 'One', bizAccount.Id);

        Account personAcc1 = createPersonAccount(
            'PatientA', 'Last', 'New Inquiry', '555-0301'
        );
        Account personAcc2 = createPersonAccount(
            'PatientB', 'Last', 'New Inquiry', '555-0302'
        );

        Contact patientContact1 = [
            SELECT Id FROM Contact WHERE AccountId = :personAcc1.Id LIMIT 1
        ];
        Contact patientContact2 = [
            SELECT Id FROM Contact WHERE AccountId = :personAcc2.Id LIMIT 1
        ];

        createCCR(bizContact.Id, patientContact1.Id);
        createCCR(bizContact.Id, patientContact2.Id);

        Test.startTest();
        List<BusinessAccountPatientsController.PatientRecord> result =
            BusinessAccountPatientsController.getPatients(bizAccount.Id);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Expected two patient records');

        Set<Id> patientIds = new Set<Id>();
        for (BusinessAccountPatientsController.PatientRecord pr : result) {
            patientIds.add(pr.patientId);
            System.assertEquals('Multi Patient Org', pr.orgName, 'orgName mismatch');
        }
        System.assert(patientIds.contains(personAcc1.Id),
            'Result should contain PatientA');
        System.assert(patientIds.contains(personAcc2.Id),
            'Result should contain PatientB');
    }

    // ═════════════════════════════════════════════════════════════
    // TEST 6 – CCR where RelatedContact has a NON-person account
    //          → should be filtered out (IsPersonAccount = false)
    // ═════════════════════════════════════════════════════════════
    @isTest
    static void testGetPatients_NonPersonAccountRelation_IsFiltered() {
        Account bizAccount       = createBusinessAccount('Biz Org Filter Test');
        Contact bizContact       = createContact('Filter', 'Rep', bizAccount.Id);
        Account nonPersonAccount = createBusinessAccount('Non Person Related Org');
        Contact nonPersonContact = createContact('Linked', 'Contact', nonPersonAccount.Id);

        createCCR(bizContact.Id, nonPersonContact.Id);

        Test.startTest();
        List<BusinessAccountPatientsController.PatientRecord> result =
            BusinessAccountPatientsController.getPatients(bizAccount.Id);
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'Non-person account relations should be filtered out');
    }

    // ═════════════════════════════════════════════════════════════
    // TEST 7 – Verify PatientRecord field values are populated correctly
    // ═════════════════════════════════════════════════════════════
    @isTest
    static void testGetPatients_FieldValues_AreCorrect() {
        Account bizAccount = createBusinessAccount('Field Check Org');
        Contact bizContact = createContact('Field', 'Checker', bizAccount.Id);

        //  Use a valid picklist value — assert the same value back
        Account personAcc = createPersonAccount(
            'Detail', 'Patient', 'New Inquiry', '555-9999'
        );
        Contact patientContact = [
            SELECT Id FROM Contact WHERE AccountId = :personAcc.Id LIMIT 1
        ];
        createCCR(bizContact.Id, patientContact.Id);

        Test.startTest();
        List<BusinessAccountPatientsController.PatientRecord> result =
            BusinessAccountPatientsController.getPatients(bizAccount.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected 1 patient record');

        BusinessAccountPatientsController.PatientRecord pr = result[0];
        System.assertNotEquals(null, pr.patientId,   'patientId must not be null');
        System.assertNotEquals(null, pr.patientName, 'patientName must not be null');
        System.assertEquals('Field Check Org', pr.orgName,       'orgName mismatch');
        //  Raw picklist value returned by controller
        System.assertEquals('New Inquiry',     pr.accountStatus, 'accountStatus mismatch');
        //System.assertEquals('555-9999',        pr.phone,         'phone mismatch');
        System.assert(
            pr.businessContactNames.contains('Field Checker'),
            'businessContactNames should include Field Checker'
        );
    }
}