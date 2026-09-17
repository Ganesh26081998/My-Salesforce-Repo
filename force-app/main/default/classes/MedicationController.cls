/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : MedicationController
CreatedOn      : 16-05-2026
LastModifiedOn : 30-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This controller class is used to manage Medication Statement
                data, dynamic medication column configuration, medication
                field retrieval, custom setting persistence, medication
                display wrappers, and synchronization of
                PatientMedicationDosage data with MedicationStatement records.
----------------------------------------------------------------------------
*/
public with sharing class MedicationController {
    
    public List<RowWrapper> medications { get; set; }
    public List<String> selectedColumnLabels { get; set; }
    public List<String> selectedColumnFields { get; set; }
    public String accountName { get; set; }
    
    private static final Map<String, Set<String>> EXCLUDED_FIELDS_BY_OBJECT =
        new Map<String, Set<String>>{       
            'MedicationStatement' => new Set<String>{
                'patientid',
                'assertiondatetime',
                'careobservationid',
                'caseid',
                'clinicalencounterid',
                'statusreasoncodeid',
                'medicationcodeid',
                'medicationreasoncodeid',
                'createdbyid',
                'createddate',
                'isdeleted',
                'deliverysetting',        
                'lastmodifiedbyid',
                'lastmodifieddate',
                'lastreferenceddate',
                'lastvieweddate',
                'medicationid',
                'medication_name__c',
                'medicationreasonid',
                'medicationrequestid',
                'id',
                'parentmedicationstatementid',
                'name',
                'ownerid',
                'procedureid',
                'sourcesystem',
                'sourcesystemidentifier',
                'sourcesystemmodified',        
                'statementsourceid',        
                'systemmodstamp',
                'dosagequantitydenominator__c',
                'dosagequantitynumerator__c',
                'dosagequantitytype__c',
                'client_instruction__c',
                'comments__c',
                'route_csb__c'
            }
        };

    private static final Map<String, String> OBJECT_TO_ABBR = new Map<String, String>{
        'MedicationStatement' => 'MS'
    };
                        
    private static final Map<String, String> ABBR_TO_OBJECT = new Map<String, String>{
        'MS' => 'MedicationStatement'
    };

    // ─── VF Page Constructor ───────────────────────────────────────────────
    public MedicationController() {
        
        Id accountId = ApexPages.currentPage().getParameters().get('recordId');
        
        try {
            Account acc = [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1];
            accountName = acc.Name;
        } catch(Exception e) {
            accountName = '';
        }
        
        medications        = new List<RowWrapper>();
        selectedColumnLabels = new List<String>();
        selectedColumnFields = new List<String>();
        
        List<String> queryFields = new List<String>{ 'Id', 'Medication_Name__c' };

        // ── Load per-user per-account preference ──
        String rawColumns = getColumnsForAccount(accountId);

        if (String.isNotBlank(rawColumns)) {
            for (String raw : rawColumns.split(',')) {
                
                String value = expandField(raw.trim());
                if (String.isBlank(value) || !value.contains('.')) continue;
                
                List<String> parts = value.split('\\.');
                String objectApi = parts[0];
                String fieldApi  = parts[1];
                
                Schema.DescribeFieldResult d =
                    Schema.getGlobalDescribe()
                        .get(objectApi)?.getDescribe()
                        .fields.getMap()
                        .get(fieldApi)?.getDescribe();
                
                if (d == null) continue;
                
                selectedColumnLabels.add(d.getLabel());
                selectedColumnFields.add(value);
                
                if (objectApi.equalsIgnoreCase('MedicationStatement')) {
                    queryFields.add(fieldApi);
                }
            }
        }

        String sortBy  = ApexPages.currentPage().getParameters().get('sortBy');
        String sortDir = ApexPages.currentPage().getParameters().get('sortDir');

        Set<String> allowedSortFields = getAllowedSortFields(accountId);

        if (String.isBlank(sortBy) || !allowedSortFields.contains(sortBy.toLowerCase())) {
            sortBy = 'CreatedDate';
        }
        if (String.isBlank(sortDir) ||
            (!sortDir.equalsIgnoreCase('ASC') && !sortDir.equalsIgnoreCase('DESC'))) {
            sortDir = 'DESC';
        }

        String nullHandling = sortDir.equalsIgnoreCase('DESC') ? ' NULLS LAST' : ' NULLS FIRST';

        String soql =
            'SELECT ' + String.join(queryFields, ',') +
            ' FROM MedicationStatement' +
            ' WHERE PatientId = :accountId' +
            ' ORDER BY ' + sortBy + ' ' + sortDir + nullHandling +
            ', Medication_Name__c ASC';

        System.debug('sortBy='  + sortBy);
        System.debug('sortDir=' + sortDir);
        System.debug('SOQL='    + soql);

        for (SObject sob : Database.query(soql)) {
            medications.add(new RowWrapper((MedicationStatement)sob, selectedColumnFields));
        }
    }

    // ─── Get Available Fields ──────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getAvailableFields() {
        
        List<String> objects = new List<String>{ 'MedicationStatement' };
        List<FieldOption> options = new List<FieldOption>();
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        
        for (String objectApi : objects) {
            
            Map<String, Schema.SObjectField> fieldMap =
                gd.get(objectApi).getDescribe().fields.getMap();
            
            Set<String> excluded = EXCLUDED_FIELDS_BY_OBJECT.containsKey(objectApi)
                ? EXCLUDED_FIELDS_BY_OBJECT.get(objectApi)
                : new Set<String>();
            
            for (String fieldApi : fieldMap.keySet()) {
                if (excluded.contains(fieldApi.toLowerCase())) continue;
                
                Schema.DescribeFieldResult d = fieldMap.get(fieldApi).getDescribe();
                options.add(new FieldOption(
                    d.getLabel(),
                    objectApi + '.' + fieldApi,
                    String.valueOf(d.getType())
                ));
            }
        }
        
        options.sort(new FieldOptionSorter());
        return options;
    }

    // ─── Save Selected Fields ──────────────────────────────────────────────
    @AuraEnabled
    public static void saveSelectedFields(List<String> selectedFields, Id accountId) {

        if (accountId == null) {
            throw new AuraHandledException('Account ID is required to save field preferences.');
        }

        List<String> correctedFields = new List<String>();
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        for (String val : selectedFields) {

            if (String.isBlank(val) || !val.contains('.')) continue;

            List<String> parts = val.split('\\.');
            if (parts.size() < 2) continue;

            String objectApi = parts[0].trim();
            String fieldApi  = parts[1].trim();

            if (String.isBlank(objectApi) || String.isBlank(fieldApi)) continue;
            if (!gd.containsKey(objectApi)) continue;

            for (String actualField : gd.get(objectApi).getDescribe().fields.getMap().keySet()) {
                if (actualField.toLowerCase() == fieldApi.toLowerCase()) {
                    String abbr = OBJECT_TO_ABBR.containsKey(objectApi)
                        ? OBJECT_TO_ABBR.get(objectApi) : objectApi;
                    correctedFields.add(abbr + '.' + actualField);
                    break;
                }
            }
        }

        // Upsert preference record for this User + Account
        List<User_Medication_Preference__c> existing = [
            SELECT Id
            FROM User_Medication_Preference__c
            WHERE User__c    = :UserInfo.getUserId()
            AND   Account__c = :accountId
            LIMIT 1
        ];

        User_Medication_Preference__c pref = existing.isEmpty()
            ? new User_Medication_Preference__c(
                User__c    = UserInfo.getUserId(),
                Account__c = accountId)
            : existing[0];

        pref.Selected_Columns__c = correctedFields.isEmpty()
            ? '' : String.join(correctedFields, ',');

        upsert pref;
    }

    // ─── Get Medication Data (LWC) ─────────────────────────────────────────
    @AuraEnabled
    public static MedicationResponse getMedicationData(Id accountId, String sortBy, String sortDir) {

        Set<String> allowedSortFields = getAllowedSortFields(accountId);

        if (String.isBlank(sortBy) || !allowedSortFields.contains(sortBy.toLowerCase())) {
            sortBy = 'CreatedDate';
        }
        if (String.isBlank(sortDir) ||
            (!sortDir.equalsIgnoreCase('ASC') && !sortDir.equalsIgnoreCase('DESC'))) {
            sortDir = 'DESC';
        }

        String nullHandling = sortDir.equalsIgnoreCase('DESC') ? ' NULLS LAST' : ' NULLS FIRST';

        MedicationResponse response = new MedicationResponse();

        List<String> baseFields       = new List<String>{ 'Id', 'Medication_Name__c' };
        List<String> selectedFieldValues = new List<String>();
        List<FieldOption> selectedFields = new List<FieldOption>();

        // ── Load per-user per-account preference ──
        String rawColumns = getColumnsForAccount(accountId);

        if (String.isNotBlank(rawColumns)) {

            Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

            for (String r : rawColumns.split(',')) {

                String value = expandField(r.trim());
                if (String.isBlank(value) || !value.contains('.')) continue;

                List<String> parts = value.split('\\.');
                String objectApi = parts[0];
                String fieldApi  = parts[1];

                if (!gd.containsKey(objectApi) ||
                    !gd.get(objectApi).getDescribe().fields.getMap().containsKey(fieldApi)) continue;

                Schema.DescribeFieldResult d =
                    gd.get(objectApi).getDescribe().fields.getMap().get(fieldApi).getDescribe();

                selectedFields.add(new FieldOption(d.getLabel(), value, String.valueOf(d.getType())));
                selectedFieldValues.add(value);

                if (objectApi == 'MedicationStatement') {
                    baseFields.add(fieldApi);
                }
            }
        }

        String soql =
            'SELECT ' + String.join(baseFields, ',') +
            ' FROM MedicationStatement' +
            ' WHERE PatientId = :accountId' +
            ' ORDER BY ' + sortBy + ' ' + sortDir + nullHandling + ', Medication_Name__c ASC';

        List<Map<String,Object>> rows = new List<Map<String,Object>>();

        for (SObject sob : Database.query(soql)) {

            Map<String,Object> row = new Map<String,Object>();
            row.put('Id',                sob.get('Id'));
            row.put('Medication_Name__c', sob.get('Medication_Name__c'));

            for (String fld : selectedFieldValues) {

                fld = fld.trim();
                if (String.isBlank(fld) || !fld.contains('.')) continue;

                List<String> parts = fld.split('\\.');
                String objectApi = parts[0];
                String fieldApi  = parts[1];

                try {
                    Object val = (objectApi == 'MedicationStatement') ? sob.get(fieldApi) : null;

                    if (val instanceof DateTime) {
                        row.put(fld, ((DateTime)val).format('M/d/yyyy, h:mm a'));
                    } else {
                        row.put(fld, val);
                    }
                } catch(Exception e) {
                    row.put(fld, null);
                }
            }
            rows.add(row);
        }

        response.selectedFields = selectedFields;
        response.records        = rows;
        return response;
    }

    // ─── Private Helpers ───────────────────────────────────────────────────

    // Single place to read the preference for a User + Account
    private static String getColumnsForAccount(Id accountId) {
        if (accountId == null) return '';
        List<User_Medication_Preference__c> prefs = [
            SELECT Selected_Columns__c
            FROM User_Medication_Preference__c
            WHERE User__c    = :UserInfo.getUserId()
            AND   Account__c = :accountId
            LIMIT 1
        ];
        return (!prefs.isEmpty() && String.isNotBlank(prefs[0].Selected_Columns__c))
            ? prefs[0].Selected_Columns__c : '';
    }

    private static String expandField(String abbreviated) {
        if (String.isBlank(abbreviated) || !abbreviated.contains('.')) return abbreviated;
        List<String> parts = abbreviated.split('\\.');
        String prefix     = parts[0].trim();
        String fieldPart  = parts[1].trim();
        String fullObject = ABBR_TO_OBJECT.containsKey(prefix)
            ? ABBR_TO_OBJECT.get(prefix) : prefix;
        return fullObject + '.' + fieldPart;
    }

    private static Set<String> getAllowedSortFields(Id accountId) {
        Set<String> allowed = new Set<String>{ 'createddate', 'medication_name__c' };
        String rawColumns = getColumnsForAccount(accountId);
        if (String.isNotBlank(rawColumns)) {
            for (String raw : rawColumns.split(',')) {
                String expanded = expandField(raw.trim());
                if (String.isBlank(expanded) || !expanded.contains('.')) continue;
                allowed.add(expanded.split('\\.')[1].toLowerCase());
            }
        }
        return allowed;
    }

    // ─── Inner Classes ─────────────────────────────────────────────────────

    public class RowWrapper {
        public String medicationName { get; set; }
        public List<String> cellValues { get; set; }
        
        public RowWrapper(MedicationStatement med, List<String> selectedFields) {
            medicationName = med.Medication_Name__c;
            cellValues     = new List<String>();
            for (String fld : selectedFields) {
                List<String> parts = fld.split('\\.');
                String fieldApi    = parts[1];
                try {
                    Object val = med.get(fieldApi);
                    if (val == null) {
                        cellValues.add('');
                    } else if (val instanceof DateTime) {
                        cellValues.add(((DateTime)val).format('M/d/yyyy, h:mm a'));
                    } else {
                        cellValues.add(String.valueOf(val));
                    }
                } catch(Exception e) {
                    cellValues.add('');
                }
            }
        }
    }

    public class FieldOptionSorter implements Comparator<FieldOption> {
        public Integer compare(FieldOption a, FieldOption b) {
            String labelA = a.label != null ? a.label.toLowerCase() : '';
            String labelB = b.label != null ? b.label.toLowerCase() : '';
            return labelA.compareTo(labelB);
        }
    }

    public class FieldOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String type;
        public FieldOption(String label, String value, String type) {
            this.label = label;
            this.value = value;
            this.type  = type;
        }
    }

    public class MedicationResponse {
        @AuraEnabled public List<FieldOption> selectedFields;
        @AuraEnabled public List<Map<String,Object>> records;
    }
}