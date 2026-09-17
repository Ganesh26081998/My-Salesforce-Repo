/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : InvoiceService
CreatedOn      : 10-05-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This service class is used to manage invoice generation,
                 PDF creation, email delivery, billing validations, bulk
                 invoice processing, household invoice handling, related
                 client processing, ZIP generation support, and invoice
                 utility operations for standard and household invoices.
----------------------------------------------------------------------------
*/
public with sharing class InvoiceService {

    // ═════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═════════════════════════════════════════════════════════════════════════
    public static final String INVOICE_TYPE_STANDARD  = 'Standard Invoice';
    public static final String INVOICE_TYPE_HOUSEHOLD = 'Household Invoice';
    public static final String RELATION_TYPE_COUPLE   = 'Couple Household';
    public static final String SHARE_TYPE_VIEWER      = 'V';
    public static final String JOB_STATUS_PROCESSING  = 'Processing';
    public static final String BLI_TYPE_CLIENT        = 'Client Billable';
    public static final String BLI_TYPE_EXPENSE       = 'Expense/Credit';
    public static final String BLI_TYPE_MILEAGE       = 'Mileage';
    private static final String EMAIL_TEMPLATE_NAME   = 'Invoice_Email_Template';

    // ═════════════════════════════════════════════════════════════════════════
    // EXCEPTIONS
    // ═════════════════════════════════════════════════════════════════════════
    public class InvoiceException  extends Exception {}
    private class NoEmailException extends Exception {}

    // ═════════════════════════════════════════════════════════════════════════
    // INNER DATA CLASSES
    // ═════════════════════════════════════════════════════════════════════════
    public class LineItemResult {
        public List<CareDetailRow>    careDetails;
        public List<CareSummaryRow>   careSummaryRows;
        public List<HourlySummaryRow> hourlySummaryRows;
        public Decimal totalHourlyCharges;
        public Decimal totalMileageCharges;
        public Decimal totalExpenseCharges;
        public Decimal totalCharges;

        public LineItemResult() {
            careDetails         = new List<CareDetailRow>();
            careSummaryRows     = new List<CareSummaryRow>();
            hourlySummaryRows   = new List<HourlySummaryRow>();
            totalHourlyCharges  = 0;
            totalMileageCharges = 0;
            totalExpenseCharges = 0;
            totalCharges        = 0;
        }
    }

    public class CareDetailRow {
        public String  billingName          { get; set; }
        public String  billingLineItemName  { get; set; }
        public Date    serviceDate          { get; set; }
        public String  quantity             { get; set; }
        public String  rate                 { get; set; }
        public String  amount               { get; set; }
        public String  description          { get; set; }
        public Boolean isHourly             { get; set; }
        public Boolean isExpenseOrMileage   { get; set; }
        public Integer billingRowSpan       { get; set; }
        public Integer bliRowSpan           { get; set; }
        public Boolean showBillingName      { get; set; }
        public Boolean showBliName          { get; set; }

        public CareDetailRow(
            String bN, String bliN, Date sd, String qty, String rate, String amt,
            String descr, Boolean isHourly, Boolean isExpOrMil, Integer billRowSpan, Integer bliRowSpan
        ) {
            this.billingName         = bN;
            this.billingLineItemName = bliN;
            this.serviceDate         = sd;
            this.quantity            = qty;
            this.rate                = rate;
            this.amount              = amt;
            this.description         = descr;
            this.isHourly            = isHourly;
            this.isExpenseOrMileage  = isExpOrMil;
            this.billingRowSpan      = billRowSpan;
            this.bliRowSpan          = bliRowSpan;
            this.showBillingName     = false;
            this.showBliName         = false;
        }
    }

    public class CareSummaryRow {
        public Decimal rate          { get; set; }
        public Decimal totalQuantity { get; set; }
        public Decimal totalAmount   { get; set; }

        public CareSummaryRow(Decimal rate) {
            this.rate          = rate;
            this.totalQuantity = 0;
            this.totalAmount   = 0;
        }
    }

    public class HourlySummaryRow {
        public Decimal rate        { get; set; }
        public Decimal totalHours  { get; set; }
        public Decimal totalAmount { get; set; }
        public Boolean isFlatAmount {get; set;}

        public HourlySummaryRow(Decimal rate, Boolean isFlatAmount) {
            this.rate        = rate;
            this.isFlatAmount = isFlatAmount;
            this.totalHours  = 0;
            this.totalAmount = 0;
        }
    }

    public class RelatedPatientWrapper {
        @AuraEnabled public Id     contactId;
        @AuraEnabled public Id     accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String roleName;
    }

    public class BulkResult {
        @AuraEnabled public Integer totalRequested;
        @AuraEnabled public Integer existingCount;
        @AuraEnabled public Integer generatedCount;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // LINE ITEM BUILDER  (used by InvoicePDFController + HouseholdInvoice page)
    // ═════════════════════════════════════════════════════════════════════════
    public static LineItemResult buildLineItemResult(
        Id accountId, String fromDateParam, String toDateParam
    ) {
        Date fromDate = parseUsDate(fromDateParam);
        Date toDate   = parseUsDate(toDateParam);

        Datetime fromDt = Datetime.newInstance(fromDate, Time.newInstance(0,0,0,0));
        Datetime toDt   = Datetime.newInstance(toDate,   Time.newInstance(23,59,59,999));

        // ── 1. Collect billing IDs + hours from Events (one query) ────────────
        Map<Id, String>  billingToEventText = new Map<Id, String>();
        Map<Id, Decimal> billingToHours     = new Map<Id, Decimal>();
        Map<Id, String> billingToRateType = new Map<Id, String>();
        Map<Id, String> billingToSubject = new Map<Id, String>();
        Map<Id, Boolean> billingToIsAllDay = new Map<Id, Boolean>();
        for (Event e : [
            SELECT Subject, WhatId, StartDateTime, EndDateTime,
                   Owner.FirstName, Owner.LastName, Billing__c, IsAllDayEvent, ActivityDate, Client_Rate__c
            FROM   Event
            WHERE  AccountId              = :accountId
            AND    WhatId                 != null
            AND    Billing__c             != null
            AND    Billing__r.Is_Synced__c = true
            //AND    StartDateTime          <= :toDt
            //AND    EndDateTime            >= :fromDt
            AND (
    (
        IsAllDayEvent = true
        AND ActivityDate >= :fromDate
        AND ActivityDate <= :toDate
    )
    OR
    (
        IsAllDayEvent = false
        AND StartDateTime <= :toDt
        AND EndDateTime >= :fromDt
    )
)
        ]) {
            if (billingToEventText.containsKey(e.Billing__c)) continue;
            // Decimal hours = ((Decimal)(e.EndDateTime.getTime() - e.StartDateTime.getTime())
            //     / (1000 * 60 * 60)).setScale(2);
            Decimal hours;

            if (e.IsAllDayEvent) {
                Integer days = e.ActivityDate.addDays(1).daysBetween(e.ActivityDate);
                hours = 24; // or days * 24 if multi-day all-day events are possible
            } else {
                hours = ((Decimal)(e.EndDateTime.getTime() - e.StartDateTime.getTime())
                    / (1000 * 60 * 60)).setScale(2);
            }
            billingToHours.put(e.Billing__c, hours);
            billingToRateType.put(e.Billing__c, e.Client_Rate__c);
            billingToSubject.put(e.Billing__c, e.Subject);
            // billingToEventText.put(e.Billing__c,
            //     e.StartDateTime.format('h:mm a') + ' - ' + e.EndDateTime.format('h:mm a') +
            //     ' ' + e.Owner.LastName + ', ' + e.Owner.FirstName
            // );
            billingToIsAllDay.put(e.Billing__c, e.IsAllDayEvent); // Store All-Day status
            
            String timeDisplay = e.IsAllDayEvent 
                ? 'All Day' 
                : e.StartDateTime.format('h:mm a') + ' - ' + e.EndDateTime.format('h:mm a');

            billingToEventText.put(e.Billing__c,
                timeDisplay + ' ' + e.Owner.LastName + ', ' + e.Owner.FirstName
            );
        }

        // ── 2. Fetch line items (one query) ───────────────────────────────────
        List<Billing_Line_Item__c> lineItems = [
            SELECT Name, Invoice__r.Name, Service_Date__c,
                   Quantity__c, Rate__c, Amount__c,
                   Client_Rate_Amount__c, Mileage_Description__c,
                   Expense_Amount__c, Expense_Description__c,
                   Invoice__r.Event_Start_Date_Time__c, Invoice__r.Event_End_Date_Time__c,
                   Invoice__r.Event_Assignee__r.FirstName, Invoice__r.Event_Assignee__r.LastName,
                   Invoice__r.Event_Duration_Hours__c, RecordTypeId, Type__c, Description__c
            FROM   Billing_Line_Item__c
            WHERE  Invoice__r.Client__c = :accountId
            AND    Invoice__c           IN :billingToHours.keySet()
            AND    Service_Date__c      >= :fromDate
            AND    Service_Date__c      <= :toDate
            ORDER BY Service_Date__c ASC, Invoice__r.Event_Start_Date_Time__c ASC
        ];

        // ===== ADD HERE =====
        System.debug('========== LINE ITEMS ==========');
        for (Billing_Line_Item__c bli : lineItems) {
            System.debug(
        'Invoice=' + bli.Invoice__r.Name +
        ' | Type=' + bli.Type__c +
        ' | ServiceDate=' + bli.Service_Date__c
    );
}

        // ── 3. Build rows ─────────────────────────────────────────────────────
        LineItemResult res           = new LineItemResult();
        Map<Decimal, CareSummaryRow>   rateMap       = new Map<Decimal, CareSummaryRow>();
        Map<String, HourlySummaryRow> hourlyRateMap = new Map<String, HourlySummaryRow>();
        List<CareDetailRow> tempDetails = new List<CareDetailRow>();

        for (Billing_Line_Item__c bli : lineItems) {
            if (!billingToHours.containsKey(bli.Invoice__c)) continue;

            Decimal hours = billingToHours.get(bli.Invoice__c);
            String  descr  = buildEventDescription(bli);

            // if (bli.Type__c == BLI_TYPE_CLIENT) {
            //     Decimal amt = (bli.Client_Rate_Amount__c * hours).setScale(2);
            //     tempDetails.add(new CareDetailRow(
            //         bli.Invoice__r.Name, bli.Name, bli.Service_Date__c,
            //         hours + ' hrs', bli.Client_Rate_Amount__c + '/hr',
            //         '$' + amt, descr, true, false, 0, 0
            //     ));
            //     accumulateHourly(hourlyRateMap, bli.Client_Rate_Amount__c, hours, amt);
            //     res.totalHourlyCharges += amt;

            // }

            

        // If it's an all-day event, cleanly replace standard time stamps in the text with "All Day"
        if (billingToIsAllDay.get(bli.Invoice__c) == true) {
            // Regular expression captures typical variations like "12:00am - 12:00am" or "12:00am - 11:59pm"
            descr = descr.replaceAll('(?i)\\d{1,2}:\\d{2}\\s*(am|pm)\\s*-\\s*\\d{1,2}:\\d{2}\\s*(am|pm)', 'All Day');
        }

            if (bli.Type__c == BLI_TYPE_CLIENT) {

                // Decimal qty  = bli.Quantity__c;
                Decimal qty  = bli.Invoice__r.Event_Duration_Hours__c;
                Decimal rate = bli.Rate__c;
                // Decimal amt  = bli.Amount__c;
                Decimal amt;

                if (billingToRateType.get(bli.Invoice__c) == 'Flat Amount') {
                    amt = rate;
                } else {
                    amt = (qty * rate).setScale(2);
                }
            System.debug('----------------------------');
            System.debug('Invoice Name : ' + bli.Invoice__r.Name);
            System.debug('Type         : ' + bli.Type__c);
            System.debug('Subject      : ' + billingToSubject.get(bli.Invoice__c));
            System.debug('Qty          : ' + qty);
            System.debug('Rate         : ' + rate);
            System.debug('Amount       : ' + amt);
            System.debug('Description  : ' + descr);
            System.debug('Is All Day   : ' + billingToIsAllDay.get(bli.Invoice__c));
            
                tempDetails.add(new CareDetailRow(
                    bli.Invoice__r.Name,
                    billingToSubject.get(bli.Invoice__c),
                    bli.Service_Date__c,
                    billingToRateType.get(bli.Invoice__c) == 'Flat Amount'
                        ? '1'
                        : qty + ' hrs',
                    billingToRateType.get(bli.Invoice__c) == 'Flat Amount'
                        ? formatCurrency(rate)
                        : formatCurrency(rate) + '/hr',
                    formatCurrency(amt),
                    descr,
                    true,
                    false,
                    0,
                    0
                ));

                // accumulateHourly(hourlyRateMap, rate, qty, amt);
                Boolean isFlatAmount = billingToRateType.get(bli.Invoice__c) == 'Flat Amount';

                accumulateHourly(
                    hourlyRateMap,
                    rate,
                    qty,
                    amt,
                    isFlatAmount
                );
                res.totalHourlyCharges += amt;

                Decimal rateKey = bli.Rate__c == null ? 0 : bli.Rate__c;
                if (!rateMap.containsKey(rateKey)) rateMap.put(rateKey, new CareSummaryRow(rateKey));
                rateMap.get(rateKey).totalQuantity += qty  == null ? 0 : qty ;
                rateMap.get(rateKey).totalAmount   += amt   == null ? 0 : amt;
            }
             else if (bli.Type__c == BLI_TYPE_EXPENSE) {
                addExpenseRow(tempDetails, bli, billingToSubject.get(bli.Invoice__c));
                if (bli.Amount__c != null) res.totalExpenseCharges += bli.Amount__c;

            } else if (bli.Type__c == BLI_TYPE_MILEAGE) {
                addMileageRow(tempDetails, bli, billingToSubject.get(bli.Invoice__c));
                if (bli.Amount__c != null) res.totalMileageCharges += bli.Amount__c;
            }

            // Decimal rateKey = bli.Rate__c == null ? 0 : bli.Rate__c;
            // if (!rateMap.containsKey(rateKey)) rateMap.put(rateKey, new CareSummaryRow(rateKey));
            // rateMap.get(rateKey).totalQuantity += qty  == null ? 0 : qty ;
            // rateMap.get(rateKey).totalAmount   += bli.Amount__c   == null ? 0 : bli.Amount__c;
        }

        System.debug('========== CARE DETAILS ==========');
System.debug('Total Care Detail Rows = ' + tempDetails.size());
 
for (CareDetailRow row : tempDetails) {
    System.debug(
        row.billingName +
        ' | ' +
        row.billingLineItemName +
        ' | ' +
        row.description
    );
}

        res.totalCharges = res.totalHourlyCharges + res.totalMileageCharges + res.totalExpenseCharges;
        applyRowSpans(tempDetails);
        res.careDetails       = tempDetails;
        res.careSummaryRows   = rateMap.values();
        // res.hourlySummaryRows = hourlyRateMap.values();
        List<HourlySummaryRow> summaryRows = new List<HourlySummaryRow>();
        HourlySummaryRow flatRow;

        for (HourlySummaryRow row : hourlyRateMap.values()) {
            if (row.isFlatAmount) {
                flatRow = row;
            } else {
                summaryRows.add(row);
            }
        }

        if (flatRow != null) {
            summaryRows.add(flatRow);
        }

        res.hourlySummaryRows = summaryRows;
                return res;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // AURA — SINGLE INVOICE GENERATION
    // ═════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static String generatePdf(Id accountId, String fromDateStr, String toDateStr) {
        try {
            Date fromDate = parseUsDate(fromDateStr);
            Date toDate   = parseUsDate(toDateStr);
            Invoice__c invoice = createInvoiceAndFile(accountId, fromDateStr, toDateStr);
            System.debug('invoice: '+invoice);
            // sendInvoiceEmail(invoice, accountId);
            return '/apex/InvoicePDF?accountId=' + accountId
                + '&fromDate=' + fromDate + '&toDate=' + toDate
                + '&invoiceNo=' + EncodingUtil.urlEncode(invoice.Name, 'UTF-8');
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String generateSuperBill(
        Id primaryAccountId, List<Id> selectedRelatedAccountIds,
        String fromDateStr, String toDateStr
    ) {
        if (primaryAccountId == null || String.isBlank(fromDateStr) || String.isBlank(toDateStr)) {
            throw new AuraHandledException('Missing required parameters.');
        }
        Invoice__c invoice = createSuperBillAndFile(
            primaryAccountId, selectedRelatedAccountIds, fromDateStr, toDateStr
        );
        if (invoice == null) {
            throw new AuraHandledException(
                'No billables found for the selected date range.'
            );
        }        
        return '/apex/HouseholdInvoice?primaryAccountId=' + primaryAccountId
            + '&relatedAccountIds=' + (selectedRelatedAccountIds != null ? String.join(selectedRelatedAccountIds, ',') : '')
            + '&fromDate=' + fromDateStr + '&toDate=' + toDateStr
            + '&invoiceId=' + EncodingUtil.urlEncode(invoice.Name, 'UTF-8');
    }
    
    @AuraEnabled
public static Id generatePdfForPreview(
    Id accountId,
    String fromDateStr,
    String toDateStr
) {
    return generatePdfAndReturnId(
        accountId,
        fromDateStr,
        toDateStr
    );
}

    // ── Id-returning variants used by batch / queueable jobs ─────────────────
    public static Id generatePdfAndReturnId(Id accountId, String fromDateStr, String toDateStr) {
        Invoice__c inv = createInvoiceAndFile(accountId, fromDateStr, toDateStr);
        return inv != null ? inv.Id : null;
    }

    @AuraEnabled
public static Id generateSuperBillForPreview(
    Id primaryAccountId,
    List<Id> selectedRelatedAccountIds,
    String fromDateStr,
    String toDateStr
) {
    return generateSuperBillAndReturnId(
        primaryAccountId,
        new List<Id>(selectedRelatedAccountIds),
        fromDateStr,
        toDateStr
    );
}
    

    public static Id generateSuperBillAndReturnId(
        Id primaryAccountId, List<Id> relatedIds, String fromDateStr, String toDateStr
    ) {
        System.debug('Invoice BEFORE create: ' + primaryAccountId);
        Invoice__c inv = createSuperBillAndFile(primaryAccountId, relatedIds, fromDateStr, toDateStr);
        System.debug('Invoice AFTER create: ' + inv);
        if (inv != null) {
            System.debug('Invoice ID: ' + inv.Id);
            Invoice__c dbInv = [
    SELECT Id,
           Name,
           InvoiceType__c,
           From_Date__c,
           To_Date__c,
           Client__c
    FROM Invoice__c
    WHERE Id = :inv.Id
    LIMIT 1
];

System.debug('DB Invoice: ' + dbInv);
        }
        return inv != null ? inv.Id : null;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // AURA — QUERY HELPERS
    // ═════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static List<Invoice__c> getInvoicesForAccounts(
        List<Id> accountIds, String fromDateStr, String toDateStr, String invoiceType
    ) {
        if (accountIds == null || accountIds.isEmpty()
                || String.isBlank(fromDateStr) || String.isBlank(toDateStr)) {
            return new List<Invoice__c>();
        }
        Date fromDate = Date.valueOf(fromDateStr);
        Date toDate   = Date.valueOf(toDateStr);        

        Set<Id> allAccountIds = new Set<Id>();

        allAccountIds.addAll(accountIds);
        if (invoiceType == 'Household Invoice') {

            Map<Id, List<Id>> relatedMap =
                getRelatedAccountsForPrimaries(
                    accountIds,
                    Date.valueOf(fromDateStr),
                    Date.valueOf(toDateStr)
                );

            for (List<Id> relIds : relatedMap.values()) {
                allAccountIds.addAll(relIds);
            }
        }        

        return [
            SELECT Id, Name, InvoiceType__c, From_Date__c, To_Date__c,
                   Invoice_Date__c, Client__c, Client__r.Name, PDF_File_Id__c
            FROM   Invoice__c
            WHERE  Client__c      IN :allAccountIds
            AND    From_Date__c   <= :toDate          // invoice starts before window closes
            AND    To_Date__c     >= :fromDate         // invoice ends after window opens
            AND    InvoiceType__c  = :invoiceType
            ORDER  BY Client__r.Name, From_Date__c ASC
        ];
    }

    @AuraEnabled
    public static Boolean hasBillingsInRange(Id accountId, String fromDateStr, String toDateStr) {
        System.debug('hasBillingsInRange');
        return hasBillings(accountId, parseUsDate(fromDateStr), parseUsDate(toDateStr));
    }

    @AuraEnabled
    public static List<RelatedPatientWrapper> getRelatedPatients(Id primaryAccountId) {
        if (primaryAccountId == null) return new List<RelatedPatientWrapper>();
        Account acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :primaryAccountId LIMIT 1];
        if (acc.PersonContactId == null) return new List<RelatedPatientWrapper>();

        List<RelatedPatientWrapper> results = new List<RelatedPatientWrapper>();
        for (HealthCloudGA__ContactContactRelation__c rel : [
            SELECT HealthCloudGA__Contact__c, HealthCloudGA__Contact__r.Name,
                   HealthCloudGA__Contact__r.AccountId, HealthCloudGA__Role__r.Name
            FROM   HealthCloudGA__ContactContactRelation__c
            WHERE  HealthCloudGA__RelatedContact__c = :acc.PersonContactId
            AND    Type__c = :RELATION_TYPE_COUPLE
        ]) {
            RelatedPatientWrapper w = new RelatedPatientWrapper();
            w.contactId = rel.HealthCloudGA__Contact__c;
            w.accountId = rel.HealthCloudGA__Contact__r.AccountId;
            w.name      = rel.HealthCloudGA__Contact__r.Name;
            w.roleName  = rel.HealthCloudGA__Role__r != null ? rel.HealthCloudGA__Role__r.Name : '';
            results.add(w);
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> checkSuperBillEligibility(
        Id primaryAccountId, List<Id> selectedRelatedAccountIds,
        String fromDateStr, String toDateStr
    ) {
        Date fromDate = Date.valueOf(fromDateStr);
        Date toDate   = Date.valueOf(toDateStr);
        Map<String, Object> result = new Map<String, Object>();        
        
        result.put('hasPrimaryBillables', hasBillings(primaryAccountId, fromDate, toDate));

        Set<Id> relatedIdSet = new Set<Id>();
        if (selectedRelatedAccountIds != null) {
            relatedIdSet.addAll(selectedRelatedAccountIds);
        }
        
        Set<Id> validRelated = new Set<Id>();

        if (selectedRelatedAccountIds != null && !selectedRelatedAccountIds.isEmpty()) {

            validRelated = filterAccountsWithBillings(
                relatedIdSet,
                fromDate,
                toDate
            );

        } else {

            Map<Id, List<Id>> relatedMap =
                getRelatedAccountsForPrimaries(
                    new List<Id>{ primaryAccountId },
                    fromDate,
                    toDate
                );
                System.debug('=== RELATED MAP: ' + relatedMap);

            if (relatedMap.containsKey(primaryAccountId)) {
                validRelated.addAll(
                    relatedMap.get(primaryAccountId)
                );
            }
        }
        System.debug('validRelated>> '+validRelated);
        result.put('validRelatedAccountIds', validRelated);
        return result;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // AURA — BULK OPERATIONS
    // ═════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static void generateFilteredInvoices(
        List<Id> accountIds, String fromDateStr, String toDateStr
    ) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new AuraHandledException('No records found.');
        }
        Date fromDate    = parseUsDate(fromDateStr);
        Date toDate      = parseUsDate(toDateStr);
        Boolean anyDone  = false;

        for (Id accId : accountIds) {
            List<Invoice__c> existing = [
                SELECT Id, PDF_File_Id__c FROM Invoice__c
                WHERE Client__c = :accId AND From_Date__c = :fromDate AND To_Date__c = :toDate LIMIT 1
            ];
            if (!existing.isEmpty() && existing[0].PDF_File_Id__c != null) continue;

            createInvoiceAndFile(accId, fromDateStr, toDateStr);
            anyDone = true;
        }

        if (!anyDone) throw new AuraHandledException('All filtered invoices are already generated.');
    }

    @AuraEnabled
    public static BulkResult validateBeforeGeneration(
        List<Id> accountIds, String fromDateStr, String toDateStr, String type
    ) {
        if (accountIds == null || accountIds.isEmpty()) throw new AuraHandledException('No clients selected.');
        Date fromDate = parseUsDate(fromDateStr);
        Date toDate   = parseUsDate(toDateStr);
        Integer existingCount = queryExistingInvoices(accountIds, fromDate, toDate, type).size();
        BulkResult res    = new BulkResult();
        res.existingCount  = existingCount;
        res.totalRequested = accountIds.size();
        res.generatedCount = accountIds.size() - existingCount;
        return res;
    }

    @AuraEnabled
    public static BulkResult bulkGenerateInvoices(
        List<Id> accountIds, String fromDateStr, String toDateStr, String type
    ) {
        System.debug('bulkGenerateInvoices - accountIds'+ accountIds);
        if (accountIds == null || accountIds.isEmpty()) throw new AuraHandledException('No accounts selected.');
        Date fromDate = parseUsDate(fromDateStr);
        Date toDate   = parseUsDate(toDateStr);
 
        // FIX: query by exact date match so we never skip a genuinely missing invoice
        Map<Id, Invoice__c> existingMap = queryExistingInvoices(accountIds, fromDate, toDate, type);
 
        // For household invoices, resolve related accounts once (bulkified)
        Map<Id, List<Id>> relatedMap = type == INVOICE_TYPE_HOUSEHOLD
            ? getRelatedAccountsForPrimaries(accountIds, fromDate, toDate)
            : new Map<Id, List<Id>>();
 
        Integer generated = 0;
        for (Id accId : accountIds) {
            if (existingMap.containsKey(accId)) continue;
 
            if (type == INVOICE_TYPE_STANDARD) {
                generatePdf(accId, fromDateStr, toDateStr);
            } else if (type == INVOICE_TYPE_HOUSEHOLD) {
                // FIX: pass the correctly-derived related IDs instead of null/empty
                List<Id> related = relatedMap.containsKey(accId)
                    ? relatedMap.get(accId)
                    : new List<Id>();
                generateSuperBill(accId, related, fromDateStr, toDateStr);
            }
            generated++;
        }
 
        BulkResult res    = new BulkResult();
        res.generatedCount = generated;
        res.existingCount  = existingMap.size();
        res.totalRequested = accountIds.size();
        return res;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // AURA — ASYNC BULK EMAIL + ZIP
    // ═════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static Id startBulkInvoiceEmail(
        List<Id> accountIds, String fromDateStr, String toDateStr, String type
    ) {
        validateBulkInput(accountIds, fromDateStr, toDateStr, type);
        Date fromDate = Date.valueOf(fromDateStr);
        Date toDate   = Date.valueOf(toDateStr);

        List<Id> finalIds = filterAccountsByType(accountIds, type);
        Map<Id, List<Id>> relatedMap = type == INVOICE_TYPE_HOUSEHOLD
            ? getRelatedAccountsForPrimaries(accountIds, fromDate, toDate)
            : new Map<Id, List<Id>>();

        Bulk_Zip_Job__c job = insertJob(fromDate, toDate, type);
        Database.executeBatch(
            new BulkInvoiceEmailBatch(job.Id, finalIds, fromDateStr, toDateStr, type, relatedMap), 1
        );
        return job.Id;
    }

    @AuraEnabled
    public static Id startBulkInvoiceZip(
        List<Id> accountIds, String fromDateStr, String toDateStr, String type, String periodsJson
    ) {
        validateBulkInput(accountIds, fromDateStr, toDateStr, type);
        Date fromDate = Date.valueOf(fromDateStr);
        Date toDate   = Date.valueOf(toDateStr);
        Bulk_Zip_Job__c job = insertJob(fromDate, toDate, type);
        List<Object> periods = new List<Object>();

        if (!String.isBlank(periodsJson)) {
            periods = (List<Object>) JSON.deserializeUntyped(periodsJson);
        }
        System.enqueueJob(new BulkInvoiceZipQueueable(
            job.Id, accountIds, fromDateStr, toDateStr, type, new Set<Id>(), periods
        ));
        return job.Id;
    }

    @AuraEnabled
    public static Bulk_Zip_Job__c getZipJobStatus(Id jobId) {
        return [
            SELECT Id, Status__c, Error_Message__c, Zip_File_Id__c,
                   From_Date__c, To_Date__c, Invoice_Type__c
            FROM   Bulk_Zip_Job__c WHERE Id = :jobId LIMIT 1
        ];
    }

    // ═════════════════════════════════════════════════════════════════════════
    // INVOICE RECORD + PDF CREATION
    // ═════════════════════════════════════════════════════════════════════════
    public static Invoice__c createInvoiceAndFile(
        Id accountId, String fromDateStr, String toDateStr
    ) {
        System.debug('createInvoiceAndFile called');
        if (accountId == null || fromDateStr == null || toDateStr == null) {
            throw new AuraHandledException('Missing required parameters');
        }
        Date fromDate = parseUsDate(fromDateStr);
        Date toDate   = parseUsDate(toDateStr);
        System.debug('!hasBillables(accountId, fromDate, toDate) '+!hasBillables(accountId, fromDate, toDate));
        if (!hasBillables(accountId, fromDate, toDate)) return null;

        Invoice__c invoice = findOrCreateStandardInvoice(accountId, fromDate, toDate);
        System.debug('invoice from findOrCreateStandardInvoice: '+invoice);  

        //////////
        System.debug('Invoice Id: ' + invoice.Id);
        System.debug('PDF_File_Id__c: ' + invoice.PDF_File_Id__c);
        /////////

        // Only generate + attach a PDF if one does not already exist.
        // Prevents duplicate ContentVersions on every preview/open.
        // if (invoice.PDF_File_Id__c == null) {
            ////////////
            System.debug('Generating new PDF...');
            ////////////
            Blob pdfBlob = renderPage(Page.InvoicePDF, new Map<String, String>{
                'accountId' => accountId, 'fromDate' => fromDateStr,
                'toDate' => toDateStr,    'invoiceNo' => invoice.Name
            });
            Account acc = [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1];
            attachPdf(invoice, pdfBlob, buildPdfFileName(INVOICE_TYPE_STANDARD, acc.Name, invoice.Name));
        // } else {
            ////////////
            // System.debug('Skipping PDF generation. Existing PDF found.');
            ////////////
        // }
        return invoice;
    }

    public static Invoice__c createSuperBillAndFile(
        Id primaryAccountId, List<Id> selectedRelatedAccountIds,
        String fromDateStr, String toDateStr
    ) {
        if (primaryAccountId == null || String.isBlank(fromDateStr) || String.isBlank(toDateStr)) {
            throw new AuraHandledException('Missing required parameters.');
        }
        Date fromDate = parseUsDate(fromDateStr);
        Date toDate   = parseUsDate(toDateStr);

       // Primary account may not have direct Event records for household invoices
// (billings live on related member accounts). Only block if no related
// accounts were supplied either — eligible related IDs will carry the invoice.
// if (!hasBillings(primaryAccountId, fromDate, toDate)) {
//     return null;
// }
Boolean hasPrimary = hasBillings(primaryAccountId, fromDate, toDate);
        // List<Id> eligibleRelatedIds = filterEligibleRelated(selectedRelatedAccountIds, fromDate, toDate);
        // System.debug('eligibleRelatedIds: '+eligibleRelatedIds);

        // String   groupKey           = buildGroupKey(primaryAccountId, eligibleRelatedIds);
         List<Id> eligibleRelatedIds;
 
    if (selectedRelatedAccountIds != null && !selectedRelatedAccountIds.isEmpty()) {
        // Caller supplied specific related IDs (e.g. user selected from modal)
        // — filter to only those that have billings in the period.
        eligibleRelatedIds = filterEligibleRelated(selectedRelatedAccountIds, fromDate, toDate);
    } else {
        // Bulk/automated path — derive related IDs the same way the ZIP
        // queueable does, so the groupKey always matches.
        Map<Id, List<Id>> relMap = getRelatedAccountsForPrimaries(
            new List<Id>{ primaryAccountId }, fromDate, toDate
        );
        eligibleRelatedIds = relMap.containsKey(primaryAccountId)
            ? relMap.get(primaryAccountId)
            : new List<Id>();
    }
    System.debug('eligibleRelatedIds: '+eligibleRelatedIds);
    // Only stop if neither Primary nor Related has billables
if (!hasPrimary && (eligibleRelatedIds == null || eligibleRelatedIds.isEmpty())) {
    return null;
// or throw new AuraHandledException('No billables found for the selected date range.');
}
    String     groupKey = buildGroupKey(primaryAccountId, eligibleRelatedIds);
        Invoice__c invoice          = findOrCreateHouseholdInvoice(primaryAccountId, groupKey, fromDate, toDate);
// Only generate + attach a PDF if one does not already exist.
    // if (invoice.PDF_File_Id__c == null) {

        Blob pdfBlob = renderPage(Page.HouseholdInvoice, new Map<String, String>{
            'primaryAccountId'  => primaryAccountId,
            'relatedAccountIds' => eligibleRelatedIds != null ? String.join(eligibleRelatedIds, ',') : '',
            'fromDate'  => fromDateStr, 'toDate' => toDateStr, 'invoiceId' => invoice.Name
        });
        Account acc = [SELECT Name FROM Account WHERE Id = :primaryAccountId LIMIT 1];
        attachPdf(invoice, pdfBlob, buildPdfFileName(INVOICE_TYPE_HOUSEHOLD, acc.Name, invoice.Name));
    // }
        return invoice;
    }

    // public static void regeneratePdfForInvoice(
    //     Invoice__c inv, List<Id> relatedIds, String fromDateStr, String toDateStr
    // ) {
    //     if (inv == null || inv.Id == null) return;
    //     Account acc  = [SELECT Name FROM Account WHERE Id = :inv.Client__c LIMIT 1];
    //     String  name = buildPdfFileName(inv.InvoiceType__c, acc.Name, inv.Name);
    //     Blob pdfBlob;
 
    //     if (inv.InvoiceType__c == INVOICE_TYPE_HOUSEHOLD) {
    //         pdfBlob = renderPage(Page.HouseholdInvoice, new Map<String, String>{
    //             'primaryAccountId'  => inv.Client__c,
    //             'relatedAccountIds' => (relatedIds != null && !relatedIds.isEmpty())
    //                 ? String.join(relatedIds, ',') : '',
    //             'fromDate'  => fromDateStr,
    //             'toDate'    => toDateStr,
    //             'invoiceId' => inv.Name
    //         });
    //     } else {
    //         pdfBlob = renderPage(Page.InvoicePDF, new Map<String, String>{
    //             'accountId' => inv.Client__c,
    //             'fromDate'  => fromDateStr,
    //             'toDate'    => toDateStr,
    //             'invoiceNo' => inv.Name
    //         });
    //     }
 
    //     ContentVersion cv = new ContentVersion(
    //         Title        = name,
    //         PathOnClient = name + '.pdf',
    //         VersionData  = pdfBlob
    //     );
    //     insert cv;
    //     Id contentDocId = [
    //         SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
    //     ].ContentDocumentId;
    //     insert new ContentDocumentLink(
    //         ContentDocumentId = contentDocId,
    //         LinkedEntityId    = inv.Id,
    //         ShareType         = SHARE_TYPE_VIEWER
    //     );
    //     // FIX: include Invoice_Date__c = today in the same update.
    //     update new Invoice__c(
    //         Id                  = inv.Id,
    //         PDF_File_Id__c      = contentDocId,
    //         PDFGeneratedDate__c = Datetime.now(),
    //         Invoice_Date__c     = Date.today()    // always today
    //     );
    // }
    public static void regeneratePdfForInvoice(
    Invoice__c inv, List<Id> relatedIds, String fromDateStr, String toDateStr
) {
    if (inv == null || inv.Id == null) return;

    // ── Delete ALL existing PDF ContentDocumentLinks for this invoice ──
    List<ContentDocumentLink> existingLinks = [
        SELECT ContentDocumentId
        FROM   ContentDocumentLink
        WHERE  LinkedEntityId = :inv.Id
        AND    ContentDocument.FileExtension = 'pdf'
    ];
    if (!existingLinks.isEmpty()) {
        Set<Id> oldDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : existingLinks) {
            oldDocIds.add(cdl.ContentDocumentId);
        }
        delete [SELECT Id FROM ContentDocument WHERE Id IN :oldDocIds];
    }

    Account acc  = [SELECT Name FROM Account WHERE Id = :inv.Client__c LIMIT 1];
    String  name = buildPdfFileName(inv.InvoiceType__c, acc.Name, inv.Name);
    Blob pdfBlob;

    if (inv.InvoiceType__c == INVOICE_TYPE_HOUSEHOLD) {
        pdfBlob = renderPage(Page.HouseholdInvoice, new Map<String, String>{
            'primaryAccountId'  => inv.Client__c,
            'relatedAccountIds' => (relatedIds != null && !relatedIds.isEmpty())
                ? String.join(relatedIds, ',') : '',
            'fromDate'  => fromDateStr,
            'toDate'    => toDateStr,
            'invoiceId' => inv.Name
        });
    } else {
        pdfBlob = renderPage(Page.InvoicePDF, new Map<String, String>{
            'accountId' => inv.Client__c,
            'fromDate'  => fromDateStr,
            'toDate'    => toDateStr,
            'invoiceNo' => inv.Name
        });
    }

    ContentVersion cv = new ContentVersion(
        Title        = name,
        PathOnClient = name + '.pdf',
        VersionData  = pdfBlob
    );
    insert cv;
    Id contentDocId = [
        SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
    ].ContentDocumentId;
    insert new ContentDocumentLink(
        ContentDocumentId = contentDocId,
        LinkedEntityId    = inv.Id,
        ShareType         = SHARE_TYPE_VIEWER
    );
    update new Invoice__c(
        Id                  = inv.Id,
        PDF_File_Id__c      = contentDocId,
        PDFGeneratedDate__c = Datetime.now()
        // Invoice_Date__c     = Date.today()
    );
}

    // ── Private invoice record helpers ────────────────────────────────────────
    private static Invoice__c findOrCreateStandardInvoice(Id accountId, Date fromDate, Date toDate) {
        System.debug('findOrCreateStandardInvoice called');
        List<Invoice__c> existing = [
            SELECT Id, Name, PDF_File_Id__c, PDFGeneratedDate__c, Invoice_Date__c
            FROM   Invoice__c
            WHERE  Client__c      = :accountId
            AND    From_Date__c   = :fromDate
            AND    To_Date__c     = :toDate
            AND    InvoiceType__c = :INVOICE_TYPE_STANDARD
            LIMIT  1
        ];
        System.debug('existing: ' + existing);
 
        if (!existing.isEmpty()) {
            // Invoice__c inv = existing[0];
            // // Always refresh the invoice date to today so the PDF is current.
            // inv.Invoice_Date__c = Date.today();
            // update inv;
            // return inv;
            return existing[0];
        }
 
        return insertNewInvoice(new Invoice__c(
            InvoiceType__c  = INVOICE_TYPE_STANDARD,
            Client__c       = accountId,
            From_Date__c    = fromDate,
            To_Date__c      = toDate,
            Invoice_Date__c = Date.today()
        ));
    }

     private static Invoice__c findOrCreateHouseholdInvoice(
        Id primaryAccountId, String groupKey, Date fromDate, Date toDate
    ) {
        System.debug('findOrCreateHouseholdInvoice called');
        List<Invoice__c> existing = [
            SELECT Id, Name, PDF_File_Id__c, PDFGeneratedDate__c, Invoice_Date__c
            FROM   Invoice__c
            WHERE  InvoiceType__c          = :INVOICE_TYPE_HOUSEHOLD
            AND    Client__c               = :primaryAccountId
            AND    SuperBillPatientGroup__c = :groupKey
            AND    From_Date__c            = :fromDate
            AND    To_Date__c              = :toDate
            LIMIT  1
        ];
        System.debug('existing: ' + existing);
 
        if (!existing.isEmpty()) {
            // Invoice__c inv = existing[0];
            // // Always refresh the invoice date to today.
            // inv.Invoice_Date__c = Date.today();
            // update inv;
            // return inv;
            return existing[0];
        }
 
        return insertNewInvoice(new Invoice__c(
            InvoiceType__c          = INVOICE_TYPE_HOUSEHOLD,
            Client__c               = primaryAccountId,
            Primary_Client__c       = primaryAccountId,
            SuperBillPatientGroup__c = groupKey,
            From_Date__c            = fromDate,
            To_Date__c              = toDate,
            Invoice_Date__c         = Date.today()
        ));
    }

    private static Invoice__c insertNewInvoice(Invoice__c inv) {
        System.debug('insertNewInvoice called');
        Integer suffix = Math.mod(Math.abs(Crypto.getRandomInteger()), 900) + 100;
        inv.Name = 'INV_' + suffix;
        insert inv;
        inv.Name = inv.Name + String.valueOf(inv.Id).right(4);
        update inv;
        System.debug('inv '+inv);
        return inv;
    }

     private static void attachPdf(Invoice__c invoice, Blob pdfBlob, String pdfFileName) {
        /////////
        System.debug('attachPdf() called');
        /////////
        if (invoice.PDF_File_Id__c != null) {
            try { delete new ContentDocument(Id = invoice.PDF_File_Id__c); }
            catch (Exception e) { System.debug('Could not delete old PDF: ' + e.getMessage()); }
        }
        ContentVersion cv = new ContentVersion(
            Title         = pdfFileName,
            PathOnClient  = pdfFileName + '.pdf',
            VersionData   = pdfBlob
        );
        insert cv;
        Id contentDocId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocId,
            LinkedEntityId    = invoice.Id,
            ShareType         = SHARE_TYPE_VIEWER
        );
        // FIX: also persist Invoice_Date__c so preview links always show today.
        invoice.PDF_File_Id__c      = contentDocId;
        invoice.PDFGeneratedDate__c = Datetime.now();
        // invoice.Invoice_Date__c     = Date.today();
        if (invoice.Invoice_Date__c == null) {
            invoice.Invoice_Date__c = Date.today();
        }
        update invoice;
    }
 

    private static Blob renderPage(PageReference page, Map<String, String> params) {
        for (String k : params.keySet()) page.getParameters().put(k, params.get(k));        

        if (Test.isRunningTest()) {
            return Blob.valueOf('Test PDF Content');
        } else {
            return page.getContentAsPDF();
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // EMAIL
    // ═════════════════════════════════════════════════════════════════════════
    public static void sendInvoiceEmail(Invoice__c invoice, Id accountId) {
        // Re-query to get the freshest field values including the updated
        // Invoice_Date__c that was just stamped by attachPdf/regeneratePdfForInvoice.
        Invoice__c inv = [
            SELECT Id, Name, InvoiceType__c, PDF_File_Id__c,
                   From_Date__c, To_Date__c, Invoice_Date__c,
                   Client__r.PersonEmail, Client__r.Name
            FROM   Invoice__c
            WHERE  Id = :invoice.Id
            LIMIT  1
        ];
        try {
            sendEmailInternal(inv, accountId);
        } catch (NoEmailException nee) {
            System.debug('Email skipped — no address: ' + nee.getMessage());
        } catch (Exception e) {
            System.debug('Invoice email failed: ' + e.getMessage());
        }
        // No separate update needed — Invoice_Date__c was already set by attachPdf.
    }
   
    // ═════════════════════════════════════════════════════════════════════════
    // EMAIL  — replace the entire sendEmailInternal method
    // ═════════════════════════════════════════════════════════════════════════

    private static void sendEmailInternal(Invoice__c inv, Id accountId) {

        Account acct = [
            SELECT Id, Name, PersonContactId, PersonEmail, Send_Invoice_to_Client__c
            FROM   Account
            WHERE  Id = :accountId
            LIMIT  1
        ];

       
        List<EmailRecipient> recipients = new List<EmailRecipient>();
        Set<String>          addedKeys  = new Set<String>();   // dedup by email+name pair

        // ── 1. Related contacts who are flagged to receive invoices ───────────
        for (HealthCloudGA__ContactContactRelation__c ccr : [
            SELECT HealthCloudGA__Contact__r.Email,
                   HealthCloudGA__Contact__r.Name,
                   HealthCloudGA__Contact__c
            FROM   HealthCloudGA__ContactContactRelation__c
            WHERE  HealthCloudGA__RelatedContact__c = :acct.PersonContactId
            AND    HealthCloudGA__Contact__r.Additional_duties__c INCLUDES ('Receives invoices')
            AND    HealthCloudGA__Contact__r.Email != null
        ]) {
            String email = ccr.HealthCloudGA__Contact__r.Email;
            String name  = ccr.HealthCloudGA__Contact__r.Name;

            String dedupKey = email.toLowerCase() + '|' + name.toLowerCase();
            if (!addedKeys.contains(dedupKey)) {
                addedKeys.add(dedupKey);
                recipients.add(new EmailRecipient(email, name));
            }
        }

        // ── 2. Client themselves (if opted in) ────────────────────────────────
        if (acct.Send_Invoice_to_Client__c && String.isNotBlank(acct.PersonEmail)) {
            String email    = acct.PersonEmail;
            String name     = acct.Name;
            String dedupKey = email.toLowerCase() + '|' + name.toLowerCase();
            if (!addedKeys.contains(dedupKey)) {
                addedKeys.add(dedupKey);
                recipients.add(new EmailRecipient(email, name));
            }
        }

        if (recipients.isEmpty()) {
            System.debug('No email recipients found. Skipping email.');
            return;
        }

        // ── 3. Load email template ────────────────────────────────────────────
        List<EmailTemplate> templates = [
            SELECT Id, Subject, Body FROM EmailTemplate
            WHERE  DeveloperName = :EMAIL_TEMPLATE_NAME LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new InvoiceException('Email template "' + EMAIL_TEMPLATE_NAME + '" not found.');
        }
        EmailTemplate tmpl = templates[0];

        // ── 4. Load PDF attachment ────────────────────────────────────────────
        if (inv.PDF_File_Id__c == null) {
            throw new InvoiceException('Invoice PDF has not been generated yet.');
        }
        ContentVersion cv = [
            SELECT VersionData, Title FROM ContentVersion
            WHERE  ContentDocumentId = :inv.PDF_File_Id__c AND IsLatest = true LIMIT 1
        ];

        Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
        attach.setFileName(cv.Title + '.pdf');
        attach.setBody(cv.VersionData);
        attach.setContentType('application/pdf');

        // ── 5. Org-wide email address ─────────────────────────────────────────
        List<OrgWideEmailAddress> owaList = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE  IsAllowAllProfiles = true LIMIT 1
        ];

        // ── 6. Build one email per recipient (preserving each contact's name) ─
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (EmailRecipient r : recipients) {

            String personalizedSubject = resolveTemplate(tmpl.Subject, inv, r.name);
            String personalizedBody    = resolveTemplate(tmpl.Body,    inv, r.name);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setSubject(personalizedSubject);
            email.setPlainTextBody(personalizedBody);
            email.setToAddresses(new List<String>{ r.email });
            email.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attach });
            email.setSaveAsActivity(false);
            if (!owaList.isEmpty()) {
                email.setOrgWideEmailAddressId(owaList[0].Id);
            }
            emails.add(email);
        }

        // ── 7. Send ───────────────────────────────────────────────────────────
        Messaging.SendEmailResult[] results = Messaging.sendEmail(emails);

        List<String> errors = new List<String>();
        for (Messaging.SendEmailResult res : results) {
            if (!res.isSuccess()) {
                for (Messaging.SendEmailError err : res.getErrors()) {
                    errors.add(err.getMessage());
                }
            }
        }
        if (!errors.isEmpty()) {
            throw new InvoiceException('Email send failed: ' + String.join(errors, '; '));
        }
        
        // Mark invoice as emailed
        inv.Invoice_Emailed__c = true;
        update inv;
    }
    

     private class EmailRecipient {
        String email;
        String name;
        EmailRecipient(String email, String name) {
            this.email = email;
            this.name  = name;
        }
    }

    private static String resolveTemplate(String tmpl, Invoice__c inv,  String recipientName) {
        Map<String, String> tokens = new Map<String, String>{
            '{!Invoice__c.Name}'            => inv.Name,
            '{!Invoice__c.InvoiceType__c}'  => inv.InvoiceType__c,
            '{!Invoice__c.From_Date__c}'    => inv.From_Date__c    != null ? String.valueOf(inv.From_Date__c)    : '',
            '{!Invoice__c.To_Date__c}'      => inv.To_Date__c      != null ? String.valueOf(inv.To_Date__c)      : '',
            '{!Invoice__c.Invoice_Date__c}' => inv.Invoice_Date__c != null ? String.valueOf(inv.Invoice_Date__c) : '',
            '{!Invoice__c.Client__r.Name}'  => recipientName
        };
        String resolved = tmpl;
        for (String token : tokens.keySet()) resolved = resolved.replace(token, tokens.get(token));
        return resolved;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // BILLING CHECKS
    // ═════════════════════════════════════════════════════════════════════════
    public static Boolean hasBillings(Id accountId, Date fromDate, Date toDate) {
        System.debug('hasBillings');
        System.debug('hasBillings accountId fromDate toDate>> '+accountId+' '+fromDate+' '+toDate);
        if (accountId == null || fromDate == null || toDate == null) return false;
        Datetime fromDt = Datetime.newInstance(fromDate, Time.newInstance(0,0,0,0));
        Datetime toDt   = Datetime.newInstance(toDate,   Time.newInstance(23,59,59,999));

        Set<Id> billingIds = new Set<Id>();
        for (Event e : [
            SELECT Billing__c FROM Event
            WHERE AccountId = :accountId AND Billing__c != null
            AND Billing__r.Is_Synced__c = true
            //AND StartDateTime <= :toDt AND EndDateTime >= :fromDt
            AND (
    (
        IsAllDayEvent = true
        AND ActivityDate >= :fromDate
        AND ActivityDate <= :toDate
    )
    OR
    (
        IsAllDayEvent = false
        AND StartDateTime <= :toDt
        AND EndDateTime >= :fromDt
    )
)
        ]) {
            billingIds.add(e.Billing__c);
        }
        System.debug('hasBillings billingIds>> '+billingIds);
        if (billingIds.isEmpty()) return false;

        System.debug('billingIds: '+billingIds);

        return ![ SELECT Id FROM Billing_Line_Item__c
                  WHERE Invoice__c IN :billingIds
                  AND Service_Date__c >= :fromDate AND Service_Date__c <= :toDate LIMIT 1 ].isEmpty();
    }

    /**
     * Bulkified — replaces calling hasBillings() in a loop.
     * Returns the subset of accountIds that have billing records.
     */
    public static Set<Id> filterAccountsWithBillings(
        Set<Id> accountIds, Date fromDate, Date toDate
    ) {
        if (accountIds == null || accountIds.isEmpty()) return new Set<Id>();
        Datetime fromDt = Datetime.newInstance(fromDate, Time.newInstance(0,0,0,0));
        Datetime toDt   = Datetime.newInstance(toDate,   Time.newInstance(23,59,59,999));

        Map<Id, Id> billingToAccount = new Map<Id, Id>();
        for (Event e : [
            SELECT AccountId, Billing__c FROM Event
            WHERE AccountId IN :accountIds AND Billing__c != null
            AND Billing__r.Is_Synced__c = true
            //AND StartDateTime <= :toDt AND EndDateTime >= :fromDt
            AND (
    (
        IsAllDayEvent = true
        AND ActivityDate >= :fromDate
        AND ActivityDate <= :toDate
    )
    OR
    (
        IsAllDayEvent = false
        AND StartDateTime <= :toDt
        AND EndDateTime >= :fromDt
    )
)
        ]) {
            billingToAccount.put(e.Billing__c, e.AccountId);
        }
        if (billingToAccount.isEmpty()) return new Set<Id>();

        Set<Id> result = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Invoice__c billingId FROM Billing_Line_Item__c
            WHERE Invoice__c IN :billingToAccount.keySet()
            AND Service_Date__c >= :fromDate AND Service_Date__c <= :toDate
            GROUP BY Invoice__c
        ]) {
            Id accId = billingToAccount.get((Id) ar.get('billingId'));
            if (accId != null) result.add(accId);
        }
        return result;
    }


     public static Boolean hasBillables(Id accountId, Date fromDate, Date toDate) {
        if (accountId == null || fromDate == null || toDate == null) return false;
 
        Datetime fromDt = Datetime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
        Datetime toDt   = Datetime.newInstance(toDate,   Time.newInstance(23, 59, 59, 999));
 
        // Step 1: Collect Billing IDs from synced Events whose window overlaps the range
        Set<Id> billingIds = new Set<Id>();
        for (Event e : [
            SELECT Billing__c
            FROM   Event
            WHERE  AccountId              = :accountId
            AND    Billing__c             != null
            AND    Billing__r.Is_Synced__c = true
            
            //AND    StartDateTime          <= :toDt
            //AND    EndDateTime            >= :fromDt
            AND (
    (
        IsAllDayEvent = true
        AND ActivityDate >= :fromDate
        AND ActivityDate <= :toDate
    )
    OR
    (
        IsAllDayEvent = false
        AND StartDateTime <= :toDt
        AND EndDateTime >= :fromDt
    )
)
        ]) {
            billingIds.add(e.Billing__c);
        }
 
        if (billingIds.isEmpty()) return false;
 
        // Step 2: Check whether any BLI under those Billings falls in the date range
        return ![
            SELECT Id
            FROM   Billing_Line_Item__c
            WHERE  Invoice__c       IN :billingIds
            AND    Service_Date__c  >= :fromDate
            AND    Service_Date__c  <= :toDate
            LIMIT  1
        ].isEmpty();
    }

    // ═════════════════════════════════════════════════════════════════════════
    // RELATED ACCOUNT HELPERS
    // ═════════════════════════════════════════════════════════════════════════
    // public static Map<Id, List<Id>> getRelatedAccountsForPrimaries(
    //     List<Id> primaryAccountIds, Date fromDate, Date toDate
    // ) {
    //     Map<Id, List<Id>> primaryToRelatedMap = new Map<Id, List<Id>>();
    //     Map<Id, Id>       contactToPrimaryMap = new Map<Id, Id>();

    //     for (Account acc : [SELECT Id, PersonContactId FROM Account WHERE Id IN :primaryAccountIds]) {
    //         if (acc.PersonContactId != null) contactToPrimaryMap.put(acc.PersonContactId, acc.Id);
    //     }
    //     if (contactToPrimaryMap.isEmpty()) return primaryToRelatedMap;

    //     Set<Id>    allRelatedAccIds       = new Set<Id>();
    //     Map<Id, Id> relatedAccToPrimaryMap = new Map<Id, Id>();

    //     for (HealthCloudGA__ContactContactRelation__c rel : [
    //         SELECT HealthCloudGA__Contact__r.AccountId, HealthCloudGA__RelatedContact__c
    //         FROM   HealthCloudGA__ContactContactRelation__c
    //         WHERE  HealthCloudGA__RelatedContact__c IN :contactToPrimaryMap.keySet()
    //         AND    Type__c = :RELATION_TYPE_COUPLE
    //     ]) {
    //         Id primaryId    = contactToPrimaryMap.get(rel.HealthCloudGA__RelatedContact__c);
    //         Id relatedAccId = rel.HealthCloudGA__Contact__r.AccountId;
    //         if (primaryId == null || relatedAccId == null) continue;
    //         allRelatedAccIds.add(relatedAccId);
    //         relatedAccToPrimaryMap.put(relatedAccId, primaryId);
    //     }

    //     // One bulkified call instead of N individual hasBillings() calls
    //     Set<Id> withBillings = filterAccountsWithBillings(allRelatedAccIds, fromDate, toDate);

    //     for (Id relAccId : allRelatedAccIds) {
    //         if (!withBillings.contains(relAccId)) continue;
    //         Id primaryId = relatedAccToPrimaryMap.get(relAccId);
    //         if (!primaryToRelatedMap.containsKey(primaryId)) {
    //             primaryToRelatedMap.put(primaryId, new List<Id>());
    //         }

    //         if (!primaryToRelatedMap.get(primaryId).contains(relAccId)) {
    //             primaryToRelatedMap.get(primaryId).add(relAccId);
    //         }
    //     }
    //     return primaryToRelatedMap;
    // }

    public static Map<Id, List<Id>> getRelatedAccountsForPrimaries(
    List<Id> primaryAccountIds, Date fromDate, Date toDate
) {
    Map<Id, List<Id>> primaryToRelatedMap = new Map<Id, List<Id>>();
    Map<Id, Id> contactToPrimaryMap = new Map<Id, Id>();

    for (Account acc : [SELECT Id, PersonContactId FROM Account WHERE Id IN :primaryAccountIds]) {
        if (acc.PersonContactId != null) contactToPrimaryMap.put(acc.PersonContactId, acc.Id);
    }
    if (contactToPrimaryMap.isEmpty()) return primaryToRelatedMap;

    Set<Id> allRelatedAccIds        = new Set<Id>();
    Map<Id, Id> relatedAccToPrimaryMap = new Map<Id, Id>();

    // ── Direction 1: account is the primary (RelatedContact side) ──────────
    for (HealthCloudGA__ContactContactRelation__c rel : [
        SELECT HealthCloudGA__Contact__r.AccountId, HealthCloudGA__RelatedContact__c
        FROM   HealthCloudGA__ContactContactRelation__c
        WHERE  HealthCloudGA__RelatedContact__c IN :contactToPrimaryMap.keySet()
        AND    Type__c = :RELATION_TYPE_COUPLE
    ]) {
        Id primaryId    = contactToPrimaryMap.get(rel.HealthCloudGA__RelatedContact__c);
        Id relatedAccId = rel.HealthCloudGA__Contact__r.AccountId;
        if (primaryId == null || relatedAccId == null) continue;
        allRelatedAccIds.add(relatedAccId);
        relatedAccToPrimaryMap.put(relatedAccId, primaryId);
    }

    // ── Direction 2: account is the related (Contact side) ─────────────────
    for (HealthCloudGA__ContactContactRelation__c rel : [
        SELECT HealthCloudGA__RelatedContact__r.AccountId, HealthCloudGA__Contact__c
        FROM   HealthCloudGA__ContactContactRelation__c
        WHERE  HealthCloudGA__Contact__c IN :contactToPrimaryMap.keySet()
        AND    Type__c = :RELATION_TYPE_COUPLE
    ]) {
        Id selectedAccId = contactToPrimaryMap.get(rel.HealthCloudGA__Contact__c);
        Id otherAccId    = rel.HealthCloudGA__RelatedContact__r.AccountId;
        if (selectedAccId == null || otherAccId == null) continue;
        allRelatedAccIds.add(otherAccId);
        relatedAccToPrimaryMap.put(otherAccId, selectedAccId);
    }

    // ── Bulkified billing check ─────────────────────────────────────────────
    Set<Id> withBillings = filterAccountsWithBillings(allRelatedAccIds, fromDate, toDate);

    for (Id relAccId : allRelatedAccIds) {
        if (!withBillings.contains(relAccId)) continue;
        Id primaryId = relatedAccToPrimaryMap.get(relAccId);
        if (!primaryToRelatedMap.containsKey(primaryId)) {
            primaryToRelatedMap.put(primaryId, new List<Id>());
        }
        if (!primaryToRelatedMap.get(primaryId).contains(relAccId)) {
            primaryToRelatedMap.get(primaryId).add(relAccId);
        }
    }
    return primaryToRelatedMap;
}

    private static List<Id> filterEligibleRelated(List<Id> relatedIds, Date fromDate, Date toDate) {
        if (relatedIds == null || relatedIds.isEmpty()) return new List<Id>();
        Set<Id> relatedIdSet = new Set<Id>();
        if (relatedIds != null) {
            relatedIdSet.addAll(relatedIds);
        }
        Set<Id> withBillings = filterAccountsWithBillings(relatedIdSet, fromDate, toDate);
        List<Id> eligible = new List<Id>();
        for (Id id : relatedIds) { if (withBillings.contains(id)) eligible.add(id); }
        return eligible;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // UTILITY
    // ═════════════════════════════════════════════════════════════════════════
    public static String buildPdfFileName(String invoiceType, String clientName, String invoiceName) {
        String safeName = String.isNotBlank(clientName)
            ? clientName.replaceAll('[^a-zA-Z0-9 ]', '').trim().replaceAll('\\s+', '_') : '';
        return (invoiceType == INVOICE_TYPE_HOUSEHOLD ? 'Household_Invoice_' : 'Standard_Invoice_')
            + safeName + '_' + invoiceName;
    }

    public static List<String> wrapText(String text, Integer maxLen) {
        List<String> lines = new List<String>();
        if (String.isBlank(text)) return lines;
        String line = '';
        for (String word : text.split(' ')) {
            String candidate = (line == '' ? word : line + ' ' + word);
            if (candidate.length() <= maxLen) {
                line = candidate;
            } else {
                if (!String.isBlank(line)) lines.add(line);
                line = word;
            }
        }
        if (!String.isBlank(line)) lines.add(line);
        return lines;
    }

    @TestVisible
    public static Date parseUsDate(String dateStr) {
        if (String.isBlank(dateStr)) return null;
        dateStr = dateStr.trim();
        if (dateStr.contains(':')) {
            try { return Datetime.valueOf(dateStr.replace('/', '-')).date(); }
            catch (Exception e) { throw new AuraHandledException('Invalid datetime format: ' + dateStr); }
        }
        dateStr = dateStr.replace('/', '-');
        List<String> parts = dateStr.split('-');
        if (parts.size() != 3) throw new AuraHandledException('Invalid date format: ' + dateStr);
        Integer year, month, day;
        if (parts[0].length() == 4) {
            year = Integer.valueOf(parts[0]); month = Integer.valueOf(parts[1]); day = Integer.valueOf(parts[2]);
        } else {
            month = Integer.valueOf(parts[0]); day = Integer.valueOf(parts[1]); year = Integer.valueOf(parts[2]);
        }
        return Date.newInstance(year, month, day);
    }

    // ── Private helpers ───────────────────────────────────────────────────────
    private static String buildGroupKey(Id primaryId, List<Id> relatedIds) {
        List<String> ids = new List<String>{ primaryId };
        if (relatedIds != null) for (Id id : relatedIds) ids.add(String.valueOf(id));
        ids.sort();
        return String.join(ids, ',');
    }

    private static String buildEventDescription(Billing_Line_Item__c bli) {
        String startStr = formatTime(bli.Invoice__r.Event_Start_Date_Time__c);
        String endStr   = formatTime(bli.Invoice__r.Event_End_Date_Time__c);
        String assignee = '';
        if (bli.Invoice__r.Event_Assignee__r != null) {
            assignee = ' '
                + (bli.Invoice__r.Event_Assignee__r.LastName  != null ? bli.Invoice__r.Event_Assignee__r.LastName  : '')
                + (bli.Invoice__r.Event_Assignee__r.FirstName != null ? ', ' + bli.Invoice__r.Event_Assignee__r.FirstName : '');
        }
        return startStr + (String.isNotBlank(startStr) && String.isNotBlank(endStr) ? ' - ' : '') + endStr + assignee;
    }

    private static String formatTime(Datetime dt) {
        if (dt == null) return '';
        return dt.format('h:mm a').toLowerCase().replace(' am', 'am').replace(' pm', 'pm');
    }

    private static void accumulateHourly(
        Map<String, HourlySummaryRow> mapp,
        Decimal rate,
        Decimal hours,
        Decimal amt,
        Boolean isFlatAmount
    ) {
        String key = isFlatAmount ? 'FLAT' : String.valueOf(rate);

        if (!mapp.containsKey(key)) {
            mapp.put(key, new HourlySummaryRow(rate, isFlatAmount));
        }

        if (!isFlatAmount) {
            mapp.get(key).totalHours += hours;
        }

        mapp.get(key).totalAmount += amt;
    }

    private static void addExpenseRow(List<CareDetailRow> listt, Billing_Line_Item__c bli, String subject) {
        if (bli.Amount__c == null || bli.Amount__c == 0) return;
         listt.add(new CareDetailRow(
            bli.Invoice__r.Name,
            subject,
            bli.Service_Date__c,
            '',
            '',
            formatCurrency(bli.Amount__c),
            '- Expense: ' + (String.isBlank(bli.Expense_Description__c) ? '' : bli.Expense_Description__c),
            false,
            true,
            0,
            0
        ));
    }

    private static void addMileageRow(List<CareDetailRow> listt, Billing_Line_Item__c bli, String subject) {
        if (bli.Amount__c == null || bli.Amount__c == 0) return;

        listt.add(new CareDetailRow(
            bli.Invoice__r.Name,
            subject,
            bli.Service_Date__c,
            '',
            '',
            formatCurrency(bli.Amount__c),
            '- Mileage: ' + (String.isBlank(bli.Mileage_Description__c) ? '' : bli.Mileage_Description__c),
            false,
            true,
            0,
            0
        ));
    }

    private static void applyRowSpans(List<CareDetailRow> rows) {

    Map<String, Integer> billingCount = new Map<String, Integer>();
    Map<String, Integer> bliCount     = new Map<String, Integer>();

    for (CareDetailRow cd : rows) {

        billingCount.put(
            cd.billingName,
            (billingCount.get(cd.billingName) ?? 0) + 1
        );

        String bliKey = cd.billingName + '|' + cd.billingLineItemName;

        bliCount.put(
            bliKey,
            (bliCount.get(bliKey) ?? 0) + 1
        );
    }

    String currentBilling = '';
    String currentBliKey = '';

    for (CareDetailRow cd : rows) {

        cd.showBillingName = cd.billingName != currentBilling;

        if (cd.showBillingName) {
            cd.billingRowSpan = billingCount.get(cd.billingName);
            currentBilling = cd.billingName;
        }

        String bliKey = cd.billingName + '|' + cd.billingLineItemName;

        cd.showBliName = bliKey != currentBliKey;

        if (cd.showBliName) {
            cd.bliRowSpan = bliCount.get(bliKey);
            currentBliKey = bliKey;
        }
    }
}

    private static Map<Id, Invoice__c> queryExistingInvoices(
        List<Id> accountIds, Date fromDate, Date toDate, String type
    ) {
        Map<Id, Invoice__c> mapp = new Map<Id, Invoice__c>();
        for (Invoice__c inv : [
            SELECT Id, Client__c FROM Invoice__c
            WHERE  Client__c     IN :accountIds
            AND    From_Date__c   = :fromDate   // exact match
            AND    To_Date__c     = :toDate     // exact match
            AND    InvoiceType__c = :type
        ]) {
            // First-one-wins; duplicate invoices for same client+period are a data issue.
            if (!mapp.containsKey(inv.Client__c)) {
                mapp.put(inv.Client__c, inv);
            }
        }
        return mapp;
    }

    private static List<Id> filterAccountsByType(List<Id> accountIds, String type) {
        Boolean isPrimary = (type == INVOICE_TYPE_HOUSEHOLD);
        List<Account> filtered = [
            SELECT Id FROM Account WHERE Id IN :accountIds AND Is_Primary__c = :isPrimary
        ];
        if (isPrimary && filtered.isEmpty()) {
            throw new InvoiceException(
                'No primary accounts found. Household Invoice can only be generated for primary clients.'
            );
        }
        List<Id> ids = new List<Id>();
        for (Account a : filtered) ids.add(a.Id);
        return ids;
    }

    private static void validateBulkInput(
        List<Id> accountIds, String fromDateStr, String toDateStr, String type
    ) {
        System.debug('validateBulkInput - accountIds'+ accountIds);
        if (accountIds == null || accountIds.isEmpty()) throw new AuraHandledException('No accounts selected.');
        if (String.isBlank(fromDateStr) || String.isBlank(toDateStr)) throw new AuraHandledException('Invalid date range.');
        if (String.isBlank(type)) throw new AuraHandledException('Invoice type is required.');
        Date f, t;
        try { f = Date.valueOf(fromDateStr); t = Date.valueOf(toDateStr); }
        catch (Exception e) { throw new AuraHandledException('Invalid date format. Expected YYYY-MM-DD.'); }
        if (f > t) throw new AuraHandledException('From Date cannot be greater than To Date.');
    }

    private static Bulk_Zip_Job__c insertJob(Date fromDate, Date toDate, String type) {
        Bulk_Zip_Job__c job = new Bulk_Zip_Job__c(
            Status__c = JOB_STATUS_PROCESSING, From_Date__c = fromDate,
            To_Date__c = toDate, Invoice_Type__c = type
        );
        insert job;
        return job;
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) {
            return '$0.00';
        }

        String value = String.valueOf(amount.setScale(2));

        List<String> parts = value.split('\\.');

        String integerPart = parts[0];
        String decimalPart = parts.size() > 1 ? parts[1] : '00';

        while (decimalPart.length() < 2) {
            decimalPart += '0';
        }

        // Add commas
        String formattedInteger = '';
        while (integerPart.length() > 3) {
            formattedInteger =
                ',' + integerPart.substring(integerPart.length() - 3) + formattedInteger;
            integerPart = integerPart.substring(0, integerPart.length() - 3);
        }

        formattedInteger = integerPart + formattedInteger;

        return '$' + formattedInteger + '.' + decimalPart;
    }
}