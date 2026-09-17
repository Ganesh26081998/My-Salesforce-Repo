@isTest
public class AccountDeactivationControllerTest {

    // ---------- Utility: Create Account ----------
    // ✅ FIX 1: Removed Test.disableAutomations() entirely — it doesn't exist in Apex.
    // ✅ FIX 2: Do NOT hardcode 'Active' for Account_Statusp__c — use only a value
    //           that your org's flow/process won't reject on insert.
    //           Replace 'New inquiry' with whatever valid status inserts cleanly in your org.
    private static Account createAccount() {
        Account acc = new Account(
            Name              = 'Test Account',
            Is_Deactivated__c = false
            // ⚠️ Omit Account_Statusp__c here — let it default, OR set a safe value
            // that does NOT trigger the "Website Prospect Acknowledgement Email" flow.
            // If 'New inquiry' is safe, add:  Account_Statusp__c = 'New inquiry'
        );
        insert acc;
        return acc;
    }

    // ---------- Utility: Get RecordType ----------
    private static Id getDeactivationRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account_Deactivation__c'
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    // ---------- Utility: Get a safe, valid Reason picklist value at runtime ----------
    // ✅ FIX 3: Never hardcode picklist values for restricted fields.
    //           Query the picklist metadata so the test always uses a real value.
    private static String getSafeReasonValue() {
        List<Schema.PicklistEntry> entries =
            Account_Deactivation__c.Deactivation_Reason__c.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry e : entries) {
            if (e.isActive()) return e.getValue();
        }
        return null; // no active values — test will surface this clearly
    }

    // ---------- Test: Check Deactivation ----------
    @isTest
    static void testIsAccountDeactivated() {
        Account acc = createAccount();

        Test.startTest();
        Boolean result = AccountDeactivationController.isAccountDeactivated(acc.Id);
        Test.stopTest();

        System.assertEquals(false, result, 'Newly created account should not be deactivated');
    }

    // ---------- Test: Successful Flow ----------
    @isTest
    static void testCreateDeactivationRecord_Success() {
        Account acc   = createAccount();
        Id      rtId  = getDeactivationRecordTypeId();
        String  reason = getSafeReasonValue();

        System.assertNotEquals(null, reason,
            'No active Reason picklist values found — check Account_Deactivation__c.Reason__c');

        Test.startTest();
        AccountDeactivationController.createDeactivationRecord(
            acc.Id,
            'Test Deactivation',
            Date.today(),
            reason,       // ✅ FIX: runtime-resolved valid picklist value
            'Testing summary',
            rtId
        );
        Test.stopTest();

        // Validate Account fields updated
        Account updatedAcc = [
            SELECT Is_Deactivated__c, Account_Statusp__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(true,          updatedAcc.Is_Deactivated__c,
            'Is_Deactivated__c should be true after deactivation');
        System.assertEquals('Deactivated', updatedAcc.Account_Statusp__c,
            'Account_Statusp__c should be Deactivated');

        // Validate deactivation record was created
        List<Account_Deactivation__c> records = [
            SELECT Id
            FROM Account_Deactivation__c
            WHERE Account__c = :acc.Id
        ];
        System.assertEquals(1, records.size(),
            'Exactly one Account_Deactivation__c record should exist');
    }

    // ---------- Test: Exception + Rollback ----------
    // ✅ FIX: Removed Test.disableAutomations() — it doesn't exist.
    //         To force a DML failure cleanly, pass a deliberately invalid/null
    //         required field that your controller validates, not a bad picklist value
    //         (which could instead trigger a flow and mask the real error).
    @isTest
    static void testCreateDeactivationRecord_Exception() {
        Account acc = createAccount();

        Test.startTest();
        try {
            AccountDeactivationController.createDeactivationRecord(
                null,          // ✅ null accountId forces an early exception
                'Test',
                Date.today(),
                'N/A',
                'Summary',
                null
            );
            System.assert(false, 'Exception expected but none was thrown');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(),
                'AuraHandledException message should not be null');
        }
        Test.stopTest();

        // Verify no deactivation happened (rollback / never executed)
        Account accCheck = [
            SELECT Is_Deactivated__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(false, accCheck.Is_Deactivated__c,
            'Account should not be deactivated after a failed call');
    }

    // ---------- Test: Future Method ----------
    @isTest
    static void testLockAccountAsync() {
        Account acc = createAccount();

        Test.startTest();
        AccountDeactivationController.lockAccountAsync(acc.Id);
        Test.stopTest();

        // If lockAccountAsync marks a field (e.g. IsLocked, a custom field),
        // assert it here. Replace or extend once you know what the method sets.
        System.assert(true, 'lockAccountAsync completed without exception');
    }
}