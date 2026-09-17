/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : InvoicesCleanupBatch
CreatedOn      : 07-05-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This batch class is used to clean up old Invoice records
                 by retaining only the latest configured number of invoices
                 and deleting older records from the system.
----------------------------------------------------------------------------
*/
global class InvoicesCleanupBatch implements Database.Batchable<SObject> {

    private static final Integer RETENTION_COUNT = 500;

    private Set<Id> latestInvoiceIds = new Set<Id>();
    
    global Database.QueryLocator start(Database.BatchableContext bc) {

        for (Invoice__c inv : [
            SELECT Id
            FROM Invoice__c
            ORDER BY CreatedDate DESC
            LIMIT :RETENTION_COUNT
        ]) {
            latestInvoiceIds.add(inv.Id);
        }

        return Database.getQueryLocator([
            SELECT Id
            FROM Invoice__c
            WHERE Id NOT IN :latestInvoiceIds
        ]);
    }

    // ---------------------------------------------------------------------
    global void execute(
        Database.BatchableContext bc,
        List<SObject> scope
    ) {

        if (scope.isEmpty()) {
            return;
        }

        Database.delete(scope, false);
    }
    
    global void finish(Database.BatchableContext bc) {

        System.debug(
            LoggingLevel.INFO,
            'Old invoices removed. Kept latest ' +
            RETENTION_COUNT +
            ' invoices.'
        );
    }
}