/*
----------------------------------------------------------------------------
Author        : Prasad Patil
Class Name    : WellSpringAccountDeactivationController
CreatedOn     : 13-03-2026
LastModifiedOn: 15-05-2026
LastModifiedBy: Tushar Darode
Description   : This controller is used to manage Account deactivation 
                functionality. It supports checking deactivation status,
                retrieving latest deactivation details, fetching 
                deactivation reason picklist values, creating Account 
                deactivation records, updating Account deactivation status,
                and handling post-deactivation account locking operations.
----------------------------------------------------------------------------
*/

public without sharing class WellSpringAccountDeactivationController {

    public static Boolean bypassTriggerLock = false;

    // Queried server-side so FLS on Is_Deactivated__c never prevents the LWC
    // from detecting an already-deactivated account.
    @AuraEnabled(cacheable=true)
    public static Boolean isAccountDeactivated(Id accountId) {
        return [SELECT Is_Deactivated__c FROM Account WHERE Id = :accountId LIMIT 1]
               .Is_Deactivated__c == true;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLatestDeactivationData(Id accountId) {
        Map<String, Object> result = new Map<String, Object>();
        if (accountId == null) return result;

        Map<String, Schema.SObjectField> fieldsMap =
            Account_Deactivation__c.SObjectType.getDescribe().fields.getMap();
        Boolean hasOtherReason = fieldsMap.containsKey('Other_Reason__c');

        List<String> selectedFields = new List<String>{
            'Name',
            'Deactivation_Date__c',
            'Deactivation_Reason__c',
            'Deactivation_summary__c'
        };
        if (hasOtherReason) {
            selectedFields.add('Other_Reason__c');
        }

        String soql =
            'SELECT ' + String.join(selectedFields, ',') +
            ' FROM Account_Deactivation__c' +
            ' WHERE Account__c = :accountId' +
            ' ORDER BY CreatedDate DESC LIMIT 1';

        List<SObject> rows = Database.query(soql);
        if (rows.isEmpty()) return result;

        SObject latest = rows[0];
        result.put('name', latest.get('Name'));
        result.put('deactivationDate', latest.get('Deactivation_Date__c'));
        result.put('deactivationReason', latest.get('Deactivation_Reason__c'));
        result.put('deactivationSummary', latest.get('Deactivation_summary__c'));
        if (hasOtherReason) {
            result.put('otherReason', latest.get('Other_Reason__c'));
        }
        return result;
    }

     @AuraEnabled(cacheable=true)
    public static List<String> getDeactivationReasonOptions() {
        List<String> options = new List<String>();
        for (Schema.PicklistEntry entry :
             Account_Deactivation__c.Deactivation_Reason__c.getDescribe().getPicklistValues()) {
                 if (entry.isActive()) {
                     options.add(entry.getValue());
                 }
             }
        return options;
    }

    @AuraEnabled
    public static void createDeactivationRecord(
        Id     accountId,
        String name,
        Date   deactivationDate,
        String deactivationReason,
        String otherReason,
        String deactivationSummary        
    ) {
        Savepoint sp = Database.setSavepoint();
        try {
            Date effectiveDate = deactivationDate == null ? Date.today() : deactivationDate;

            // Step 1: Create the deactivation record
            Account_Deactivation__c deactivation = new Account_Deactivation__c(
                Name                    = name,
                Account__c              = accountId,
                Deactivation_Date__c    = effectiveDate,
                Deactivation_Reason__c  = deactivationReason,
                Deactivation_summary__c = deactivationSummary
                
            );

            if (String.isNotBlank(otherReason)) {
                Map<String, Schema.SObjectField> fieldsMap =
                    Account_Deactivation__c.SObjectType.getDescribe().fields.getMap();
                if (fieldsMap.containsKey('Other_Reason__c')) {
                    deactivation.put('Other_Reason__c', otherReason);
                } else {
                    String existingSummary = (String)deactivation.get('Deactivation_summary__c');
                    String prefix = String.isBlank(existingSummary) ? '' : existingSummary + '\n';
                    deactivation.put('Deactivation_summary__c', prefix + 'Other Reason: ' + otherReason);
                }
            }

            insert deactivation;

            // Step 2: Link the deactivation record on Account while it is still active
            // (done as a separate DML before deactivation so no deactivation-related
            // trigger or flow can interfere with setting this lookup)
            update new Account(
                Id                      = accountId,
                Account_Deactivation__c = deactivation.Id
            );

            // Step 3: Deactivate the Account (bypass trigger to allow the update)
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

        // Step 3: Attempt Approval.lock() after the transaction commits
        lockAccountAsync(accountId);
    }

    // Backward-compatible single-record entry point.
    public static void lockAccountAsync(Id accountId) {
        if (accountId == null) return;
        lockAccountsAsync(new List<Id>{ accountId });
    }

    // Runs in its own transaction after the main one commits.
    // Supports trigger-driven bulk locking and legacy callers.
    @future
    public static void lockAccountsAsync(List<Id> accountIds) {
     /*   if (accountIds == null || accountIds.isEmpty()) return;
        for (Id accountId : accountIds) {
            if (accountId != null) {
                Approval.lock(accountId);
            }
        }*/
    }
}