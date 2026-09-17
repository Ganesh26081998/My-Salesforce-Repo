/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : BillingSyncBatch
CreatedOn     : 13-12-2025
LastModifiedOn: 22-06-2026
LastModifiedBy: Rohit Dhote
Description   : Syncs pending Billing records to QuickBooks by creating the
                required Customer and Invoice records, then logs the result
                back to Salesforce.
----------------------------------------------------------------------------
*/

public without sharing class BillingSyncBatch implements Database.Batchable<List<Billing__c>>, Database.AllowsCallouts, Database.Stateful {
    private static final String STATUS_SYNCED = 'Synced';
    private static final String STATUS_FAILED = 'Failed';
    private static final String ERROR_LOCATION_REQUIRED = 'Location field is required';
    private static final String ERROR_NO_INVOICE_ID = 'No Invoice ID returned from QB';
    private static final String TIME_ZONE_CHICAGO = 'America/Chicago';

    public Integer successCount = 0;
    public Integer failureCount = 0;
    public Integer skippedCount = 0;

    private Datetime startDateTime;
    private Datetime endDateTime;
    private List<String> locations;
    private List<Id> selectedRecordIds;

    public BillingSyncBatch() {}

    public BillingSyncBatch(Datetime startDateTime, Datetime endDateTime, List<String> locations) {
        this.startDateTime = startDateTime;
        this.endDateTime = endDateTime;
        this.locations = locations;
    }

    public BillingSyncBatch(List<Id> recordIds) {
        this.selectedRecordIds = recordIds;
    }

    // Return Iterable instead of QueryLocator
    public Iterable<List<Billing__c>> start(Database.BatchableContext batchContext) {
        List<Billing__c> billings = Database.query(buildBillingQuery());
        return new BillingGroupIterable(billings);
    }

    // scope now contains groups of List<Billing__c>
    public void execute(Database.BatchableContext batchContext, List<List<Billing__c>> scope) {
        if (scope.isEmpty()) {
            return;
        }

        // Flatten scope to query Accounts & Line Items for all groups in this batch chunk
        List<Billing__c> allBillingsInScope = new List<Billing__c>();
        for (List<Billing__c> groupList : scope) {
            allBillingsInScope.addAll(groupList);
        }

        Map<Id, Account> accountsById = getAccountsById(allBillingsInScope);
        Map<Id, List<Billing_Line_Item__c>> lineItemsByBillingId = getLineItemsByBillingId(allBillingsInScope);

        List<Account> accountsToUpdate = new List<Account>();
        List<Billing__c> billingsToUpdate = new List<Billing__c>();
        List<Billing_Line_Item__c> lineItemsToUpdate = new List<Billing_Line_Item__c>();
        List<QB_Customer_Location__c> locationRecordsToUpsert = new List<QB_Customer_Location__c>();

        // Process each pre-grouped list (one group = 1 customer + 1 location)
        for (List<Billing__c> groupedBillings : scope) {
            Account client = accountsById.get(groupedBillings[0].Client__c);

            List<Billing_Line_Item__c> combinedLineItems = new List<Billing_Line_Item__c>();
            for (Billing__c b : groupedBillings) {
                if (lineItemsByBillingId.containsKey(b.Id) && lineItemsByBillingId.get(b.Id) != null) {
                    combinedLineItems.addAll(lineItemsByBillingId.get(b.Id));
                }
            }

            processBillingGroup(
                groupedBillings,
                client,
                combinedLineItems,
                accountsToUpdate,
                billingsToUpdate,
                lineItemsToUpdate,
                locationRecordsToUpsert
            );
        }

        updateRecords(accountsToUpdate, billingsToUpdate, lineItemsToUpdate, locationRecordsToUpsert);
    }

    public void finish(Database.BatchableContext batchContext) {
        try {
            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedBy.Email
                FROM AsyncApexJob
                WHERE Id = :batchContext.getJobId()
            ];

            sendCompletionEmail(job);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to send QuickBooks sync completion email: ' + e.getMessage());
        }
    }

    private String buildBillingQuery() {
        String query =
            'SELECT Id, Name, Client__c, Amount__c, Due_Date__c, Invoice_Date__c, ' +
            'QB_Invoice_Id__c, QB_Sync_Status__c, Notes__c, Location_g__c, Is_Synced__c, ' +
            'Event_Start_Date_Time__c, Event_End_Date_Time__c ' +
            'FROM Billing__c ' +
            'WHERE Is_Synced__c = false ' +
            'AND QB_Sync_Status__c != :STATUS_SYNCED';

        if (startDateTime != null) {
            query += ' AND Event_Start_Date_Time__c >= :startDateTime';
        }

        if (endDateTime != null) {
            query += ' AND Event_End_Date_Time__c <= :endDateTime';
        }

        if (locations != null && !locations.isEmpty()) {
            query += ' AND Location_g__c IN :locations';
        }

        if (selectedRecordIds != null && !selectedRecordIds.isEmpty()) {
            query += ' AND Id IN :selectedRecordIds';
        }

        query += ' ORDER BY Client__c ASC, Location_g__c ASC, CreatedDate ASC';

        return query;
    }

    private Map<Id, Account> getAccountsById(List<Billing__c> billings) {
        Set<Id> accountIds = new Set<Id>();
        for (Billing__c billing : billings) {
            if (billing.Client__c != null) {
                accountIds.add(billing.Client__c);
            }
        }

        if (accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }

        return new Map<Id, Account>([
            SELECT Id, Name, QB_Customer_Id__c, PersonEmail, Mobile_Phones__c,
                   Address__Street__s, Address__City__s, Address__StateCode__s,
                   Address__PostalCode__s, Address__CountryCode__s
            FROM Account
            WHERE Id IN :accountIds
        ]);
    }

    private Map<Id, List<Billing_Line_Item__c>> getLineItemsByBillingId(List<Billing__c> billings) {
        Map<Id, List<Billing_Line_Item__c>> lineItemsByBillingId = new Map<Id, List<Billing_Line_Item__c>>();
        Set<Id> billingIds = new Set<Id>();

        for (Billing__c billing : billings) {
            billingIds.add(billing.Id);
        }

        if (billingIds.isEmpty()) {
            return lineItemsByBillingId;
        }

        for (Billing_Line_Item__c lineItem : [
            SELECT Id, Invoice__c, Description__c, Quantity__c, Rate__c, Amount__c, Type__c
            FROM Billing_Line_Item__c
            WHERE Invoice__c IN :billingIds
            AND Type__c != :QuickBooksInvoiceService.EXCLUDED_LINE_ITEM_TYPE
            ORDER BY CreatedDate ASC
        ]) {
            if (!lineItemsByBillingId.containsKey(lineItem.Invoice__c)) {
                lineItemsByBillingId.put(lineItem.Invoice__c, new List<Billing_Line_Item__c>());
            }
            lineItemsByBillingId.get(lineItem.Invoice__c).add(lineItem);
        }

        return lineItemsByBillingId;
    }

    private void processBillingGroup(
        List<Billing__c> billings,
        Account client,
        List<Billing_Line_Item__c> combinedLineItems,
        List<Account> accountsToUpdate,
        List<Billing__c> billingsToUpdate,
        List<Billing_Line_Item__c> lineItemsToUpdate,
        List<QB_Customer_Location__c> locationRecordsToUpsert
    ) {
        Billing__c primary = billings[0];
        String location = primary.Location_g__c;

        try {
            validateBillingGroup(billings, client);
            ensureQuickBooksCustomer(client, location, locationRecordsToUpsert);

            QuickBooksInvoiceService.InvoiceResult invoiceResult = QuickBooksInvoiceService.createInvoiceResult(
                billings,
                client,
                location,
                combinedLineItems
            );

            if (String.isNotBlank(invoiceResult.invoiceId)) {
                for (Billing__c b : billings) {
                    markBillingSynced(b, invoiceResult.invoiceId);
                    billingsToUpdate.add(b);
                    successCount++;
                }
                lineItemsToUpdate.addAll(invoiceResult.lineItemsToUpdate);
            } else {
                for (Billing__c b : billings) {
                    markBillingFailed(b, ERROR_NO_INVOICE_ID);
                    billingsToUpdate.add(b);
                    failureCount++;
                }
            }
        } catch (BillingSkipException e) {
            for (Billing__c b : billings) {
                markBillingFailed(b, e.getMessage());
                billingsToUpdate.add(b);
                skippedCount++;
            }
        } catch (Exception e) {
            for (Billing__c b : billings) {
                markBillingFailed(b, e.getMessage());
                billingsToUpdate.add(b);
                failureCount++;
            }
        }
    }

    private void validateBillingGroup(List<Billing__c> billings, Account client) {
        String location = billings[0].Location_g__c;
        if (String.isBlank(location)) {
            throw new BillingSkipException(ERROR_LOCATION_REQUIRED);
        }
        if (!QuickBooksCredentialManager.isLocationCredentialConfigured(location)) {
            throw new QuickBooksException('No QB credential for location: ' + location);
        }
        if (billings[0].Client__c == null || client == null) {
            throw new QuickBooksException('Client account is required for QuickBooks sync');
        }
    }

    private void ensureQuickBooksCustomer(
        Account client,
        String location,
        List<QB_Customer_Location__c> locationRecordsToUpsert
    ) {
        String currentId = QuickBooksCustomerService.getCustomerIdForLocation(client.Id, location);

        client.QB_Customer_Id__c = currentId;

        String quickBooksCustomerId = QuickBooksCustomerService.createOrUpdateCustomer(client, location);

        client.QB_Customer_Id__c = quickBooksCustomerId;

        if (currentId != quickBooksCustomerId) {
            locationRecordsToUpsert.add(
                new QB_Customer_Location__c(
                    Account__c = client.Id,
                    Location__c = location,
                    QB_Customer_Id__c = quickBooksCustomerId
                )
            );
        }
    }

    private void markBillingSynced(Billing__c billing, String quickBooksInvoiceId) {
        billing.QB_Invoice_Id__c = quickBooksInvoiceId;
        billing.QB_Sync_Status__c = STATUS_SYNCED;
        billing.Is_Synced__c = true;
        billing.Synced_Date__c = System.now();
        billing.QB_Sync_Error__c = null;
    }

    private void markBillingFailed(Billing__c billing, String errorMessage) {
        billing.QB_Sync_Status__c = STATUS_FAILED;
        billing.QB_Sync_Error__c = errorMessage;
    }

    private void updateRecords(
        List<Account> accountsToUpdate,
        List<Billing__c> billingsToUpdate,
        List<Billing_Line_Item__c> lineItemsToUpdate,
        List<QB_Customer_Location__c> locationRecordsToUpsert
    ) {
        if (!locationRecordsToUpsert.isEmpty()) {
            Set<Id> accountIds = new Set<Id>();
            Set<String> locationNames = new Set<String>();
            for (QB_Customer_Location__c r : locationRecordsToUpsert) {
                accountIds.add(r.Account__c);
                locationNames.add(r.Location__c);
            }

            Map<String, Id> existingKeyToId = new Map<String, Id>();
            for (QB_Customer_Location__c existing : [
                SELECT Id, Account__c, Location__c
                FROM QB_Customer_Location__c
                WHERE Account__c IN :accountIds
                AND Location__c IN :locationNames
            ]) {
                existingKeyToId.put(existing.Account__c + '_' + existing.Location__c, existing.Id);
            }

            for (QB_Customer_Location__c r : locationRecordsToUpsert) {
                String key = r.Account__c + '_' + r.Location__c;
                if (existingKeyToId.containsKey(key)) {
                    r.Id = existingKeyToId.get(key);
                }
            }

            upsert locationRecordsToUpsert;
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
        if (!lineItemsToUpdate.isEmpty()) {
            update lineItemsToUpdate;
        }
        if (!billingsToUpdate.isEmpty()) {
            update billingsToUpdate;
        }
    }

    private void sendCompletionEmail(AsyncApexJob job) {
        if (String.isBlank(job.CreatedBy.Email)) {
            return;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ job.CreatedBy.Email });
        mail.setSubject(failureCount > 0 ? 'QuickBooks Sync Alert: Failures Detected' : 'QuickBooks Sync Completed Successfully');
        mail.setPlainTextBody(buildCompletionEmailBody(job));

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    private String buildCompletionEmailBody(AsyncApexJob job) {
        String cstTime = System.now().format('MM/dd/yyyy hh:mm a', TIME_ZONE_CHICAGO);

        return 'The QuickBooks Sync process finished on: ' + cstTime + ' CST\n\n' +
            'Total Batches: ' + job.TotalJobItems + '\n' +
            'Synced Billings: ' + successCount + '\n' +
            'Failed Billings: ' + failureCount + '\n' +
            'Skipped Billings: ' + skippedCount + '\n\n' +
            'Note: Multiple billing records for the same client have been consolidated into single QuickBooks invoices.\n\n' +
            'Please review the Salesforce Billing records to identify any specific error messages.';
    }

    private class BillingSkipException extends Exception {}
}