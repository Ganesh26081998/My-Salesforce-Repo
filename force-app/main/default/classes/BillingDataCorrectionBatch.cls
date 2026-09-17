public class BillingDataCorrectionBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private String subjectPrefix;
    private Integer updatedLineItemCount = 0;
    private Integer updatedBillingCount = 0;
    private Integer errorCount = 0;
        
    public BillingDataCorrectionBatch(String subjectPrefix) {
        this.subjectPrefix = subjectPrefix;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String subjectPattern = subjectPrefix + '%';
        return Database.getQueryLocator([
            SELECT
                Id,
                Billing__c,
                IsAllDayEvent,
                StartDateTime,
                EndDateTime,
                ActivityDate,
                Client_Rate_Amount__c,
                Caregiver_Rate_Amount__c
            FROM Event
            WHERE Is_Billable_Produced__c = true
            AND Billing__c != null
            AND Billing__r.Is_Historic_Data__c = FALSE
            and Client_Rate__c !='Not Payable' and Billing__r.Event_Duration_Hours__c !=1 and Billing__r.CreatedDate !=THIS_MONTH 
            
        ]);
    }

    public void execute(
        Database.BatchableContext bc,
        List<Event> scope
    ) {
        Map<Id, Event> billingToEventMap = new Map<Id, Event>();

        for (Event ev : scope) {
            billingToEventMap.put(ev.Billing__c, ev);
        }

        if (billingToEventMap.isEmpty()) {
            return;
        }

        List<Billing_Line_Item__c> lineItemsToUpdate =
            new List<Billing_Line_Item__c>();

        for (Billing_Line_Item__c bli : [
            SELECT
                Id,
                Invoice__c,
                Type__c,
                Quantity__c,
                Rate__c,
                Amount__c
            FROM Billing_Line_Item__c
            WHERE Invoice__c IN :billingToEventMap.keySet()
            AND Type__c IN ('Client Billable', 'Caregiver Billable')
        ]) {
            Event ev = billingToEventMap.get(bli.Invoice__c);

            if (ev == null) {
                continue;
            }

            Decimal quantity;

            if (ev.IsAllDayEvent) {
                quantity = 24;
            } else {
                quantity = (
                    (Decimal)(
                        ev.EndDateTime.getTime() -
                        ev.StartDateTime.getTime()
                    ) / (1000 * 60 * 60)
                ).setScale(2);
            }

            if (bli.Type__c == 'Client Billable') {
    Decimal rate = ev.Client_Rate_Amount__c;

    if (rate != null) {
        lineItemsToUpdate.add(
            new Billing_Line_Item__c(
                Id = bli.Id,
                Quantity__c = quantity,
                Rate__c = rate,
                Amount__c = quantity * rate
            )
        );
    }
} else if (bli.Type__c == 'Caregiver Billable') {
    Decimal rate = ev.Caregiver_Rate_Amount__c;

    if (rate != null) {
        lineItemsToUpdate.add(
            new Billing_Line_Item__c(
                Id = bli.Id,
                Quantity__c = quantity,
                Rate__c = rate,
                Amount__c = quantity * rate
            )
        );
    }
}
        }

        if (!lineItemsToUpdate.isEmpty()) {
            Database.SaveResult[] lineItemResults =
                Database.update(lineItemsToUpdate, false);

            for (Database.SaveResult result : lineItemResults) {
                if (result.isSuccess()) {
                    updatedLineItemCount++;
                } else {
                    errorCount++;

                    for (Database.Error err : result.getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'BLI Update Error: ' + err.getMessage()
                        );
                    }
                }
            }
        }

        Map<Id, Decimal> billingTotals = new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT
                Invoice__c billingId,
                SUM(Amount__c) totalAmount
            FROM Billing_Line_Item__c
            WHERE Invoice__c IN :billingToEventMap.keySet()
            AND Type__c != 'Caregiver Billable'
            GROUP BY Invoice__c
        ]) {
            billingTotals.put(
                (Id) ar.get('billingId'),
                (Decimal) ar.get('totalAmount')
            );
        }

        List<Billing__c> billingsToUpdate = new List<Billing__c>();

        for (Id billingId : billingToEventMap.keySet()) {
            billingsToUpdate.add(
                new Billing__c(
                    Id = billingId,
                    Amount__c = billingTotals.containsKey(billingId)
                        ? billingTotals.get(billingId)
                        : 0
                )
            );
        }

        if (!billingsToUpdate.isEmpty()) {
            Database.SaveResult[] billingResults =
                Database.update(billingsToUpdate, false);

            for (Database.SaveResult result : billingResults) {
                if (result.isSuccess()) {
                    updatedBillingCount++;
                } else {
                    errorCount++;

                    for (Database.Error err : result.getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'Billing Update Error: ' + err.getMessage()
                        );
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            LoggingLevel.INFO,
            'Updated BLI Count: ' + updatedLineItemCount
        );

        System.debug(
            LoggingLevel.INFO,
            'Updated Billing Count: ' + updatedBillingCount
        );

        System.debug(
            LoggingLevel.ERROR,
            'Error Count: ' + errorCount
        );
    }
}