/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : SuperBillPDFController
CreatedOn      : 30-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This controller class is used to generate Super Bill PDF
                 data for primary and related clients, including organization
                 details, patient billing sections, care detail rows, invoice
                 summaries, hourly summaries, totals, and formatted client
                 address information for PDF rendering.
----------------------------------------------------------------------------
*/
public with sharing class SuperBillPDFController {    

    public String companyName { get; set; }
    public String companyStreet { get; set; }
    public String companyCity { get; set; }
    public String companyState { get; set; }
    public String companyPostalCode { get; set; }
    public String companyCountry { get; set; }
    public String companyAddress { get; set; }
    public String companyPhone { get; set; }

    public String clientName { get; set; }
    public String clientAddress { get; set; }

    public Contact primaryContact { get; set; }
    public Contact relatedContact { get; set; }

    public String primaryContactId { get; set; }
    public String relatedContactId { get; set; }

    public String fromDateStr { get; set; }
    public String toDateStr { get; set; }

    public String invoiceNo { get; set; }
    public String invoiceDate { get; set; }

    public List<String> addressLines { get; set; }

    public List<PatientSection> patientSections { get; set; }
    public List<InvoiceService.HourlySummaryRow> hourlySummaryRows { get; set; }

    public Decimal grandTotal { get; set; }
    public Decimal totalHourlyCharges { get; set; }
    public Decimal totalMileageCharges { get; set; }
    public Decimal totalExpenseCharges { get; set; }
    public Decimal totalCharges { get; set; }
    public Decimal amountDue { get; set; }

    public String paymentDesc { get; set; }

    // -------------------------------------------------------------------------
    public SuperBillPDFController() {

        patientSections = new List<PatientSection>();
        hourlySummaryRows = new List<InvoiceService.HourlySummaryRow>();

        grandTotal = 0;
        totalHourlyCharges = 0;
        totalMileageCharges = 0;
        totalExpenseCharges = 0;

        paymentDesc = 'Payment received on ';

        String primaryAccountId = ApexPages.currentPage().getParameters().get('primaryAccountId');
        String relatedIdsParam = ApexPages.currentPage().getParameters().get('relatedAccountIds');
        String fromParam = ApexPages.currentPage().getParameters().get('fromDate');
        String toParam = ApexPages.currentPage().getParameters().get('toDate');

        invoiceNo = ApexPages.currentPage().getParameters().get('invoiceId');

        if (String.isBlank(primaryAccountId) || String.isBlank(fromParam) || String.isBlank(toParam)) {
            return;
        }

        Date fromDate;
        Date toDate;

        try {
            fromDate = Date.valueOf(fromParam);
            toDate = Date.valueOf(toParam);
        } catch (Exception ex) {
            return;
        }

        fromDateStr = formatDate(fromDate);
        toDateStr = formatDate(toDate);

        // invoiceDate = formatDate(Date.today());
        invoiceDate = loadInvoiceDate(invoiceNo);

        loadOrganizationDetails();
        loadClientDetails(primaryAccountId);

        List<Account> primaryAccounts = [
            SELECT Id, Name, PersonContactId
            FROM Account
            WHERE Id = :primaryAccountId
            LIMIT 1
        ];

        if (primaryAccounts.isEmpty()) {
            return;
        }

        Account primaryAcc = primaryAccounts[0];

        PatientSection primarySection = new PatientSection();

        primarySection.patientName = primaryAcc.Name;
        primarySection.patientLabel = 'Primary Client';
        primarySection.roleName = 'Self';

primarySection.rows = BillingPDFUtility.getCareDetailRows(
    primaryAcc.Id,
    fromDate,
    toDate
);

if (primarySection.rows != null && !primarySection.rows.isEmpty()) {

    

    applyBillingRowSpan(primarySection.rows);

    primarySection.patientTotal = calculateTotal(primarySection.rows);

    patientSections.add(primarySection);

    grandTotal += primarySection.patientTotal;
}
        // primarySection.rows = BillingPDFUtility.getCareDetailRows(
        //     primaryAcc.Id,
        //     fromDate,
        //     toDate
        // );

        // if (primarySection.rows == null || primarySection.rows.isEmpty()) {
        //     return; // no data for primary — skip entire invoice
        // }

        // applyBillingRowSpan(primarySection.rows);

        // primarySection.patientTotal = calculateTotal(primarySection.rows);

        // patientSections.add(primarySection);

        // grandTotal += primarySection.patientTotal;

        // ---------------------------------------------------------------------
        // RELATED CLIENTS
        // ---------------------------------------------------------------------
        if (!String.isBlank(relatedIdsParam)) {

            List<Id> relatedAccountIds = new List<Id>();

            for (String s : relatedIdsParam.split(',')) {
                relatedAccountIds.add((Id) s);
            }

            Map<Id, HealthCloudGA__ContactContactRelation__c> relMap =
                new Map<Id, HealthCloudGA__ContactContactRelation__c>();

            List<HealthCloudGA__ContactContactRelation__c> relList = [
                SELECT
                    HealthCloudGA__Contact__r.AccountId,
                    HealthCloudGA__Contact__r.Name,
                    HealthCloudGA__Role__r.Name                	
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE HealthCloudGA__RelatedContact__c = :primaryAcc.PersonContactId
                AND HealthCloudGA__Contact__r.AccountId IN :relatedAccountIds
                AND Type__c = 'Couple Household'
            ];
            
            System.debug('relList: '+relList);

            for (HealthCloudGA__ContactContactRelation__c rel : relList) {
                relMap.put(rel.HealthCloudGA__Contact__r.AccountId, rel);
            }

            for (Id relAccId : relatedAccountIds) {

                HealthCloudGA__ContactContactRelation__c rel = relMap.get(relAccId);

                if (rel == null) {
                    continue;
                }

                PatientSection section = new PatientSection();

                section.patientName = rel.HealthCloudGA__Contact__r.Name;

                section.patientLabel = 'Related Client';

                section.roleName =
                    rel.HealthCloudGA__Role__r != null
                    ? rel.HealthCloudGA__Role__r.Name
                    : '';

                section.rows = BillingPDFUtility.getCareDetailRows(
                    relAccId,
                    fromDate,
                    toDate
                );

                if (section.rows == null || section.rows.isEmpty()) {
                    continue; // no data for this related client — skip their section
                }

                

                applyBillingRowSpan(section.rows);

                section.patientTotal = calculateTotal(section.rows);

                patientSections.add(section);

                grandTotal += section.patientTotal;
            }
        }

        if (patientSections.isEmpty()) {
            return;
        }

        prepareAddressLines();

        List<BillingPDFUtility.CareDetailRow> allRows =
            new List<BillingPDFUtility.CareDetailRow>();

        for (PatientSection ps : patientSections) {
            allRows.addAll(ps.rows);
        }

        buildSummary(allRows);
    }

    // -------------------------------------------------------------------------
    private void loadOrganizationDetails() {

        Organization org = [
            SELECT Name, Street, City, State, PostalCode, Country, Phone
            FROM Organization
            LIMIT 1
        ];

        companyName = org.Name;

        if (org.Street != null) {
            companyStreet = org.Street.replace('\n', '<br/>');
        }

        companyCity = org.City == null ? '' : org.City;
        companyState = org.State == null ? '' : org.State;
        companyPostalCode = org.PostalCode == null ? '' : org.PostalCode;
        companyCountry = org.Country == null ? '' : org.Country;

        if (org.Phone != null) {

            String digits = org.Phone.replaceAll('[^0-9]', '');

            if (digits.length() == 10) {

                companyPhone =
                    digits.substring(0,3) + '-' +
                    digits.substring(3,6) + '-' +
                    digits.substring(6,10);
            }
        }
    }

    // -------------------------------------------------------------------------
    private void loadClientDetails(String primaryAccountId) {

        List<Account> clients = [
            SELECT Id, Name, Address__Street__s,
                Address__City__s,
                Address__StateCode__s,
                Address__PostalCode__s                
            FROM Account
            WHERE Id = :primaryAccountId
            LIMIT 1
        ];

        if (clients.isEmpty()) {
            return;
        }

        Account client = clients[0];

        clientName = client.Name;
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

    // -------------------------------------------------------------------------
    public void prepareAddressLines() {

        addressLines = clientAddress.split('\n');
    }

    // -------------------------------------------------------------------------
    private static List<String> wrapText(String text, Integer maxLen) {

        List<String> lines = new List<String>();

        if (String.isBlank(text)) {
            return lines;
        }

        List<String> words = text.split(' ');
        String line = '';

        for (String word : words) {

            if ((line + ' ' + word).trim().length() <= maxLen) {
                line = (line == '' ? word : line + ' ' + word);
            } else {
                lines.add(line);
                line = word;
            }
        }

        if (!String.isBlank(line)) {
            lines.add(line);
        }

        return lines;
    }

    // -------------------------------------------------------------------------
    private static String formatDate(Date d) {

        return Datetime.newInstance(
            d,
            Time.newInstance(0,0,0,0)
        ).format('MM/dd/yyyy');
    }

    // -------------------------------------------------------------------------
    // @TestVisible
    // private void applyBillingRowSpan(List<BillingPDFUtility.CareDetailRow> rows) {

    //     if (rows == null || rows.isEmpty()) {
    //         return;
    //     }

    //     Map<String, Integer> billingCount = new Map<String, Integer>();

    //     for (BillingPDFUtility.CareDetailRow cd : rows) {

    //         if (!billingCount.containsKey(cd.billingName)) {
    //             billingCount.put(cd.billingName, 0);
    //         }

    //         billingCount.put(
    //             cd.billingName,
    //             billingCount.get(cd.billingName) + 1
    //         );
    //     }

    //     String currentBilling = null;

    //     for (BillingPDFUtility.CareDetailRow cd : rows) {

    //         if (currentBilling == null || cd.billingName != currentBilling) {

    //             cd.showBillingName = true;

    //             cd.billingRowSpan = billingCount.get(cd.billingName);

    //             currentBilling = cd.billingName;

    //         } else {
    //             cd.showBillingName = false;
    //         }
    //     }
    // }
    @TestVisible
private void applyBillingRowSpan(List<BillingPDFUtility.CareDetailRow> rows) {

    if (rows == null || rows.isEmpty()) {
        return;
    }

    Map<String, Integer> billingCount = new Map<String, Integer>();
    Map<String, Integer> subjectCount = new Map<String, Integer>();

    for (BillingPDFUtility.CareDetailRow cd : rows) {

        billingCount.put(
            cd.billingName,
            (billingCount.get(cd.billingName) ?? 0) + 1
        );

        String subjectKey = cd.billingName + '|' + cd.billingLineItemName;

        subjectCount.put(
            subjectKey,
            (subjectCount.get(subjectKey) ?? 0) + 1
        );
    }

    String currentBilling = '';
    String currentSubjectKey = '';

    for (BillingPDFUtility.CareDetailRow cd : rows) {

        // Billable No
        cd.showBillingName = cd.billingName != currentBilling;

        if (cd.showBillingName) {
            cd.billingRowSpan = billingCount.get(cd.billingName);
            currentBilling = cd.billingName;
        }

        // Subject
        String subjectKey = cd.billingName + '|' + cd.billingLineItemName;

        cd.showBliName = subjectKey != currentSubjectKey;

        if (cd.showBliName) {
            cd.bliRowSpan = subjectCount.get(subjectKey);
            currentSubjectKey = subjectKey;
        }
    }
}

    // -------------------------------------------------------------------------
    private Decimal calculateTotal(List<BillingPDFUtility.CareDetailRow> rows) {

        Decimal total = 0;

        if (rows == null) {
            return 0;
        }

        for (BillingPDFUtility.CareDetailRow cd : rows) {

            if (cd.amount != null && cd.amount.startsWith('$')) {

                total += Decimal.valueOf(
                    cd.amount.replace('$','').replace(',','')
                );
            }
        }

        return total.setScale(2);
    }

    // -------------------------------------------------------------------------
    private void buildSummary(List<BillingPDFUtility.CareDetailRow> rows) {

        Map<String, InvoiceService.HourlySummaryRow> hourlyMap =
            new Map<String, InvoiceService.HourlySummaryRow>();

        for (BillingPDFUtility.CareDetailRow cd : rows) {

            // -------------------------------------------------------------
            // HOURLY
            // -------------------------------------------------------------
            // if (cd.rate != null && cd.rate.contains('/hr')) {

            //     // Decimal rateVal =
            //     //     Decimal.valueOf(cd.rate.replace('/hr',''));
            //     Decimal rateVal = Decimal.valueOf(
            //         cd.rate
            //             .replace('$', '')
            //             .replace('/hr', '')
            //             .replace(',', '')
            //     );

            //     Decimal hours = 0;

            //     if (cd.quantity != null && cd.quantity.contains('hrs')) {

            //         hours = Decimal.valueOf(
            //             cd.quantity.replace(' hrs','')
            //         );
            //     }

            //     Decimal amount = Decimal.valueOf(
            //         cd.amount.replace('$','').replace(',','')
            //     );

            //     if (!hourlyMap.containsKey(rateVal)) {
            //         hourlyMap.put(
            //             rateVal,
            //             new InvoiceService.HourlySummaryRow(rateVal)
            //         );
            //     }

            //     hourlyMap.get(rateVal).totalHours += hours;
            //     hourlyMap.get(rateVal).totalAmount += amount;

            //     totalHourlyCharges += amount;
            // }
            
            if (cd.rate != null) {

    Decimal amount = Decimal.valueOf(
        cd.amount.replace('$','').replace(',','')
    );

    if (cd.rate.contains('/hr')) {

        Decimal rateVal = Decimal.valueOf(
            cd.rate
                .replace('$', '')
                .replace('/hr', '')
                .replace(',', '')
        );

        Decimal hours = 0;

        if (cd.quantity != null && cd.quantity.contains('hrs')) {
            hours = Decimal.valueOf(
                cd.quantity.replace(' hrs', '')
            );
        }

        String key = 'HR_' + rateVal;

        if (!hourlyMap.containsKey(key)) {
            InvoiceService.HourlySummaryRow row =
                new InvoiceService.HourlySummaryRow(rateVal, false);
            row.isFlatAmount = false;
            hourlyMap.put(key, row);
        }

        hourlyMap.get(key).totalHours += hours;
        hourlyMap.get(key).totalAmount += amount;

        totalHourlyCharges += amount;

    } else {

        // Flat Amount
        String key = 'FLAT';

        if (!hourlyMap.containsKey(key)) {
            InvoiceService.HourlySummaryRow row =
                new InvoiceService.HourlySummaryRow(0, true);
            row.isFlatAmount = true;
            hourlyMap.put(key, row);
        }

        hourlyMap.get(key).totalAmount += amount;

        totalHourlyCharges += amount;
    }
}
            // -------------------------------------------------------------
            // MILEAGE
            // -------------------------------------------------------------
            else if (
                cd.description != null &&
                cd.description.toLowerCase().contains('mileage')
            ) {

                totalMileageCharges += Decimal.valueOf(
                    cd.amount.replace('$','').replace(',','')
                );
            }

            // -------------------------------------------------------------
            // EXPENSE
            // -------------------------------------------------------------
            else if (
                cd.description != null &&
                cd.description.toLowerCase().contains('expense')
            ) {

                totalExpenseCharges += Decimal.valueOf(
                    cd.amount.replace('$','').replace(',','')
                );
            }
        }

        // hourlySummaryRows.addAll(hourlyMap.values());
        List<InvoiceService.HourlySummaryRow> hourlyRows = new List<InvoiceService.HourlySummaryRow>();
InvoiceService.HourlySummaryRow flatRow;

for (InvoiceService.HourlySummaryRow row : hourlyMap.values()) {
    if (row.isFlatAmount) {
        flatRow = row;
    } else {
        hourlyRows.add(row);
    }
}

hourlySummaryRows.addAll(hourlyRows);

if (flatRow != null) {
    hourlySummaryRows.add(flatRow);
}

        totalCharges =
            totalHourlyCharges +
            totalMileageCharges +
            totalExpenseCharges;

        amountDue = 0;
    }

    private String loadInvoiceDate(String invoiceNoParam) {
        if (String.isBlank(invoiceNoParam)) {
            return formatDate(Date.today());
        }
        List<Invoice__c> invoices = [
            SELECT Invoice_Date__c
            FROM   Invoice__c
            WHERE  Name = :invoiceNoParam
            LIMIT  1
        ];
        if (!invoices.isEmpty() && invoices[0].Invoice_Date__c != null) {
            return formatDate(invoices[0].Invoice_Date__c);
        }
        return formatDate(Date.today());
    }

    // -------------------------------------------------------------------------
    public class PatientSection {

        public String patientName { get; set; }
        public String patientLabel { get; set; }
        public String roleName { get; set; }

        public List<BillingPDFUtility.CareDetailRow> rows { get; set; }

        public Decimal patientTotal { get; set; }
    }
}