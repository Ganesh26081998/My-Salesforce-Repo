/*
----------------------------------------------------------------------------
Author        : Tushar Darode
Class Name    : AccountActivationController
CreatedOn     : 13-01-2026
LastModifiedOn: 15-04-2026
LastModifiedBy: Tushar Darode
Description   : This class is used to convert the prospect into the active patient.
----------------------------------------------------------------------------
*/

public with sharing class AccountActivationController {
 
    // Mock wrapper to intercept execution context during test runs
    @TestVisible private static Boolean mockObjectAccess = true;
    @TestVisible private static Boolean mockFieldAccess = true;
    @TestVisible private static Boolean forceDmlException = false;
    @TestVisible private static Id mockPersonAccountRtId = null;
 
    @AuraEnabled
    public static ActivationResult activateAccount(Id accountId) {
 
        ActivationResult result = new ActivationResult();
 
        // ---------- Input Validation ----------
        if (accountId == null) {
            result.success = false;
            result.message = 'Account Id is required.';
            return result;
        }
 
        // ---------- Security ----------
        if (!mockObjectAccess || !Schema.sObjectType.Account.isAccessible() || !Schema.sObjectType.Account.isUpdateable()) {
            result.success = false;
            result.message = 'Insufficient access to Account.';
            return result;
        }
 
        if (!mockFieldAccess || !Schema.sObjectType.Account.fields.Account_Status__c.isUpdateable()) {
            result.success = false;
            result.message = 'Insufficient access to Account Status.';
            return result;
        }
 
        try {
            Account acc = [
                SELECT Id, IsPersonAccount, Account_Status__c
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
 
            if (!acc.IsPersonAccount) {
                result.success = false;
                result.message = 'Only Person Accounts can be activated.';
                return result;
            }
 
            if (acc.Account_Status__c == 'Client') {
                result.success = false;
                result.message = 'Account is already activated.';
                return result;
            }
 
            acc.Account_Status__c = 'Client';
            // Forces DmlException cleanly inside the test run
            //if (forceDmlException) {
             //   throw new DmlException('Forced Mock DML Exception Error');
            //}
            if (forceDmlException && Test.isRunningTest()) {
                acc.addError('Forced Mock DML Exception Error');
            }
            update acc;
 
            result.success = true;
            result.message = 'Person Account activated successfully.';
        }
        // catch (DmlException e) {
        //     result.success = false;
        //     result.message = e.getMessage();
        // }
        catch (DmlException e) {
            result.success = false;

            String cleanMessage = e.getDmlMessage(0);

            // Remove Salesforce validation wrapper text
            if (cleanMessage.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION')) {

                Integer commaIndex = cleanMessage.indexOf(',');
                Integer fieldIndex = cleanMessage.indexOf(': [');

                if (commaIndex != -1 && fieldIndex != -1) {
                    cleanMessage = cleanMessage.substring(
                        commaIndex + 1,
                        fieldIndex
                    ).trim();
                }
            }

            result.message = cleanMessage;
        }


        catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
        }
 
        return result;
    }
 
    public class ActivationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }
}