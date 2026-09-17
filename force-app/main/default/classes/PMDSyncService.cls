public with sharing class PMDSyncService {

    @InvocableMethod(label='Sync PMD From Medication Statement')
    public static void syncPMDFromMedicationStatement(
        List<Id> medicationStatementIds
    ) {

        if(medicationStatementIds == null ||
           medicationStatementIds.isEmpty()) {
            return;
        }

        Map<Id, PatientMedicationDosage> existingMap =
            new Map<Id, PatientMedicationDosage>();

        for(PatientMedicationDosage pmd : [

            SELECT
                Id,
                ParentRecordId
            FROM PatientMedicationDosage
            WHERE ParentRecordId IN :medicationStatementIds
        ]) {

            existingMap.put(
                pmd.ParentRecordId,
                pmd
            );
        }

        List<MedicationStatement> msList = [

            SELECT
                Id,
                DosageQuantityType__c,
                DosageQuantityDenominator__c,
                DosageQuantityNumerator__c,
                Comments__c,
                Client_Instruction__c,
                Route_CSB__c
            FROM MedicationStatement
            WHERE Id IN :medicationStatementIds
        ];

        List<PatientMedicationDosage> toInsert =
            new List<PatientMedicationDosage>();

        List<PatientMedicationDosage> toUpdate =
            new List<PatientMedicationDosage>();

        for(MedicationStatement ms : msList) {

            // UPDATE
            if(existingMap.containsKey(ms.Id)) {

                PatientMedicationDosage pmd =
                    existingMap.get(ms.Id);

                pmd.DosageQuantityType =
                    ms.DosageQuantityType__c;

                pmd.DosageQuantityDenominator =
                    ms.DosageQuantityDenominator__c;

                pmd.DosageQuantityNumerator =
                    ms.DosageQuantityNumerator__c;

                pmd.Comments =
                    ms.Comments__c;

                pmd.PatientInstruction =
                    ms.Client_Instruction__c;

                pmd.RouteId =
                    ms.Route_CSB__c;

                toUpdate.add(pmd);
            }

            // INSERT
            else {

                PatientMedicationDosage pmd =
                    new PatientMedicationDosage();

                pmd.ParentRecordId = ms.Id;

                pmd.DosageQuantityType =
                    ms.DosageQuantityType__c;

                pmd.DosageQuantityDenominator =
                    ms.DosageQuantityDenominator__c;

                pmd.DosageQuantityNumerator =
                    ms.DosageQuantityNumerator__c;

                pmd.Comments =
                    ms.Comments__c;

                pmd.PatientInstruction =
                    ms.Client_Instruction__c;

                pmd.RouteId =
                    ms.Route_CSB__c;

                toInsert.add(pmd);
            }
        }

        if(!toInsert.isEmpty()) {
            insert toInsert;
        }

        if(!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}