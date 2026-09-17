/**
 * Class Name      : SecondaryAssessmentControllerTest
 * Description     : Test class for SecondaryAssessmentController.
 *
 */
@isTest
private class SecondaryAssessmentControllerTest {

    // ------------------------------------------------------------------
    // Test data helpers
    // ------------------------------------------------------------------

    private static Account createPersonAccount() {

        Account acc = new Account(
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Prospect')
                .getRecordTypeId(),
            FirstName = 'Test',
            LastName = 'Client'
        );
        insert acc;

        return [
            SELECT Id, PersonContactId, Name
            FROM Account
            WHERE Id = :acc.Id
        ];
    }

    private static Question_Master__c createQuestion(
        String assessmentType,
        String questionText,
        Decimal sequence,
        String questionType,
        String section,
        String options
    ) {
        Question_Master__c q = new Question_Master__c(
            Assessment_Type__c = assessmentType,
            Question_Text__c = questionText,
            Sequence__c = sequence,
            Question_Type__c = questionType,
            Section__c = section,
            Answer_Options__c = options,
            Active__c = true,
            HelpText__c = 'Help text for ' + questionText
        );
        insert q;
        return q;
    }

    // ------------------------------------------------------------------
    // getQuestions
    // ------------------------------------------------------------------

    @isTest
static void testGetQuestions() {

    Account acc = createPersonAccount();

    createQuestion(
        'Geriatric Depression Scale',
        'Are you basically satisfied with your life?',
        1,
        'Single-Select',
        'Section A',
        'Yes;No'
    );

    Test.startTest();

    SecondaryAssessmentController.QuestionWrapper wrapper =
        SecondaryAssessmentController.getQuestions(
            'Geriatric Depression Scale',
            acc.Id
        );

    Test.stopTest();

    System.assertEquals(
        1,
        wrapper.questions.size()
    );
}

    // ------------------------------------------------------------------
    // saveAssessment
    // ------------------------------------------------------------------

    @isTest
    static void testSaveAssessment_Success() {
        Account acc = createPersonAccount();
        Question_Master__c q =
            createQuestion('Nursing Assessment', 'Question 1', 1, 'Text', 'Section A', null);

        SecondaryAssessmentController.QuestionAnswerWrapper qa =
            new SecondaryAssessmentController.QuestionAnswerWrapper();
        qa.questionId = q.Id;
        qa.answer = 'Yes';
        qa.notes = 'Some note';

        Test.startTest();
        Id assessmentId = SecondaryAssessmentController.saveAssessment(
            acc.Id,
            'Nursing Assessment',
            new List<SecondaryAssessmentController.QuestionAnswerWrapper>{ qa }
        );
        Test.stopTest();

        System.assertNotEquals(null, assessmentId);

        List<Assessment_Answer__c> savedAnswers = [
            SELECT Id
            FROM Assessment_Answer__c
            WHERE Secondary_Assessment__c = :assessmentId
        ];
        System.assertEquals(1, savedAnswers.size());
    }

    @isTest
    static void testSaveAssessment_NullAnswersList() {
        Account acc = createPersonAccount();

        Test.startTest();
        Id assessmentId =
            SecondaryAssessmentController.saveAssessment(acc.Id, 'Nursing Assessment', null);
        Test.stopTest();

        System.assertNotEquals(null, assessmentId);
    }

    @isTest
    static void testSaveAssessment_SkipsBlankAnswers() {
        Account acc = createPersonAccount();
        Question_Master__c q =
            createQuestion('Nursing Assessment', 'Question 1', 1, 'Text', 'Section A', null);

        SecondaryAssessmentController.QuestionAnswerWrapper qa =
            new SecondaryAssessmentController.QuestionAnswerWrapper();
        qa.questionId = q.Id;
        qa.answer = null;
        qa.notes = null;

        Test.startTest();
        Id assessmentId = SecondaryAssessmentController.saveAssessment(
            acc.Id,
            'Nursing Assessment',
            new List<SecondaryAssessmentController.QuestionAnswerWrapper>{ qa }
        );
        Test.stopTest();

        List<Assessment_Answer__c> savedAnswers = [
            SELECT Id
            FROM Assessment_Answer__c
            WHERE Secondary_Assessment__c = :assessmentId
        ];
        System.assertEquals(0, savedAnswers.size());
    }

