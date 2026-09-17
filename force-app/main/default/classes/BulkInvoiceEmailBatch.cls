/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : BulkInvoiceEmailBatch
CreatedOn      : 30-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This batch class is used to generate invoices in bulk and
                 send invoice emails to clients for the selected date range.
                 It supports both Standard Invoice and Super Bill generation,
                 tracks processing status, email failures, and updates the
                 batch job summary after completion.
----------------------------------------------------------------------------
*/
global class BulkInvoiceEmailBatch
    implements Database.Batchable<SObject>,
               Database.Stateful,
               Database.AllowsCallouts {

    global Id       jobRecordId;
    global String   fromDateStr;
    global String   toDateStr;
    global String   invoiceType;

    // Stateful counters — survive across execute() calls
    private  Integer  successCount = 0;
    private  Integer  failCount    = 0;
    private  Integer  emailFailed  = 0;
    private  List<String> errors   = new List<String>();

    // Precomputed once in start() — passed via constructor, stored for execute()
    private  Map<Id, List<Id>> relatedMap = new Map<Id, List<Id>>();
    private  List<Id> accountIds = new List<Id>();

    global BulkInvoiceEmailBatch(
        Id       jobRecordId,
        List<Id> accountIds,
        String   fromDateStr,
        String   toDateStr,
        String   invoiceType,
        Map<Id, List<Id>> relatedMap
    ) {
        this.jobRecordId = jobRecordId;
        this.fromDateStr = fromDateStr;
        this.toDateStr   = toDateStr;
        this.invoiceType = invoiceType;
        this.relatedMap  = relatedMap != null ? relatedMap : new Map<Id, List<Id>>();
        this.accountIds = accountIds != null ? accountIds : new List<Id>();       
    }

    // ── start(): build QueryLocator from stashed account Ids ─────────────────
    global Database.QueryLocator start(Database.BatchableContext bc) {        

        return Database.getQueryLocator([
            SELECT Id, Name, PersonEmail, Is_Primary__c
            FROM   Account
            WHERE  Id IN :accountIds
        ]);
    }

    // IMPORTANT:
    // Batch must run with scope size = 1 because
    // PDF generation + email sending are heavy operations.
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        Account acc = (Account) scope[0];
        if (acc == null) {
            return;
        }
        Id accId = acc.Id;

        try {
            // ── 1. Find or create exactly ONE invoice for the exact date range ──
            Id invoiceId;

            if (invoiceType == 'Standard Invoice') {
                invoiceId = InvoiceService.generatePdfAndReturnId(
                    accId, fromDateStr, toDateStr
                );
            } else {
                List<Id> relatedIds = relatedMap.containsKey(accId)
                    ? relatedMap.get(accId)
                    : new List<Id>();

                invoiceId = InvoiceService.generateSuperBillAndReturnId(
                    accId, relatedIds, fromDateStr, toDateStr
                );
            }

            if (invoiceId == null) {
                System.debug('No invoice generated for account: ' + accId);
                successCount++;
                return;
            }

            // ── 2. Send exactly ONE email for this invoice ──────────────────────
            Invoice__c inv = [
                SELECT Id, Name, InvoiceType__c, PDF_File_Id__c,
                    From_Date__c, To_Date__c, Invoice_Date__c,
                    Client__r.PersonEmail, Client__r.Name
                FROM Invoice__c
                WHERE Id = :invoiceId
                LIMIT 1
            ];

            try {
                InvoiceService.sendInvoiceEmail(inv, accId);
            } catch (Exception emailEx) {
                emailFailed++;
                System.debug('Email failed for ' + inv.Name + ': ' + emailEx.getMessage());
            }

            successCount++;

        } catch (InvoiceService.InvoiceException e) {
            // No billable records — skip silently
            System.debug('Skipping account ' + accId + ': ' + e.getMessage());
            successCount++;
        } catch (Exception ex) {
            failCount++;
            errors.add('Account ' + accId + ': ' + ex.getMessage());
            System.debug('BulkInvoiceEmailBatch.execute error: '
                + ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }

    // ── finish(): mark job complete and notify the triggering user ────────────
    global void finish(Database.BatchableContext bc) {
        String summary =
            'Processed: ' + (successCount + failCount) +
            ' | Success: ' + successCount +
            ' | Failed: ' + failCount +
            (emailFailed > 0 ? ' | Email Errors: ' + emailFailed : '') +
            (errors.isEmpty() ? '' : '\nErrors:\n' + String.join(errors, '\n'));

        update new Bulk_Zip_Job__c(
            Id               = jobRecordId,
            Status__c        = failCount > 0 && successCount == 0 ? 'Failed' : 'Completed',
            Error_Message__c = summary
        );
       
    }

}