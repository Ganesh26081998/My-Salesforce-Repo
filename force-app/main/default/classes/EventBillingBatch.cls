/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : EventBillingBatch
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : It automatically converts completed calendar appointments into 
                calculated financial Billing records so they are ready to be synced to QuickBooks.
----------------------------------------------------------------------------
*/

public class EventBillingBatch
implements Database.Batchable<SObject>, Database.Stateful {

    private List<Id> processedEventIds =
        new List<Id>();

    //  ADDED: Date filter fields
    private Date startDate;
    private Date endDate;

    //  ADDED: No-arg constructor (keeps backward compatibility)
    public EventBillingBatch() {
        this.startDate = null;
        this.endDate = null;
    }

    //  ADDED: Date constructor used by EventBillingQueueable
    public EventBillingBatch(Date startDate, Date endDate) {
        this.startDate = startDate;
        this.endDate = endDate;
    }

    // -------------------------------------------------------------------------
    // START —  CHANGED: Dynamic query with optional date filters
    // -------------------------------------------------------------------------
    public Database.QueryLocator start(
        Database.BatchableContext bc
    ) {

        String query =
            'SELECT ' +
                'Id, ' +
                'WhatId, ' +
                'OwnerId, ' +
                'Status__c, ' +
                'Is_Billable_Produced__c, ' +
                'Location__c, ' +
                'IsAllDayEvent, ' +
                'CreatedDate, ' +
                'StartDateTime, ' +
                'EndDateTime, ' +
                'ActivityDate, ' +
                'IsChild, ' +

                'Client_Rate_Amount__c, ' +
                'Client_Billing_Details__c, ' +

                'Caregiver_Rate_Amount__c, ' +
                'Caregiver_Billing_Details__c, ' +

                'Client_Rate__c, ' +
                'Caregiver_Rate__c, ' +

                'Mileage_Amount__c, ' +
                'Mileage_Amount_2__c, ' +
                'Mileage_Amount_3__c, ' +
                'Mileage_Amount_4__c, ' +
                'Mileage_Amount_5__c, ' +

                'Mileage_Description__c, ' +
                'Mileage_Description_2__c, ' +
                'Mileage_Description_3__c, ' +
                'Mileage_Description_4__c, ' +
                'Mileage_Description_5__c, ' +

                'Expense_Amount__c, ' +
                'Expense_Amount_2__c, ' +
                'Expense_Amount_3__c, ' +
                'Expense_Amount_4__c, ' +
                'Expense_Amount_5__c, ' +

                'Expense_Description__c, ' +
                'Expense_Description_2__c, ' +
                'Expense_Description_3__c, ' +
                'Expense_Description_4__c, ' +
                'Expense_Description_5__c ' +

            'FROM Event ' +
            'WHERE Status__c = \'Completed\' ' +
            'AND IsChild = false ' + 
            'AND Is_Billable_Produced__c = false';

        //  ADDED: Apply date filters only when provided
        if (startDate != null) {
            query += ' AND DAY_ONLY(StartDateTime) >= :startDate';
        }

        if (endDate != null) {
            query += ' AND DAY_ONLY(EndDateTime) <= :endDate';
        }

        return Database.getQueryLocator(query);
    }

    // -------------------------------------------------------------------------
    // EXECUTE — NO CHANGES
    // -------------------------------------------------------------------------
    public void execute(
        Database.BatchableContext bc,
        List<Event> scope
    ) {

        Savepoint sp = Database.setSavepoint();

        try {

            List<Billing__c> billings =
                new List<Billing__c>();

            Map<Id, Event> eventMap =
                new Map<Id, Event>();

            Map<Id, Billing__c> eventToBillingMap =
                new Map<Id, Billing__c>();

            // -----------------------------------------------------------------
            // CREATE BILLINGS
            // -----------------------------------------------------------------
            for (Event ev : scope) {

                // Only Account-related events
                if (
                    ev.WhatId == null ||
                    ev.WhatId.getSObjectType() !=
                    Account.SObjectType
                ) {
                    continue;
                }

                // Skip invalid dates
                if (
                    ev.StartDateTime == null ||
                    ev.EndDateTime == null
                ) {
                    continue;
                }

                Decimal totalMileage =
                    getTotalMileage(ev);

                Decimal totalExpense =
                    getTotalExpense(ev);

                // Nothing billable
                if (
                    (ev.Client_Rate_Amount__c == null ||
                     ev.Client_Rate_Amount__c == 0) &&

                    (ev.Caregiver_Rate_Amount__c == null ||
                     ev.Caregiver_Rate_Amount__c == 0) &&

                    totalMileage == 0 &&
                    totalExpense == 0
                ) {
                    continue;
                }

                Datetime startDT;
                Datetime endDT;

                // -------------------------------------------------------------
                // ALL DAY EVENT
                // -------------------------------------------------------------
                if (ev.IsAllDayEvent) {

                    Date baseDate =
                        // ev.StartDateTime.date();
                        ev.ActivityDate;

                    startDT = Datetime.newInstance(
                        baseDate,
                        Time.newInstance(0, 0, 0, 0)
                    );

                    endDT = Datetime.newInstance(
                        baseDate,
                        Time.newInstance(23, 59, 59, 0)
                    );

                } else {

                    startDT = ev.StartDateTime;
                    endDT = ev.EndDateTime;
                }

                Billing__c bill =
                    new Billing__c(
                        Client__c = ev.WhatId,

                        Invoice_Date__c = Date.today(),

                        Invoice_Period_Start_Date__c =
                            startDT.date(),

                        Invoice_Period_End_Date__c =
                            endDT.date(),

                        Care_From_Date__c =
                            startDT.date(),

                        Care_To_Date__c =
                            endDT.date(),

                        Paid_Status__c = 'Paid',

                        Amount__c = 0,

                        Event_Date__c =
                            startDT.date(),

                        Event_Assignee__c =
                            ev.OwnerId,

                        Event_Start_Date_Time__c =
                            startDT,

                        Event_End_Date_Time__c =
                            endDT,

                        Location_g__c =
                            ev.Location__c,

                        Care_Manager_Rate__c =
                            ev.Caregiver_Billing_Details__c                                
                    );

                billings.add(bill);

                eventMap.put(
                    ev.Id,
                    ev
                );

                eventToBillingMap.put(
                    ev.Id,
                    bill
                );
            }

            if (billings.isEmpty()) {
                return;
            }

            Database.insert(
                billings,
                false
            );

            // -----------------------------------------------------------------
            // CREATE LINE ITEMS
            // -----------------------------------------------------------------
            List<Billing_Line_Item__c> lineItems =
                BillingLineItemHelper.createLineItems(
                    eventToBillingMap,
                    eventMap
                );

            if (!lineItems.isEmpty()) {

                Database.insert(
                    lineItems,
                    false
                );
            }

            // -----------------------------------------------------------------
            // CALCULATE BILLING TOTALS
            // -----------------------------------------------------------------
            Map<Id, Decimal> billingTotals =
                new Map<Id, Decimal>();

            for (AggregateResult ar : [

                SELECT
                    Invoice__c invoiceId,
                    SUM(Amount__c) totalAmount

                FROM Billing_Line_Item__c

                WHERE Invoice__c IN :billings
                AND Type__c != 'Caregiver Billable'

                GROUP BY Invoice__c
            ]) {

                billingTotals.put(
                    (Id) ar.get('invoiceId'),
                    (Decimal) ar.get('totalAmount')
                );
            }

            List<Billing__c> billsToUpdate =
                new List<Billing__c>();

            for (Id billId : billingTotals.keySet()) {

                billsToUpdate.add(
                    new Billing__c(
                        Id = billId,
                        Amount__c =
                            billingTotals.get(billId)
                    )
                );
            }

            if (!billsToUpdate.isEmpty()) {

                Database.update(
                    billsToUpdate,
                    false
                );
            }

            // -----------------------------------------------------------------
            // UPDATE EVENTS
            // -----------------------------------------------------------------
            List<Event> eventsToUpdate =
                new List<Event>();

            for (Id eventId :
                eventToBillingMap.keySet()) {

                eventsToUpdate.add(
                    new Event(
                        Id = eventId,

                        Billing__c =
                            eventToBillingMap.get(eventId).Id,

                        Is_Billable_Produced__c = true
                    )
                );

                processedEventIds.add(eventId);
            }

            if (!eventsToUpdate.isEmpty()) {

                Database.update(
                    eventsToUpdate,
                    false
                );
            }

        } catch (Exception ex) {

            Database.rollback(sp);

            System.debug(
                LoggingLevel.ERROR,
                'EventBillingBatch Error: ' +
                ex.getMessage()
            );
        }
    }

    // -------------------------------------------------------------------------
    // FINISH — NO CHANGES
    // -------------------------------------------------------------------------
    public void finish(
        Database.BatchableContext bc
    ) {

        System.debug(
            LoggingLevel.INFO,
            'Processed Event Count: ' +
            processedEventIds.size()
        );
    }

    // -------------------------------------------------------------------------
    // TOTAL MILEAGE — NO CHANGES
    // -------------------------------------------------------------------------
    private static Decimal getTotalMileage(
        Event ev
    ) {

        Decimal total = 0;

        total += ev.Mileage_Amount__c != null
            ? ev.Mileage_Amount__c
            : 0;

        total += ev.Mileage_Amount_2__c != null
            ? ev.Mileage_Amount_2__c
            : 0;

        total += ev.Mileage_Amount_3__c != null
            ? ev.Mileage_Amount_3__c
            : 0;

        total += ev.Mileage_Amount_4__c != null
            ? ev.Mileage_Amount_4__c
            : 0;

        total += ev.Mileage_Amount_5__c != null
            ? ev.Mileage_Amount_5__c
            : 0;

        return total;
    }

    // -------------------------------------------------------------------------
    // TOTAL EXPENSE — NO CHANGES
    // -------------------------------------------------------------------------
    private static Decimal getTotalExpense(
        Event ev
    ) {

        Decimal total = 0;

        total += ev.Expense_Amount__c != null
            ? ev.Expense_Amount__c
            : 0;

        total += ev.Expense_Amount_2__c != null
            ? ev.Expense_Amount_2__c
            : 0;

        total += ev.Expense_Amount_3__c != null
            ? ev.Expense_Amount_3__c
            : 0;

        total += ev.Expense_Amount_4__c != null
            ? ev.Expense_Amount_4__c
            : 0;

        total += ev.Expense_Amount_5__c != null
            ? ev.Expense_Amount_5__c
            : 0;

        return total;
    }
}