    @isTest
    static void testSaveAssessment_FamilyCaregiver_NoFamilyContact_Throws() {
        Account acc = createPersonAccount();

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            SecondaryAssessmentController.saveAssessment(
                acc.Id,
                'Family Caregiver Assessment',
                new List<SecondaryAssessmentController.QuestionAnswerWrapper>()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception when no Family Contact exists.');
    }

    @isTest
    static void testSaveAssessment_FamilyCaregiver_WithFamilyContact_Success() {
        Account acc = createPersonAccount();

        Contact familyMember = new Contact(LastName = 'Family Member');
        insert familyMember;
        
        Id contactRoleRtId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();
        
        HealthCloudGA__ReciprocalRole__c r = new HealthCloudGA__ReciprocalRole__c(
            Name = 'Test Reciprocal Role',
            HealthCloudGA__InverseRole__c =  'father',
            RecordTypeId = contactRoleRtId
        );
        insert r;

        HealthCloudGA__ContactContactRelation__c rel =
            new HealthCloudGA__ContactContactRelation__c(
                HealthCloudGA__Contact__c = familyMember.Id,
                HealthCloudGA__RelatedContact__c = acc.PersonContactId,
                Type__c = 'Family Contact',
                HealthCloudGA__Role__c = r.Id
            );
        insert rel;

        Test.startTest();
        Id assessmentId = SecondaryAssessmentController.saveAssessment(
            acc.Id,
            'Family Caregiver Assessment',
            new List<SecondaryAssessmentController.QuestionAnswerWrapper>()
        );
        Test.stopTest();

        System.assertNotEquals(null, assessmentId);
    }

    // ------------------------------------------------------------------
    // getAssessments
    // ------------------------------------------------------------------

    @isTest
    static void testGetAssessments() {
        Account acc = createPersonAccount();
        insert new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Nursing Assessment'
        );

        Test.startTest();
        List<SecondaryAssessment__c> results =
            SecondaryAssessmentController.getAssessments(acc.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
    }

    @isTest
    static void testGetAssessments_NullAccountId_ReturnsEmptyList() {
        Test.startTest();
        List<SecondaryAssessment__c> results =
            SecondaryAssessmentController.getAssessments(null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    // ------------------------------------------------------------------
    // getAssessmentData
    // ------------------------------------------------------------------

    @isTest
    static void testGetAssessmentData_BalanceAndGait_HighRisk() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Balance & Gait Assessment',
            Status__c = 'Draft'
        );
        insert sa;

        Question_Master__c qBalance = createQuestion(
            'Balance & Gait Assessment',
            'Sitting Balance',
            1,
            'Single-Select',
            'Balance Assessment',
            'Leans or slides in chair;Steady, safe'
        );
        Question_Master__c qGait = createQuestion(
            'Balance & Gait Assessment',
            'Indication of Gait',
            2,
            'Single-Select',
            'Gait Assessment',
            'Any hesitancy or multiple attempts;No hesitancy'
        );

        insert new List<Assessment_Answer__c>{
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qBalance.Id,
                Answer__c = 'Steady, safe',
                Status__c = 'Completed'
            ),
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qGait.Id,
                Answer__c = 'No hesitancy',
                Status__c = 'Completed'
            )
        };

        Test.startTest();
        SecondaryAssessmentController.AssessmentViewerWrapper wrapper =
            SecondaryAssessmentController.getAssessmentData(sa.Id);
        Test.stopTest();

