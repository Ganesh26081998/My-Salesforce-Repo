/*
----------------------------------------------------------------------------
Author         : Ganesh Uppin
Class Name     : CarePlanCaseController
CreatedOn      : 13-01-2026
LastModifiedOn : 20-05-2026
LastModifiedBy : Ganesh Uppin

Description    : This class is used to manage Care Plan update,
                 retrieval, validation, and PDF generation functionality.
                 It handles Problems, Goals, Interventions, Stakeholders,
                 Schedule details, Contact associations, and ensures only
                 the latest Care Plan can be edited.
----------------------------------------------------------------------------
*/
public with sharing class CarePlanCaseController {

     // Existing wrapper classes
    public class CarePlanResponseWrapper {
        @AuraEnabled public List<CarePlanProblemWrapper> problems;
        @AuraEnabled public List<CarePlanGoalWrapper> goals;
    }
    
    public class CarePlanProblemWrapper {
        @AuraEnabled public Id problemId;
        @AuraEnabled public String problemName;
    }
    
    public class CarePlanGoalWrapper {
        @AuraEnabled public Id goalId;
        @AuraEnabled public String goalName;
        @AuraEnabled public String type;
        @AuraEnabled public List<CarePlanTaskWrapper> tasks;
    }
    
    public class CarePlanTaskWrapper {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String taskName;
        @AuraEnabled public String taskDescription;
    }
    
    // New wrapper classes for saving
    public class CarePlanDataWrapper {
        @AuraEnabled public List<ProblemBlockWrapper> problems;
        @AuraEnabled public List<GoalBlockWrapper> longTermGoals;
        @AuraEnabled public List<GoalBlockWrapper> quarterlyGoals;
        @AuraEnabled public List<StakeholderWrapper> stakeholders;
        @AuraEnabled public ScheduleWrapper schedule;
        @AuraEnabled public ClientImpactWrapper clientImpact; 
    }
    
    public class ProblemBlockWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public List<String> selectedIds;
        @AuraEnabled public String selectedName;
        @AuraEnabled public String severity;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isCustom; 
    }
    
    public class GoalBlockWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public List<String> selectedIds;
        @AuraEnabled public String selectedName;
        @AuraEnabled public String category;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isCustom; 
        @AuraEnabled public String successCriteria;
        @AuraEnabled public List<InterventionWrapper> interventions;
    }
    
    public class InterventionWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public List<String> selectedIds;
        @AuraEnabled public String selectedName;
        @AuraEnabled public String category;
        @AuraEnabled public String specificIntervention;
        @AuraEnabled public String frequency;
        @AuraEnabled public Boolean isCustom;
        @AuraEnabled public String duration;

        @AuraEnabled public String details;
    }
    
    public class StakeholderWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public Boolean isNew;
        @AuraEnabled public String stakeholderType;
        @AuraEnabled public String contactName;
       // @AuraEnabled public String userId;
       @AuraEnabled public Id contactId;
        @AuraEnabled public String roleInCare;
        @AuraEnabled public String communicationPreference;
        @AuraEnabled public String communicationFrequency;
    }
    
    public class ScheduleWrapper {
        @AuraEnabled public String startDate;
        @AuraEnabled public String reviewDate;
        @AuraEnabled public String frequency;
        @AuraEnabled public String duration;
        @AuraEnabled public String hoursPerWeek;
    }

    public class ClientImpactWrapper {
    @AuraEnabled public String quarterlyGoalStatus;
    @AuraEnabled public String clientStability;
    @AuraEnabled public String outcomeSummary;
    @AuraEnabled public String planAdjustment;
}
    
    public class SaveResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id carePlanId;
        @AuraEnabled public Id pdfContentDocumentId;
    }

    @AuraEnabled
public static String getNextCarePlanTitle(Id accountId) {

    if (accountId == null) {
        return null;
    }

    // Get Account Name
    Account acc = [
        SELECT Name
        FROM Account
        WHERE Id = :accountId
        LIMIT 1
    ];

    // Get Care Plan Record Type
    Id carePlanRtId = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Case'
        AND DeveloperName = 'CarePlan'
        LIMIT 1
    ].Id;

    // Fetch latest Care Plan Case
    List<Case> cases = [
        SELECT Id, Sequence_Number__c
        FROM Case
        WHERE RecordTypeId = :carePlanRtId
        AND AccountId = :accountId
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    Integer nextSequence = 1;

    if (!cases.isEmpty() && String.isNotBlank(cases[0].Sequence_Number__c)) {
        nextSequence = Integer.valueOf(cases[0].Sequence_Number__c) + 1;
    }

    // Format as 4-digit sequence (0001, 0002, ...)
    String sequenceStr = String.valueOf(nextSequence).leftPad(4, '0');
    return acc.Name + '- CP ' + sequenceStr;
    //return acc.Name + ' Care - Plan ' + sequenceStr;
}


    @AuraEnabled(cacheable=true)
    public static List<Case> getCarePlans(Id accountId) {

        if (accountId == null) {
            return new List<Case>();
        }

        Id carePlanRtId = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Case'
            AND DeveloperName = 'CarePlan'
            LIMIT 1
        ].Id;

        return [
            SELECT Id, Subject, CreatedDate, CreatedBy.Name, CaseNumber,LastModifiedBy.Name
            FROM Case
            WHERE RecordTypeId = :carePlanRtId
            AND AccountId = :accountId
            ORDER BY CreatedDate DESC
        ];
    }

      @AuraEnabled
