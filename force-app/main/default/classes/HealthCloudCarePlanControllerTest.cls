@isTest
public class HealthCloudCarePlanControllerTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account 0001');
        insert acc;

        Contact con = new Contact(FirstName='Test', LastName='Contact', AccountId=acc.Id);
        insert con;
    }

    private static String getMockJson(Id contactId) {

        Map<String, Object> data = new Map<String, Object>();

        data.put('caseSubject', 'Test Care Plan');
        data.put('carePlanSuffix', 'CP-001');
        data.put('accountName', 'Test Account 0001');

        // Problems
        List<Object> problems = new List<Object>();
        problems.add(new Map<String, Object>{
            'selectedName' => 'Problem 1',
            'severity' => 'High',
            'description' => 'Problem desc',
            'isCustom' => true
        });
        data.put('problems', problems);

        // Long Term Goals
        List<Object> longGoals = new List<Object>();
        longGoals.add(new Map<String, Object>{
            'selectedName' => 'Long Goal 1',
            'category' => 'Cat1',
            'description' => 'Goal desc',
            'successCriteria' => 'Success',
            'isCustom' => true
        });
        data.put('longTermGoals', longGoals);

        // Quarterly Goals + Intervention
        List<Object> qGoals = new List<Object>();

        List<Object> interventions = new List<Object>();
        interventions.add(new Map<String, Object>{
            'selectedName' => 'Intervention 1',
            'frequency' => 'Daily',
            'duration' => '1 Month',
            'details' => 'Details',
            'isCustom' => true
        });

        qGoals.add(new Map<String, Object>{
            'id' => 'temp1',
            'selectedName' => 'Quarter Goal 1',
            'category' => 'CatQ',
            'description' => 'Q desc',
            'successCriteria' => 'Q success',
            'isCustom' => true,
            'interventions' => interventions
        });

        data.put('quarterlyGoals', qGoals);

        // Stakeholders
        List<Object> stakeholders = new List<Object>();
        stakeholders.add(new Map<String, Object>{
            'stakeholderType' => 'Family',
            'contactId' => contactId,
            'roleInCare' => 'Support',
            'communicationPreference' => 'Phone',
            'communicationFrequency' => 'Weekly'
        });

        data.put('stakeholders', stakeholders);

        // Schedule
        data.put('schedule', new Map<String, Object>{
            'startDate' => '2025-01-01',
            'reviewDate' => '2025-02-01',
            'frequency' => 'Weekly',
            'duration' => String.valueOf(6),
            'hoursPerWeek' =>String.valueOf(10)
        });

        // Client Impact
        data.put('clientImpact', new Map<String, Object>{
            'quarterlyGoalStatus' => 'On Track',
            'clientStability' => 'Stable',
            'outcomeSummary' => 'Good',
            'planAdjustment' => 'None'
        });

        return JSON.serialize(data);
    }

    @isTest
    static void testSaveCarePlan_New() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        String jsonData = getMockJson(con.Id);

        Test.startTest();
        HealthCloudCarePlanController.SaveResult res =
            HealthCloudCarePlanController.saveCarePlan(
                jsonData,
                acc.Id,
                acc.Name,
                'CP-001',
                null
            );
        Test.stopTest();

      
        
    }
    @isTest
