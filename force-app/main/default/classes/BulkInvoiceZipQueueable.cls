/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : BulkInvoiceZipQueueable
CreatedOn      : 07-05-2026
LastModifiedOn : 25-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This queueable class is used to generate, validate, refresh,
                 and collect invoice PDF files in chunks for bulk ZIP creation.
                 It handles standard and household invoices, regenerates stale
                 PDFs when billing data changes, collects ContentVersion files,
                 and initiates the bulk ZIP batch process.
----------------------------------------------------------------------------
*/
public class BulkInvoiceZipQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer CHUNK_SIZE = 5;

    private Id       jobRecordId;
    private List<Id> accountIds;
    private String   fromDateStr;
    private String   toDateStr;
    private String   invoiceType;
    private List<Object> periods;

    // Use Set<Id> to prevent duplicate CV Ids across chained executions.
    private Set<Id> collectedCVIdSet;

    public BulkInvoiceZipQueueable(
        Id       jobRecordId,
        List<Id> accountIds,
        String   fromDateStr,
        String   toDateStr,
        String   invoiceType,
        Set<Id>  collectedCVIdSet,
        List<Object> periods
    ) {
        this.jobRecordId      = jobRecordId;
        this.accountIds       = accountIds;
        this.fromDateStr      = fromDateStr;
        this.toDateStr        = toDateStr;
        this.invoiceType      = invoiceType;
        this.collectedCVIdSet = collectedCVIdSet != null ? collectedCVIdSet : new Set<Id>();
        this.periods = periods;
    }

    // =========================================================================
    public void execute(QueueableContext ctx) {
        try {

            // ── 1. Slice current chunk ────────────────────────────────────────
            Integer  chunkEnd  = Math.min(CHUNK_SIZE, accountIds.size());
            List<Id> chunk     = new List<Id>();
            List<Id> remaining = new List<Id>();
            for (Integer i = 0;        i < chunkEnd;          i++) chunk.add(accountIds[i]);
            for (Integer i = chunkEnd; i < accountIds.size(); i++) remaining.add(accountIds[i]);

            // Date reqFrom = InvoiceService.parseUsDate(fromDateStr);
            // Date reqTo   = InvoiceService.parseUsDate(toDateStr);
            List<Map<String, Object>> periodList = new List<Map<String, Object>>();

if (periods != null && !periods.isEmpty()) {

    for (Object obj : periods) {
        periodList.add((Map<String, Object>) obj);
    }

} else {

    periodList.add(new Map<String, Object>{
        'fromDate' => fromDateStr,
        'toDate'   => toDateStr
    });
}
            

            for (Map<String, Object> period : periodList) {

    String currentFromDate =
        (String) period.get('fromDate');

    String currentToDate =
        (String) period.get('toDate');

    Date reqFrom = InvoiceService.parseUsDate(currentFromDate);

    Date reqTo = InvoiceService.parseUsDate(currentToDate);

    if (reqFrom == null || reqTo == null) {
                markJobFailed('Invalid date range.');
                return;
            }

            // ── 2. Query existing invoices that EXACTLY match the requested range ──
            List<Invoice__c> allExisting = [
                SELECT Id, Client__c, From_Date__c, To_Date__c,
                       PDF_File_Id__c, PDFGeneratedDate__c, Invoice_Date__c,
                       InvoiceType__c, Name, SuperBillPatientGroup__c
                FROM   Invoice__c
                WHERE  Client__c      IN :chunk
                AND    InvoiceType__c  = :invoiceType
                AND    From_Date__c    = :reqFrom
                AND    To_Date__c      = :reqTo
            ];

            // Group by Client__c (first-one-wins for the invoice record itself)
            Map<Id, Invoice__c> exactInvoiceByAccount = new Map<Id, Invoice__c>();
            for (Invoice__c inv : allExisting) {
                if (!exactInvoiceByAccount.containsKey(inv.Client__c)) {
                    exactInvoiceByAccount.put(inv.Client__c, inv);
                }
            }

            // ── 3. For Household Invoice: resolve related accounts ─────────────
            Map<Id, List<Id>> relatedMap = new Map<Id, List<Id>>();
            if (invoiceType == InvoiceService.INVOICE_TYPE_HOUSEHOLD) {
                relatedMap = InvoiceService.getRelatedAccountsForPrimaries(chunk, reqFrom, reqTo);
            }

            // ── 4. Per account: resolve invoice (existing or generate new) ────
            // KEY FIX: Collect ALL invoice Ids that need to be in the ZIP.
            // For existing invoices we always force a PDF regen (to stamp
            // today's Invoice_Date__c) instead of only regening when stale.
            Set<Id>     invoiceIdsForZip   = new Set<Id>();
            Set<Id>     invoicesNeedingRegen = new Set<Id>(); // always regen on download

            for (Id accId : chunk) {

                Invoice__c existingInv = exactInvoiceByAccount.get(accId);

                if (existingInv != null) {
                    // Invoice exists — mark it for regen so the PDF always
                    // reflects today's Invoice_Date__c regardless of when the
                    // invoice record was originally created.
                    invoiceIdsForZip.add(existingInv.Id);
                    if (existingInv.PDF_File_Id__c == null) {
                        invoicesNeedingRegen.add(existingInv.Id);
                    }

                } else {
                    // No invoice for this exact period — generate one now.
                    try {
                        Id newId;
                        if (invoiceType == InvoiceService.INVOICE_TYPE_STANDARD) {
                            newId = InvoiceService.generatePdfAndReturnId(
                                accId, currentFromDate, currentToDate
                            );
                        } else {
                            List<Id> related = relatedMap.containsKey(accId)
                                ? relatedMap.get(accId)
                                : new List<Id>();
                            newId = InvoiceService.generateSuperBillAndReturnId(
                                accId, related, currentFromDate, currentToDate
                            );
                        }
                        // Newly generated invoices already have today's date
                        // (set in findOrCreate* / attachPdf), so no extra regen
                        // needed for them.
                        if (newId != null) invoiceIdsForZip.add(newId);

                    } catch (InvoiceService.InvoiceException e) {
                        System.debug('Skipping account ' + accId + ': ' + e.getMessage());
                    }
                }
            }

            // ── 5. No date stamping — Invoice_Date__c is preserved from creation.
            // PDFs are only regenerated when actually missing (see step 4 guard above).

            // if (!invoicesNeedingRegen.isEmpty()) {
            //     List<Invoice__c> toStamp = new List<Invoice__c>();
            //     for (Id invId : invoicesNeedingRegen) {
            //         toStamp.add(new Invoice__c(
            //             Id              = invId,
            //             Invoice_Date__c = Date.today()
            //         ));
            //     }
            //     update toStamp;
            // }

            // ── 6. Delete old PDFs for invoices that need regen ───────────────
            // Collect the old ContentDocument Ids from the queried records.
            Map<Id, Id> invoiceToOldDocId = new Map<Id, Id>();
            for (Invoice__c inv : allExisting) {
                if (invoicesNeedingRegen.contains(inv.Id) && inv.PDF_File_Id__c != null) {
                    invoiceToOldDocId.put(inv.Id, inv.PDF_File_Id__c);
                }
            }

            if (!invoiceToOldDocId.isEmpty()) {
                delete [
                    SELECT Id FROM ContentDocument
                    WHERE  Id IN :invoiceToOldDocId.values()
                ];
                // Clear the PDF pointer so regeneratePdfForInvoice re-attaches cleanly.
                List<Invoice__c> toClear = new List<Invoice__c>();
                for (Id invId : invoiceToOldDocId.keySet()) {
                    toClear.add(new Invoice__c(
                        Id                  = invId,
                        PDF_File_Id__c      = null,
                        PDFGeneratedDate__c = null
                    ));
                }
                update toClear;
            }

            // ── 7. Regenerate PDF for every invoice in the ZIP ────────────────
            // This covers:
            //   a) Existing invoices (invoicesNeedingRegen) — PDF just deleted above.
            //   b) Any invoice whose PDF_File_Id__c was already null for other reasons.
            if (!invoiceIdsForZip.isEmpty()) {
                for (Invoice__c inv : [
                    SELECT Id, Client__c, Name, InvoiceType__c,
                           PDF_File_Id__c, SuperBillPatientGroup__c
                    FROM   Invoice__c
                    WHERE  Id            IN :invoiceIdsForZip
                    AND    PDF_File_Id__c  = null
                ]) {
                    List<Id> relatedIds =
                        (invoiceType == InvoiceService.INVOICE_TYPE_HOUSEHOLD
                         && relatedMap.containsKey(inv.Client__c))
                        ? relatedMap.get(inv.Client__c)
                        : new List<Id>();

                    InvoiceService.regeneratePdfForInvoice(
                        inv, relatedIds, currentFromDate, currentToDate
                    );
                }
            }

            // ── 8. Collect ContentVersion IDs (deduplication via Set) ─────────
            if (!invoiceIdsForZip.isEmpty()) {
                for (ContentDocumentLink cdl : [
                    SELECT ContentDocument.LatestPublishedVersionId
                    FROM   ContentDocumentLink
                    WHERE  LinkedEntityId IN :invoiceIdsForZip
                    AND    ContentDocument.FileExtension = 'pdf'
                ]) {
                    if (cdl.ContentDocument.LatestPublishedVersionId != null) {
                        collectedCVIdSet.add(cdl.ContentDocument.LatestPublishedVersionId);
                    }
                }
            }
            }

            // ── 9. Chain or hand off to Batch ─────────────────────────────────
            if (!remaining.isEmpty()) {
                System.enqueueJob(new BulkInvoiceZipQueueable(
                    jobRecordId, remaining, fromDateStr, toDateStr,
                    invoiceType, collectedCVIdSet, periods
                ));
            } else if (collectedCVIdSet.isEmpty()) {
                markJobFailed('No PDF files were found to include in the zip.');
            } else {
                Database.executeBatch(
                    new BulkZipBatch(
                        jobRecordId,
                        new List<Id>(collectedCVIdSet),
                        fromDateStr, toDateStr, invoiceType
                    ),
                    20
                );
            }

        } catch (Exception ex) {
            markJobFailed(ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }

    // =========================================================================
    private void markJobFailed(String errorMsg) {
        try {
            update new Bulk_Zip_Job__c(
                Id               = jobRecordId,
                Status__c        = 'Failed',
                Error_Message__c = errorMsg
            );
        } catch (Exception e) {
            System.debug('markJobFailed: ' + e.getMessage());
        }
    }
}