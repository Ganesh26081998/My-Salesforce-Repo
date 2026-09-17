/*
----------------------------------------------------------------------------
Author         : Ganesh Uppin
Class Name     : HealthCloudCarePlanController
CreatedOn      : 13-01-2026
LastModifiedOn : 20-05-2026
LastModifiedBy : Ganesh Uppin

Description    : This class is used to manage Care Plan creation
                 retrieval, and PDF generation functionality in Health Cloud.
                 It handles Problems, Goals, Interventions, Stakeholders,
                 Schedule details, and generates Care Plan PDF documents.
----------------------------------------------------------------------------
*/
public with sharing class HealthCloudCarePlanController {
    
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
        @AuraEnabled public String caseSubject;
        @AuraEnabled public String carePlanSuffix;
        @AuraEnabled public List<ProblemBlockWrapper> problems;
        @AuraEnabled public List<GoalBlockWrapper> longTermGoals;
        @AuraEnabled public List<GoalBlockWrapper> quarterlyGoals;
        @AuraEnabled public List<StakeholderWrapper> stakeholders;
        @AuraEnabled public ScheduleWrapper schedule;
        @AuraEnabled public String sequenceNumber;
        @AuraEnabled public String accountName;
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
        @AuraEnabled public String duration;
        @AuraEnabled public String details;
        @AuraEnabled public Boolean isCustom;
    }
    
    public class StakeholderWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String stakeholderType;
        @AuraEnabled public String contactName;
        //@AuraEnabled public Id userId; 
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
    public class ContactOptionWrapper {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
}

