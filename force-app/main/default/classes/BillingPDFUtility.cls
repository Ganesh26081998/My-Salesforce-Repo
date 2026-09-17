/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : BillingPDFUtility
CreatedOn      : 30-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This utility class is used to prepare Billing PDF detail rows
                 for client invoices by fetching billing events, billing line
                 items, calculating hours, rates, amounts, and formatting
                 service descriptions for PDF generation.
----------------------------------------------------------------------------
*/
public with sharing class BillingPDFUtility {

    /* ===============================
       WRAPPER CLASS
    =============================== */
    public class CareDetailRow {

        public String billingName {get;set;}
        public String billingLineItemName {get;set;}
        public Date serviceDate {get;set;}
        public String quantity {get;set;}
        public String rate {get;set;}
        public String amount {get;set;}
        public String description {get;set;}

        public Boolean isHourly {get;set;}
        public Boolean isExpenseOrMileage {get;set;}

        public Integer billingRowSpan {get;set;}
        public Integer bliRowSpan {get;set;}

        public Boolean showBillingName {get;set;}
        public Boolean showBliName {get;set;}

        public CareDetailRow(
            String billingName,
            String billingLineItemName,
            Date serviceDate,
            String quantity,
            String rate,
            String amount,
            String description,
            Boolean is_hourly,
            Boolean isExpOrMil,
            Integer billRowSpan,
            Integer bliRowSpan
        ) {
            this.billingName = billingName;
            this.billingLineItemName = billingLineItemName;
            this.serviceDate = serviceDate;
            this.quantity = quantity;
            this.rate = rate;
            this.amount = amount;
            this.description = description;

            this.isHourly = is_hourly;
            this.isExpenseOrMileage = isExpOrMil;

            this.billingRowSpan = billRowSpan;
            this.bliRowSpan = bliRowSpan;

            this.showBillingName = false;
            this.showBliName = false;
        }
    }


    /* ===============================
       MAIN METHOD
    =============================== */
    public static List<CareDetailRow> getCareDetailRows(
        Id accountId,
        Date fromDate,
        Date toDate
    ) {

        DateTime fromDateTime = DateTime.newInstance(fromDate, Time.newInstance(0,0,0,0));
        DateTime toDateTime   = DateTime.newInstance(toDate, Time.newInstance(23,59,59,0));

        Set<Id> billingIds = new Set<Id>();
        // Map<Id, Decimal> billingToHours = new Map<Id, Decimal>();
        Map<Id, Decimal> billingToDuration = new Map<Id, Decimal>();
        Map<Id, String> billingToRateType = new Map<Id, String>();

        Map<Id, Boolean> billingToIsAllDay = new Map<Id, Boolean>();
        Map<Id, String> billingToSubject = new Map<Id, String>();

        /* ===============================
           STEP 1: GET EVENTS
        =============================== */
        for (Event e : [
            SELECT Subject,
                   Billing__c,
                   StartDateTime,
                   EndDateTime,
                   IsAllDayEvent,
                   Client_Rate__c,
                   Billing__r.Event_Duration_Hours__c
            FROM Event
            WHERE AccountId = :accountId
            AND Billing__c != null
            AND Billing__r.Is_Synced__c = true
            //AND StartDateTime <= :toDateTime
            //AND EndDateTime   >= :fromDateTime
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

            if (e.Billing__c == null) continue;

            billingIds.add(e.Billing__c);

            if (!billingToDuration.containsKey(e.Billing__c)) {

                // Decimal hours =
                //     ((Decimal)(e.EndDateTime.getTime() - e.StartDateTime.getTime())
                //     / (1000 * 60 * 60)).setScale(2);

                // billingToHours.put(e.Billing__c, hours);
                billingToDuration.put(
                    e.Billing__c,
                    e.Billing__r.Event_Duration_Hours__c
                );

                billingToRateType.put(
                    e.Billing__c,
                    e.Client_Rate__c
                );

                billingToIsAllDay.put(
                    e.Billing__c,
                    e.IsAllDayEvent
                );

                billingToSubject.put(
                    e.Billing__c,
                    e.Subject
                );
            }
        }

        if (billingIds.isEmpty()) {
            return new List<CareDetailRow>();
        }

        /* ===============================
           STEP 2: GET BILLING LINE ITEMS
        =============================== */
        List<Billing_Line_Item__c> lineItems = [
            SELECT Name,
                   Invoice__c,
                   Invoice__r.Name,
                   Service_Date__c,
                   Type__c,
                   Client_Rate_Amount__c,
                   Caregiver_Rate_Amount__c,
                   Rate__c,
                   Quantity__c,
                   Amount__c,
                   Description__c,
                   Mileage_Description__c,
                   Expense_Description__c,
                   Invoice__r.Event_Start_Date_Time__c,
                   Invoice__r.Event_End_Date_Time__c,
                   Invoice__r.Event_Assignee__r.FirstName,
                   Invoice__r.Event_Assignee__r.LastName,
				   Invoice__r.Event_Duration_Hours__c 
            FROM Billing_Line_Item__c
            WHERE Invoice__c IN :billingIds
            AND Service_Date__c >= :fromDate
            AND Service_Date__c <= :toDate
            ORDER BY Service_Date__c ASC,
                Invoice__r.Event_Start_Date_Time__c ASC,
                Name ASC
        ];

        List<CareDetailRow> results = new List<CareDetailRow>();

        /* ===============================
           STEP 3: BUILD DETAIL ROWS
        =============================== */
        for (Billing_Line_Item__c bli : lineItems) {

            if (!billingToDuration.containsKey(bli.Invoice__c)) continue;

			Decimal duration = bli.Invoice__r.Event_Duration_Hours__c;

            String rateType = billingToRateType.get(bli.Invoice__c);

            String quantityText = rateType == 'Flat Amount'
                ? '1'
                : (duration != null ? duration + ' hrs' : '');

            // String rateText = rateType == 'Flat Amount'
            //     ? '$' + bli.Rate__c.setScale(2)
            //     : '$' + bli.Rate__c.setScale(2) + '/hr';

            String rateText;

if (bli.Rate__c != null) {
    rateText = rateType == 'Flat Amount'
        ? '$' + bli.Rate__c.setScale(2).format()
        : '$' + bli.Rate__c.setScale(2).format() + '/hr';
} else {
    rateText = rateType == 'Flat Amount'
        ? '$0.00'
        : '$0.00/hr';
}

            // String amountText = '$' + bli.Amount__c.setScale(2);
            Decimal amt = 0;

if (bli.Rate__c != null) {
    if (rateType == 'Flat Amount') {
        amt = bli.Rate__c;
    } else {
        amt = (duration != null ? duration : 0) * bli.Rate__c;
    }
}

String amountText = formatCurrency(amt);

			// String hoursStr = (duration != null)
			// ? duration + ' hrs'
			// : '';

			// String hoursStr = String.valueOf(bli.Invoice__r.Event_Duration_Hours__c) + ' hrs';

           DateTime start_date_time = bli.Invoice__r.Event_Start_Date_Time__c;
                DateTime end_date_time = bli.Invoice__r.Event_End_Date_Time__c;


                String startStr = '';
                String endStr = '';

                if (start_date_time != null) {
                    startStr = start_date_time.format('h:mm a')
                        .toLowerCase()
                        .replace(' am', 'am')
                        .replace(' pm', 'pm');
                }

                if (end_date_time != null) {
                    endStr = end_date_time.format('h:mm a')
                        .toLowerCase()
                        .replace(' am', 'am')
                        .replace(' pm', 'pm');
                }

                // String description =
                //     startStr +
                //     (startStr != '' && endStr != '' ? ' - ' : '') +
                //     endStr +
                //     (
                //         (bli != null &&
                //         bli.Invoice__r != null &&
                //         bli.Invoice__r.Event_Assignee__r != null)
                //         ?
                //         ' ' +
                //         (bli.Invoice__r.Event_Assignee__r.LastName != null 
                //         ? bli.Invoice__r.Event_Assignee__r.LastName : '') +                   
                //         (bli.Invoice__r.Event_Assignee__r.FirstName != null 
                //             ?  ', ' + bli.Invoice__r.Event_Assignee__r.FirstName : '')
                //         : ''
                //     );

                Boolean isAllDay = billingToIsAllDay.containsKey(bli.Invoice__c)
    ? billingToIsAllDay.get(bli.Invoice__c)
    : false;

String timeText;

if (isAllDay) {
    timeText = 'All Day';
} else {
    timeText =
        startStr +
        (startStr != '' && endStr != '' ? ' - ' : '') +
        endStr;
}

String description =
    timeText +
    (
        (bli != null &&
        bli.Invoice__r != null &&
        bli.Invoice__r.Event_Assignee__r != null)
        ?
        ' ' +
        (bli.Invoice__r.Event_Assignee__r.LastName != null
            ? bli.Invoice__r.Event_Assignee__r.LastName : '') +
        (bli.Invoice__r.Event_Assignee__r.FirstName != null
            ? ', ' + bli.Invoice__r.Event_Assignee__r.FirstName : '')
        : ''
    );


            if (bli.Type__c == 'Client Billable' && bli.Client_Rate_Amount__c != null) {

                results.add(new CareDetailRow(
                    bli.Invoice__r.Name,
                    billingToSubject.get(bli.Invoice__c),
                    bli.Service_Date__c,
                    quantityText,
                    rateText,
                    amountText,
                    description,
                    true,
                    false,
                    0,
                    0
                ));
            }            
            else if (bli.Type__c == 'Expense/Credit' ) {

                String expenseDesc = String.isBlank(bli.Expense_Description__c) ? '' : ' ' + bli.Expense_Description__c;

                results.add(new CareDetailRow(
                    bli.Invoice__r.Name,
                    billingToSubject.get(bli.Invoice__c),
                    bli.Service_Date__c,
                    '',
                    '',
                    // '$' + String.valueOf(bli.Amount__c),
                    formatCurrency(bli.Amount__c),
                    '- Expense:'+expenseDesc,
                    false,
                    true,
                    0,
                    0
                ));
            }
             else if ( bli.Type__c == 'Mileage') {

                String expenseDesc = String.isBlank(bli.Mileage_Description__c) ? '' : ' ' + bli.Mileage_Description__c;

                results.add(new CareDetailRow(
                    bli.Invoice__r.Name,
                    billingToSubject.get(bli.Invoice__c),
                    bli.Service_Date__c,
                    '',
                    '',
                    // '$' + String.valueOf(bli.Amount__c),
                    formatCurrency(bli.Amount__c),
                    '- Mileage:'+expenseDesc,
                    false,
                    true,
                    0,
                    0
                ));
            }
        }

        return results;
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