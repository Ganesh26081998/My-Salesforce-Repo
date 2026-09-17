/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : BillingLineItemHelper
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : It takes the specific details from a calendar appointment 
                (like time worked, mileage, and expenses) and automatically
                generates the individual child charge records (Line Items) that make up the final invoice.
----------------------------------------------------------------------------
*/

public class BillingLineItemHelper {

    public static List<Billing_Line_Item__c> createLineItems(
        Map<Id, Billing__c> eventToBillingMap,
        Map<Id, Event> eventMap
    ) {
        
        // Removed the RecordType SOQL query and rtMap entirely.

        List<Billing_Line_Item__c> items = new List<Billing_Line_Item__c>();

        for (Id eventId : eventToBillingMap.keySet()) {

            Event ev = eventMap.get(eventId);
            Billing__c bill = eventToBillingMap.get(eventId);
            // Date serviceDate = ev.StartDateTime.date();
            Date serviceDate = ev.IsAllDayEvent
                ? ev.ActivityDate
                : ev.StartDateTime.date();

            Decimal quantity;

            if (ev.IsAllDayEvent) {
                // Treat an all-day event as 24 hours.
                // If your business wants 8 billable hours instead, change 24 to 8.
                quantity = 24;
            } else {
                quantity = ((Decimal)(ev.EndDateTime.getTime() - ev.StartDateTime.getTime())
                    / (1000 * 60 * 60)).setScale(2);
            }

            Decimal crrate = ev.Client_Rate_Amount__c;

            Decimal cgrate = ev.Caregiver_Rate_Amount__c;

            /* CLIENT */
            if (ev.Client_Rate_Amount__c != null && ev.Client_Rate_Amount__c > 0) {
                if (ev.Client_Rate__c == 'Hourly' || ev.Client_Rate__c == 'Not Payable') {
                    items.add(new Billing_Line_Item__c(
                        Invoice__c = bill.Id,
                        Type__c = 'Client Billable', // Swapped RecordTypeId for Picklist
                        Description__c = 'Client Service Charges',
                        Service_Date__c = serviceDate,
                        Client_Rate_Amount__c = ev.Client_Rate_Amount__c,
                        Client_Billing_Details__c = ev.Client_Billing_Details__c,
                        Amount__c = quantity * crrate,
                        Quantity__c = quantity,
                        Rate__c = crrate
                    ));
                }
                else if (ev.Client_Rate__c == 'Flat Amount') {
                    items.add(new Billing_Line_Item__c(
                        Invoice__c = bill.Id,
                        Type__c = 'Client Billable', // Swapped RecordTypeId for Picklist
                        Description__c = 'Client Service Charges',
                        Service_Date__c = serviceDate,
                        Client_Rate_Amount__c = ev.Client_Rate_Amount__c,
                        Client_Billing_Details__c = ev.Client_Billing_Details__c,
                        Amount__c = crrate,
                        Quantity__c = 1,
                        Rate__c = crrate
                    ));
                }

                
            }

            /* CAREGIVER */
            if (ev.Caregiver_Rate_Amount__c != null && ev.Caregiver_Rate_Amount__c > 0) {
                 if (ev.Caregiver_Rate__c == 'Hourly' || ev.Caregiver_Rate__c == 'Not Payable') {
                    items.add(new Billing_Line_Item__c(
                        Invoice__c = bill.Id,
                        Type__c = 'Caregiver Billable', // Swapped RecordTypeId for Picklist
                        Description__c = 'Care Manager Pay',
                        Service_Date__c = serviceDate,
                        Caregiver_Rate_Amount__c = ev.Caregiver_Rate_Amount__c,
                        Caregiver_Billing_Details__c = ev.Caregiver_Billing_Details__c,
                        Amount__c = quantity * cgrate,
                        Quantity__c = quantity,
                        Rate__c = cgrate
                    ));
                }
                else if (ev.Caregiver_Rate__c == 'Flat Amount') {
                    items.add(new Billing_Line_Item__c(
                        Invoice__c = bill.Id,
                        Type__c = 'Caregiver Billable', // Swapped RecordTypeId for Picklist
                        Description__c = 'Care Manager Pay',
                        Service_Date__c = serviceDate,
                        Caregiver_Rate_Amount__c = ev.Caregiver_Rate_Amount__c,
                        Caregiver_Billing_Details__c = ev.Caregiver_Billing_Details__c,
                        Amount__c = cgrate,
                        Quantity__c = 1,
                        Rate__c = cgrate
                    ));
                 }
            }
           

            /* MILEAGE - Create Separate Line Items */

            List<Decimal> mileageAmounts = new List<Decimal>{
                ev.Mileage_Amount__c,
                ev.Mileage_Amount_2__c,
                ev.Mileage_Amount_3__c,
                ev.Mileage_Amount_4__c,
                ev.Mileage_Amount_5__c
            };

            List<String> mileageDescriptions = new List<String>{
                ev.Mileage_Description__c,
                ev.Mileage_Description_2__c,
                ev.Mileage_Description_3__c,
                ev.Mileage_Description_4__c,
                ev.Mileage_Description_5__c
            };

            for (Integer i = 0; i < mileageAmounts.size(); i++) {
                
                if (mileageAmounts[i] != null && mileageAmounts[i] > 0) {
                    
                    items.add(new Billing_Line_Item__c(
                        Invoice__c = bill.Id,
                        Type__c = 'Mileage',
                        Mileage_Index__c = i + 1,
                        Mileage_Description__c = mileageDescriptions[i],
                        Description__c = mileageDescriptions[i],
                        Service_Date__c = serviceDate,
                        Amount__c = mileageAmounts[i],
                        Millage_Amount__c = mileageAmounts[i],
                        Quantity__c = 1,
                        Rate__c = mileageAmounts[i]
                    ));
                }
            }

           

            /* EXPENSE - Create Separate Line Items */

            List<Decimal> expenseAmounts = new List<Decimal>{
                ev.Expense_Amount__c,
                ev.Expense_Amount_2__c,
                ev.Expense_Amount_3__c,
                ev.Expense_Amount_4__c,
                ev.Expense_Amount_5__c
            };

            List<String> expenseDescriptions = new List<String>{
                ev.Expense_Description__c,
                ev.Expense_Description_2__c,
                ev.Expense_Description_3__c,
                ev.Expense_Description_4__c,
                ev.Expense_Description_5__c
            };

            for (Integer i = 0; i < expenseAmounts.size(); i++) {
                
                if (expenseAmounts[i] != null && expenseAmounts[i] != 0) {
                    
                    items.add(new Billing_Line_Item__c(
                        Invoice__c = bill.Id,
                        Type__c = 'Expense/Credit',
                        Expense_Index__c = i + 1,
                        Description__c = expenseDescriptions[i],
                        Expense_Description__c =  expenseDescriptions[i],
                        Service_Date__c = serviceDate,
                        Amount__c = expenseAmounts[i],
                        Expense_Amount__c = expenseAmounts[i],
                        Quantity__c = 1,
                        Rate__c = expenseAmounts[i]
                    ));
                }
            }

        }        

        return items;
    }
}