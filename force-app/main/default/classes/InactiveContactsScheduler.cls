/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : InactiveContactsScheduler
CreatedOn      : 02-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This scheduler class is used to execute the
                 InactiveContactsBatch asynchronously using the configured
                 batch size from custom metadata for identifying and notifying
                 Account Owners about inactive Contacts.
----------------------------------------------------------------------------
*/
global class InactiveContactsScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {

        Inactive_Contact_Config__mdt config = [
            SELECT Batch_Size__c
            FROM   Inactive_Contact_Config__mdt
            WHERE  DeveloperName = 'InactiveContactConfig'
            LIMIT  1
        ];

        Integer batchSize = Integer.valueOf(config.Batch_Size__c);
        Database.executeBatch(new InactiveContactsBatch(), batchSize);
    }
}