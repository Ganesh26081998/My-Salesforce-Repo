// /*
// ----------------------------------------------------------------------------
// Author        : Tushar Darode
// Class Name    : VitalBoardController
// CreatedOn     : 13-03-2026
// LastModifiedOn: 15-05-2026
// LastModifiedBy: Tushar
// Description   : This class manages Care Observation data for patients, including 
//                 retrieving, processing, and saving vital observation records. 
//                 It supports filtering observations by patient and date range, 
//                 formatting observation values with units for UI display, and 
//                 creating new Care Observation records from the Vital Board UI.
// ----------------------------------------------------------------------------
// */

public without sharing class VitalBoardController {

    @AuraEnabled
    public static List<VitalWrapper> getVitalData(Date fromDate, Date toDate, Id patientId) {

        String query = 'SELECT Id, ' +
                       'ObservedSubjectId, ObservedSubject.Name, ' +
                       'Category, Value__c, ' +
                       'ObservedValueUnitId, ObservedValueUnit.UnitCode, ObservedValueUnit.Name, ' +
                       'Effective_Date_and_Time__c  ,' +
                       'CreatedDate, LastModifiedDate ' +
                       'FROM CareObservation ' +
                       'WHERE Effective_Date_and_Time__c  != NULL';

        if (patientId != null) {
            query += ' AND ObservedSubjectId = :patientId';
        }

        if (fromDate != null) {
            DateTime fromDT = DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
            query += ' AND Effective_Date_and_Time__c >= :fromDT';
        }

        if (toDate != null) {
            DateTime toDT = DateTime.newInstance(toDate.addDays(1), Time.newInstance(0, 0, 0, 0));
            query += ' AND Effective_Date_and_Time__c < :toDT';
        }

        query += ' ORDER BY ObservedSubject.Name, Category, Effective_Date_and_Time__c ';

        List<CareObservation> records = Database.query(query);
        return processData(records);
    }

    @AuraEnabled
    public static void saveObservation(Id patientId, String category, String value, String effectiveDateTime) {

        if (patientId == null) {
            throw new AuraHandledException('Client is required.');
        }

        DateTime dt = (DateTime) JSON.deserialize('"' + effectiveDateTime + '"', DateTime.class);

        CareObservation obs = new CareObservation();
        obs.ObservedSubjectId = patientId;
        obs.Category = category;
        obs.Value__c = value;
        obs.Effective_Date_and_Time__c = dt;

        try {
            insert obs;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateObservation(
        Id observationId,
        String category,
        String value,
        String effectiveDateTime
    ) {

        CareObservation obs = [
            SELECT Id, Value__c, Effective_Date_and_Time__c
            FROM CareObservation
            WHERE Id = :observationId
            LIMIT 1
        ];
        obs.Category  = category;
        obs.Value__c = value;

        if (String.isNotBlank(effectiveDateTime)) {
            obs.Effective_Date_and_Time__c =
                (DateTime) JSON.deserialize(
                    '"' + effectiveDateTime + '"',
                    DateTime.class
                );
        }

        update obs;
    }

    @AuraEnabled
    public static void deleteObservation(Id observationId) {

        delete [
            SELECT Id
            FROM CareObservation
            WHERE Id = :observationId
            LIMIT 1
        ];
    }

    private static List<VitalWrapper> processData(List<CareObservation> records) {

        Map<String, VitalWrapper> mapData = new Map<String, VitalWrapper>();

        for (CareObservation rec : records) {

            String patientId = rec.ObservedSubjectId;

            String patientName = (rec.ObservedSubject != null)
                ? rec.ObservedSubject.Name
                : 'Unknown';

            String vital = rec.Category;

            //String dateKey = rec.Effective_Date_and_Time__c.format('yyyy-MM-dd\'T\'HH:mm:ss');
            String dateKey = rec.Effective_Date_and_Time__c.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss');
            String key = patientId + '-' + vital;

            if (!mapData.containsKey(key)) {
                mapData.put(key, new VitalWrapper(patientId, patientName, vital));
            }

            String unit = '';

            if (rec.ObservedValueUnit != null) {
                if (rec.ObservedValueUnit.UnitCode != null) {
                    unit = rec.ObservedValueUnit.UnitCode;
                } else if (rec.ObservedValueUnit.Name != null) {
                    unit = rec.ObservedValueUnit.Name;
                }
            }

            String formattedValue = '';

            if (rec.Value__c != null) {
                formattedValue = rec.Value__c;
            }

            String value = (formattedValue != '')
                ? formattedValue 
                : '—';

            Map<String, ObservationEntry> valueMap =
                mapData.get(key).values;

            String uniqueKey = dateKey;
            Integer suffix = 1;

            while (valueMap.containsKey(uniqueKey)) {
                uniqueKey = dateKey + '_' + suffix;
                suffix++;
            }

            valueMap.put(
                uniqueKey,
                new ObservationEntry(
                    rec.Id,
                    value,
                    dateKey,
                    rec.CreatedDate.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss'),
                    rec.LastModifiedDate.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss')
                )
            );
        }

        return mapData.values();
    }

    // ===================== WRAPPERS =====================

    public class VitalWrapper {
        @AuraEnabled public String patientId;
        @AuraEnabled public String patientName;
        @AuraEnabled public String vital;
        @AuraEnabled public Map<String, ObservationEntry> values;

        public VitalWrapper(String pId, String pName, String v) {
            patientId = pId;
            patientName = pName;
            vital = v;
            values = new Map<String, ObservationEntry>();
        }
    }

    public class ObservationEntry {
        @AuraEnabled public String recordId;
        @AuraEnabled public String value;
        @AuraEnabled public String effectiveDateTime;
        @AuraEnabled public String createdDateTime;
        @AuraEnabled public String lastModifiedDateTime;

        public ObservationEntry(String recordId, String value, String effectiveDateTime,String createdDateTime,String lastModifiedDateTime ) {
            this.recordId = recordId;
            this.value = value;
            this.effectiveDateTime = effectiveDateTime;
            this.createdDateTime      = createdDateTime;
            this.lastModifiedDateTime = lastModifiedDateTime;
        }
    }
}