public static String getLatestCarePlanPdfBase64(Id accountId) {
    if (accountId == null) return null;

    Id carePlanRtId = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Case' AND DeveloperName = 'CarePlan'
        LIMIT 1
    ].Id;

    List<Case> latest = [
        SELECT Id
        FROM Case
        WHERE AccountId = :accountId
        AND RecordTypeId = :carePlanRtId
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    if (latest.isEmpty()) return null;

    List<ContentDocumentLink> links = [
        SELECT ContentDocumentId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :latest[0].Id
        //ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    if (links.isEmpty()) return null;

    ContentVersion cv = [
        SELECT VersionData
        FROM ContentVersion
        WHERE ContentDocumentId = :links[0].ContentDocumentId
        AND IsLatest = true
        LIMIT 1
    ];

    return (cv.VersionData == null) ? null : EncodingUtil.base64Encode(cv.VersionData);
}
    
    /* this is to update latest care plan only */
    private static Boolean isLatestCarePlan(Id carePlanId) {
         Id carePlanRtId = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Case'
            AND DeveloperName = 'CarePlan'
            LIMIT 1
        ].Id;
    Case current = [
        SELECT Id, AccountId, CreatedDate
        FROM Case
        WHERE Id = :carePlanId
        LIMIT 1
    ];

    Case latest = [
        SELECT Id
        FROM Case
        WHERE AccountId = :current.AccountId
        AND RecordTypeId = :carePlanRtId
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    return latest.Id == carePlanId;
}


     /*Ganesh save code*/
    @AuraEnabled
public static SaveResult saveCarePlan(String carePlanDataJson, Id accountId, String accountName,String carePlanSuffix, Id carePlanId) {
    SaveResult result = new SaveResult();
    Savepoint sp = Database.setSavepoint();

    try {
         //🔐 BLOCK EDIT IF NOT LATEST
        if (carePlanId != null && !isLatestCarePlan(carePlanId)) {
            result.success = false;
            result.message = 'Only the latest Care Plan can be edited. Please edit the most recent Care Plan.';
            return result;
        }
        CarePlanDataWrapper carePlanData =
            (CarePlanDataWrapper) JSON.deserialize(carePlanDataJson, CarePlanDataWrapper.class);

        /* ================= CASE (CARE PLAN) ================= */

      
        Case carePlan;
String fullSubject = String.isNotBlank(carePlanSuffix)
    ? accountName + ' ' + carePlanSuffix
    : accountName;

if (carePlanId != null) {
    carePlan = [
        SELECT Id,AccountId, Account.Is_Deactivated__c, Description, Start_Date__c, Review_Date__c, How_Often_We_re_Seeing_the_Client__c,
    Anticipated_Duration_Months__c, 
    Anticipated_Hours_per_Week__c,
    Quarterly_Goal_Status__c, Overall_Client_Stability_This_Quarter__c,
    Outcome_Summary__c, Plan_Adjustment__c
        FROM Case
        WHERE Id = :carePlanId
        LIMIT 1
    ];
    if (carePlan.AccountId != null && carePlan.Account.Is_Deactivated__c) {
    result.success = false;
    result.message = 'Account is deactivated. Care Plan editing is not allowed.';
    return result;
}

    if (String.isNotBlank(accountName)) {
        carePlan.Subject = fullSubject;
    }
    carePlan.Careplan_Suffix__c = carePlanSuffix;
} else {
    Integer len = accountName.length();
    carePlan = new Case(
        AccountId = accountId,
        Subject = String.isNotBlank(accountName)
            ? fullSubject
            : 'Well Spring Care Plan - ' + Date.today(),
        Status = 'New',
        Origin = 'Web',
        Type = 'Care Plan',
        Priority = 'Medium',
        Sequence_Number__c = accountName.substring(len - 4, len),
        Careplan_Suffix__c = carePlanSuffix
    );
    List<RecordType> carePlanRts = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Case'
        AND DeveloperName = 'CarePlan'
        LIMIT 1
    ];
    if (!carePlanRts.isEmpty()) {
        carePlan.RecordTypeId = carePlanRts[0].Id;
    }
}

        
        if (carePlanData.schedule != null) {
    if (String.isNotBlank(carePlanData.schedule.startDate)) {
        carePlan.Start_Date__c = Date.valueOf(carePlanData.schedule.startDate);
    }
    if (String.isNotBlank(carePlanData.schedule.reviewDate)) {
        carePlan.Review_Date__c = Date.valueOf(carePlanData.schedule.reviewDate);
    }
    carePlan.How_Often_We_re_Seeing_the_Client__c = carePlanData.schedule.frequency;
    
    if (String.isNotBlank(carePlanData.schedule.duration)) {
        carePlan.Anticipated_Duration_Months__c = carePlanData.schedule.duration;
    }
    if (String.isNotBlank(carePlanData.schedule.hoursPerWeek)) {
        carePlan.Anticipated_Hours_per_Week__c = Integer.valueOf(carePlanData.schedule.hoursPerWeek);
    }
}

    // Save Client Impact Review fields
if (carePlanData.clientImpact != null) {
    carePlan.Quarterly_Goal_Status__c = carePlanData.clientImpact.quarterlyGoalStatus;
    carePlan.Overall_Client_Stability_This_Quarter__c = carePlanData.clientImpact.clientStability;
    carePlan.Outcome_Summary__c = carePlanData.clientImpact.outcomeSummary;
    carePlan.Plan_Adjustment__c = carePlanData.clientImpact.planAdjustment;
}

        upsert carePlan;
        result.carePlanId = carePlan.Id;

       /* ================= PROBLEMS ================= */



/* ================= PROBLEMS ================= */

List<HealthCloudGA__CarePlanProblem__c> problemInsert =
    new List<HealthCloudGA__CarePlanProblem__c>();
List<HealthCloudGA__CarePlanProblem__c> problemUpdate =
    new List<HealthCloudGA__CarePlanProblem__c>();

if (carePlanData.problems != null) {
    for (ProblemBlockWrapper p : carePlanData.problems) {
        // ⭐ Check if it's a valid Salesforce ID (starts with valid prefix and right length)
        Boolean isExistingRecord = p.id != null 
            && p.id.length() == 18 
            && p.id.startsWith('a0A');
        
        if (isExistingRecord) {
            // UPDATE existing
            problemUpdate.add(new HealthCloudGA__CarePlanProblem__c(
                Id = (Id)p.id,
                Name = p.selectedName,
                HealthCloudGA__Priority__c = p.severity,
                //HealthCloudGA__Description__c = p.description,
                Problem_Description__c = p.description,
                isCustom__c = p.isCustom == true
            ));
        } else {
            // INSERT new (either null or temp ID)
            problemInsert.add(new HealthCloudGA__CarePlanProblem__c(
                HealthCloudGA__CarePlan__c = carePlan.Id,
                Name = p.selectedName,
                HealthCloudGA__Priority__c = p.severity,
                //HealthCloudGA__Description__c = p.description,
                Problem_Description__c =  p.description,
                isCustom__c = p.isCustom == true
            ));
        }
    }
}

if (!problemInsert.isEmpty()) insert problemInsert;
if (!problemUpdate.isEmpty()) update problemUpdate;

// ================= PROBLEMS – DELETE =================

// Fetch existing problems for this Care Plan
Map<Id, HealthCloudGA__CarePlanProblem__c> existingProblems = new Map<Id, HealthCloudGA__CarePlanProblem__c>();
for (HealthCloudGA__CarePlanProblem__c p : [
    SELECT Id
    FROM HealthCloudGA__CarePlanProblem__c
    WHERE HealthCloudGA__CarePlan__c = :carePlan.Id
]) {
    existingProblems.put(p.Id, p);
}

// Collect problem IDs sent from UI
Set<Id> activeProblemIds = new Set<Id>();
for (ProblemBlockWrapper p : carePlanData.problems) {
    if (p.id != null && p.id.length() == 18) {
        activeProblemIds.add((Id)p.id);
    }
}
// ⭐ ADD newly inserted problem IDs so they don't get deleted
for (HealthCloudGA__CarePlanProblem__c p : problemInsert) {
    activeProblemIds.add(p.Id);
}

// Identify deleted problems
List<HealthCloudGA__CarePlanProblem__c> problemsToDelete = new List<HealthCloudGA__CarePlanProblem__c>();
for (Id existingId : existingProblems.keySet()) {
    if (!activeProblemIds.contains(existingId)) {
        problemsToDelete.add(existingProblems.get(existingId));
    }
}

// Delete removed problems
if (!problemsToDelete.isEmpty()) {
    delete problemsToDelete;
}





List<HealthCloudGA__CarePlanGoal__c> goalInsert =
    new List<HealthCloudGA__CarePlanGoal__c>();
List<HealthCloudGA__CarePlanGoal__c> goalUpdate =
    new List<HealthCloudGA__CarePlanGoal__c>();

// Long Term Goals
if (carePlanData.longTermGoals != null) {
    for (GoalBlockWrapper g : carePlanData.longTermGoals) {
        // ⭐ Check if it's a valid Salesforce ID (18 chars + starts with 'a09')
        Boolean isExistingRecord = g.id != null 
            && g.id.length() == 18 
            && g.id.startsWith('a09');
        
        if (isExistingRecord) {
            // UPDATE existing
            goalUpdate.add(new HealthCloudGA__CarePlanGoal__c(
                Id = (Id)g.id,
                Name = g.selectedName,
                HealthCloudGA__Description__c = g.description,
                Goal_Category__c = g.category,
                Success_Criteria__c = g.successCriteria,
                Goal_Type__c = 'Long Term',
                isCustom__c = g.isCustom == true
            ));
        } else {
            // INSERT new (either null or temp ID)
            goalInsert.add(new HealthCloudGA__CarePlanGoal__c(
                Case__c = carePlan.Id,
                Name = g.selectedName,
                HealthCloudGA__Description__c = g.description,
                Goal_Category__c = g.category,
                Success_Criteria__c = g.successCriteria,
                Goal_Type__c = 'Long Term',
                isCustom__c = g.isCustom == true
            ));
        }
    }
}

// Quarterly Goals
if (carePlanData.quarterlyGoals != null) {
    for (GoalBlockWrapper g : carePlanData.quarterlyGoals) {
        // ⭐ Check if it's a valid Salesforce ID (18 chars + starts with 'a09')
        Boolean isExistingRecord = g.id != null 
            && g.id.length() == 18 
            && g.id.startsWith('a09');
        
        if (isExistingRecord) {
            // UPDATE existing
            goalUpdate.add(new HealthCloudGA__CarePlanGoal__c(
                Id = (Id)g.id,
                Name = g.selectedName,
                HealthCloudGA__Description__c = g.description,
                Goal_Category__c = g.category,
                Success_Criteria__c = g.successCriteria,
                Goal_Type__c = 'Quarterly',
                isCustom__c = g.isCustom == true
            ));
        } else {
            // INSERT new (either null or temp ID)
            goalInsert.add(new HealthCloudGA__CarePlanGoal__c(
                Case__c = carePlan.Id,
                Name = g.selectedName,
                HealthCloudGA__Description__c = g.description,
                Goal_Category__c = g.category,
                Success_Criteria__c = g.successCriteria,
                Goal_Type__c = 'Quarterly',
                isCustom__c = g.isCustom == true
            ));
        }
    }
}

if (!goalInsert.isEmpty()) insert goalInsert;
if (!goalUpdate.isEmpty()) update goalUpdate;

// ================= LONG TERM GOALS – DELETE =================

// Fetch existing Long Term Goals for this Care Plan
Map<Id, HealthCloudGA__CarePlanGoal__c> existingLongTermGoals = new Map<Id, HealthCloudGA__CarePlanGoal__c>();
for (HealthCloudGA__CarePlanGoal__c g : [
    SELECT Id
    FROM HealthCloudGA__CarePlanGoal__c
    WHERE Case__c = :carePlan.Id
    AND Goal_Type__c = 'Long Term'
]) {
    existingLongTermGoals.put(g.Id, g);
}

// Collect Long Term Goal IDs sent from UI
Set<Id> activeLongTermGoalIds = new Set<Id>();
for (GoalBlockWrapper g : carePlanData.longTermGoals) {
    if (g.id != null && g.id.length() == 18) {
        activeLongTermGoalIds.add((Id) g.id);
    }
}
// ⭐ ADD newly inserted goal IDs so they don't get deleted
for (HealthCloudGA__CarePlanGoal__c g : goalInsert) {
    if (g.Goal_Type__c == 'Long Term') {
        activeLongTermGoalIds.add(g.Id);
    }
}

// Identify deleted Long Term Goals
List<HealthCloudGA__CarePlanGoal__c> longTermGoalsToDelete = new List<HealthCloudGA__CarePlanGoal__c>();
for (Id existingId : existingLongTermGoals.keySet()) {
    if (!activeLongTermGoalIds.contains(existingId)) {
        longTermGoalsToDelete.add(existingLongTermGoals.get(existingId));
    }
}

// Delete removed Long Term Goals
if (!longTermGoalsToDelete.isEmpty()) {
    delete longTermGoalsToDelete;
}

// ================= QUARTERLY GOALS – DELETE =================

// Fetch existing Quarterly Goals for this Care Plan
Map<Id, HealthCloudGA__CarePlanGoal__c> existingQuarterlyGoals = new Map<Id, HealthCloudGA__CarePlanGoal__c>();
for (HealthCloudGA__CarePlanGoal__c g : [
    SELECT Id
    FROM HealthCloudGA__CarePlanGoal__c
    WHERE Case__c = :carePlan.Id
    AND Goal_Type__c = 'Quarterly'
]) {
    existingQuarterlyGoals.put(g.Id, g);
}

// Collect Quarterly Goal IDs sent from UI
Set<Id> activeQuarterlyGoalIds = new Set<Id>();
for (GoalBlockWrapper g : carePlanData.quarterlyGoals) {
    if (g.id != null && g.id.length() == 18) {
        activeQuarterlyGoalIds.add((Id) g.id);
    }
}
// ⭐ ADD newly inserted goal IDs so they don't get deleted
for (HealthCloudGA__CarePlanGoal__c g : goalInsert) {
    if (g.Goal_Type__c == 'Quarterly') {
        activeQuarterlyGoalIds.add(g.Id);
    }
}
// Identify deleted Quarterly Goals
List<HealthCloudGA__CarePlanGoal__c> quarterlyGoalsToDelete = new List<HealthCloudGA__CarePlanGoal__c>();
for (Id existingId : existingQuarterlyGoals.keySet()) {
    if (!activeQuarterlyGoalIds.contains(existingId)) {
        quarterlyGoalsToDelete.add(existingQuarterlyGoals.get(existingId));
    }
}

// Delete removed Quarterly Goals
if (!quarterlyGoalsToDelete.isEmpty()) {
    delete quarterlyGoalsToDelete;
}



       /* ================= INTERVENTIONS ================= */






/* ================= INTERVENTIONS ================= */

List<Care_Plan_Intervention__c> interventionInsert =
    new List<Care_Plan_Intervention__c>();
List<Care_Plan_Intervention__c> interventionUpdate =
    new List<Care_Plan_Intervention__c>();

if (carePlanData.quarterlyGoals != null) {
    for (GoalBlockWrapper g : carePlanData.quarterlyGoals) {
        if (g.interventions == null) continue;

        for (InterventionWrapper i : g.interventions) {
            // ⭐ Check if it's a valid Salesforce ID (18 chars + starts with 'a1Y')
            Boolean isExistingRecord = i.id != null 
                && i.id.length() == 18 
                && !i.id.startsWith('temp-');
                //&& i.id.startsWith('a1Y');
            
            if (isExistingRecord) {
                // UPDATE existing
                interventionUpdate.add(new Care_Plan_Intervention__c(
                    Id = (Id)i.id,
                    Name = i.selectedName,
                    Care_Plan_Intervention_Category__c = i.category,
                    Care_Plan_Int_Specific_Intervention__c = i.specificIntervention,
                    Care_Plan_Intervention_Frequency__c = i.frequency,
                    Care_Plan_Int_Duration_Optional__c = i.duration,
                    Care_Plan_Intervention_Details__c = i.details,
                    isCustom__c = i.isCustom == true

                ));
            } else {
                // INSERT new (either null or temp ID)
                interventionInsert.add(new Care_Plan_Intervention__c(
                    Case__c = carePlan.Id,
                    Name = i.selectedName,
                    Care_Plan_Intervention_Category__c = i.category,
                    Care_Plan_Int_Specific_Intervention__c = i.specificIntervention,
                    Care_Plan_Intervention_Frequency__c = i.frequency,
                    Care_Plan_Int_Duration_Optional__c = i.duration,
                    Care_Plan_Intervention_Details__c = i.details,
                    isCustom__c = i.isCustom == true
                ));
            }
        }
    }
}

if (!interventionInsert.isEmpty()) insert interventionInsert;
if (!interventionUpdate.isEmpty()) update interventionUpdate;

// ================= INTERVENTIONS – DELETE =================

// Fetch existing interventions for this Care Plan
Map<Id, Care_Plan_Intervention__c> existingInterventions = new Map<Id, Care_Plan_Intervention__c>();
for (Care_Plan_Intervention__c inv : [
    SELECT Id
    FROM Care_Plan_Intervention__c
    WHERE Case__c = :carePlan.Id
]) {
    existingInterventions.put(inv.Id, inv);
}

// Collect intervention IDs sent from UI
Set<Id> activeInterventionIds = new Set<Id>();
if (carePlanData.quarterlyGoals != null) {
    for (GoalBlockWrapper g : carePlanData.quarterlyGoals) {
        if (g.interventions == null) continue;
        for (InterventionWrapper i : g.interventions) {
            if (i.id != null && i.id.length() == 18) {
                try {
                    activeInterventionIds.add((Id) i.id);
                } catch (Exception e) {
                    // Not a valid SF ID — skip
                }
            }
        }
    }
}
// Add newly inserted intervention IDs so they don't get deleted
for (Care_Plan_Intervention__c inv : interventionInsert) {
    activeInterventionIds.add(inv.Id);
}

// Identify deleted interventions
List<Care_Plan_Intervention__c> interventionsToDelete = new List<Care_Plan_Intervention__c>();
for (Id existingId : existingInterventions.keySet()) {
    if (!activeInterventionIds.contains(existingId)) {
        interventionsToDelete.add(existingInterventions.get(existingId));
    }
}

// Delete removed interventions
if (!interventionsToDelete.isEmpty()) {
    delete interventionsToDelete;
}
/* ================= STAKEHOLDERS ================= */

List<Care_Plan_Stakeholders__c> stakeholderInsert =
    new List<Care_Plan_Stakeholders__c>();
List<Care_Plan_Stakeholders__c> stakeholderUpdate =
    new List<Care_Plan_Stakeholders__c>();

if (carePlanData.stakeholders != null) {
   
    for (StakeholderWrapper s : carePlanData.stakeholders) {

    if (s.isNew == true) {
        stakeholderInsert.add(new Care_Plan_Stakeholders__c(
            Case__c = carePlan.Id,
            Name = s.contactName,
            Stake_Holder_Type__c = s.stakeholderType,
            Role_in_Care__c = s.roleInCare,
            Communication_Preference__c = s.communicationPreference,
            How_Often_to_Communicate__c = s.communicationFrequency
        ));
    } else {
        stakeholderUpdate.add(new Care_Plan_Stakeholders__c(
            Id = (Id)s.id,
            Name = s.contactName,
            Stake_Holder_Type__c = s.stakeholderType,
            Role_in_Care__c = s.roleInCare,
            Communication_Preference__c = s.communicationPreference,
            How_Often_to_Communicate__c = s.communicationFrequency
        ));
    }
}

}

if (!stakeholderInsert.isEmpty()) insert stakeholderInsert;
if (!stakeholderUpdate.isEmpty()) update stakeholderUpdate;

/* ================= STAKEHOLDERS - DELETE REMOVED ================= */

// Existing stakeholders on this care plan
Map<Id, Care_Plan_Stakeholders__c> existingStakeholders = new Map<Id, Care_Plan_Stakeholders__c>(
    [SELECT Id FROM Care_Plan_Stakeholders__c WHERE Case__c = :carePlan.Id]
);

// IDs still present in UI payload
Set<Id> activeStakeholderIds = new Set<Id>();
if (carePlanData.stakeholders != null) {
    for (StakeholderWrapper s : carePlanData.stakeholders) {
        if (String.isNotBlank(s.id)
            && !s.id.startsWith('temp-')
            && (s.id.length() == 15 || s.id.length() == 18)) {
            activeStakeholderIds.add((Id)s.id);
        }
    }
}

// keep newly inserted rows too
for (Care_Plan_Stakeholders__c sRec : stakeholderInsert) {
    activeStakeholderIds.add(sRec.Id);
}

// delete rows removed in UI
List<Care_Plan_Stakeholders__c> stakeholdersToDelete = new List<Care_Plan_Stakeholders__c>();
for (Id existingId : existingStakeholders.keySet()) {
    if (!activeStakeholderIds.contains(existingId)) {
        stakeholdersToDelete.add(existingStakeholders.get(existingId));
    }
}
if (!stakeholdersToDelete.isEmpty()) {
    delete stakeholdersToDelete;
}


/* ================= CARE PLAN USERS (JUNCTION) ================= */





/* ================= CARE PLAN CONTACT (JUNCTION) ================= */

List<Care_Plan_Contact__c> toInsert = new List<Care_Plan_Contact__c>();
Set<Id> seenContacts = new Set<Id>();

for (StakeholderWrapper sw : carePlanData.stakeholders) {
    if (sw.contactId == null) continue;

    if (seenContacts.contains(sw.contactId)) {
        result.success = false;
        result.message = 'Duplicate contacts are not allowed in the same Care Plan.';
        return result;
    }
    seenContacts.add(sw.contactId);

    toInsert.add(new Care_Plan_Contact__c(
        Case__c = carePlan.Id,
        Contact__c = sw.contactId
       
    ));
}

// Replace all existing case-contact junctions on each save
delete [SELECT Id FROM Care_Plan_Contact__c WHERE Case__c = :carePlan.Id];

if (!toInsert.isEmpty()) insert toInsert;



        result.pdfContentDocumentId = generateAndSavePDF(carePlan.Id, carePlanData);
        result.success = true;
        result.message = 'Care Plan updated successfully';

    } catch (Exception e) {
        Database.rollback(sp);
        result.success = false;
        result.message = e.getMessage();
    }

    return result;
}


    
   

    
    // =================== PDF GENERATION METHODS ===================
    
    private static Id generateAndSavePDF(Id carePlanId, CarePlanDataWrapper carePlanData) {
        try {
            // ⭐ DELETE OLD PDFs BEFORE CREATING NEW ONE
            try {
                List<ContentDocumentLink> oldPdfLinks = [
                    SELECT ContentDocumentId 
                    FROM ContentDocumentLink 
                    WHERE LinkedEntityId = :carePlanId
                ];
                
                if (!oldPdfLinks.isEmpty()) {
                    // Collect all ContentDocumentIds to delete
                    Set<Id> docIds = new Set<Id>();
                    for (ContentDocumentLink cdl : oldPdfLinks) {
                        docIds.add(cdl.ContentDocumentId);
                    }
                    
                    // Delete old ContentDocumentLinks first
                    delete oldPdfLinks;
                    
                    // Delete old ContentDocuments with error handling
                    List<ContentDocument> docsToDelete = [
                        SELECT Id 
                        FROM ContentDocument 
                        WHERE Id IN :docIds
                    ];
                    
                    if (!docsToDelete.isEmpty()) {
                        Database.delete(docsToDelete, false); // false = continue on error
                    }
                    
                    System.debug('Old PDFs deleted successfully');
                }
            } catch (Exception deleteEx) {
                System.debug('Warning: Could not delete old PDFs: ' + deleteEx.getMessage());
                // Continue with PDF generation even if deletion fails
            }
            
            String pdfContent = generatePDFContent(carePlanData);
            
            // Generate PDF as blob
            Blob pdfBlob = Blob.toPdf(pdfContent);
            
            // Create ContentVersion
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Care Plan - ' + System.now().format('yyyy-MM-dd HH:mm:ss');
            cv.PathOnClient = 'CarePlan_' + System.now().format('yyyyMMdd_HHmmss_SSS') + '.pdf';
            cv.VersionData = pdfBlob;
            cv.IsMajorVersion = true;
            insert cv;
            
            // Get ContentDocumentId
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            
            // Link to Care Plan record
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = cv.ContentDocumentId;
            cdl.LinkedEntityId = carePlanId;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            insert cdl;
            
            System.debug('New PDF created and linked successfully');
            return cv.ContentDocumentId;
            
        } catch (Exception e) {
            System.debug('Error generating PDF: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
            return null;
        }
    }

    private static String generatePDFContent(CarePlanDataWrapper carePlanData) {
        System.debug('Generating PDF Content');
        System.debug('CarePlanData: ' + carePlanData);

        String html = '<html><body style="font-family: Arial, sans-serif; font-size: 12px;">';

        html += '<table width="100%" cellpadding="0" cellspacing="0">';
        html += '<tr><td style="font-size:22px; color:#0176d3; font-weight:bold; border-bottom:3px solid #0176d3; padding-bottom:10px;">';
        html += 'WellSpring Care Plan</td></tr>';
        html += '<tr><td height="10"></td></tr>';
        html += '<tr><td><b>Generated:</b> ' + System.now().format('MMMM dd, yyyy hh:mm a') + '</td></tr>';
        html += '<tr><td height="20"></td></tr>';
        html += '</table>';

        /* ================= PROBLEMS ================= */
        if (carePlanData.problems != null && !carePlanData.problems.isEmpty()) {
            html += sectionHeader('Care Plan Problems');
            for (ProblemBlockWrapper problem : carePlanData.problems) {
                //html += titleBlock(problem.selectedName, '#f0f9ff', '#0176d3');
                html += spacer(12);
                html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
                html += '<tr><td width="30%"><b>Problem Name</b></td><td>' + safe(problem.selectedName) + '</td></tr>';
                html += '<tr><td width="30%"><b>Priority</b></td><td>' + safe(problem.severity) + '</td></tr>';
                html += '<tr><td><b>Description</b></td><td>' + safe(problem.description) + '</td></tr>';
                html += '</table>';
                html += spacer(20);
            }
        }

        /* ================= LONG TERM GOALS ================= */
        if (carePlanData.longTermGoals != null && !carePlanData.longTermGoals.isEmpty()) {
            html += sectionHeader('Long Term Goals');
            for (GoalBlockWrapper goal : carePlanData.longTermGoals) {
                //html += titleBlock(goal.selectedName, '#f0f9ff', '#0176d3');
                html += spacer(12);
                html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
                html += '<tr><td width="30%"><b>Long Term Goal Name</b></td><td>' + safe(goal.selectedName) + '</td></tr>';
                html += '<tr><td><b>Description</b></td><td>' + safe(goal.description) + '</td></tr>';
                html += '<tr><td><b>Success Criteria</b></td><td>' + safe(goal.successCriteria) + '</td></tr>';
                html += '</table>';
                html += spacer(20);
            }
        }

        /* ================= QUARTERLY GOALS ================= */
        if (carePlanData.quarterlyGoals != null && !carePlanData.quarterlyGoals.isEmpty()) {
            html += sectionHeader('Quarterly Goals & Interventions');
            for (GoalBlockWrapper goal : carePlanData.quarterlyGoals) {
                //html += titleBlock(goal.selectedName, '#f0f9ff', '#0176d3');
                html += spacer(12);
                html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
                html += '<tr><td width="30%"><b>Quarterly Goal Name</b></td><td>' + safe(goal.selectedName) + '</td></tr>';
                html += '<tr><td><b>Description</b></td><td>' + safe(goal.description) + '</td></tr>';
                html += '<tr><td><b>Success Criteria</b></td><td>' + safe(goal.successCriteria) + '</td></tr>';
                html += '</table>';
                html += spacer(16);
                
                if (goal.interventions != null && !goal.interventions.isEmpty()) {
                    html += '<table width="100%" cellpadding="0" cellspacing="0">';
                    html += '<tr><td style="font-size:14px; font-weight:bold; color:#014486;">Interventions</td></tr>';
                    html += '<tr><td height="10"></td></tr>';
                    html += '</table>';
                    
                    for (InterventionWrapper intv : goal.interventions) {
                        // html += '<table width="100%" cellpadding="8" cellspacing="0" style="border-collapse:collapse; border:1px solid #000;">';
                        // html += '<tr><td width="30%"><b>Intervention Name</b></td><td>' + safe(intv.selectedName) + '</td></tr>';
                        // html += '</table>';
                        html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
                        html += '<tr>';
                        html += '<td width="30%" style="border:1px solid #000;"><b>Intervention Name</b></td>';
                        html += '<td style="border:1px solid #000;">' + safe(intv.selectedName) + '</td>';
                        html += '</tr>';
                        html += '</table>';
                        html += spacer(12);
                        html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
                        html += '<tr><td><b>Frequency</b></td><td>' + safe(intv.frequency) + '</td></tr>';
                        html += '<tr><td><b>Duration</b></td><td>' + safe(intv.duration) + '</td></tr>';
                        html += '<tr><td><b>Details</b></td><td>' + safe(intv.details) + '</td></tr>';
                        html += '</table>';
                        html += spacer(20);
                    }
                }
            }
        }

        /* ================= STAKEHOLDERS ================= */
        if (carePlanData.stakeholders != null && !carePlanData.stakeholders.isEmpty()) {
            html += sectionHeader('Stakeholders to Engage');
            html += spacer(12);
            Map<Id, String> stakeholderContactNamesById = getStakeholderContactNameMap(carePlanData);
            for (StakeholderWrapper stakeholder : carePlanData.stakeholders) {
                html += spacer(12);
                html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
                //html += '<tr><td width="30%"><b>Contact Name</b></td><td>' + safe(stakeholder.contactName) + '</td></tr>';
                html += '<tr><td width="30%"><b>Contact Name</b></td><td>' +
                safe(stakeholder.contactId != null && stakeholderContactNamesById.containsKey(stakeholder.contactId)
                    ? stakeholderContactNamesById.get(stakeholder.contactId)
                    : stakeholder.contactName) +
                '</td></tr>';
                html += '<tr><td width="30%"><b>Type</b></td><td>' + safe(stakeholder.stakeholderType) + '</td></tr>';
                html += '<tr><td><b>Role in Care</b></td><td>' + safe(stakeholder.roleInCare) + '</td></tr>';
                //html += '<tr><td><b>Communication Preference</b></td><td>' + safe(stakeholder.communicationPreference) + '</td></tr>';
                //html += '<tr><td><b>Communication Frequency</b></td><td>' + safe(stakeholder.communicationFrequency) + '</td></tr>';
                html += '</table>';
                html += spacer(20);
            }
        }

        /* ================= SCHEDULE ================= */
        if (carePlanData.schedule != null) {
            html += sectionHeader('Schedule');
            html += spacer(20);
            html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
            html += '<tr><td width="30%"><b>Start Date</b></td><td>' + formatDateForPdf(carePlanData.schedule.startDate) + '</td></tr>';
            html += '<tr><td><b>Review Date</b></td><td>' + formatDateForPdf(carePlanData.schedule.reviewDate) + '</td></tr>';
            //html += '<tr><td width="30%"><b>Start Date</b></td><td>' + safe(carePlanData.schedule.startDate) + '</td></tr>';
            //html += '<tr><td><b>Review Date</b></td><td>' + safe(carePlanData.schedule.reviewDate) + '</td></tr>';
            html += '<tr><td><b>How Often Seeing Client</b></td><td>' + safe(carePlanData.schedule.frequency) + '</td></tr>';
            html += '<tr><td><b>Anticipated Duration</b></td><td>' + safe(carePlanData.schedule.duration) + '</td></tr>';
            html += '<tr><td><b>Hours per Week</b></td><td>' + safe(carePlanData.schedule.hoursPerWeek) + '</td></tr>';
            html += '</table>';
            html += spacer(20);
        }

        /* ================= CLIENT IMPACT REVIEW ================= */
            if (carePlanData.clientImpact != null) {
                html += sectionHeader('Client Impact Review');
                html += spacer(20);
                html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
                html += '<tr><td width="30%"><b>Quarterly Goal Status</b></td><td>' + safe(carePlanData.clientImpact.quarterlyGoalStatus) + '</td></tr>';
                html += '<tr><td><b>Overall Client Stability This Quarter</b></td><td>' + safe(carePlanData.clientImpact.clientStability) + '</td></tr>';
                html += '<tr><td><b>Plan Adjustment</b></td><td>' + safe(carePlanData.clientImpact.planAdjustment) + '</td></tr>';
                html += '<tr><td><b>Outcome Summary</b></td><td>' + safe(carePlanData.clientImpact.outcomeSummary) + '</td></tr>';
                
                html += '</table>';
                html += spacer(20);
            }

        html += '</body></html>';
        return html;
    }

    private static String spacer(Integer h) {
        return '<table width="100%" cellpadding="0" cellspacing="0"><tr><td height="' + h + '"></td></tr></table>';
    }

    private static String sectionHeader(String title) {
        return '<table width="100%" cellpadding="0" cellspacing="0">' +
               '<tr><td style="font-size:18px; color:#014486; font-weight:bold; border-bottom:2px solid #ccc; padding-bottom:5px;">'
               + title + '</td></tr>' +
               '<tr><td height="24"></td></tr></table>';
    }

    private static String titleBlock(String text, String bg, String border) {
        return '<table width="100%" cellpadding="8" cellspacing="0" style="background:' + bg +
               '; border-left:4px solid ' + border + ';">' +
               '<tr><td><b>' + text + '</b></td></tr></table>';
    }

    private static Map<Id, String> getStakeholderContactNameMap(CarePlanDataWrapper carePlanData) {
    Map<Id, String> contactNamesById = new Map<Id, String>();
    Set<Id> contactIds = new Set<Id>();

    if (carePlanData != null && carePlanData.stakeholders != null) {
        for (StakeholderWrapper stakeholder : carePlanData.stakeholders) {
            if (stakeholder != null && stakeholder.contactId != null) {
                contactIds.add(stakeholder.contactId);
            }
        }
    }

    if (contactIds.isEmpty()) return contactNamesById;

    for (Contact c : [SELECT Id, Name FROM Contact WHERE Id IN :contactIds]) {
        contactNamesById.put(c.Id, c.Name);
    }
    return contactNamesById;
}
	@TestVisible
    private static String formatDateForPdf(String rawDate) {
    if (String.isBlank(rawDate)) return '-';
    try {
        Date d = Date.valueOf(rawDate);
        Datetime dt = Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        return dt.format('MMM dd, yyyy');
    } catch (Exception e) {
        return safe(rawDate);
    }
}


    private static String safe(String val) {
        return String.isBlank(val) ? '-' : val;
    }
    
}