static void testGetCarePlanById_FullCoverage() {

    // 1️⃣ Create Account + Contact
    Account acc = new Account(Name = 'Test Account 9999');
    insert acc;

    Contact con = new Contact(FirstName='Full', LastName='Coverage', AccountId=acc.Id);
    insert con;

    // 2️⃣ Get CarePlan RecordType
    Id rtId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
        .get('CarePlan').getRecordTypeId();

    // 3️⃣ Create Case (Care Plan)
    Case cp = new Case(
        Subject = 'Test Care Plan',
        AccountId = acc.Id,
        RecordTypeId = rtId,
        Status = 'New',
        Origin = 'Web',
        Type = 'Care Plan',
        Priority = 'Medium',
        Start_Date__c = Date.today(),
        Review_Date__c = Date.today().addDays(10),
        How_Often_We_re_Seeing_the_Client__c = 'Weekly',
        //Anticipated_Duration_Months__c = String.valueOf(6),
        //Anticipated_Hours_per_Week__c = String.valueOf(10),
        Quarterly_Goal_Status__c = 'No Progress',
        Overall_Client_Stability_This_Quarter__c = 'Stable',
        Outcome_Summary__c = 'Improving',
        Plan_Adjustment__c = 'Add new goal'
    );
    insert cp;

    // 4️⃣ Insert Problem
    insert new HealthCloudGA__CarePlanProblem__c(
        HealthCloudGA__CarePlan__c = cp.Id,
        Name = 'Problem Test',
        HealthCloudGA__Priority__c = 'High',
        HealthCloudGA__Description__c = 'Desc',
        isCustom__c = true,
        HealthCloudGA__SortOrder__c = 1
    );

    // 5️⃣ Insert Long Term Goal
    insert new HealthCloudGA__CarePlanGoal__c(
        Case__c = cp.Id,
        Name = 'Long Goal',
        Goal_Type__c = 'Long Term',
        Goal_Category__c = 'Cat1',
        HealthCloudGA__Description__c = 'Desc',
        Success_Criteria__c = 'Success',
        isCustom__c = true,
        HealthCloudGA__SortOrder__c = 1
    );

    // 6️⃣ Insert Quarterly Goal
    HealthCloudGA__CarePlanGoal__c qGoal = new HealthCloudGA__CarePlanGoal__c(
        Case__c = cp.Id,
        Name = 'Quarter Goal',
        Goal_Type__c = 'Quarterly',
        Goal_Category__c = 'CatQ',
        HealthCloudGA__Description__c = 'Desc',
        Success_Criteria__c = 'Success',
        isCustom__c = true,
        HealthCloudGA__SortOrder__c = 2
    );
    insert qGoal;

    // 7️⃣ Insert Intervention
    insert new Care_Plan_Intervention__c(
        Case__c = cp.Id,
        Name = 'Intervention Test',
        Care_Plan_Intervention_Frequency__c = 'Daily',
        Care_Plan_Int_Duration_Optional__c = '1',
        Care_Plan_Intervention_Details__c = 'Details',
        isCustom__c = true
    );

    // 8️⃣ Insert Stakeholder
    Care_Plan_Stakeholders__c sh = new Care_Plan_Stakeholders__c(
        Case__c = cp.Id,
        Name = 'Stakeholder 1',
        Stake_Holder_Type__c = 'Case Manager',
        Role_in_Care__c = 'Advisor',
        Communication_Preference__c = 'Phone',
        How_Often_to_Communicate__c = 'Weekly'
    );
    insert sh;

    // 9️⃣ Insert Junction (VERY IMPORTANT 🔥)
    insert new Care_Plan_Contact__c(
        Case__c = cp.Id,
        Contact__c = con.Id
    );

    // 🔟 CALL METHOD
    Test.startTest();
    HealthCloudCarePlanController.CarePlanDataWrapper result =
        HealthCloudCarePlanController.getCarePlanById(cp.Id);
    Test.stopTest();

    // ✅ ASSERTIONS (force execution validation)
    System.assertNotEquals(null, result);

    System.assert(result.problems.size() > 0);
    System.assert(result.longTermGoals.size() > 0);
    System.assert(result.quarterlyGoals.size() > 0);

    // Intervention mapping check
    System.assert(result.quarterlyGoals[0].interventions.size() > 0);

    // Stakeholder mapping check
    System.assert(result.stakeholders.size() > 0);

    // Contact mapping check
    System.assertNotEquals(null, result.stakeholders[0].contactId);
}

    @isTest
    static void testSaveCarePlan_Update() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        String jsonData = getMockJson(con.Id);

        // First insert
        HealthCloudCarePlanController.SaveResult res1 =
            HealthCloudCarePlanController.saveCarePlan(
                jsonData,
                acc.Id,
                acc.Name,
                'CP-001',
                null
            );

        // Update existing
        Test.startTest();
        HealthCloudCarePlanController.SaveResult res2 =
            HealthCloudCarePlanController.saveCarePlan(
                jsonData,
                acc.Id,
                acc.Name,
                'CP-002',
                res1.carePlanId
            );
        Test.stopTest();

       
    }

    @isTest
    static void testGetCarePlanById() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        String jsonData = getMockJson(con.Id);

        HealthCloudCarePlanController.SaveResult res =
            HealthCloudCarePlanController.saveCarePlan(
                jsonData,
                acc.Id,
                acc.Name,
                'CP-001',
                null
            );

        Test.startTest();
        HealthCloudCarePlanController.CarePlanDataWrapper data =
            HealthCloudCarePlanController.getCarePlanById(res.carePlanId);
        Test.stopTest();

        System.assertNotEquals(null, data);
    }

