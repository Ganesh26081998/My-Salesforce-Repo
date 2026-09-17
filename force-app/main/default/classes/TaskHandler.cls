/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : TaskHandler
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : This Apex class automatically populates a custom text field 
                on a Task with the actual name of its related Contact or Account.
----------------------------------------------------------------------------
*/

public class TaskHandler {
    
    public static void setCustomerName(List<Task> tasks) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        
        // Collect all IDs
        for (Task task : tasks) {
            if (task.WhoId != null && String.valueOf(task.WhoId).startsWith('003')) {
                contactIds.add(task.WhoId);
            } else if (task.WhatId != null && String.valueOf(task.WhatId).startsWith('001')) {
                accountIds.add(task.WhatId);
            }
        }
        
        // Query Contact and Account data
        Map<Id, Contact> contacts = new Map<Id, Contact>(
            [SELECT Id, Name FROM Contact WHERE Id IN :contactIds]
        );
        Map<Id, Account> accounts = new Map<Id, Account>(
            [SELECT Id, Name FROM Account WHERE Id IN :accountIds]
        );
        
        // Set Customer Name
        for (Task task : tasks) {
            if (task.WhoId != null && contacts.containsKey(task.WhoId)) {
                task.Customer_Name__c = contacts.get(task.WhoId).Name;
            } else if (task.WhatId != null && accounts.containsKey(task.WhatId)) {
                task.Customer_Name__c = accounts.get(task.WhatId).Name;
            }
        }
    }
}