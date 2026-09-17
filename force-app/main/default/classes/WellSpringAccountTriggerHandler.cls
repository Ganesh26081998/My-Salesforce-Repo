public without sharing class WellSpringAccountTriggerHandler {

    // Entry point called by the trigger
    public void run() {
        if (Trigger.isBefore) {
            if (Trigger.isUpdate) beforeUpdate((List<Account>) Trigger.new, (Map<Id, Account>) Trigger.oldMap);
        } else if (Trigger.isAfter) {
            if (Trigger.isUpdate) afterUpdate((List<Account>) Trigger.new, (Map<Id, Account>) Trigger.oldMap);
        }
    }

    // BEFORE UPDATE
    // Block any edit on an account that is already deactivated.
    // The bypass flag allows the deactivation controller's own update through.
    private void beforeUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        if (WellSpringAccountDeactivationController.bypassTriggerLock) return;

        for (Account acc : newAccounts) {
            Account oldAcc = oldMap.get(acc.Id);
            if (oldAcc.Is_Deactivated__c) {
                acc.addError('This account has been deactivated and cannot be modified.');
            }

            // Enforce status when an account becomes deactivated (manual or automated).
            if (acc.Is_Deactivated__c && !oldAcc.Is_Deactivated__c) {
                acc.Account_Statusp__c = 'Deactivated';
            }
        }
    }

    // AFTER UPDATE
    // When an admin manually checks Is_Deactivated__c, trigger Approval.lock()
    // asynchronously (the controller handles its own deactivation path directly).
    private void afterUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        if (WellSpringAccountDeactivationController.bypassTriggerLock) return;

        List<Id> tolock = new List<Id>();
        for (Account acc : newAccounts) {
            if (acc.Is_Deactivated__c && !oldMap.get(acc.Id).Is_Deactivated__c) {
                tolock.add(acc.Id);
            }
        }

        if (!tolock.isEmpty()) {
            WellSpringAccountDeactivationController.lockAccountsAsync(tolock);
        }
    }
}