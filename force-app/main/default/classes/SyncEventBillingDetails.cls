public with sharing class SyncEventBillingDetails {

    @AuraEnabled(cacheable=true)
    public static Boolean isBillingSynced(Id eventId) {
        if (eventId == null) {
            return true; 
        }

        Event ev = [
            SELECT Billing__r.Is_Synced__c
            FROM Event
            WHERE Id = :eventId
            LIMIT 1
        ];

        return ev.Billing__r != null && ev.Billing__r.Is_Synced__c;
    }

    private static Decimal safeSum(List<Decimal> values) {
        Decimal total = 0;
        for (Decimal d : values) {
            if (d != null) {
                total += d;
            }
        }
        return total;
    }

    private static Decimal safeValue(Decimal value) {
        return value != null ? value : 0;
    }

    @AuraEnabled
    public static void updateBillingLineItems(Id eventId) {

        if (eventId == null) {
            throw new AuraHandledException('Event Id is required.');
        }

        
        List<String> errorMessages = new List<String>();

        Event ev = [
            SELECT Id,
                   Billing__c,
                   Billing__r.Is_Synced__c,
                   StartDateTime,
                   Client_Rate_Amount__c, Client_Billing_Details__c,
                   Caregiver_Rate_Amount__c, Caregiver_Billing_Details__c,
                   Mileage_Amount__c, Mileage_Amount_2__c, Mileage_Amount_3__c,
                   Mileage_Amount_4__c, Mileage_Amount_5__c,
                   Mileage_Description__c, Mileage_Description_2__c,
                   Mileage_Description_3__c, Mileage_Description_4__c, Mileage_Description_5__c,
                   Expense_Amount__c, Expense_Amount_2__c, Expense_Amount_3__c,
                    Expense_Amount_4__c, Expense_Amount_5__c,
                   Expense_Description__c, Expense_Description_2__c,
                   Expense_Description_3__c, Expense_Description_4__c, Expense_Description_5__c,
                   Location__c
            FROM Event
            WHERE Id = :eventId
            LIMIT 1
        ];

        String location = ev.Location__c;
        Date serviceDate = ev.StartDateTime != null ? ev.StartDateTime.date() : null;

        if (ev.Billing__r != null && ev.Billing__r.Is_Synced__c) {
            throw new AuraHandledException(
                'Billing is already synced to QuickBooks. Event cannot be re-synced.'
            );
        }

        if (ev.Billing__c == null) {
            throw new AuraHandledException('No Billing record is linked to this Event.');
        }

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

        List<Billing_Line_Item__c> items = [
            SELECT Id, RecordTypeId, Invoice__c, Type__c,
                   Expense_Index__c, Mileage_Index__c,
                   Expense_Amount__c, Millage_Amount__c,
                   Mileage_Description__c, Expense_Description__c,
                   Client_Billing_Details__c, Client_Rate_Amount__c,
                   Caregiver_Billing_Details__c, Caregiver_Rate_Amount__c,
                   Amount__c, Rate__c, Description__c
            FROM Billing_Line_Item__c
            WHERE Invoice__c = :ev.Billing__c
        ];

        Map<Integer, Billing_Line_Item__c> existingMileageByIndex = new Map<Integer, Billing_Line_Item__c>();
        Map<Integer, Billing_Line_Item__c> existingExpenseByIndex = new Map<Integer, Billing_Line_Item__c>();
        List<Billing_Line_Item__c> itemsToInsert = new List<Billing_Line_Item__c>();

        Decimal bliTotalAmount = 0;

        for (Billing_Line_Item__c bli : items) {

            if (bli.Type__c == 'Client Billable') {
                bli.Client_Billing_Details__c = ev.Client_Billing_Details__c;
                bli.Client_Rate_Amount__c = ev.Client_Rate_Amount__c;
                bli.Amount__c = ev.Client_Rate_Amount__c;
                bli.Rate__c = ev.Client_Rate_Amount__c;
                bliTotalAmount += safeValue(ev.Client_Rate_Amount__c);

            } else if (bli.Type__c == 'Caregiver Billable') {
                bli.Caregiver_Billing_Details__c = ev.Caregiver_Billing_Details__c;
                bli.Caregiver_Rate_Amount__c = ev.Caregiver_Rate_Amount__c;
                bli.Amount__c = ev.Caregiver_Rate_Amount__c;
                bli.Rate__c = ev.Caregiver_Rate_Amount__c;
                bliTotalAmount += safeValue(ev.Caregiver_Rate_Amount__c);

            } else if (bli.Type__c == 'Mileage') {

                Integer index = bli.Mileage_Index__c != null
                    ? Integer.valueOf(bli.Mileage_Index__c) - 1
                    : -1;

                if (index >= 0 && index < mileageAmounts.size()) {

                    Decimal amt = mileageAmounts[index];
                    String mdesc = mileageDescriptions[index];

                    if (amt != null && amt != 0 && String.isBlank(mdesc)) {
                        errorMessages.add('Mileage Description required (Descrption  ' + (index+1) + ')');
                    }


                    existingMileageByIndex.put(index + 1, bli);
                    bli.Description__c = mileageDescriptions[index];
                    bli.Mileage_Description__c = mileageDescriptions[index];
                    bli.Amount__c = safeValue(mileageAmounts[index]);
                    bli.Rate__c = safeValue(mileageAmounts[index]);
                    bli.Millage_Amount__c = safeValue(mileageAmounts[index]);
                    bliTotalAmount += safeValue(mileageAmounts[index]);
                }

            } else if (bli.Type__c == 'Expense/Credit') {

                Integer index = bli.Expense_Index__c != null
                    ? Integer.valueOf(bli.Expense_Index__c) - 1
                    : -1;

                if (index >= 0 && index < expenseAmounts.size()) {

                    Decimal amt = expenseAmounts[index];
                    String lesc = expenseDescriptions[index];

                    if (amt != null && amt != 0 && String.isBlank(lesc)) {
                        errorMessages.add('Expense Description required (Description  ' + (index+1) + ')');
                    }

                    if ((amt == null || amt == 0) && String.isBlank(lesc)) {
                        continue;
                    }

                    existingExpenseByIndex.put(index + 1, bli);

                    if (!String.isBlank(lesc)) {
                        bli.Description__c = lesc;
                        bli.Expense_Description__c = lesc;
                    }

                    bli.Amount__c = safeValue(amt);
                    bli.Rate__c = safeValue(amt);
                    bli.Expense_Amount__c = safeValue(amt);

                    bliTotalAmount += safeValue(amt);
                }
            }
        }

        for (Integer i = 0; i < mileageAmounts.size(); i++) {

            Decimal amt = mileageAmounts[i];
            String mdesc = mileageDescriptions[i];

            if (amt != null && amt != 0 && String.isBlank(mdesc)) {
                errorMessages.add('Mileage Description required (Descrption  ' + (i+1) + ')');
            }

            if ((amt == null || amt == 0) && String.isBlank(mdesc)) {
                continue;
            }


         if (amt != null && !existingMileageByIndex.containsKey(i + 1)) {
        Billing_Line_Item__c newMileageItem = new Billing_Line_Item__c();
        newMileageItem.Invoice__c = ev.Billing__c;
        newMileageItem.Type__c = 'Mileage';
        newMileageItem.Mileage_Index__c = i + 1;
        newMileageItem.Description__c = mdesc;
        newMileageItem.Mileage_Description__c = mdesc;
        newMileageItem.Amount__c = amt;
        newMileageItem.Rate__c = amt;
        newMileageItem.Millage_Amount__c = amt;

        newMileageItem.Service_Date__c = serviceDate;
        newMileageItem.Quantity__c = 1;

        itemsToInsert.add(newMileageItem);
        bliTotalAmount += amt;
    }
}

        for (Integer i = 0; i < expenseAmounts.size(); i++) {

            Decimal amt = expenseAmounts[i];
            String lesc = expenseDescriptions[i];

            if (amt != null && amt != 0 && String.isBlank(lesc)) {
                errorMessages.add('Expense description required (Description  ' + (i+1) + ')');
            }

            if ((amt == null || amt == 0) && String.isBlank(lesc)) {
                continue;
            }

            if (amt != null && !existingExpenseByIndex.containsKey(i + 1)) {
                Billing_Line_Item__c newExpenseItem = new Billing_Line_Item__c();
                newExpenseItem.Invoice__c = ev.Billing__c;
                newExpenseItem.Type__c = 'Expense/Credit';
                newExpenseItem.Expense_Index__c = i + 1;
                newExpenseItem.Description__c = lesc;
                newExpenseItem.Expense_Description__c = lesc;
                newExpenseItem.Amount__c = amt;
                newExpenseItem.Rate__c = amt;
                newExpenseItem.Expense_Amount__c = amt;
                newExpenseItem.Service_Date__c = serviceDate;
                newExpenseItem.Quantity__c = 1;

                itemsToInsert.add(newExpenseItem);
                bliTotalAmount += amt;
            }
        }

        Billing__c billing = [
            SELECT Id, Amount__c, Location_g__c
            FROM Billing__c
            WHERE Id = :ev.Billing__c
            LIMIT 1
        ];

        if (billing.Location_g__c != null && location != null 
            && billing.Location_g__c != location) {
            errorMessages.add(
                'Location mismatch: Event (' + location + ') vs Billable (' + billing.Location_g__c + ')'
            );
        }

        // FINAL THROW (fixes unexpected error)
        if (!errorMessages.isEmpty()) {
            throw new AuraHandledException(String.join(errorMessages, '\n'));
        }

        if (!items.isEmpty()) update items;
        if (!itemsToInsert.isEmpty()) insert itemsToInsert;

        if (bliTotalAmount != 0) {
            billing.Amount__c = bliTotalAmount;
        }
        billing.Location_g__c = location;

        update billing;
    }
}