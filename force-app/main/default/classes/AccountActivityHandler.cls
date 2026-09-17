/*
----------------------------------------------------------------------------
Author        : Bhanu Prakash
Class Name    : AccountActivityHandler
CreatedOn     : 18-03-2026
LastModifiedOn: 18-05-2026
LastModifiedBy: Bhanu Prakash
Description   : This class is used to update the Last Activity Date on the Account based on the created date of Tasks and Events.  

----------------------------------------------------------------------------
*/

public with sharing class AccountActivityHandler {
    

    public static void updateAccountDates(Set<Id> accountIds) {


        if (accountIds == null || accountIds.isEmpty()){
            
            return;
        }
        // old Map<Id, Datetime> accToDate = new Map<Id, Datetime>();
        Map<Id, Date> accToDate = new Map<Id, Date>();

        for (Task t : [
            SELECT WhatId, ActivityDate
            FROM Task
            WHERE WhatId IN :accountIds
            AND ActivityDate != NULL
            ORDER BY WhatId, ActivityDate DESC
        ]) {

            System.debug('Task Found: ' + t.Id +
                     ', WhatId=' + t.WhatId +
                     ', ActivityDate=' + t.ActivityDate);
            if (!accToDate.containsKey(t.WhatId)) {
                accToDate.put(t.WhatId, t.ActivityDate);
            }
        }
        System.debug('Map after Tasks: ' + accToDate);

        

        for (Event e : [
            SELECT WhatId, ActivityDate
            FROM Event
            WHERE WhatId IN :accountIds
            AND ActivityDate != NULL
            ORDER BY WhatId, ActivityDate DESC
        ]) {

             System.debug('Event Found: ' + e.Id +
                     ', WhatId=' + e.WhatId +
                     ', ActivityDate=' + e.ActivityDate);

            Date existingDate = accToDate.get(e.WhatId);

            if (existingDate == null ||
                e.ActivityDate > existingDate) {

                accToDate.put(e.WhatId, e.ActivityDate);
            }
        }
         System.debug('Map after Events: ' + accToDate);
        
        for (AggregateResult ar : [
            SELECT Account__c accId, MAX(CreatedDate) maxDate
            FROM Patient_Notes__c
            WHERE Account__c IN :accountIds
            GROUP BY Account__c
        ]) {
            Id accId = (Id) ar.get('accId');
            //Datetime newDate = (Datetime) ar.get('maxDate');
            Date newDate = ((Datetime) ar.get('maxDate')).date();
            System.debug('Note Found: Account=' + accId +
                     ', Date=' + newDate);
            if (!accToDate.containsKey(accId) || newDate > accToDate.get(accId)) {
                accToDate.put(accId, newDate);
            }
        }
        System.debug('Final Map before Account Update: ' + accToDate);
        
        List<Account> updates = new List<Account>();

        for (Id accId : accountIds) {

            System.debug('Updating Account: ' + accId +
                     ', New Date=' + accToDate.get(accId));

            updates.add(new Account(
                Id = accId,
                Last_Contact_Date__c = accToDate.get(accId) 
            ));
        }

        System.debug('Accounts to Update: ' + updates);

        if (!updates.isEmpty()) {
            update updates;
            System.debug('Accounts updated successfully.');
        }
        System.debug('=== updateAccountDates END ===');
    }

    
    public static Set<Id> extractAccountIdsFromWhatId(Set<Id> whatIds) {
        Set<Id> accountIds = new Set<Id>();

        for (Id wid : whatIds) {
            if (wid != null && String.valueOf(wid).startsWith('001')) {
                accountIds.add(wid);
            }
        }

        return accountIds;
    }
}