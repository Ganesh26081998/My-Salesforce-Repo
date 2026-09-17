/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : InvoicePDFController
CreatedOn      : 30-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This controller class is used to prepare and load invoice PDF
                 data including organization details, client information,
                 invoice dates, billing line items, care summaries, hourly
                 summaries, charge totals, and formatted address details for
                 invoice PDF generation.
----------------------------------------------------------------------------
*/
public with sharing class InvoicePDFController {

    // ── Page-bound properties ─────────────────────────────────────────────────
    public String  accountId          { get; set; }
    public String  companyName        { get; set; }
    public String  companyStreet      { get; set; }
    public String  companyCity        { get; set; }
    public String  companyState       { get; set; }
    public String  companyPostalCode  { get; set; }
    public String  companyCountry     { get; set; }
    public String  companyPhone       { get; set; }
    public String  clientName         { get; set; }
    public String  clientAddress      { get; set; }
    public String  invoiceNo          { get; set; }
    public String  invoiceDate        { get; set; }
    public String  fromDate           { get; set; }
    public String  toDate             { get; set; }
    public String  emailed            { get; set; }
    public String  careSummary        { get; set; }
    public Decimal careTotal          { get; set; }
    public String  paymentDesc        { get; set; }
    public Decimal paymentAmount      { get; set; }
    public String  paymentDate        { get; set; }
    public Decimal totalCharges       { get; set; }
    public Decimal totalPayments      { get; set; }
    public Decimal amountDue          { get; set; }
    public Decimal totalHourlyCharges  { get; set; }
    public Decimal totalMileageCharges { get; set; }
    public Decimal totalExpenseCharges { get; set; }

    public List<InvoiceService.CareDetailRow>    careDetails       { get; set; }
    public List<InvoiceService.CareSummaryRow>   careSummaryRows   { get; set; }
    public List<InvoiceService.HourlySummaryRow> hourlySummaryRows { get; set; }
    public List<String> addressLines { get; set; }

    // ── Constructor ───────────────────────────────────────────────────────────
    public InvoicePDFController() {
        accountId = ApexPages.currentPage().getParameters().get('accountId');
        String fromDateParam  = ApexPages.currentPage().getParameters().get('fromDate');
        String toDateParam    = ApexPages.currentPage().getParameters().get('toDate');
        String invoiceNoParam = ApexPages.currentPage().getParameters().get('invoiceNo');

        initDates(fromDateParam, toDateParam);
        initDefaults(invoiceNoParam);
        loadOrgDetails();
        loadClientDetails();
        loadLineItems(fromDateParam, toDateParam);
        prepareAddressLines();
    }

    // ── Private init helpers ──────────────────────────────────────────────────
    private void initDates(String fromDateParam, String toDateParam) {
        Date fromDateValue = InvoiceService.parseUsDate(fromDateParam);
        Date toDateValue   = InvoiceService.parseUsDate(toDateParam);
        
        if (fromDateValue == null || toDateValue == null) {
            return;
        }

        fromDate = Datetime.newInstance(fromDateValue, Time.newInstance(0,0,0,0)).format('MM/dd/yyyy');
        toDate   = Datetime.newInstance(toDateValue,   Time.newInstance(0,0,0,0)).format('MM/dd/yyyy');
    }

    private void initDefaults(String invoiceNoParam) {
        invoiceNo     = invoiceNoParam != null ? invoiceNoParam : '';
        invoiceDate   = loadInvoiceDate(invoiceNoParam);
        emailed       = '';
        careSummary   = '';
        careTotal     = 0;
        paymentDesc   = 'Payment received on ';
        paymentAmount = 0;
        totalCharges  = 0;
        totalPayments = 0;
        amountDue     = 0;
        totalHourlyCharges  = 0;
        totalMileageCharges = 0;
        totalExpenseCharges = 0;
        careDetails       = new List<InvoiceService.CareDetailRow>();
        careSummaryRows   = new List<InvoiceService.CareSummaryRow>();
        hourlySummaryRows = new List<InvoiceService.HourlySummaryRow>();
    }

    private void loadOrgDetails() {
        Organization org = [
            SELECT Name, Street, City, State, PostalCode, Country, Phone
            FROM Organization LIMIT 1
        ];
        companyName       = org.Name;
        companyStreet     = org.Street != null ? org.Street.replace('\n', '<br/>') : '';
        companyCity       = org.City       != null ? org.City       : '';
        companyState      = org.State      != null ? org.State      : '';
        companyPostalCode = org.PostalCode != null ? org.PostalCode : '';
        companyCountry    = org.Country    != null ? org.Country    : '';

        if (org.Phone != null) {
            String digits = org.Phone.replaceAll('[^0-9]', '');
            companyPhone = digits.length() == 10
                ? digits.substring(0,3) + '-' + digits.substring(3,6) + '-' + digits.substring(6,10)
                : org.Phone;
        }
    }

    private void loadClientDetails() {
        if (String.isBlank(accountId)) {
            return;
        }
        
        List<Account> clients = [
            SELECT Id, Name, Address__Street__s,
                Address__City__s,
                Address__StateCode__s,
                Address__PostalCode__s,
                Address__CountryCode__s
            FROM Account WHERE Id = :accountId LIMIT 1
        ];
        if(clients.isEmpty()) return;
        clientName    = clients[0].Name;
        List<String> parts = new List<String>();

if (String.isNotBlank(clients[0].Address__Street__s)) {
    parts.add(clients[0].Address__Street__s);
}

String cityStateZip = '';

if (String.isNotBlank(clients[0].Address__City__s)) {
    cityStateZip += clients[0].Address__City__s;
}

if (String.isNotBlank(clients[0].Address__StateCode__s)) {

    if (String.isNotBlank(cityStateZip)) {
        cityStateZip += ', ';
    }

    cityStateZip += clients[0].Address__StateCode__s;
}

if (String.isNotBlank(clients[0].Address__PostalCode__s)) {

    if (String.isNotBlank(cityStateZip)) {
        cityStateZip += ', ';
    }

    cityStateZip += clients[0].Address__PostalCode__s;
}

if (String.isNotBlank(cityStateZip)) {
    parts.add(cityStateZip);
}


clientAddress = String.join(parts, '\n');
    }

    private void loadLineItems(String fromDateParam, String toDateParam) {
        InvoiceService.LineItemResult result =
            InvoiceService.buildLineItemResult(accountId, fromDateParam, toDateParam);

        careDetails         = result.careDetails;
        careSummaryRows     = result.careSummaryRows;
        hourlySummaryRows   = result.hourlySummaryRows;
        totalHourlyCharges  = result.totalHourlyCharges;
        totalMileageCharges = result.totalMileageCharges;
        totalExpenseCharges = result.totalExpenseCharges;
        totalCharges        = result.totalCharges;
        amountDue           = 0;
    }

    private void prepareAddressLines() {
        addressLines =  clientAddress.split('\n');
    }

    private String loadInvoiceDate(String invoiceNoParam) {
        // Fallback to today only if invoice record not found
        if (String.isBlank(invoiceNoParam)) {
            return Datetime.newInstance(System.today(), Time.newInstance(0,0,0,0))
                        .format('MM/dd/yyyy');
        }

        List<Invoice__c> invoices = [
            SELECT Invoice_Date__c
            FROM   Invoice__c
            WHERE  Name = :invoiceNoParam
            LIMIT  1
        ];

        if (!invoices.isEmpty() && invoices[0].Invoice_Date__c != null) {
            // Use the saved Invoice_Date__c — never changes after first creation
            return Datetime.newInstance(
                invoices[0].Invoice_Date__c,
                Time.newInstance(0,0,0,0)
            ).format('MM/dd/yyyy');
        }

        // Fallback if no record found
        return Datetime.newInstance(System.today(), Time.newInstance(0,0,0,0))
                    .format('MM/dd/yyyy');
    }
}