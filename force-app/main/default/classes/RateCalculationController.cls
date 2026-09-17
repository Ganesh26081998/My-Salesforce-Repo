/*
----------------------------------------------------------------------------
Author        : Tushar Darode
Class Name    : RateCalculationController
CreatedOn     : 13-01-2026
LastModifiedOn: 15-05-2026
LastModifiedBy: Bhanu, Prasad, Ganesh
Description   : This controller is used to manage Event rate calculation 
                and billing-related operations. It supports retrieving 
                rate type picklist values, fetching caregiver location-
                based rates, validating and updating patient location, 
                saving Event billing/rate details, calculating mileage 
                reimbursement amounts based on custom settings, and 
                retrieving Event rate, mileage, and expense information 
                for UI display.
----------------------------------------------------------------------------
*/

public with sharing class RateCalculationController {

    public class RateWrapper {
        @AuraEnabled public String rateType;
        @AuraEnabled public Decimal rateAmount;

        public RateWrapper(String rateType, Decimal rateAmount) {
            this.rateType = rateType;
            this.rateAmount = rateAmount;
        }
    }

    // NEW METHOD: Update patient location after user confirms
@AuraEnabled
public static void updatePatientLocation(Id eventId, String selectedLocationName) {
    if (eventId == null || String.isBlank(selectedLocationName)) {
        throw new AuraHandledException('Invalid parameters');
    }
 
    Event evt = [
        SELECT WhatId
        FROM Event
        WHERE Id = :eventId
        LIMIT 1
    ];
 
    if (evt.WhatId == null || !evt.WhatId.getSObjectType().getDescribe().getName().equals('Account')) {
        throw new AuraHandledException('Event is not related to an Account');
    }
 
    Account acc = [
        SELECT Id, Location_g__c
        FROM Account
        WHERE Id = :evt.WhatId
        LIMIT 1
    ];
 
    acc.Location_g__c = selectedLocationName;
    update acc;
}

   /* @AuraEnabled(cacheable=true)
    public static List<String> getRateTypePicklistValues() {
        Schema.DescribeFieldResult dfr = Event.Client_Rate__c.getDescribe();
        List<String> values = new List<String>();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            //values.add(pe.getLabel());
            values.add(pe.getValue());
        }
        return values;
    }*/
    public class PicklistWrapper {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
}

@AuraEnabled(cacheable=true)
public static List<PicklistWrapper> getRateTypePicklistValues() {
    List<PicklistWrapper> listt = new List<PicklistWrapper>();

    for (Schema.PicklistEntry pe : Event.Client_Rate__c.getDescribe().getPicklistValues()) {
        PicklistWrapper w = new PicklistWrapper();
        w.label = pe.getLabel(); // UI label
        w.value = pe.getValue(); // API value (save this)
        listt.add(w);
    }
    return listt;
}



    @AuraEnabled(cacheable=true)
    public static List<String> getCareManagerRateTypePicklistValues() {
        Schema.DescribeFieldResult dfr = Event.Caregiver_Rate__c.getDescribe();
        List<String> values = new List<String>();

        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            values.add(pe.getLabel());
        }
        return values;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getEventOwnerInfo(Id eventId) {
        Event evt = [
            SELECT OwnerId,Caregiver_Rate__c,Client_Rate__c, Owner.Name,Billing__c,
            Is_Billable_Produced__c
            FROM Event
            WHERE Id = :eventId
            LIMIT 1
        ];

        // Boolean isBillingSynced =
        // evt.Billing__r != null &&
        // evt.Billing__r.Is_Synced__c;

        Boolean isBillingSynced = evt.Billing__c != null;
          //Ganesh code starts
         Boolean isBillableProduced =  evt.Is_Billable_Produced__c;
           //Ganesh code ends

        return new Map<String, Object>{
            'OwnerId' => evt.OwnerId,
            'OwnerName' => evt.Owner.Name,
            'ClientRate' => evt.Client_Rate__c,
            'CaregiverRate' => evt.Caregiver_Rate__c,
            'IsBillingSynced' => isBillingSynced,
              //Ganesh code starts
            'IsBillableProduced' => isBillableProduced
              //Ganesh code ends
        };
    }

    @AuraEnabled(cacheable=true)
public static List<User_City_Assignment__c> getUserLocations(Id eventId) {

    Event evt = [
        SELECT OwnerId
        FROM Event
        WHERE Id = :eventId
        LIMIT 1
    ];

    return [
        SELECT Id,
               Primary_Location__c,
               WellSpring_Location__r.Id,
               WellSpring_Location__r.City__c,
               WellSpring_Location__r.Name
        FROM User_City_Assignment__c
        WHERE User__c = :evt.OwnerId
        ORDER BY Primary_Location__c DESC
    ];
}

    @AuraEnabled(cacheable=true)
    public static List<Location_Rate__c> getRatesByLocation(Id locationId) {
        List<Location_Rate__c> rates = [
            SELECT Type_of_Rate__c, Rate_Amount__c,Rate_Type__c
            FROM Location_Rate__c
            WHERE Wellspring_Location__c = :locationId
        ];

        // if (rates.isEmpty()) {
        //     throw new AuraHandledException('Rates are not defined for the selected location.');
        // }
        return rates;
    }

   @AuraEnabled
public static void saveEventRates(Map<String, Object> fields) {
    System.debug('=== saveEventRates START ===');
    System.debug('Incoming fields map: ' + JSON.serializePretty(fields));

    if (!fields.containsKey('Id') || fields.get('Id') == null) {
        throw new AuraHandledException('Event Id is required');
    }

    Event evt = new Event();
    evt.Id = (Id) fields.get('Id');
    System.debug('Event Id to update: ' + evt.Id);

    /* ================= LOCATION ================= */
    if (fields.containsKey('Location__c') && fields.get('Location__c') != null) {
        String locationValue = String.valueOf(fields.get('Location__c'));

        Boolean isId = locationValue.length() >= 15 &&
            Pattern.matches('^[a-zA-Z0-9]{15,18}$', locationValue);

        if (isId) {
            try {
                Location__c loc = [
                    SELECT City__c
                    FROM Location__c
                    WHERE Id = :locationValue
                    LIMIT 1
                ];
                evt.Location__c = loc.City__c;
            } catch (Exception e) {
                evt.Location__c = locationValue;
            }
        } else {
            evt.Location__c = locationValue;
        }
    }

    /* ================= CLIENT DETAILS ================= */
    if (fields.containsKey('Client_Billing_Details__c')) {
        evt.Client_Billing_Details__c =
            fields.get('Client_Billing_Details__c') != null
            ? String.valueOf(fields.get('Client_Billing_Details__c'))
            : null;
    }

    if (fields.containsKey('Client_Rate__c')) {
        evt.Client_Rate__c =
            fields.get('Client_Rate__c') != null
            ? String.valueOf(fields.get('Client_Rate__c'))
            : null;
    }

    if (fields.containsKey('Client_Rate_Amount__c')) {
        Object val = fields.get('Client_Rate_Amount__c');
        evt.Client_Rate_Amount__c =
            val != null
            ? (val instanceof Decimal ? (Decimal) val : Decimal.valueOf(String.valueOf(val)))
            : null;
    }

    /* ================= CAREGIVER DETAILS ================= */
    if (fields.containsKey('Caregiver_Billing_Details__c')) {
        evt.Caregiver_Billing_Details__c =
            fields.get('Caregiver_Billing_Details__c') != null
            ? String.valueOf(fields.get('Caregiver_Billing_Details__c'))
            : null;
    }

    if (fields.containsKey('Caregiver_Rate__c')) {
        evt.Caregiver_Rate__c =
            fields.get('Caregiver_Rate__c') != null
            ? String.valueOf(fields.get('Caregiver_Rate__c'))
            : null;
    }

    if (fields.containsKey('Caregiver_Rate_Amount__c')) {
        Object val = fields.get('Caregiver_Rate_Amount__c');
        evt.Caregiver_Rate_Amount__c =
            val != null
            ? (val instanceof Decimal ? (Decimal) val : Decimal.valueOf(String.valueOf(val)))
            : null;
    }

    /* =====================================================
       IMPORTANT BUSINESS RULE:
       DO NOT UPDATE THESE FIELDS FROM THIS METHOD
       - Client_Flat_Rate_Amount__c
       - Caregiver_Flat_Rate_Amount__c
       ===================================================== */

    /* ================= MILEAGE FIELDS ================= */
    List<String> mileageAmountFields = new List<String>{
        'Mileage_Amount__c', 'Mileage_Amount_2__c', 'Mileage_Amount_3__c',
        'Mileage_Amount_4__c', 'Mileage_Amount_5__c'
    };
    List<String> mileageDescFields = new List<String>{
        'Mileage_Description__c', 'Mileage_Description_2__c', 'Mileage_Description_3__c',
        'Mileage_Description_4__c', 'Mileage_Description_5__c'
    };

    // --- Changed by Prasad - Start ---
    /* ================= ENTER MILES FIELDS + MILEAGE AMOUNT CALCULATION ================= */
    List<String> enterMilesFields = new List<String>{
        'Enter_Miles_1__c', 'Enter_Miles_2__c', 'Enter_Miles_3__c',
        'Enter_Miles_4__c', 'Enter_Miles_5__c'
    };

    // --- Changed by Prasad - Start ---
    // Query Mileage Rate from Custom Setting (as per user story)
    Decimal mileageRate = 0;
    WellSky_Custom_Setting__c settings = WellSky_Custom_Setting__c.getOrgDefaults();
    if (settings != null && settings.Mileage_Rate__c != null) {
        mileageRate = settings.Mileage_Rate__c;
    }
    System.debug('Mileage Rate from Custom Setting: ' + mileageRate);
    // --- Changed by Prasad - End ---

    for (Integer i = 0; i < 5; i++) {
        // Save Enter_Miles value from JS
        Decimal milesValue = null;
        if (fields.containsKey(enterMilesFields[i])) {
            Object val = fields.get(enterMilesFields[i]);
            if (val != null) {
                milesValue = val instanceof Decimal ? (Decimal) val : Decimal.valueOf(String.valueOf(val));
            }
            evt.put(enterMilesFields[i], milesValue);
        }

        // Calculate Mileage_Amount = Enter_Miles × Mileage_Rate (Apex-side calculation)
        if (fields.containsKey(enterMilesFields[i])) {
            Decimal calculatedAmount = (milesValue != null && mileageRate != 0)
                ? milesValue * mileageRate
                : null;
            evt.put(mileageAmountFields[i], calculatedAmount);
            System.debug('Miles[' + i + ']: ' + milesValue + ' × Rate: ' + mileageRate + ' = Amount: ' + calculatedAmount);
        }

        // Save Mileage Description as-is
        if (fields.containsKey(mileageDescFields[i])) {
            evt.put(
                mileageDescFields[i],
                fields.get(mileageDescFields[i]) != null
                ? String.valueOf(fields.get(mileageDescFields[i]))
                : null
            );
        }
    }
    // --- Changed by Prasad - End ---

    /* ================= EXPENSE FIELDS ================= */
    List<String> expenseAmountFields = new List<String>{
        'Expense_Amount__c', 'Expense_Amount_2__c', 'Expense_Amount_3__c',
        'Expense_Amount_4__c', 'Expense_Amount_5__c'
    };
    List<String> expenseDescFields = new List<String>{
        'Expense_Description__c', 'Expense_Description_2__c', 'Expense_Description_3__c',
        'Expense_Description_4__c', 'Expense_Description_5__c'
    };

    for (Integer i = 0; i < 5; i++) {
        if (fields.containsKey(expenseAmountFields[i])) {
            Object val = fields.get(expenseAmountFields[i]);
            evt.put(
                expenseAmountFields[i],
                val != null
                ? (val instanceof Decimal ? (Decimal) val : Decimal.valueOf(String.valueOf(val)))
                : null
            );
        }

        if (fields.containsKey(expenseDescFields[i])) {
            evt.put(
                expenseDescFields[i],
                fields.get(expenseDescFields[i]) != null
                ? String.valueOf(fields.get(expenseDescFields[i]))
                : null
            );
        }
    }

    System.debug('Event before update: ' + JSON.serializePretty(evt));

    try {
        update evt;
        System.debug('=== UPDATE SUCCESSFUL ===');
    } catch (DmlException e) {
        //System.debug('DML ERROR: ' + e.getMessage());

         System.debug('===== DML EXCEPTION DETAILS =====');
    System.debug('Message: ' + e.getMessage());
    System.debug('Num DML Errors: ' + e.getNumDml());

    for (Integer i = 0; i < e.getNumDml(); i++) {
        System.debug('Status Code: ' + e.getDmlStatusCode(i));
        System.debug('Record Id: ' + e.getDmlId(i));
        System.debug('Fields: ' + e.getDmlFields(i));
        System.debug('Message: ' + e.getDmlMessage(i));
    }
        throw new AuraHandledException('Error saving Event: ' + e.getMessage());
    }
}


    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getEventRateData(Id eventId) {
        try {
            Event evt = [
                SELECT Id, Location__c,
                       Client_Billing_Details__c, Client_Rate_Amount__c,Client_Rate__c,
                       Caregiver_Billing_Details__c, Caregiver_Rate_Amount__c,Caregiver_Rate__c,
                       Mileage_Amount__c, Mileage_Description__c,
                       Mileage_Amount_2__c, Mileage_Description_2__c,
                       Mileage_Amount_3__c, Mileage_Description_3__c,
                       Mileage_Amount_4__c, Mileage_Description_4__c,
                       Mileage_Amount_5__c, Mileage_Description_5__c,
                       Expense_Amount__c, Expense_Description__c,
                       Expense_Amount_2__c, Expense_Description_2__c,
                       Expense_Amount_3__c, Expense_Description_3__c,
                       Expense_Amount_4__c, Expense_Description_4__c,
                       Expense_Amount_5__c, Expense_Description_5__c,
                       Client_Flat_Rate_Amount__c, Caregiver_Flat_Rate_Amount__c,
                       // --- Changed by Prasad - Start ---
                       Enter_Miles_1__c, Enter_Miles_2__c, Enter_Miles_3__c,
                       Enter_Miles_4__c, Enter_Miles_5__c
                       // --- Changed by Prasad - End ---
                FROM Event
                WHERE Id = :eventId
                LIMIT 1
            ];

            Map<String, Object> result = new Map<String, Object>();

            // Location is TEXT - store as is (city name)
            result.put('Location__c', evt.Location__c);
            result.put('Client_Billing_Details__c', evt.Client_Billing_Details__c);
            result.put('Client_Rate_Amount__c', evt.Client_Rate_Amount__c);
            result.put('Client_Rate__c', evt.Client_Rate__c);
            result.put('Caregiver_Rate__c', evt.Caregiver_Rate__c);
            result.put('Caregiver_Billing_Details__c', evt.Caregiver_Billing_Details__c);
            result.put('Caregiver_Rate_Amount__c', evt.Caregiver_Rate_Amount__c);

            // NEW LIVE-IN / FLAT RATE DATA
            result.put('Client_Flat_Rate_Amount__c', evt.Client_Flat_Rate_Amount__c);
            result.put('Caregiver_Flat_Rate_Amount__c', evt.Caregiver_Flat_Rate_Amount__c);

            // Mileage entries
            List<Map<String, Object>> mileageList = new List<Map<String, Object>>();
            List<String> mileageFields = new List<String>{'', '_2', '_3', '_4', '_5'};

            // --- Changed by Prasad - Start ---
            List<String> enterMilesFieldNames = new List<String>{
                'Enter_Miles_1__c', 'Enter_Miles_2__c', 'Enter_Miles_3__c',
                'Enter_Miles_4__c', 'Enter_Miles_5__c'
            };
            // --- Changed by Prasad - End ---

            for (Integer i = 0; i < 5; i++) {
                String suffix = mileageFields[i];
                String amountField = 'Mileage_Amount' + suffix + '__c';
                String descField = 'Mileage_Description' + suffix + '__c';

                Object amount = evt.get(amountField);
                Object description = evt.get(descField);
                // --- Changed by Prasad - Start ---
                Object miles = evt.get(enterMilesFieldNames[i]);
                // --- Changed by Prasad - End ---

                if (amount != null || description != null) {
                    Map<String, Object> entry = new Map<String, Object>();
                    entry.put('id', i);
                    entry.put('amount', amount != null ? amount : 0);
                    entry.put('description', description != null ? String.valueOf(description) : '');
                    // --- Changed by Prasad - Start ---
                    entry.put('miles', miles != null ? miles : 0);
                    // --- Changed by Prasad - End ---
                    mileageList.add(entry);
                }
            }
            result.put('mileageEntries', mileageList);

            // Expense entries
            List<Map<String, Object>> expenseList = new List<Map<String, Object>>();
            for (Integer i = 0; i < 5; i++) {
                String suffix = mileageFields[i];
                String amountField = 'Expense_Amount' + suffix + '__c';
                String descField = 'Expense_Description' + suffix + '__c';

                Object amount = evt.get(amountField);
                Object description = evt.get(descField);

                if (amount != null || description != null) {
                    Map<String, Object> entry = new Map<String, Object>();
                    entry.put('id', i);
                    entry.put('amount', amount != null ? amount : 0);
                    entry.put('description', description != null ? String.valueOf(description) : '');
                    expenseList.add(entry);
                }
            }
            result.put('expenseEntries', expenseList);

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving event data: ' + e.getMessage());
        }
    }

    // --- Changed by Prasad - Start ---
    @AuraEnabled(cacheable=true)
    public static Decimal getMileageRate() {
        // Query from Custom Setting (as per user story)
        WellSky_Custom_Setting__c settings = WellSky_Custom_Setting__c.getOrgDefaults();
        if (settings != null && settings.Mileage_Rate__c != null) {
            return settings.Mileage_Rate__c;
        }
        return 0;
    }
    // --- Changed by Prasad - End ---

    //add ons for ticket no 46
   @AuraEnabled
public static ValidationResult validatePatientLocation(
    Id eventId,
    String selectedLocationName
) {
    ValidationResult result = new ValidationResult();
 
    if (eventId == null) {
        return result;
    }
 
    Event evt = [
        SELECT WhatId
        FROM Event
        WHERE Id = :eventId
        LIMIT 1
    ];
 
    if (evt.WhatId == null || !evt.WhatId.getSObjectType().getDescribe().getName().equals('Account')) {
        return result;
    }
 
    Account acc = [
        SELECT Id, Location_g__c
        FROM Account
        WHERE Id = :evt.WhatId
        LIMIT 1
    ];
 
    result.patientLocation = acc.Location_g__c;
 
    // Scenario 1: Patient location is blank - DO NOT UPDATE YET
    if (String.isBlank(acc.Location_g__c)) {
        result.isPatientLocationBlank = true;
        return result;  // Just flag it, don't update
    }
 
    // Scenario 2: Mismatch
    if (!String.isBlank(selectedLocationName) &&
        acc.Location_g__c != selectedLocationName) {
        result.isMismatch = true;
    }
 
    return result;
}

    public class ValidationResult {
        @AuraEnabled public String patientLocation;
        @AuraEnabled public Boolean autoUpdated = false;
         @AuraEnabled public String selectedLocation;
        @AuraEnabled public Boolean isMismatch = false;
        @AuraEnabled public Boolean isPatientLocationBlank = false;

    }
}