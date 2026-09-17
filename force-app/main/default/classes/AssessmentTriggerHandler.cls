/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : AssessmentTriggerHandler
CreatedOn      : 05-05-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This handler class is used to synchronize AllergyIntolerance
                 and HealthCondition records with Initial Assessment data.
                 It manages insert, update, and delete operations based on
                 assessment field changes and maintains related patient
                 health and allergy information.
----------------------------------------------------------------------------
*/
public class AssessmentTriggerHandler {
    private static Boolean isRunning = false;

    public static void deleteChildRecords( List<Initial_Assessment__c> assessments ) {
        Set<Id> assessmentIds = new Set<Id>();

        for (Initial_Assessment__c ass : assessments) {
            assessmentIds.add(ass.Id);
        }

        List<AllergyIntolerance> allergies = [
            SELECT Id
            FROM AllergyIntolerance
            WHERE Assessment__c IN :assessmentIds
        ];

        if (!allergies.isEmpty()) {
            delete allergies;
        }

        List<HealthCondition> healthConditions = [
            SELECT Id
            FROM HealthCondition
            WHERE Assessment__c IN :assessmentIds
        ];

        if (!healthConditions.isEmpty()) {
            delete healthConditions;
        }
    }
    
    public static void handleAllergySync(
        List<Initial_Assessment__c> newList,
        Map<Id, Initial_Assessment__c> oldMap
    ) {

        Set<Id> assessmentIds =
            new Map<Id, Initial_Assessment__c>(
                newList
            ).keySet();

        Map<Id, AllergyIntolerance> existingMap =
            new Map<Id, AllergyIntolerance>();

        for (AllergyIntolerance al : [
            SELECT Id, Assessment__c
            FROM AllergyIntolerance
            WHERE Assessment__c IN :assessmentIds
        ]) {

            existingMap.put(
                al.Assessment__c,
                al
            );
        }

        List<AllergyIntolerance> toInsert =
            new List<AllergyIntolerance>();

        List<AllergyIntolerance> toUpdate =
            new List<AllergyIntolerance>();

        List<AllergyIntolerance> toDelete =
            new List<AllergyIntolerance>();

        for (Initial_Assessment__c rec : newList) {

            Initial_Assessment__c oldRec =
                oldMap != null
                ? oldMap.get(rec.Id)
                : null;

            Boolean isChanged =
                oldMap == null ||
                (
                    oldRec != null &&
                    (
                        rec.Allergies__c != oldRec.Allergies__c ||
                        rec.Notes_Allergies__c != oldRec.Notes_Allergies__c
                    )
                );

            Boolean hasValue =
                String.isNotBlank(rec.Allergies__c);

            if (!isChanged) {
                continue;
            }

            // -----------------------------------------------------------------
            // DELETE
            // -----------------------------------------------------------------
            if (!hasValue &&
                existingMap.containsKey(rec.Id)) {

                toDelete.add(
                    existingMap.get(rec.Id)
                );

                continue;
            }

            // -----------------------------------------------------------------
            // INSERT / UPDATE
            // -----------------------------------------------------------------
            if (hasValue) {

                if (existingMap.containsKey(rec.Id)) {

                    AllergyIntolerance existing =
                        existingMap.get(rec.Id);
                    
                    existing.Prospect__c = rec.Prospect__c;

                    mapAllergyFields(
                        existing,
                        rec
                    );

                    toUpdate.add(existing);

                } else {

                    AllergyIntolerance al =
                        new AllergyIntolerance();

                    al.Assessment__c = rec.Id;
                    al.PatientId     = rec.Prospect__c;
                    al.Prospect__c   = rec.Prospect__c;

                    mapAllergyFields(
                        al,
                        rec
                    );

                    toInsert.add(al);
                }
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }

        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
    }

    // -------------------------------------------------------------------------
    public static void handleHealthConditionSync(
        List<Initial_Assessment__c> newList,
        Map<Id, Initial_Assessment__c> oldMap
    ) {

        Set<Id> assessmentIds =
            new Map<Id, Initial_Assessment__c>(
                newList
            ).keySet();

        Map<Id, HealthCondition> existingMap =
            new Map<Id, HealthCondition>();

        for (HealthCondition hc : [
            SELECT Id, Assessment__c
            FROM HealthCondition
            WHERE Assessment__c IN :assessmentIds
        ]) {

            existingMap.put(
                hc.Assessment__c,
                hc
            );
        }

        List<HealthCondition> toInsert =
            new List<HealthCondition>();

        List<HealthCondition> toUpdate =
            new List<HealthCondition>();

        List<HealthCondition> toDelete =
            new List<HealthCondition>();

        for (Initial_Assessment__c rec : newList) {

            Initial_Assessment__c oldRec =
                oldMap != null
                ? oldMap.get(rec.Id)
                : null;

            Boolean isChanged =
                hasHealthConditionChanged(
                    rec,
                    oldRec,
                    oldMap
                );

            Boolean hasValue =
                hasHealthConditionValues(rec);

            if (!isChanged) {
                continue;
            }

            // -----------------------------------------------------------------
            // DELETE
            // -----------------------------------------------------------------
            if (!hasValue &&
                existingMap.containsKey(rec.Id)) {

                toDelete.add(
                    existingMap.get(rec.Id)
                );

                continue;
            }

            // -----------------------------------------------------------------
            // INSERT / UPDATE
            // -----------------------------------------------------------------
            if (hasValue) {

                if (existingMap.containsKey(rec.Id)) {

                    HealthCondition existing =
                        existingMap.get(rec.Id);
                                        
                    existing.Prospect__c = rec.Prospect__c;

                    mapHealthConditionFields(
                        existing,
                        rec
                    );

                    toUpdate.add(existing);

                } else {

                    HealthCondition hc =
                        new HealthCondition();

                    hc.Assessment__c = rec.Id;
                    hc.PatientId     = rec.Prospect__c;
                    hc.Prospect__c   = rec.Prospect__c;

                    mapHealthConditionFields(
                        hc,
                        rec
                    );

                    toInsert.add(hc);
                }
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }

        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
    }

    // -------------------------------------------------------------------------
    private static void mapAllergyFields(
        AllergyIntolerance al,
        Initial_Assessment__c rec
    ) {

        al.Allergies__c = rec.Allergies__c;
        al.Notes__c = rec.Notes_Allergies__c;
    }

    // -------------------------------------------------------------------------
    private static void mapHealthConditionFields(
        HealthCondition hc,
        Initial_Assessment__c rec
    ) {

        hc.Chronic_Acute_Conditions__c =
            rec.Chronic_Acute_Conditions__c;

        hc.Hearing__c = rec.Hearing__c;
        hc.Speech__c = rec.Speech__c;
        hc.Hearing_Aid__c = rec.Hearing_Aid__c;
        hc.Vision__c = rec.Vision__c;
        hc.Swallowing__c = rec.Swallowing__c;

        hc.Other_for_Medical_Conditions__c =
            rec.Other_for_Medical_Conditions__c;

        hc.Functional_Limitations__c =
            rec.Functional_Limitations__c;

        hc.Diagnosed_Disorders_Medications__c =
            rec.Diagnosed_Disorders_Medications__c;

        hc.Lethargy__c = rec.Lethargy__c;
        hc.Depression__c = rec.Depression__c;

        hc.Past_Current_Substance_Abuse__c =
            rec.Past_Current_Substance_Abuse__c;

        hc.Can_client_be_left_alone__c =
            rec.Can_client_be_left_alone__c;

        hc.Wanderer__c = rec.Wanderer__c;
        hc.Dementia__c = rec.Dementia__c;
        hc.Symptoms__c = rec.Symptoms__c;
        hc.Triggers__c = rec.Triggers__c;
    }

    // -------------------------------------------------------------------------
    private static Boolean hasHealthConditionChanged(
        Initial_Assessment__c rec,
        Initial_Assessment__c oldRec,
        Map<Id, Initial_Assessment__c> oldMap
    ) {

        return
            oldMap == null ||
            (
                oldRec != null &&
                (
                    rec.Chronic_Acute_Conditions__c != oldRec.Chronic_Acute_Conditions__c ||
                    rec.Hearing__c != oldRec.Hearing__c ||
                    rec.Speech__c != oldRec.Speech__c ||
                    rec.Hearing_Aid__c != oldRec.Hearing_Aid__c ||
                    rec.Vision__c != oldRec.Vision__c ||
                    rec.Swallowing__c != oldRec.Swallowing__c ||
                    rec.Other_for_Medical_Conditions__c != oldRec.Other_for_Medical_Conditions__c ||
                    rec.Functional_Limitations__c != oldRec.Functional_Limitations__c ||
                    rec.Diagnosed_Disorders_Medications__c != oldRec.Diagnosed_Disorders_Medications__c ||
                    rec.Lethargy__c != oldRec.Lethargy__c ||
                    rec.Depression__c != oldRec.Depression__c ||
                    rec.Past_Current_Substance_Abuse__c != oldRec.Past_Current_Substance_Abuse__c ||
                    rec.Can_client_be_left_alone__c != oldRec.Can_client_be_left_alone__c ||
                    rec.Wanderer__c != oldRec.Wanderer__c ||
                    rec.Dementia__c != oldRec.Dementia__c ||
                    rec.Symptoms__c != oldRec.Symptoms__c ||
                    rec.Triggers__c != oldRec.Triggers__c
                )
            );
    }

    // -------------------------------------------------------------------------
    private static Boolean hasHealthConditionValues(
        Initial_Assessment__c rec
    ) {

        return
            String.isNotBlank(rec.Chronic_Acute_Conditions__c) ||
            String.isNotBlank(rec.Hearing__c) ||
            String.isNotBlank(rec.Speech__c) ||
            rec.Hearing_Aid__c ||
            String.isNotBlank(rec.Vision__c) ||
            String.isNotBlank(rec.Swallowing__c) ||
            String.isNotBlank(rec.Other_for_Medical_Conditions__c) ||
            String.isNotBlank(rec.Functional_Limitations__c) ||
            String.isNotBlank(rec.Diagnosed_Disorders_Medications__c) ||
            rec.Lethargy__c ||
            rec.Depression__c ||
            rec.Past_Current_Substance_Abuse__c ||
            String.isNotBlank(rec.Can_client_be_left_alone__c) ||
            String.isNotBlank(rec.Wanderer__c) ||
            String.isNotBlank(rec.Dementia__c) ||
            String.isNotBlank(rec.Symptoms__c) ||
            String.isNotBlank(rec.Triggers__c);
    }
}