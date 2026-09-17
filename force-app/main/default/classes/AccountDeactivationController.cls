public without sharing class AccountDeactivationController {

    public static Boolean bypassTriggerLock = false;

    // Queried server-side so FLS on Is_Deactivated__c never prevents the LWC
    // from detecting an already-deactivated account.
    @AuraEnabled(cacheable=true)
    public static Boolean isAccountDeactivated(Id accountId) {
        return [SELECT Is_Deactivated__c FROM Account WHERE Id = :accountId LIMIT 1]
               .Is_Deactivated__c == true;
    }

    @AuraEnabled
    public static void createDeactivationRecord(
        Id     accountId,
        String name,
        Date   deactivationDate,
        String deactivationReason,
        String deactivationSummary,
        Id     recordTypeId
    ) {
        Savepoint sp = Database.setSavepoint();
        try {
            // ── Step 1: Create the deactivation record ────────────────────────
            insert new Account_Deactivation__c(
                Name                    = name,
                Account__c              = accountId,
                Deactivation_Date__c    = deactivationDate,
                Deactivation_Reason__c  = deactivationReason,
                Deactivation_summary__c = deactivationSummary,
                RecordTypeId            = recordTypeId
            );

            // ── Step 2: Check the checkbox (before trigger bypassed) ──────────
            bypassTriggerLock = true;
            update new Account(
                Id                = accountId,
                Is_Deactivated__c = true,
                Account_Statusp__c = 'Deactivated'
            );

        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        } finally {
            bypassTriggerLock = false;
        }

        // ── Step 3: Attempt Approval.lock() after the transaction commits ─────
        lockAccountAsync(accountId);
    }

    // Runs in its own transaction after the main one commits.
    // No try-catch so any failure is visible in debug logs.
    @future
    public static void lockAccountAsync(Id accountId) {
        
    if (!Test.isRunningTest()) {
        Approval.lock(accountId);
    }
       // Approval.lock(accountId);
    }
}