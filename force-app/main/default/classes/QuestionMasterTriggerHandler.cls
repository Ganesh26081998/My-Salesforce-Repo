/*
---------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : QuestionMasterTriggerHandler
CreatedOn      : 8/5/2026
LastModifiedOn : 8/12/2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This trigger handler class manages Question Master record
                 processing, including automatic question sequence management
                 when questions are created, updated, moved, or deleted within
                 an assessment. It ensures question sequences remain ordered
                 across the entire assessment.
---------------------------------------------------------------------------
*/
public with sharing class QuestionMasterTriggerHandler {

    // Recursion guard: the DML this handler runs to fix Sequence__c
    // must not cause the trigger to re-process its own update.
    private static Boolean isRenumbering = false;

    public static void handleAfterInsert(List<Question_Master__c> newRecords) {

        if (isRenumbering) {
            return;
        }

        Set<String> assessmentTypes = new Set<String>();
        Set<Id> priorityIds = new Set<Id>();

        for (Question_Master__c q : newRecords) {

            if (String.isNotBlank(q.Assessment_Type__c)) {
                assessmentTypes.add(q.Assessment_Type__c);
            }

            priorityIds.add(q.Id);
        }

        renumberAssessmentTypes(assessmentTypes, priorityIds);
    }

    public static void handleAfterUpdate(
        List<Question_Master__c> newRecords,
        Map<Id, Question_Master__c> oldMap
    ) {

        if (isRenumbering) {
            return;
        }

        Set<String> assessmentTypes = new Set<String>();
        Set<Id> priorityIds = new Set<Id>();

        for (Question_Master__c q : newRecords) {

            Question_Master__c oldQ = oldMap.get(q.Id);

            // Only Active__c toggling triggers renumbering, per requirement.
            if (oldQ.Active__c != q.Active__c) {

                if (String.isNotBlank(oldQ.Assessment_Type__c)) {
                    assessmentTypes.add(oldQ.Assessment_Type__c);
                }

                if (String.isNotBlank(q.Assessment_Type__c)) {
                    assessmentTypes.add(q.Assessment_Type__c);
                }

                priorityIds.add(q.Id);
            }
        }

        renumberAssessmentTypes(assessmentTypes, priorityIds);
    }

    public static void handleAfterDelete(List<Question_Master__c> oldRecords) {

        if (isRenumbering) {
            return;
        }

        Set<String> assessmentTypes = new Set<String>();

        for (Question_Master__c q : oldRecords) {
            if (String.isNotBlank(q.Assessment_Type__c)) {
                assessmentTypes.add(q.Assessment_Type__c);
            }
        }

        // No priority records on delete - nothing new is claiming a slot.
        renumberAssessmentTypes(assessmentTypes, new Set<Id>());
    }

    public static void handleAfterUndelete(List<Question_Master__c> newRecords) {

        if (isRenumbering) {
            return;
        }

        Set<String> assessmentTypes = new Set<String>();
        Set<Id> priorityIds = new Set<Id>();

        for (Question_Master__c q : newRecords) {

            if (String.isNotBlank(q.Assessment_Type__c)) {
                assessmentTypes.add(q.Assessment_Type__c);
            }

            priorityIds.add(q.Id);
        }

        renumberAssessmentTypes(assessmentTypes, priorityIds);
    }

    private static void renumberAssessmentTypes(
        Set<String> assessmentTypes,
        Set<Id> priorityRecordIds
    ) {

        if (assessmentTypes.isEmpty()) {
            return;
        }

        List<Question_Master__c> activeQuestions = [
            SELECT Id,
                   Assessment_Type__c,
                   Group__c,
                   Sequence__c,
                   Dependent_On_Question__c
            FROM Question_Master__c
            WHERE Assessment_Type__c IN :assessmentTypes
            AND Active__c = true
            ORDER BY Assessment_Type__c,
                     Sequence__c ASC NULLS LAST,
                     Id
        ];

        Map<String, List<Question_Master__c>> byType =
            new Map<String, List<Question_Master__c>>();

        for (Question_Master__c q : activeQuestions) {

            if (!byType.containsKey(q.Assessment_Type__c)) {
                byType.put(
                    q.Assessment_Type__c,
                    new List<Question_Master__c>()
                );
            }

            byType.get(q.Assessment_Type__c).add(q);
        }

        List<Question_Master__c> toUpdate = new List<Question_Master__c>();

        for (String assessmentType : byType.keySet()) {

            List<Question_Master__c> typeQuestions =
                byType.get(assessmentType);

            typeQuestions.sort(
                new QuestionSequenceComparator(priorityRecordIds)
            );

            toUpdate.addAll(renumberOneType(typeQuestions));
        }

        if (!toUpdate.isEmpty()) {

            isRenumbering = true;

            try {
                update toUpdate;
            } finally {
                isRenumbering = false;
            }
        }
    }

    private static List<Question_Master__c> renumberOneType(
        List<Question_Master__c> orderedQuestions
    ) {

        List<Question_Master__c> changed = new List<Question_Master__c>();

        // Group dependent children by their parent Id, preserving the
        // relative order they were already in (current Sequence__c order).
        Map<Id, List<Question_Master__c>> dependentsByParentId =
            new Map<Id, List<Question_Master__c>>();

        for (Question_Master__c q : orderedQuestions) {

            if (q.Dependent_On_Question__c != null) {

                if (!dependentsByParentId.containsKey(q.Dependent_On_Question__c)) {
                    dependentsByParentId.put(
                        q.Dependent_On_Question__c,
                        new List<Question_Master__c>()
                    );
                }

                dependentsByParentId.get(q.Dependent_On_Question__c).add(q);
            }
        }

        Integer parentNumber = 0;
        String currentParentGroup;
        Integer groupChildIndex = 0;

        for (Question_Master__c q : orderedQuestions) {

            if (q.Dependent_On_Question__c != null) {
                continue;
            }

            Boolean isGroupedDecimalChild =
                String.isNotBlank(q.Group__c) &&
                q.Group__c == currentParentGroup &&
                q.Sequence__c != null &&
                q.Sequence__c != q.Sequence__c.setScale(0);

            Decimal newSequence;

            if (isGroupedDecimalChild) {

                groupChildIndex++;
                newSequence = parentNumber + (groupChildIndex * 0.1);

            } else {

                parentNumber++;
                groupChildIndex = 0;
                currentParentGroup = q.Group__c;

                newSequence = parentNumber;
            }

            if (q.Sequence__c == null || q.Sequence__c != newSequence) {
                q.Sequence__c = newSequence;
                changed.add(q);
            }

            if (!isGroupedDecimalChild &&
                dependentsByParentId.containsKey(q.Id)) {

                Integer dependentIndex = 0;

                for (Question_Master__c dependent : dependentsByParentId.get(q.Id)) {

                    dependentIndex++;

                    Decimal newDependentSequence =
                        newSequence + (dependentIndex * 0.1);

                    if (dependent.Sequence__c == null ||
                        dependent.Sequence__c != newDependentSequence) {

                        dependent.Sequence__c = newDependentSequence;
                        changed.add(dependent);
                    }
                }
            }
        }

        return changed;
    }

    private class QuestionSequenceComparator implements Comparator<Question_Master__c> {

        private Set<Id> priorityIds;

        public QuestionSequenceComparator(Set<Id> priorityIds) {
            this.priorityIds =
                priorityIds != null ? priorityIds : new Set<Id>();
        }

        public Integer compare(Question_Master__c a, Question_Master__c b) {

            Decimal seqA = a.Sequence__c;
            Decimal seqB = b.Sequence__c;

            if (seqA == null && seqB == null) {
                return 0;
            }
            if (seqA == null) {
                return 1;
            }
            if (seqB == null) {
                return -1;
            }

            Integer bySequence;

            if (seqA < seqB) {
                bySequence = -1;
            } else if (seqA > seqB) {
                bySequence = 1;
            } else {
                bySequence = 0;
            }

            if (bySequence != 0) {
                return bySequence;
            }

            // Tie on Sequence__c: the priority (just-changed) record
            // sorts first, so it keeps the typed number and everything
            // else already sitting there gets pushed down.
            Boolean aIsPriority = priorityIds.contains(a.Id);
            Boolean bIsPriority = priorityIds.contains(b.Id);

            if (aIsPriority && !bIsPriority) {
                return -1;
            }
            if (bIsPriority && !aIsPriority) {
                return 1;
            }

            return 0;
        }
    }
}