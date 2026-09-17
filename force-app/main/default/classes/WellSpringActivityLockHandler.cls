public without sharing class WellSpringActivityLockHandler {

    /**
     * Called from WellSpringTaskTrigger and WellSpringEventTrigger.
     * Blocks insert/update of Tasks and Events whose WhatId points to
     * a deactivated Account (Is_Deactivated__c = true).
     *
     * WhatId is polymorphic so cross-object validation rules cannot be used.
     */
    public static void blockIfDeactivated(List<SObject> records) {
        // Collect Account IDs from WhatId where the related object is Account
        Set<Id> accountIds = new Set<Id>();
        for (SObject rec : records) {
            Id whatId = (Id) rec.get('WhatId');
            if (whatId != null && whatId.getSObjectType() == Account.SObjectType) {
                accountIds.add(whatId);
            }
        }

        if (accountIds.isEmpty()) return;

        // Query deactivated accounts
        Set<Id> deactivatedIds = new Set<Id>();
        for (Account acc : [SELECT Id FROM Account WHERE Id IN :accountIds AND Is_Deactivated__c = true]) {
            deactivatedIds.add(acc.Id);
        }

        if (deactivatedIds.isEmpty()) return;

        // Block any record linked to a deactivated account
        for (SObject rec : records) {
            Id whatId = (Id) rec.get('WhatId');
            if (deactivatedIds.contains(whatId)) {
                rec.addError('Cannot add or edit timeline activities — this account has been deactivated.');
            }
        }
    }
}