        System.assertEquals(1, wrapper.balanceScore);
        System.assertEquals(1, wrapper.gaitScore);
        System.assertEquals(2, wrapper.combinedScore);
        System.assertEquals('High Risk', wrapper.riskLevel);
    }

    @isTest
    static void testGetAssessmentData_NonBalanceGait_NoScoring() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Nursing Assessment',
            Status__c = 'Draft'
        );
        insert sa;

        Question_Master__c q =
            createQuestion('Nursing Assessment', 'Question 1', 1, 'Text', 'Section A', null);
        insert new Assessment_Answer__c(
            Secondary_Assessment__c = sa.Id,
            Assessment_Question__c = q.Id,
            Answer__c = 'Answer text',
            Status__c = 'Completed'
        );

        Test.startTest();
        SecondaryAssessmentController.AssessmentViewerWrapper wrapper =
            SecondaryAssessmentController.getAssessmentData(sa.Id);
        Test.stopTest();

        System.assertEquals(1, wrapper.questions.size());
        System.assertEquals(1, wrapper.answers.size());
        System.assertEquals(null, wrapper.riskLevel);
    }

    // ------------------------------------------------------------------
    // completeAssessment
    // ------------------------------------------------------------------

    @isTest
    static void testCompleteAssessment_Success() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Nursing Assessment',
            Status__c = 'Draft'
        );
        insert sa;

        Test.startTest();
        SecondaryAssessmentController.completeAssessment(sa.Id);
        Test.stopTest();

        SecondaryAssessment__c updated = [
            SELECT Status__c
            FROM SecondaryAssessment__c
            WHERE Id = :sa.Id
        ];
        System.assertEquals('Completed', updated.Status__c);
    }

    @isTest
    static void testCompleteAssessment_NullId_Throws() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            SecondaryAssessmentController.completeAssessment(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for null assessment Id.');
    }

    // ------------------------------------------------------------------
    // saveAssessmentAnswers
    // ------------------------------------------------------------------

    @isTest
    static void testSaveAssessmentAnswers_InsertAndUpdate() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Nursing Assessment'
        );
        insert sa;

        Question_Master__c q1 =
            createQuestion('Nursing Assessment', 'Question 1', 1, 'Text', 'Section A', null);
        Question_Master__c q2 =
            createQuestion('Nursing Assessment', 'Question 2', 2, 'Text', 'Section A', null);

        insert new Assessment_Answer__c(
            Secondary_Assessment__c = sa.Id,
            Assessment_Question__c = q1.Id,
            Answer__c = 'Old',
            Status__c = 'Completed'
        );

        SecondaryAssessmentController.QuestionAnswerWrapper qa1 =
            new SecondaryAssessmentController.QuestionAnswerWrapper();
        qa1.questionId = q1.Id;
        qa1.answer = 'Updated';
        qa1.notes = 'Updated note';

        SecondaryAssessmentController.QuestionAnswerWrapper qa2 =
            new SecondaryAssessmentController.QuestionAnswerWrapper();
        qa2.questionId = q2.Id;
        qa2.answer = 'New answer';
        qa2.notes = null;

        Test.startTest();
        SecondaryAssessmentController.saveAssessmentAnswers(
            sa.Id,
            new List<SecondaryAssessmentController.QuestionAnswerWrapper>{ qa1, qa2 }
        );
        Test.stopTest();

        Map<Id, Assessment_Answer__c> answersByQuestion = new Map<Id, Assessment_Answer__c>();
        for (Assessment_Answer__c a : [
            SELECT Assessment_Question__c, Answer__c, Notes__c
            FROM Assessment_Answer__c
            WHERE Secondary_Assessment__c = :sa.Id
        ]) {
            answersByQuestion.put(a.Assessment_Question__c, a);
        }

        System.assertEquals(2, answersByQuestion.size());
        System.assertEquals('Updated', answersByQuestion.get(q1.Id).Answer__c);
        System.assertEquals('New answer', answersByQuestion.get(q2.Id).Answer__c);
    }

    @isTest
    static void testSaveAssessmentAnswers_NullAssessmentId_Throws() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            SecondaryAssessmentController.saveAssessmentAnswers(
                null,
                new List<SecondaryAssessmentController.QuestionAnswerWrapper>()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for null assessment Id.');
    }

    @isTest
    static void testSaveAssessmentAnswers_EmptyOrNullAnswers_NoOp() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Nursing Assessment'
        );
        insert sa;

        Test.startTest();
        SecondaryAssessmentController.saveAssessmentAnswers(
            sa.Id,
            new List<SecondaryAssessmentController.QuestionAnswerWrapper>()
        );
        SecondaryAssessmentController.saveAssessmentAnswers(sa.Id, null);
        Test.stopTest();

        List<Assessment_Answer__c> results = [
            SELECT Id
            FROM Assessment_Answer__c
            WHERE Secondary_Assessment__c = :sa.Id
        ];
        System.assertEquals(0, results.size());
    }

    @isTest
    static void testSaveAssessmentAnswers_SkipsBlankNewAnswerAndNullQuestion() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Nursing Assessment'
        );
        insert sa;

        Question_Master__c q =
            createQuestion('Nursing Assessment', 'Question 1', 1, 'Text', 'Section A', null);

        SecondaryAssessmentController.QuestionAnswerWrapper blankAnswer =
            new SecondaryAssessmentController.QuestionAnswerWrapper();
        blankAnswer.questionId = q.Id;
        blankAnswer.answer = null;
        blankAnswer.notes = null;

        SecondaryAssessmentController.QuestionAnswerWrapper noQuestion =
            new SecondaryAssessmentController.QuestionAnswerWrapper();
        noQuestion.questionId = null;
        noQuestion.answer = 'Should be ignored';

        Test.startTest();
        SecondaryAssessmentController.saveAssessmentAnswers(
            sa.Id,
            new List<SecondaryAssessmentController.QuestionAnswerWrapper>{ blankAnswer, noQuestion }
        );
        Test.stopTest();

        List<Assessment_Answer__c> results = [
            SELECT Id
            FROM Assessment_Answer__c
            WHERE Secondary_Assessment__c = :sa.Id
        ];
        System.assertEquals(0, results.size());
    }

    // ------------------------------------------------------------------
    // deleteAssessment
    // ------------------------------------------------------------------

    @isTest
    static void testDeleteAssessment_Success() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Nursing Assessment'
        );
        insert sa;

        Question_Master__c q =
            createQuestion('Nursing Assessment', 'Question 1', 1, 'Text', 'Section A', null);
        insert new Assessment_Answer__c(
            Secondary_Assessment__c = sa.Id,
            Assessment_Question__c = q.Id,
            Answer__c = 'Answer',
            Status__c = 'Completed'
        );

        Test.startTest();
        Id returnedAccountId = SecondaryAssessmentController.deleteAssessment(sa.Id);
        Test.stopTest();

        System.assertEquals(acc.Id, returnedAccountId);

        List<SecondaryAssessment__c> remaining = [
            SELECT Id
            FROM SecondaryAssessment__c
            WHERE Id = :sa.Id
        ];
        System.assertEquals(0, remaining.size());

        List<Assessment_Answer__c> remainingAnswers = [
            SELECT Id
            FROM Assessment_Answer__c
            WHERE Secondary_Assessment__c = :sa.Id
        ];
        System.assertEquals(0, remainingAnswers.size());
    }

    @isTest
    static void testDeleteAssessment_NoAnswers_Success() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Nursing Assessment'
        );
        insert sa;

        Test.startTest();
        Id returnedAccountId = SecondaryAssessmentController.deleteAssessment(sa.Id);
        Test.stopTest();

        System.assertEquals(acc.Id, returnedAccountId);
    }

    @isTest
    static void testDeleteAssessment_NullId_Throws() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            SecondaryAssessmentController.deleteAssessment(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for null assessment Id.');
    }

    // ------------------------------------------------------------------
    // generateAndAttachPdf
    // ------------------------------------------------------------------

    @isTest
    static void testGenerateAndAttachPdf_NullId_Throws() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            SecondaryAssessmentController.generateAndAttachPdf(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for null assessment Id.');
    }

    @isTest
    static void testGenerateAndAttachPdf_FirstGeneration_GeriatricDepressionScale() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Geriatric Depression Scale',
            Status__c = 'Draft'
        );
        insert sa;

        Question_Master__c q = createQuestion(
            'Geriatric Depression Scale',
            'Are you basically satisfied with your life?',
            1,
            'Single-Select',
            'Section A',
            'Yes;No'
        );
        insert new Assessment_Answer__c(
            Secondary_Assessment__c = sa.Id,
            Assessment_Question__c = q.Id,
            Answer__c = 'No',
            Status__c = 'Completed'
        );

        Test.startTest();
        Boolean isUpdate = SecondaryAssessmentController.generateAndAttachPdf(sa.Id);
        Test.stopTest();

        System.assertEquals(false, isUpdate);

        SecondaryAssessment__c updated = [
            SELECT PDF_Generated__c
            FROM SecondaryAssessment__c
            WHERE Id = :sa.Id
        ];
        System.assertEquals(true, updated.PDF_Generated__c);

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :sa.Id
        ];
        System.assertEquals(1, links.size());
    }

    @isTest
    static void testGenerateAndAttachPdf_SecondGeneration_CreatesNewVersion() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Home from the Hospital Assessment',
            Status__c = 'Draft'
        );
        insert sa;

        Question_Master__c q = createQuestion(
            'Home from the Hospital Assessment',
            'Question 1',
            1,
            'Single-Select',
            'Section A',
            '1;2;3;4;5'
        );
        insert new Assessment_Answer__c(
            Secondary_Assessment__c = sa.Id,
            Assessment_Question__c = q.Id,
            Answer__c = '3',
            Status__c = 'Completed'
        );

        Test.startTest();
        SecondaryAssessmentController.generateAndAttachPdf(sa.Id);
        Boolean isUpdate = SecondaryAssessmentController.generateAndAttachPdf(sa.Id);
        Test.stopTest();

        System.assertEquals(true, isUpdate);
    }

    @isTest
    static void testGenerateAndAttachPdf_BalanceGaitAssessment() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Balance & Gait Assessment',
            Status__c = 'Draft'            
        );
        insert sa;

        Question_Master__c qBalance = createQuestion(
            'Balance & Gait Assessment',
            'Sitting Balance',
            1,
            'Single-Select',
            'Balance Assessment',
            'Leans or slides in chair;Steady, safe'
        );
        Question_Master__c qGait = createQuestion(
            'Balance & Gait Assessment',
            'Indication of Gait',
            2,
            'Single-Select',
            'Gait Assessment',
            'Any hesitancy or multiple attempts;No hesitancy'
        );

        insert new List<Assessment_Answer__c>{
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qBalance.Id,
                Answer__c = 'Steady, safe',
                Status__c = 'Completed'
            ),
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qGait.Id,
                Answer__c = 'No hesitancy',
                Status__c = 'Completed'
            )
        };

        Test.startTest();
        SecondaryAssessmentController.generateAndAttachPdf(sa.Id);
        Test.stopTest();

        SecondaryAssessment__c updated = [
            SELECT PDF_Generated__c
            FROM SecondaryAssessment__c
            WHERE Id = :sa.Id
        ];
        System.assertEquals(true, updated.PDF_Generated__c);
    }

    @isTest
    static void testGenerateAndAttachPdf_MiniMentalStateExamination() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Mini Mental State Examination',
            Status__c = 'Draft'            
        );
        insert sa;

        Question_Master__c q1 = createQuestion(
            'Mini Mental State Examination',
            'Orientation to time',
            1,
            'Number',
            'Orientation',
            null
        );
        Question_Master__c q11 = createQuestion(
            'Mini Mental State Examination',
            'Draw the pentagon',
            1,
            'Text',
            'Visuospatial',
            null
        );

        insert new List<Assessment_Answer__c>{
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = q1.Id,
                Answer__c = '5',
                Status__c = 'Completed'
            ),
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = q11.Id,
                Answer__c = '1',
                Status__c = 'Completed'
            )
        };

        Test.startTest();
        SecondaryAssessmentController.generateAndAttachPdf(sa.Id);
        Test.stopTest();

        SecondaryAssessment__c updated = [
            SELECT PDF_Generated__c
            FROM SecondaryAssessment__c
            WHERE Id = :sa.Id
        ];
        System.assertEquals(true, updated.PDF_Generated__c);
    }

    @isTest
    static void testGenerateAndAttachPdf_FamilyCaregiverMultiSelect() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Family Caregiver Assessment',
            Status__c = 'Draft'            
        );
        insert sa;

        Question_Master__c q = createQuestion(
            'Family Caregiver Assessment',
            'Support Question',
            1,
            'Multi-Select',
            'Section A',
            'Option1;Option2'
        );
        insert new Assessment_Answer__c(
            Secondary_Assessment__c = sa.Id,
            Assessment_Question__c = q.Id,
            Answer__c = 'Option1;Option2',
            Status__c = 'Completed'
        );

        Test.startTest();
        SecondaryAssessmentController.generateAndAttachPdf(sa.Id);
        Test.stopTest();

        SecondaryAssessment__c updated = [
            SELECT PDF_Generated__c
            FROM SecondaryAssessment__c
            WHERE Id = :sa.Id
        ];
        System.assertEquals(true, updated.PDF_Generated__c);
    }

    @isTest
    static void testGenerateAndAttachPdf_CaregiverAssessment_DaysAndDuration() {
        Account acc = createPersonAccount();
        SecondaryAssessment__c sa = new SecondaryAssessment__c(
            Account__c = acc.Id,
            Assessment_Type__c = 'Caregiver Assessment',
            Status__c = 'Draft'            
        );
        insert sa;

        Question_Master__c qDays = createQuestion(
            'Caregiver Assessment',
            'Days',
            1,
            'Multi-Select',
            'Care Schedule',
            'M;T;W;Th;Fri;S;Su'
        );
        Question_Master__c qHoursMon = createQuestion(
            'Caregiver Assessment',
            'Hours per Day - Monday',
            2,
            'Text',
            'Care Schedule',
            null
        );
        Question_Master__c qHoursTue = createQuestion(
            'Caregiver Assessment',
            'Hours per Day - Tuesday',
            3,
            'Text',
            'Care Schedule',
            null
        );
        Question_Master__c qYears = createQuestion(
            'Caregiver Assessment',
            'How long has caregiver been caring for care receiver - Years',
            4,
            'Number',
            'Care Duration',
            null
        );
        Question_Master__c qMonths = createQuestion(
            'Caregiver Assessment',
            'How long has caregiver been caring for care receiver - Months',
            5,
            'Number',
            'Care Duration',
            null
        );

        insert new List<Assessment_Answer__c>{
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qDays.Id,
                Answer__c = 'M;T',
                Status__c = 'Completed'
            ),
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qHoursMon.Id,
                Answer__c = '4',
                Status__c = 'Completed'
            ),
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qHoursTue.Id,
                Answer__c = '3',
                Status__c = 'Completed'
            ),
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qYears.Id,
                Answer__c = '2',
                Status__c = 'Completed'
            ),
            new Assessment_Answer__c(
                Secondary_Assessment__c = sa.Id,
                Assessment_Question__c = qMonths.Id,
                Answer__c = '6',
                Status__c = 'Completed'
            )
        };

        Test.startTest();
        SecondaryAssessmentController.generateAndAttachPdf(sa.Id);
        Test.stopTest();

        SecondaryAssessment__c updated = [
            SELECT PDF_Generated__c
            FROM SecondaryAssessment__c
            WHERE Id = :sa.Id
        ];
        System.assertEquals(true, updated.PDF_Generated__c);
    }
}