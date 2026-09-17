/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : ClientInvoiceController
CreatedOn      : 30-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This controller class is used to fetch client accounts for
                 bulk invoice generation based on billing data, date range,
                 location, client name, and invoice-related filters. It also
                 provides active location picklist values for UI filtering.
----------------------------------------------------------------------------
*/
public with sharing class ClientInvoiceController {

    @AuraEnabled(cacheable=true)
    public static List<String> getLocationPicklistValues() {
        try {
            List<String> picklistValues = new List<String>();

            Schema.DescribeFieldResult fieldResult =
                Account.Location_g__c.getDescribe();

            for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
                if (entry.isActive()) {
                    picklistValues.add(entry.getLabel());
                }
            }

            return picklistValues;

        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Error fetching location picklist values: ' + e.getMessage()
            );

            throw new AuraHandledException(
                'Unable to fetch location values.'
            );
        }
    }


    @AuraEnabled(cacheable=true)
    public static List<Account> getAccountsForBulkInvoice(
        Date fromDate,
        Date toDate,
        String location,
        String clientName,
        String primaryFilter,
        String sendInvoiceFilter
    ) {

        if (fromDate == null || toDate == null) {
            return new List<Account>();
        }

        Datetime fromDateTime =
            Datetime.newInstance(
                fromDate,
                Time.newInstance(0, 0, 0, 0)
            );

        Datetime toDateTime =
            Datetime.newInstance(
                toDate,
                Time.newInstance(23, 59, 59, 999)
            );

        /*
         * Get Prospect Record Type Id
         */
        Id prospectRecordTypeId =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Prospect')
                .getRecordTypeId();

        /*
         * Get Billing Ids and Account Ids from Events
         */
        Set<Id> billingIds = new Set<Id>();
        Set<Id> clientAccountIds = new Set<Id>();

        for (Event evt : [
            SELECT AccountId, Billing__c
            FROM Event
            WHERE AccountId != null
            AND Billing__c != null
            AND Billing__r.Is_Synced__c = true
            //AND StartDateTime <= :toDateTime
            //AND EndDateTime >= :fromDateTime
            AND (
    (
        IsAllDayEvent = true
        AND ActivityDate >= :fromDate
        AND ActivityDate <= :toDate
    )
    OR
    (
        IsAllDayEvent = false
        AND StartDateTime <= :toDateTime
        AND EndDateTime >= :fromDateTime
    )
)
        ]) {
            billingIds.add(evt.Billing__c);
            clientAccountIds.add(evt.AccountId);
        }

        if (billingIds.isEmpty() || clientAccountIds.isEmpty()) {
            return new List<Account>();
        }

        /*
         * Get only Accounts having Billing Line Items
         */
        Set<Id> accountsWithBillingData = new Set<Id>();

        for (Billing_Line_Item__c bli : [
            SELECT Invoice__r.Client__c
            FROM Billing_Line_Item__c
            WHERE Invoice__c IN :billingIds
            AND Invoice__r.Client__c IN :clientAccountIds
            AND Service_Date__c >= :fromDate
            AND Service_Date__c <= :toDate
        ]) {
            if (bli.Invoice__r.Client__c != null) {
                accountsWithBillingData.add(
                    bli.Invoice__r.Client__c
                );
            }
        }

        if (accountsWithBillingData.isEmpty()) {
            return new List<Account>();
        }

        /*
         * Dynamic SOQL only for optional filters
         */
        String query =
            'SELECT Id, Name, FirstName, LastName, Location_g__c, ' +
            'Is_Primary__c, ' +
            'Send_Invoice_to_Client__c ' +
            'FROM Account ' +
            'WHERE Id IN :accountsWithBillingData ' +
            'AND RecordTypeId = :prospectRecordTypeId';

        if (String.isNotBlank(location) && location != 'All') {
            query += ' AND Location_g__c = :location';
        }

        if (String.isNotBlank(clientName)) {
            String clientNameFilter = '%' + clientName + '%';
            query += ' AND Name LIKE :clientNameFilter';
        }

        if (primaryFilter == 'true') {
            query += ' AND Is_Primary__c = true';
        } else if (primaryFilter == 'false') {
            query += ' AND Is_Primary__c = false';
        }

        if (sendInvoiceFilter == 'true') {
            query += ' AND Send_Invoice_to_Client__c = true';
        } else if (sendInvoiceFilter == 'false') {
            query += ' AND Send_Invoice_to_Client__c = false';
        }
    
        query += ' ORDER BY LastName ASC, FirstName ASC';

        return Database.query(query);
    }

    @AuraEnabled(cacheable=true)
    public static Map<Id, Boolean> getInvoiceEmailStatus(
        List<Id> accountIds,
        Date fromDate,
        Date toDate
    ) {

        Map<Id, Boolean> result = new Map<Id, Boolean>();

        for (Invoice__c inv : [
            SELECT Client__c, Invoice_Emailed__c
            FROM Invoice__c
            WHERE Client__c IN :accountIds
            AND From_Date__c = :fromDate
            AND To_Date__c = :toDate
        ]) {
            result.put(inv.Client__c, inv.Invoice_Emailed__c);
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<ServicePeriodOption> getServicePeriods() {

        List<ServicePeriodOption> options = new List<ServicePeriodOption>();

        // First option
        options.add(new ServicePeriodOption('Custom', 'custom'));

        // ---------------------------------------
        // Billing Configuration
        // ---------------------------------------

        Date billingAnchor = Date.newInstance(2026, 6, 14);

        Date serviceAnchorStart = Date.newInstance(2026, 5, 31);
        Date serviceAnchorEnd   = Date.newInstance(2026, 6, 13);

        Integer cycleDays = 14;

        Date today = Date.today();

        Integer diffDays = billingAnchor.daysBetween(today);

        Integer cycleIndex;

        if (diffDays < 0) {
            cycleIndex = 0;
        } else {
            cycleIndex = diffDays / cycleDays;
        }

        Date periodStart = serviceAnchorStart.addDays(cycleIndex * cycleDays);
        Date periodEnd   = serviceAnchorEnd.addDays(cycleIndex * cycleDays);

        for (Integer i = 0; i < 13; i++) {

            options.add(
                new ServicePeriodOption(
                    formatLabel(periodStart) + ' – ' + formatLabel(periodEnd),
                    String.valueOf(periodStart) + '|' + String.valueOf(periodEnd)
                )
            );

            periodEnd = periodStart.addDays(-1);
            periodStart = periodEnd.addDays(-13);
        }

        return options;
    }

    private static String formatLabel(Date d) {

        return
            String.valueOf(d.month()).leftPad(2,'0') +
            '/' +
            String.valueOf(d.day()).leftPad(2,'0') +
            '/' +
            String.valueOf(d.year());
    }


    public class AccountPageWrapper {

        @AuraEnabled
        public List<Account> records;

        @AuraEnabled
        public Integer totalCount;

        public AccountPageWrapper(
            List<Account> records,
            Integer totalCount
        ) {
            this.records = records;
            this.totalCount = totalCount;
        }
    }

    public class ServicePeriodOption {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public ServicePeriodOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}