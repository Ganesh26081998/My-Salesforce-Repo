/*
----------------------------------------------------------------------------
Author        : Ankit Pande
Class Name    : EventRateSyncController
CreatedOn     : 13-03-2026
LastModifiedOn: 15-03-2026
LastModifiedBy: Ankit Pande
Description   : This class is used to sync rate calculation details, mileage,
 *                 expense information, client billing details, and caregiver
 *                 billing details from a recurring source event to all related
 *                 recurring events.
----------------------------------------------------------------------------
*/
public with sharing class EventRateSyncController {

    /* Custom exception for clean VF messaging */
    public class RateSyncException extends Exception {}

    // ── @TestVisible helpers ── (used by test class for branch coverage)

    @TestVisible
    private static void validateRatesAndThrow(Event src) {
        if (src.Client_Rate__c == null && src.Caregiver_Rate__c == null) {
            throw new RateSyncException('Rate calculation data is incomplete.');
        }
    }

    @TestVisible
    private static void validateSiblingsAndThrow(List<Event> siblings) {
        if (siblings.isEmpty()) {
            throw new RateSyncException('No related recurring events found.');
        }
    }

    @TestVisible
    private static List<Event> copyRateFields(Event src, List<Event> siblings) {
        for (Event e : siblings) {
            e.Location__c               = src.Location__c;
            e.Client_Billing_Details__c = src.Client_Billing_Details__c;
            e.Client_Rate__c            = src.Client_Rate__c;
            e.Client_Rate_Amount__c     = src.Client_Rate_Amount__c;

            e.Caregiver_Billing_Details__c = src.Caregiver_Billing_Details__c;
            e.Caregiver_Rate__c            = src.Caregiver_Rate__c;
            e.Caregiver_Rate_Amount__c     = src.Caregiver_Rate_Amount__c;

            e.Enter_Miles_1__c = src.Enter_Miles_1__c;
            e.Enter_Miles_2__c = src.Enter_Miles_2__c;
            e.Enter_Miles_3__c = src.Enter_Miles_3__c;
            e.Enter_Miles_4__c = src.Enter_Miles_4__c;
            e.Enter_Miles_5__c = src.Enter_Miles_5__c;

            e.Mileage_Amount__c   = src.Mileage_Amount__c;
            e.Mileage_Amount_2__c = src.Mileage_Amount_2__c;
            e.Mileage_Amount_3__c = src.Mileage_Amount_3__c;
            e.Mileage_Amount_4__c = src.Mileage_Amount_4__c;
            e.Mileage_Amount_5__c = src.Mileage_Amount_5__c;

            e.Mileage_Description__c   = src.Mileage_Description__c;
            e.Mileage_Description_2__c = src.Mileage_Description_2__c;
            e.Mileage_Description_3__c = src.Mileage_Description_3__c;
            e.Mileage_Description_4__c = src.Mileage_Description_4__c;
            e.Mileage_Description_5__c = src.Mileage_Description_5__c;

            e.Expense_Amount__c   = src.Expense_Amount__c;
            e.Expense_Amount_2__c = src.Expense_Amount_2__c;
            e.Expense_Amount_3__c = src.Expense_Amount_3__c;
            e.Expense_Amount_4__c = src.Expense_Amount_4__c;
            e.Expense_Amount_5__c = src.Expense_Amount_5__c;

            e.Expense_Description__c   = src.Expense_Description__c;
            e.Expense_Description_2__c = src.Expense_Description_2__c;
            e.Expense_Description_3__c = src.Expense_Description_3__c;
            e.Expense_Description_4__c = src.Expense_Description_4__c;
            e.Expense_Description_5__c = src.Expense_Description_5__c;
        }
        return siblings;
    }

    @TestVisible
    private static String getSuccessMessage() {
        return 'Rate calculation synced successfully to all recurring events.';
    }

    // ── Main AuraEnabled method ──────────────────────────────────

    @AuraEnabled
    public static String syncRecurringEventRates(Id eventId) {

        if (eventId == null) {
            throw new RateSyncException('Event Id is required.');
        }

        Event sourceEvt = [
            SELECT Id,
                   ActivityRecurrence2Id,
                   IsRecurrence,
                   Location__c,
                   Client_Billing_Details__c,
                   Client_Rate__c,
                   Client_Rate_Amount__c,
                   Caregiver_Billing_Details__c,
                   Caregiver_Rate__c,
                   Caregiver_Rate_Amount__c,
                   Enter_Miles_1__c, Enter_Miles_2__c, Enter_Miles_3__c,
                   Enter_Miles_4__c, Enter_Miles_5__c,
                   Mileage_Amount__c, Mileage_Amount_2__c,
                   Mileage_Amount_3__c, Mileage_Amount_4__c,
                   Mileage_Amount_5__c,
                   Mileage_Description__c, Mileage_Description_2__c,
                   Mileage_Description_3__c, Mileage_Description_4__c,
                   Mileage_Description_5__c,
                   Expense_Amount__c, Expense_Amount_2__c,
                   Expense_Amount_3__c, Expense_Amount_4__c,
                   Expense_Amount_5__c,
                   Expense_Description__c, Expense_Description_2__c,
                   Expense_Description_3__c, Expense_Description_4__c,
                   Expense_Description_5__c
            FROM Event
            WHERE Id = :eventId
            LIMIT 1
        ];

        if (sourceEvt.ActivityRecurrence2Id == null) {
            throw new RateSyncException(
                'Sync Rates can be used only for recurring events.'
            );
        }

        validateRatesAndThrow(sourceEvt);

        List<Event> siblingEvents = [
            SELECT Id,
                   Location__c,
                   Client_Billing_Details__c,
                   Client_Rate__c,
                   Client_Rate_Amount__c,
                   Caregiver_Billing_Details__c,
                   Caregiver_Rate__c,
                   Caregiver_Rate_Amount__c,
                   Enter_Miles_1__c, Enter_Miles_2__c, Enter_Miles_3__c,
                   Enter_Miles_4__c, Enter_Miles_5__c,
                   Mileage_Amount__c, Mileage_Amount_2__c,
                   Mileage_Amount_3__c, Mileage_Amount_4__c,
                   Mileage_Amount_5__c,
                   Mileage_Description__c, Mileage_Description_2__c,
                   Mileage_Description_3__c, Mileage_Description_4__c,
                   Mileage_Description_5__c,
                   Expense_Amount__c, Expense_Amount_2__c,
                   Expense_Amount_3__c, Expense_Amount_4__c,
                   Expense_Amount_5__c,
                   Expense_Description__c, Expense_Description_2__c,
                   Expense_Description_3__c, Expense_Description_4__c,
                   Expense_Description_5__c
            FROM Event
            WHERE ActivityRecurrence2Id = :sourceEvt.ActivityRecurrence2Id
              AND Id != :sourceEvt.Id
        ];

        validateSiblingsAndThrow(siblingEvents);

        copyRateFields(sourceEvt, siblingEvents);

        update siblingEvents;

        return getSuccessMessage();
    }
}