@AuraEnabled(cacheable=true)
public static List<ContactOptionWrapper> getStakeholderContactsFromCCR(Id accountId) {
    List<ContactOptionWrapper> out = new List<ContactOptionWrapper>();
    if (accountId == null) return out;

    Set<Id> seen = new Set<Id>();

    for (HealthCloudGA__ContactContactRelation__c rel : [
        SELECT HealthCloudGA__RelatedContact__c,
               HealthCloudGA__RelatedContact__r.Name
        FROM HealthCloudGA__ContactContactRelation__c
        WHERE HealthCloudGA__Contact__r.AccountId = :accountId
          AND HealthCloudGA__RelatedContact__c != null
        ORDER BY HealthCloudGA__RelatedContact__r.Name
    ]) {
        if (!seen.contains(rel.HealthCloudGA__RelatedContact__c)) {
            seen.add(rel.HealthCloudGA__RelatedContact__c);

            ContactOptionWrapper row = new ContactOptionWrapper();
            row.value = rel.HealthCloudGA__RelatedContact__c;
            row.label = rel.HealthCloudGA__RelatedContact__r.Name;
            out.add(row);
        }
    }
    return out;
}
    
    @AuraEnabled(cacheable=true)
    public static CarePlanResponseWrapper fetchAllCarePlanData() {
        CarePlanResponseWrapper res = new CarePlanResponseWrapper();
        res.problems = new List<CarePlanProblemWrapper>();
        res.goals = new List<CarePlanGoalWrapper>();
        
        
        for (HealthCloudGA__CarePlanTemplateProblem__c p : [
            SELECT Id, Name FROM HealthCloudGA__CarePlanTemplateProblem__c
            WHERE Deactivate__c = false
        ]) {
            CarePlanProblemWrapper pw = new CarePlanProblemWrapper();
            pw.problemId = p.Id;
            pw.problemName = p.Name;
            res.problems.add(pw);
        }
        
        for (HealthCloudGA__CarePlanTemplateGoal__c g : [
            SELECT Id, Name, Type__c,
                (SELECT Id, Name, HealthCloudGA__Description__c
                 FROM HealthCloudGA__CarePlanTemplateTasks__r
                 WHERE Deactivate__c = false)
            FROM HealthCloudGA__CarePlanTemplateGoal__c
            WHERE Deactivate__c = false]){
            CarePlanGoalWrapper gw = new CarePlanGoalWrapper();
            gw.goalId = g.Id;
            gw.goalName = g.Name;
            gw.type = g.Type__c;
            gw.tasks = new List<CarePlanTaskWrapper>();
            for (HealthCloudGA__CarePlanTemplateTask__c t :
                 g.HealthCloudGA__CarePlanTemplateTasks__r) {
                CarePlanTaskWrapper tw = new CarePlanTaskWrapper();
                tw.taskId = t.Id;
                tw.taskName = t.Name;
                tw.taskDescription = t.HealthCloudGA__Description__c;
                gw.tasks.add(tw);
            }
            res.goals.add(gw);
        }
        
        return res;
    }
    
    /*Shubham bro's save code*/
     @AuraEnabled
    public static SaveResult saveCarePlan(String carePlanDataJson, String accountId, String accountName,String carePlanSuffix,String carePlanId) {
        SaveResult result = new SaveResult();
        result.success = false;
        //Boolean isNewCarePlan = String.isBlank(carePlanId);
        
        Savepoint sp = Database.setSavepoint();
        
        try {
            CarePlanDataWrapper carePlanData = (CarePlanDataWrapper) JSON.deserialize(
                carePlanDataJson, 
                CarePlanDataWrapper.class
            );
            
            // Create or Update Care Plan record using Case object
            Case carePlan;
            
            if (carePlanId != null) {
                carePlan = [SELECT Id FROM Case WHERE Id = :carePlanId LIMIT 1];
            } else {
                carePlan = new Case();
                // Set Subject from prefix + suffix
    if (String.isNotBlank(accountName)) {
        String fullSubject = accountName;
        if (String.isNotBlank(carePlanSuffix)) {
            fullSubject += ' ' + carePlanSuffix;
        }
        carePlan.Subject = fullSubject;
        carePlan.Careplan_Suffix__c = carePlanSuffix;
        // Extract sequence number (last 4 chars of the PREFIX, e.g., "0001" from "Name - CP 0001")
        Integer len = accountName.length();
        carePlan.Sequence_Number__c = accountName.substring(len - 4, len);
        System.debug('Sequence Number----' + carePlan.Sequence_Number__c);
    } else {
        carePlan.Subject = 'Well Spring Care Plan - ' + System.now().format('yyyy-MM-dd');
    }
                
                // Link to Account
                if (accountId != null) {
                    carePlan.AccountId = accountId;
                }
                
                // Set hardcoded required fields
                carePlan.Status = 'New';
                carePlan.Origin = 'Web';
                carePlan.Type = 'Care Plan';
                carePlan.Priority = 'Medium';
            }
            
            
        if (carePlanData.schedule != null) {
            if (String.isNotBlank(carePlanData.schedule.startDate)) {
                carePlan.Start_Date__c = Date.valueOf(carePlanData.schedule.startDate);
            }
            if (String.isNotBlank(carePlanData.schedule.reviewDate)) {
                carePlan.Review_Date__c = Date.valueOf(carePlanData.schedule.reviewDate);
            }
            carePlan.How_Often_We_re_Seeing_the_Client__c = carePlanData.schedule.frequency;
            //Anticipated_Duration_Months__c is a number field, so we need to convert the string to a number
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
            
            // Delete existing related records if updating
            if (carePlanId != null) {
                
                delete [SELECT Id FROM HealthCloudGA__CarePlanProblem__c WHERE HealthCloudGA__CarePlan__c = :carePlan.Id];
                delete [SELECT Id FROM HealthCloudGA__CarePlanGoal__c WHERE Case__c = :carePlan.Id];  // Changed
                delete [SELECT Id FROM Care_Plan_Intervention__c WHERE Case__c = :carePlan.Id];  // Changed
                delete [SELECT Id FROM Care_Plan_Stakeholders__c WHERE Case__c = :carePlan.Id];  // Changed
               
            }
            
            // Save Problems using HealthCloudGA__CarePlanProblem__c
            List<HealthCloudGA__CarePlanProblem__c> problemsToInsert = new List<HealthCloudGA__CarePlanProblem__c>();
            if (carePlanData.problems != null) {
                for (ProblemBlockWrapper problem : carePlanData.problems) {
                    //if (problem.selectedIds != null && !problem.selectedIds.isEmpty()) {
                    if (String.isNotBlank(problem.selectedName)) {
                        HealthCloudGA__CarePlanProblem__c prob = new HealthCloudGA__CarePlanProblem__c();
                        prob.HealthCloudGA__CarePlan__c = carePlan.Id;
                        prob.Name = problem.selectedName;
                        //prob.HealthCloudGA__CarePlanProblem__c = problem.selectedIds[0];
                        prob.HealthCloudGA__Priority__c = problem.severity;
                        //prob.HealthCloudGA__Description__c = problem.description;
                        prob.Problem_Description__c = problem.description;
                        prob.isCustom__c = problem.isCustom == true;
                        prob.HealthCloudGA__SortOrder__c = problemsToInsert.size() + 1;

                       
                        
                        problemsToInsert.add(prob);
                    }
                }
            }
            
            if (!problemsToInsert.isEmpty()) {
                insert problemsToInsert;
            }
            
            // Save Long Term Goals using HealthCloudGA__CarePlanGoal__c
            List<HealthCloudGA__CarePlanGoal__c> goalsToInsert = new List<HealthCloudGA__CarePlanGoal__c>();
            if (carePlanData.longTermGoals != null) {
                for (GoalBlockWrapper goal : carePlanData.longTermGoals) {
                    //if (goal.selectedIds != null && !goal.selectedIds.isEmpty()) {
                    if (String.isNotBlank(goal.selectedName)) {
                        HealthCloudGA__CarePlanGoal__c goalRecord = new HealthCloudGA__CarePlanGoal__c();
                        goalRecord.Case__c = carePlan.Id;
                        goalRecord.Name = goal.selectedName;
                        //goalRecord.HealthCloudGA__CarePlanTemplateGoal__c = goal.selectedIds[0];
                        goalRecord.Goal_Category__c = goal.category;
                        goalRecord.HealthCloudGA__Description__c = goal.description;
                        goalRecord.Success_Criteria__c = goal.successCriteria;
                        goalRecord.isCustom__c = goal.isCustom == true;
                        goalRecord.Goal_Type__c = 'Long Term';
                        goalRecord.HealthCloudGA__SortOrder__c = goalsToInsert.size() + 1;
                        
                        goalsToInsert.add(goalRecord);
                    }
                }
            }
            
            // Save Quarterly Goals using HealthCloudGA__CarePlanGoal__c
            Map<String, Id> goalIdMap = new Map<String, Id>();
            if (carePlanData.quarterlyGoals != null) {
                for (GoalBlockWrapper goal : carePlanData.quarterlyGoals) {
                    //if (goal.selectedIds != null && !goal.selectedIds.isEmpty()) {
                    if (String.isNotBlank(goal.selectedName)) {
                        HealthCloudGA__CarePlanGoal__c goalRecord = new HealthCloudGA__CarePlanGoal__c();
                        goalRecord.Case__c = carePlan.Id;
                        goalRecord.Name = goal.selectedName;
                        //goalRecord.HealthCloudGA__CarePlanTemplateGoal__c = goal.selectedIds[0];
                        goalRecord.Goal_Category__c = goal.category;
                        goalRecord.HealthCloudGA__Description__c = goal.description;
                        goalRecord.Success_Criteria__c = goal.successCriteria;
                        goalRecord.Goal_Type__c = 'Quarterly';
                        goalRecord.isCustom__c = goal.isCustom == true;
                        goalRecord.HealthCloudGA__SortOrder__c = goalsToInsert.size() + 1;
                        
                        goalsToInsert.add(goalRecord);
                        goalIdMap.put(goal.id, null);
                    }
                }
            }
            
            if (!goalsToInsert.isEmpty()) {
                insert goalsToInsert;
                
                // Map the quarterly goal temp IDs to actual Salesforce IDs
                if (carePlanData.quarterlyGoals != null) {
                    for (GoalBlockWrapper goal : carePlanData.quarterlyGoals) {
                        //if (goal.selectedIds != null && !goal.selectedIds.isEmpty()) {
                        if (String.isNotBlank(goal.selectedName)) {
                            for (HealthCloudGA__CarePlanGoal__c insertedGoal : goalsToInsert) {
                                if (insertedGoal.Goal_Type__c == 'Quarterly' && 
                                    insertedGoal.Name == goal.selectedName) {
                                    goalIdMap.put(goal.id, insertedGoal.Id);
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            
            // Save Interventions using custom Intervention__c object
            List<Care_Plan_Intervention__c> interventionsToInsert = new List<Care_Plan_Intervention__c>();
            if (carePlanData.quarterlyGoals != null) {
                for (GoalBlockWrapper goal : carePlanData.quarterlyGoals) {
                    Id goalSalesforceId = goalIdMap.get(goal.id);
                    
                    if (goal.interventions != null && goalSalesforceId != null) {
                        for (InterventionWrapper intervention : goal.interventions) {
                            //if (intervention.selectedIds != null && !intervention.selectedIds.isEmpty()) {
                            if (String.isNotBlank(intervention.selectedName)) {
                                Care_Plan_Intervention__c intv = new Care_Plan_Intervention__c();
                                intv.Case__c = carePlan.Id;
                                //intv.Care_Plan_Goal__c = goalSalesforceId;
                                intv.Name = intervention.selectedName;
                                
                                intv.Care_Plan_Intervention_Frequency__c = intervention.frequency;
                                intv.Care_Plan_Int_Duration_Optional__c = intervention.duration;
                                intv.Care_Plan_Intervention_Details__c = intervention.details;
                                intv.isCustom__c = intervention.isCustom == true;
                                
                                if (intervention.selectedIds != null && !intervention.selectedIds.isEmpty()) {
                                   // intv.Template_Task__c = intervention.selectedIds[0];
                                }
                                
                                interventionsToInsert.add(intv);
                            }
                        }
                    }
                }
            }
            
            if (!interventionsToInsert.isEmpty()) {
                insert interventionsToInsert;
            }
            
            

            /* ================= STAKEHOLDERS ================= */
List<Care_Plan_Stakeholders__c> stakeholdersToInsert = new List<Care_Plan_Stakeholders__c>();
//Set<Id> userIds = new Set<Id>();
Set<Id> contactIds = new Set<Id>();

if (carePlanData.stakeholders != null) {
    for (StakeholderWrapper stakeholder : carePlanData.stakeholders) {

        Care_Plan_Stakeholders__c sh = new Care_Plan_Stakeholders__c();
        sh.Case__c = carePlan.Id;
        sh.Stake_Holder_Type__c = stakeholder.stakeholderType;
        sh.Role_in_Care__c = stakeholder.roleInCare;
        sh.Communication_Preference__c = stakeholder.communicationPreference;
        sh.How_Often_to_Communicate__c = stakeholder.communicationFrequency;

        stakeholdersToInsert.add(sh);

        /*if (stakeholder.userId != null) {
            userIds.add(stakeholder.userId);
        }*/
        if (stakeholder.contactId != null) {
            contactIds.add(stakeholder.contactId);
        }

    }
}

if (!stakeholdersToInsert.isEmpty()) {
    insert stakeholdersToInsert;
}



delete [SELECT Id FROM Care_Plan_Contact__c WHERE Case__c = :carePlan.Id];

List<Care_Plan_Contact__c> cpcToInsert = new List<Care_Plan_Contact__c>();
for (Id contactId : contactIds) {
    cpcToInsert.add(new Care_Plan_Contact__c(
        Case__c = carePlan.Id,
        Contact__c = contactId
    ));
}
if (!cpcToInsert.isEmpty()) 
insert cpcToInsert;

            
            // Generate and save PDF
            result.pdfContentDocumentId = generateAndSavePDF(carePlan.Id, carePlanData);
            
            result.success = true;
            result.message = 'Care Plan saved successfully!';
            
        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.message = 'Error saving Care Plan: ' + e.getMessage();
            System.debug('Error: ' + e.getMessage() + ' | Stack Trace: ' + e.getStackTraceString());
        }
        
        return result;
    }
    
 

        /* ================= CASE (CARE PLAN) ================= */

      

 

   /* ================= GOALS ================= */


    
   @AuraEnabled
public static String generatePDFPreview(String carePlanDataJson) {
    try {
        CarePlanDataWrapper carePlanData = (CarePlanDataWrapper) JSON.deserialize(
            carePlanDataJson,
            CarePlanDataWrapper.class
        );
        
        String html = generatePDFContent(carePlanData);
        
        // Convert HTML to PDF blob and return base64 string
        Blob pdfBlob = Blob.toPdf(html);
        return EncodingUtil.base64Encode(pdfBlob);
        
    } catch (Exception e) {
        throw new AuraHandledException('Error generating PDF preview: ' + e.getMessage());
    }
}
    

    @AuraEnabled
public static Id getAccountIdFromCarePlan(Id carePlanId) {
    Case carePlan = [SELECT AccountId FROM Case WHERE Id = :carePlanId LIMIT 1];
    return carePlan.AccountId;
}

  @AuraEnabled
public static CarePlanDataWrapper getCarePlanById(Id carePlanId) {
    CarePlanDataWrapper result = new CarePlanDataWrapper();
    
  
List<Case> cases = [
    SELECT Id, Subject, Description, AccountId, Account.Name,Sequence_Number__c,Careplan_Suffix__c,
    Start_Date__c, Review_Date__c, How_Often_We_re_Seeing_the_Client__c,
     Anticipated_Duration_Months__c,
      Anticipated_Hours_per_Week__c,
    Quarterly_Goal_Status__c,Overall_Client_Stability_This_Quarter__c,Outcome_Summary__c,Plan_Adjustment__c
    FROM Case
    WHERE Id = :carePlanId
    AND RecordType.DeveloperName = 'CarePlan'
    //ORDER BY CreatedDate DESC
    LIMIT 1
];

if (cases.isEmpty()) {
    return result;
}

Case carePlan = cases[0];
result.caseSubject = carePlan.Subject;  
result.sequenceNumber = carePlan.Sequence_Number__c;
result.carePlanSuffix = carePlan.Careplan_Suffix__c;
Id carePlanCaseId = carePlan.Id;

    
   
    // Read schedule from dedicated fields
result.schedule = new ScheduleWrapper();
result.schedule.startDate = carePlan.Start_Date__c != null ? String.valueOf(carePlan.Start_Date__c) : '';
result.schedule.reviewDate = carePlan.Review_Date__c != null ? String.valueOf(carePlan.Review_Date__c) : '';
result.schedule.frequency = carePlan.How_Often_We_re_Seeing_the_Client__c != null ? carePlan.How_Often_We_re_Seeing_the_Client__c : '';
result.schedule.duration = carePlan.Anticipated_Duration_Months__c != null ? String.valueOf(carePlan.Anticipated_Duration_Months__c) : '';
result.schedule.hoursPerWeek = carePlan.Anticipated_Hours_per_Week__c != null ? String.valueOf(carePlan.Anticipated_Hours_per_Week__c) : '';

// Load Client Impact Review
result.clientImpact = new ClientImpactWrapper();
result.clientImpact.quarterlyGoalStatus = carePlan.Quarterly_Goal_Status__c;
result.clientImpact.clientStability = carePlan.Overall_Client_Stability_This_Quarter__c;
result.clientImpact.outcomeSummary = carePlan.Outcome_Summary__c;
result.clientImpact.planAdjustment = carePlan.Plan_Adjustment__c;
    
    // Query Problems
    result.problems = new List<ProblemBlockWrapper>();
    for (HealthCloudGA__CarePlanProblem__c prob : [
        SELECT Id, Name, HealthCloudGA__Priority__c, Problem_Description__c,isCustom__c, Care_Plan_Template_Problem__c
        FROM HealthCloudGA__CarePlanProblem__c
        WHERE HealthCloudGA__CarePlan__c = :carePlanCaseId
        ORDER BY HealthCloudGA__SortOrder__c
    ]) {
        ProblemBlockWrapper pb = new ProblemBlockWrapper();
        pb.id = prob.Id;
        pb.selectedIds = new List<String>{prob.Id}; // Assuming Name is the ID reference
       

       
        pb.selectedName = prob.Name;
        pb.severity = prob.HealthCloudGA__Priority__c;
        //pb.description = prob.HealthCloudGA__Description__c;
        pb.description = prob.Problem_Description__c;
        pb.isCustom = prob.isCustom__c;
        //pb.isSelected = true;
        result.problems.add(pb);
    }
    
    // Query Long Term Goals
    result.longTermGoals = new List<GoalBlockWrapper>();
    for (HealthCloudGA__CarePlanGoal__c goal : [
        SELECT Id, Name, HealthCloudGA__Description__c, Goal_Type__c, Goal_Category__c,Success_Criteria__c, isCustom__c
        FROM HealthCloudGA__CarePlanGoal__c
        WHERE Case__c = :carePlanCaseId AND Goal_Type__c = 'Long Term'
        ORDER BY HealthCloudGA__SortOrder__c
    ]) {
        GoalBlockWrapper gb = new GoalBlockWrapper();
        gb.id = goal.Id;
        gb.selectedIds = new List<String>{goal.Id};
        gb.selectedName = goal.Name;
        gb.description = goal.HealthCloudGA__Description__c;
        gb.category = goal.Goal_Category__c;
        gb.successCriteria = goal.Success_Criteria__c;
        gb.isCustom = goal.isCustom__c;


        //gb.isSelected = true;
        gb.interventions = new List<InterventionWrapper>(); // No interventions for long-term
        result.longTermGoals.add(gb);
    }
    
    // Query Quarterly Goals
    result.quarterlyGoals = new List<GoalBlockWrapper>();
    Map<Id, GoalBlockWrapper> goalMap = new Map<Id, GoalBlockWrapper>();
    for (HealthCloudGA__CarePlanGoal__c goal : [
        SELECT Id, Name, HealthCloudGA__Description__c, Goal_Type__c, Goal_Category__c, isCustom__c,Success_Criteria__c
        FROM HealthCloudGA__CarePlanGoal__c
        WHERE Case__c = :carePlanCaseId AND Goal_Type__c = 'Quarterly'
        ORDER BY HealthCloudGA__SortOrder__c
    ]) {
        GoalBlockWrapper gb = new GoalBlockWrapper();
        gb.id = goal.Id;
        gb.selectedIds = new List<String>{goal.Id};
        gb.selectedName = goal.Name;
        gb.description = goal.HealthCloudGA__Description__c;
        gb.category = goal.Goal_Category__c;
        gb.isCustom = goal.isCustom__c;
        gb.successCriteria = goal.Success_Criteria__c;
        //gb.isSelected = true;
        gb.interventions = new List<InterventionWrapper>();
        result.quarterlyGoals.add(gb);
        goalMap.put(goal.Id, gb);
    }
    
    // Query Interventions and link to Quarterly Goals
    for (Care_Plan_Intervention__c intv : [
        SELECT Id, Name, Case__c,Care_Plan_Intervention_Category__c,Care_Plan_Int_Specific_Intervention__c,
        Care_Plan_Intervention_Frequency__c,Care_Plan_Int_Duration_Optional__c,Care_Plan_Intervention_Details__c,isCustom__c
        FROM Care_Plan_Intervention__c
        WHERE Case__c = :carePlanCaseId
    ]) {
        InterventionWrapper iw = new InterventionWrapper();
        iw.id = intv.Id;
        iw.selectedIds = new List<String>{intv.Id};
        iw.selectedName = intv.Name;
        iw.category = intv.Care_Plan_Intervention_Category__c;
        iw.specificIntervention = intv.Care_Plan_Int_Specific_Intervention__c;
        iw.frequency = intv.Care_Plan_Intervention_Frequency__c;
        iw.duration = intv.Care_Plan_Int_Duration_Optional__c;
        iw.details = intv.Care_Plan_Intervention_Details__c;
        iw.isCustom = intv.isCustom__c;
        //iw.isSelected = true;
        // Add to the first quarterly goal for simplicity - adjust if needed
        if (!result.quarterlyGoals.isEmpty()) {
            result.quarterlyGoals[0].interventions.add(iw);
        }
    }
    
    // Query Stakeholders
    result.stakeholders = new List<StakeholderWrapper>();
    for (Care_Plan_Stakeholders__c sh : [
        SELECT Id, Name, Stake_Holder_Type__c, Role_in_Care__c, Communication_Preference__c, How_Often_to_Communicate__c
        FROM Care_Plan_Stakeholders__c
        WHERE Case__c = :carePlanCaseId
    ]) {
        StakeholderWrapper sw = new StakeholderWrapper();
        sw.id = sh.Id;
        sw.contactName = sh.Name;
        sw.stakeholderType = sh.Stake_Holder_Type__c;
        sw.roleInCare = sh.Role_in_Care__c;
        sw.communicationPreference = sh.Communication_Preference__c;
        sw.communicationFrequency = sh.How_Often_to_Communicate__c;
        result.stakeholders.add(sw);
    }

 

// ================= CARE PLAN CONTACT (JUNCTION) =================
List<Id> contactIds = new List<Id>();

for (Care_Plan_Contact__c cpc : [
    SELECT Contact__c
    FROM Care_Plan_Contact__c
    WHERE Case__c = :carePlanCaseId
    ORDER BY CreatedDate ASC
]) {
    if (cpc.Contact__c != null) {
        contactIds.add(cpc.Contact__c);
    }
}

// Assign contacts to stakeholders (order-based mapping)
Integer i = 0;
for (StakeholderWrapper sw : result.stakeholders) {
    if (i < contactIds.size()) {
        sw.contactId = contactIds[i];
        i++;
    }
}


    
    return result;
}

    
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
            cv.Title = 'Care Plan - ' + System.now().format('yyyy-MM-dd HH:mm');
            cv.PathOnClient = 'CarePlan_' + System.now().format('yyyyMMdd_HHmmss') + '.pdf';
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
            
            return cv.ContentDocumentId;
            
        } catch (Exception e) {
            System.debug('Error generating PDF: ' + e.getMessage());
            return null;
        }
    }
    
    
private static String getLogoUrl() {
    // Static Resource name exactly as uploaded
    return URL.getOrgDomainUrl().toExternalForm() + '/resource/WellSpringLogo';
}

private static String generatePDFContent(CarePlanDataWrapper carePlanData) {
    System.debug('Generating PDF Content nn');
    System.debug('CarePlanData: ' + carePlanData);

    //Map<Id, String> stakeholderUserNamesById = getStakeholderUserNameMap(carePlanData);
    Map<Id, String> stakeholderContactNamesById = getStakeholderContactNameMap(carePlanData);
    //String logoUrl = getLogoUrl();
    String html = '<html><body style="font-family: Arial, sans-serif; font-size: 12px;">';

    html += '<table width="100%" cellpadding="0" cellspacing="0">';
//      html += '<tr>';
//    html += '<td style="width:220px; text-align:right; vertical-align:top;">'
//      + '<img src="' + logoUrl + '" style="height:46px; width:auto;" />'
//      + '</td>';
//      html += '</tr>';
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

           
            html += spacer(12);

        html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
        html += '<tr><td width="30%"><b>Problem Name</b></td><td>' + safe(problem.selectedName) + '</td></tr>';
        html += '<tr><td><b>Priority</b></td><td>' + safe(problem.severity) + '</td></tr>';
        html += '<tr><td><b>Description</b></td><td>' + safe(problem.description) + '</td></tr>';
        html += '</table>';

        html += spacer(20);
        }
    }

    /* ================= LONG TERM GOALS ================= */
    if (carePlanData.longTermGoals != null && !carePlanData.longTermGoals.isEmpty()) {

        html += sectionHeader('Long Term Goals');

        for (GoalBlockWrapper goal : carePlanData.longTermGoals) {

            
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

            
             html += spacer(12);

        html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
        html += '<tr><td width="30%"><b>Querterly Goal Name</b></td><td>' + safe(goal.selectedName) + '</td></tr>';
        html += '<tr><td><b>Description</b></td><td>' + safe(goal.description) + '</td></tr>';
        html += '<tr><td><b>Success Criteria</b></td><td>' + safe(goal.successCriteria) + '</td></tr>';
        html += '</table>';

        html += spacer(16);

            if (goal.interventions != null && !goal.interventions.isEmpty()) {

                html += '<table width="100%" cellpadding="0" cellspacing="0">';
                html += '<tr><td style="font-size:14px; font-weight:bold; color:#014486;">Interventions:</td></tr>';
                html += '<tr><td height="10"></td></tr>';
                html += '</table>';

                for (InterventionWrapper intv : goal.interventions) {

                    html += '<table width="100%" cellpadding="8" cellspacing="0" style="border-collapse:collapse; border:1px solid #000;">';
                   
                    html += '</table>';
                    html += spacer(12);


                    html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">';
                    //html += '<tr><td width="30%"><b>Category</b></td><td>' + safe(intv.category) + '</td></tr>';
                    //html += '<tr><td><b>Specific Intervention</b></td><td>' + safe(intv.specificIntervention) + '</td></tr>';
                     html += '<tr><td width="30%"><b>Intervention Name</b></td><td>' + intv.selectedName + '</td></tr>';
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
        html += spacer(14);
          
        for (StakeholderWrapper stakeholder : carePlanData.stakeholders) {

            //html += titleBlock(stakeholder.contactName, '#fef3c7', '#f59e0b');
            html += spacer(12);

            html += '<table width="100%" border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;">'; 
            //html += '<tr><td width="30%"><b>Contact Name</b></td><td>' + safe(stakeholder.contactName) + '</td></tr>';
            html += '<tr><td width="30%"><b>Stakeholder Type</b></td><td>' + safe(stakeholder.stakeholderType) + '</td></tr>';
            //html += '<tr><td><b>Stakeholder Contact</b></td><td>' + safe(stakeholder.userId != null && stakeholderUserNamesById.containsKey(stakeholder.userId) ? stakeholderUserNamesById.get(stakeholder.userId) : '-') + '</td></tr>';
            html += '<tr><td><b>Stakeholder Contact</b></td><td>' + safe(stakeholder.contactId != null && stakeholderContactNamesById.containsKey(stakeholder.contactId) ? stakeholderContactNamesById.get(stakeholder.contactId) : '-') + '</td></tr>';
            html += '<tr><td><b>Role in Care</b></td><td>' + safe(stakeholder.roleInCare) + '</td></tr>';
            
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
       // html += '<tr><td width="30%"><b>Start Date</b></td><td>' + safe(carePlanData.schedule.startDate) + '</td></tr>';
        //html += '<tr><td><b>Review Date</b></td><td>' + safe(carePlanData.schedule.reviewDate) + '</td></tr>';
        html += '<tr><td><b>How Often We’re Seeing the Client</b></td><td>' + safe(carePlanData.schedule.frequency) + '</td></tr>';
        html += '<tr><td><b>Anticipated Duration</b></td><td>' + safe(carePlanData.schedule.duration) + '</td></tr>';
        html += '<tr><td><b>Anticipated Hours per Week</b></td><td>' + safe(carePlanData.schedule.hoursPerWeek) + '</td></tr>';
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
private static String formatDateForPdf(String rawDate) {
    if (String.isBlank(rawDate)) return '-';
    try {
        Date d = Date.valueOf(rawDate); // expects yyyy-MM-dd
        Datetime dt = Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        return dt.format('MMM dd, yyyy'); // Feb 12, 2026
    } catch (Exception e) {
        return safe(rawDate);
    }
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

    if (contactIds.isEmpty()) {
        return contactNamesById;
    }

    for (Contact c : [SELECT Id, Name FROM Contact WHERE Id IN :contactIds]) {
        contactNamesById.put(c.Id, c.Name);
    }

    return contactNamesById;
}


private static String safe(String val) {
    return String.isBlank(val) ? '-' : val;
}


}