/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : CareObservationService
CreatedOn      : 20-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This service class is used to handle CareObservation record
                 processing in before and after trigger contexts. It assigns
                 default temporary names, maps observation categories to Unit
                 Of Measure records using custom metadata configuration, and
                 updates the final observation name after record creation.
----------------------------------------------------------------------------
*/
public class CareObservationService {

	public static Boolean isRunning = false;

    private static Map<String, String> categoryToUnitCode;
    private static Map<String, Id> unitCodeToId;     

    public static void handle(List<CareObservation> records, Boolean isBefore, Boolean isAfter) {
        
        loadMappings();
        
        if (isBefore) {            

            for (CareObservation rec : records) {
                if (rec.Name == null || rec.Name == '') {
                    rec.Name = 'TEMP';
                }

                if (rec.Category != null &&
                    categoryToUnitCode.containsKey(rec.Category)) {

                    String code = categoryToUnitCode.get(rec.Category);

                    if (unitCodeToId.containsKey(code)) {
                        rec.ObservedValueUnitId  = unitCodeToId.get(code);
                    }
                }
            }
        }
        
        if (isAfter) {

            if (isRunning) return;
            isRunning = true;

            List<CareObservation> updates = new List<CareObservation>();

            for (CareObservation rec : records) {
                if ((rec.Name == 'TEMP' || rec.Name == null || rec.Name == '') &&
                    rec.Name__c != null) {

                    updates.add(new CareObservation(
                        Id = rec.Id,
                        Name = rec.Name__c
                    ));
                }
            }

            if (!updates.isEmpty()) {
                update updates;
            }
        }
    }

    private static void loadMappings() {

        if (categoryToUnitCode == null) {

            categoryToUnitCode = new Map<String, String>();

            for (Observation_Unit_Mapping__mdt config : [
                SELECT Category__c, UnitCode__c
                FROM Observation_Unit_Mapping__mdt
            ]) {
                categoryToUnitCode.put(
                    config.Category__c,
                    config.UnitCode__c
                );
            }
        }

        if (unitCodeToId == null) {

            unitCodeToId = new Map<String, Id>();

            Set<String> codes = new Set<String>(categoryToUnitCode.values());

            for (UnitOfMeasure u : [
                SELECT Id, UnitCode 
                FROM UnitOfMeasure 
                WHERE UnitCode IN :codes
            ]) {
                unitCodeToId.put(u.UnitCode, u.Id);
            }
        }
    }
    
}