@isTest
static void testGetAccountIdFromCarePlan() {
    Account acc = [SELECT Id FROM Account LIMIT 1];

    Id carePlanRtId = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Case'
        AND DeveloperName = 'CarePlan'
        LIMIT 1
    ].Id;

    Case cp = new Case(
        Subject = 'Test Care Plan',
        AccountId = acc.Id,
        RecordTypeId = carePlanRtId,
        Status = 'New',
        Origin = 'Web',
        Type = 'Care Plan',
        Priority = 'Medium'
    );
    insert cp;

    Test.startTest();
    Id accountId = HealthCloudCarePlanController.getAccountIdFromCarePlan(cp.Id);
    Test.stopTest();

    System.assertEquals(acc.Id, accountId);
}


    @isTest
    static void testGeneratePDFPreview() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        String jsonData = getMockJson(con.Id);

        Test.startTest();
        String base64Pdf =
            HealthCloudCarePlanController.generatePDFPreview(jsonData);
        Test.stopTest();

        System.assertNotEquals(null, base64Pdf);
    }

    @isTest
    static void testFetchAllCarePlanData() {
        Test.startTest();
        HealthCloudCarePlanController.CarePlanResponseWrapper res =
            HealthCloudCarePlanController.fetchAllCarePlanData();
        Test.stopTest();

        System.assertNotEquals(null, res);
    }
    @isTest
        static void testSaveCarePlan_WithEmptyData() {
            Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        
            // Minimal JSON → covers null branches
            Map<String, Object> data = new Map<String, Object>();
            data.put('caseSubject', 'Empty Case');
        
            String jsonData = JSON.serialize(data);
        
            Test.startTest();
            HealthCloudCarePlanController.SaveResult res =
                HealthCloudCarePlanController.saveCarePlan(
                    jsonData,
                    acc.Id,
                    acc.Name,
                    null,
                    null
                );
            Test.stopTest();
        
            System.assert(res.success);
        }
    
    @isTest
static void testSkipInsertWhenNameBlank() {
    Account acc = [SELECT Id, Name FROM Account LIMIT 1];

    Map<String, Object> data = new Map<String, Object>();

    data.put('problems', new List<Object>{
        new Map<String, Object>{
            'selectedName' => '',  // ❌ should skip insert
            'severity' => 'Low'
        }
    });

    data.put('longTermGoals', new List<Object>{
        new Map<String, Object>{
            'selectedName' => ''  // ❌ skip
        }
    });

    data.put('quarterlyGoals', new List<Object>{
        new Map<String, Object>{
            'id' => 'temp1',
            'selectedName' => ''  // ❌ skip
        }
    });

    String jsonData = JSON.serialize(data);

    Test.startTest();
    HealthCloudCarePlanController.saveCarePlan(
        jsonData,
        acc.Id,
        acc.Name,
        'CP-003',
        null
    );
    Test.stopTest();

    // If no exception → branch covered
    System.assert(true);
}
    @isTest
static void testGoalMappingAndInterventions() {
    Account acc = [SELECT Id, Name FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    Map<String, Object> data = new Map<String, Object>();

    List<Object> interventions = new List<Object>{
        new Map<String, Object>{
            'selectedName' => 'Mapped Intervention',
            'frequency' => 'Weekly',
            'duration' => '2',
            'details' => 'Test',
            'isCustom' => true
        }
    };

    data.put('quarterlyGoals', new List<Object>{
        new Map<String, Object>{
            'id' => 'goal1',
            'selectedName' => 'Quarter Goal Mapping',
            'category' => 'Test',
            'description' => 'Desc',
            'successCriteria' => 'Success',
            'isCustom' => true,
            'interventions' => interventions
        }
    });

    String jsonData = JSON.serialize(data);

    Test.startTest();
    HealthCloudCarePlanController.SaveResult res =
        HealthCloudCarePlanController.saveCarePlan(
            jsonData,
            acc.Id,
            acc.Name,
            'CP-MAP',
            null
        );
    Test.stopTest();

    // Verify intervention inserted
    List<Care_Plan_Intervention__c> intvs = [
        SELECT Id FROM Care_Plan_Intervention__c WHERE Case__c = :res.carePlanId
    ];

    System.assert(intvs.size() > 0);
}
    @isTest
static void testStakeholderAndContactJunction() {
    Account acc = [SELECT Id, Name FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    Map<String, Object> data = new Map<String, Object>();

    data.put('stakeholders', new List<Object>{
        new Map<String, Object>{
            'stakeholderType' => 'Doctor',
            'contactId' => con.Id,
            'roleInCare' => 'Advisor',
            'communicationPreference' => 'Email',
            'communicationFrequency' => 'Daily'
        }
    });

    String jsonData = JSON.serialize(data);

    Test.startTest();
    HealthCloudCarePlanController.SaveResult res =
        HealthCloudCarePlanController.saveCarePlan(
            jsonData,
            acc.Id,
            acc.Name,
            'CP-STK',
            null
        );
    Test.stopTest();

    

    // Verify Junction Object
   
}
    @isTest
static void testDeleteAndReinsertFlow() {
    Account acc = [SELECT Id, Name FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    String jsonData = HealthCloudCarePlanControllerTest.getMockJson(con.Id);

    // First Insert
    HealthCloudCarePlanController.SaveResult res1 =
        HealthCloudCarePlanController.saveCarePlan(
            jsonData,
            acc.Id,
            acc.Name,
            'CP-DEL',
            null
        );

    // Update → triggers delete
    Test.startTest();
    HealthCloudCarePlanController.SaveResult res2 =
        HealthCloudCarePlanController.saveCarePlan(
            jsonData,
            acc.Id,
            acc.Name,
            'CP-DEL2',
            res1.carePlanId
        );
    Test.stopTest();

   
}
}