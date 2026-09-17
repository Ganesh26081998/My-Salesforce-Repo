@isTest
private class QuestionMasterTriggerHandlerTest {

    private static final String ASSESSMENT_TYPE =
        'Psychosocial Assessment';

    private static final String OTHER_ASSESSMENT_TYPE =
        'Geriatric Depression Scale';
    
    
    @TestSetup
    static void setupTestData() {
         WellSky_Custom_Setting__c cs = new WellSky_Custom_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Name = 'Bypass',
            Run_Triggers__c = true
        );
        insert cs;
    }

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------

    private static Question_Master__c buildQuestion(
        String assessmentType,
        Decimal sequence,
        String questionText,
        Boolean active
    ) {
        return new Question_Master__c(
            Assessment_Type__c = assessmentType,
            Sequence__c = sequence,
            Question_Text__c = questionText,
            Question_Type__c = 'Text',
            Active__c = active
        );
    }

    private static Map<String, Question_Master__c> queryByText(
        String assessmentType
    ) {

        Map<String, Question_Master__c> byText =
            new Map<String, Question_Master__c>();

        for (Question_Master__c q : [
            SELECT Id,
                   Question_Text__c,
                   Sequence__c,
                   Active__c,
                   Group__c,
                   Dependent_On_Question__c,
                   Show_When_Value__c
            FROM Question_Master__c
            WHERE Assessment_Type__c = :assessmentType
        ]) {
            byText.put(q.Question_Text__c, q);
        }

        return byText;
    }

    // ------------------------------------------------------------
    // Scenario 1: Normal ungrouped questions - clean 1,2,3 numbering
    // ------------------------------------------------------------

    @isTest
    static void testNormalQuestionsNumberSequentially() {

        Test.startTest();

        insert new List<Question_Master__c>{
            buildQuestion(ASSESSMENT_TYPE, 1, 'Q1', true),
            buildQuestion(ASSESSMENT_TYPE, 2, 'Q2', true),
            buildQuestion(ASSESSMENT_TYPE, 3, 'Q3', true)
        };

        Test.stopTest();

        Map<String, Question_Master__c> byText =
            queryByText(ASSESSMENT_TYPE);

        System.assertEquals(1, byText.get('Q1').Sequence__c);
        System.assertEquals(2, byText.get('Q2').Sequence__c);
        System.assertEquals(3, byText.get('Q3').Sequence__c);
    }

    // ------------------------------------------------------------
    // Scenario 2: Delete a middle question - gap closes
    // ------------------------------------------------------------

    @isTest
    static void testDeleteClosesGap() {

        insert new List<Question_Master__c>{
            buildQuestion(ASSESSMENT_TYPE, 1, 'Q1', true),
            buildQuestion(ASSESSMENT_TYPE, 2, 'Q2', true),
            buildQuestion(ASSESSMENT_TYPE, 3, 'Q3', true)
        };

        Question_Master__c q2 =
            queryByText(ASSESSMENT_TYPE).get('Q2');

        Test.startTest();
        delete q2;
        Test.stopTest();

        Map<String, Question_Master__c> byText =
            queryByText(ASSESSMENT_TYPE);

        System.assertEquals(
            2,
            byText.get('Q3').Sequence__c,
            'Q3 should shift down to fill the gap left by deleting Q2'
        );
    }

    // ------------------------------------------------------------
    // Scenario 3: Group__c decimal children (Financial Institution
    // style repeating rows) renumber alongside their parent
    // ------------------------------------------------------------

    @isTest
    static void testGroupedDecimalChildrenTrackParent() {

        Test.startTest();

        insert new List<Question_Master__c>{
            new Question_Master__c(
                Assessment_Type__c = ASSESSMENT_TYPE,
                Sequence__c = 1,
                Question_Text__c = 'Name',
                Question_Type__c = 'Text',
                Group__c = 'Financial Institution',
                Active__c = true
            ),
            new Question_Master__c(
                Assessment_Type__c = ASSESSMENT_TYPE,
                Sequence__c = 1.1,
                Question_Text__c = 'Location',
                Question_Type__c = 'Text',
                Group__c = 'Financial Institution',
                Active__c = true
            ),
            new Question_Master__c(
                Assessment_Type__c = ASSESSMENT_TYPE,
                Sequence__c = 1.2,
                Question_Text__c = 'Phone',
                Question_Type__c = 'Phone',
                Group__c = 'Financial Institution',
                Active__c = true
            ),
            buildQuestion(ASSESSMENT_TYPE, 2, 'NextQ', true)
        };

        Test.stopTest();

        Map<String, Question_Master__c> byText =
            queryByText(ASSESSMENT_TYPE);

        System.assertEquals(1, byText.get('Name').Sequence__c);
        System.assertEquals(1.1, byText.get('Location').Sequence__c);
        System.assertEquals(1.2, byText.get('Phone').Sequence__c);
        System.assertEquals(2, byText.get('NextQ').Sequence__c);
    }

    @isTest
    static void testGroupedDecimalChildrenShiftWhenParentShifts() {

        insert new List<Question_Master__c>{
            new Question_Master__c(
                Assessment_Type__c = ASSESSMENT_TYPE,
                Sequence__c = 1,
                Question_Text__c = 'Name',
                Question_Type__c = 'Text',
                Group__c = 'Financial Institution',
                Active__c = true
            ),
            new Question_Master__c(
                Assessment_Type__c = ASSESSMENT_TYPE,
                Sequence__c = 1.1,
                Question_Text__c = 'Location',
                Question_Type__c = 'Text',
                Group__c = 'Financial Institution',
                Active__c = true
            )
        };

        Test.startTest();

        // Insert a new question at position 1, which should push the
        // grouped "Name"/"Location" pair down to 2 / 2.1.
        insert buildQuestion(ASSESSMENT_TYPE, 1, 'InsertedFirst', true);

        Test.stopTest();

        Map<String, Question_Master__c> byText =
            queryByText(ASSESSMENT_TYPE);
       
        System.assertEquals(
            2.1,
            byText.get('Location').Sequence__c,
            'Grouped decimal child should track its parent\'s new number'
        );
    }

    // ------------------------------------------------------------
    // Scenario 4: Dependent_On_Question__c children track their
    // parent's new number when the parent is renumbered - this is
    // the exact bug scenario from the conversation (insert at an
    // existing number should push the old occupant + its dependent
    // down together).
    // ------------------------------------------------------------

    @isTest
    static void testDependentChildTracksParentOnInsertTie() {

        // Pad with 4 real questions first so "position 5" is a
        // genuine slot in the sequence, not an arbitrary number that
        // gets immediately compacted away.
        insert new List<Question_Master__c>{
            buildQuestion(ASSESSMENT_TYPE, 1, 'Filler1', true),
            buildQuestion(ASSESSMENT_TYPE, 2, 'Filler2', true),
            buildQuestion(ASSESSMENT_TYPE, 3, 'Filler3', true),
            buildQuestion(ASSESSMENT_TYPE, 4, 'Filler4', true)
        };

        Question_Master__c parent = buildQuestion(
            ASSESSMENT_TYPE, 5, 'Any change in residence during the past year?', true
        );
        insert parent;

        Question_Master__c dependent = buildQuestion(
            ASSESSMENT_TYPE, 5.1, 'If yes, where and why?', true
        );
        dependent.Dependent_On_Question__c = parent.Id;
        dependent.Show_When_Value__c = 'Yes';
        insert dependent;

        Question_Master__c q6 = buildQuestion(ASSESSMENT_TYPE, 6, 'NextQuestion', true);
        insert q6;

        // Confirm the "before" state is what we expect, given the
        // padding, before making the change under test.
        Map<String, Question_Master__c> before =
            queryByText(ASSESSMENT_TYPE);

        System.assertEquals(
            5,
            before.get('Any change in residence during the past year?').Sequence__c,
            'Sanity check: parent should be at 5 before the tie-break insert'
        );
        System.assertEquals(
            6,
            before.get('NextQuestion').Sequence__c,
            'Sanity check: NextQuestion should be at 6 before the tie-break insert'
        );

        Test.startTest();

        // Insert a brand-new question claiming sequence 5 - the
        // existing "5" (and its dependent "5.1") should be pushed to
        // 6 / 6.1, and the old "6" should become 7.
        insert buildQuestion(ASSESSMENT_TYPE, 5, 'Test Q', true);

        Test.stopTest();

        Map<String, Question_Master__c> byText =
            queryByText(ASSESSMENT_TYPE);

        System.assertEquals(
            5,
            byText.get('Test Q').Sequence__c,
            'Newly inserted record should win the tie and keep the typed number'
        );
        System.assertEquals(
            6,
            byText.get('Any change in residence during the past year?').Sequence__c,
            'Displaced parent should move to the next slot'
        );
        System.assertEquals(
            6.1,
            byText.get('If yes, where and why?').Sequence__c,
            'Dependent child must follow its parent\'s new number'
        );
        System.assertEquals(
            7,
            byText.get('NextQuestion').Sequence__c,
            'Everything after the displaced block should shift by one'
        );
    }

    @isTest
    static void testMultipleDependentChildrenPreserveRelativeOrder() {

        // Pad first so the parent's starting position (6) is a real,
        // deliberate slot rather than something that gets instantly
        // compacted to 1 for lack of any other active questions.
        insert new List<Question_Master__c>{
            buildQuestion(ASSESSMENT_TYPE, 1, 'Filler1', true),
            buildQuestion(ASSESSMENT_TYPE, 2, 'Filler2', true),
            buildQuestion(ASSESSMENT_TYPE, 3, 'Filler3', true),
            buildQuestion(ASSESSMENT_TYPE, 4, 'Filler4', true),
            buildQuestion(ASSESSMENT_TYPE, 5, 'Filler5', true)
        };

        Question_Master__c parent =
            buildQuestion(ASSESSMENT_TYPE, 6, 'Parent Q', true);
        insert parent;

        Question_Master__c dependent1 =
            buildQuestion(ASSESSMENT_TYPE, 6.1, 'First follow-up', true);
        dependent1.Dependent_On_Question__c = parent.Id;
        dependent1.Show_When_Value__c = 'OptionA';

        Question_Master__c dependent2 =
            buildQuestion(ASSESSMENT_TYPE, 6.2, 'Second follow-up', true);
        dependent2.Dependent_On_Question__c = parent.Id;
        dependent2.Show_When_Value__c = 'OptionB';

        insert new List<Question_Master__c>{ dependent1, dependent2 };

        // Sanity check the "before" state given the padding, before
        // making the change under test.
        Map<String, Question_Master__c> before =
            queryByText(ASSESSMENT_TYPE);

        Decimal parentSeqBefore = before.get('Parent Q').Sequence__c;

        System.assertEquals(
            6,
            parentSeqBefore,
            'Sanity check: parent should be at 6 before the displacing insert'
        );

        Test.startTest();

        // Push the parent down by one slot by inserting something new
        // at its current number.
        insert buildQuestion(ASSESSMENT_TYPE, 6, 'InsertedBeforeParent', true);

        Test.stopTest();

        Map<String, Question_Master__c> byText =
            queryByText(ASSESSMENT_TYPE);

        Decimal parentSeqAfter = byText.get('Parent Q').Sequence__c;

        System.assertEquals(
            parentSeqBefore + 1,
            parentSeqAfter,
            'Parent should be displaced down by exactly one slot'
        );
        System.assertEquals(
            parentSeqAfter + 0.1,
            byText.get('First follow-up').Sequence__c,
            'First dependent should keep its relative-first position, anchored to parent\'s NEW number'
        );
        System.assertEquals(
            parentSeqAfter + 0.2,
            byText.get('Second follow-up').Sequence__c,
            'Second dependent should keep its relative-second position, anchored to parent\'s NEW number'
        );
    }

    @isTest
    static void testDependentQuestionItselfNeverGetsATopLevelNumber() {

        Question_Master__c parent =
            buildQuestion(ASSESSMENT_TYPE, 1, 'Parent Q', true);
        insert parent;

        Question_Master__c dependent =
            buildQuestion(ASSESSMENT_TYPE, 1.1, 'Dependent Q', true);
        dependent.Dependent_On_Question__c = parent.Id;
        dependent.Show_When_Value__c = 'Yes';

        Test.startTest();
        insert dependent;
        Test.stopTest();

        Question_Master__c reQueried = [
            SELECT Sequence__c
            FROM Question_Master__c
            WHERE Id = :dependent.Id
        ];

        System.assertEquals(
            1.1,
            reQueried.Sequence__c,
            'A dependent question must never be assigned a bare integer'
        );
    }

    // ------------------------------------------------------------
    // Scenario 5: Reactivation (Active__c false -> true) triggers
    // renumbering and re-anchors any dependent children
    // ------------------------------------------------------------

    @isTest
    static void testReactivationRenumbersAndTracksDependent() {

        Question_Master__c parent =
            buildQuestion(ASSESSMENT_TYPE, 1, 'AlwaysActive', true);
        insert parent;

        Question_Master__c toDeactivate =
            buildQuestion(ASSESSMENT_TYPE, 2, 'WillBeInactive', true);
        insert toDeactivate;

        Question_Master__c dependentOfDeactivated =
            buildQuestion(ASSESSMENT_TYPE, 2.1, 'DependentOfInactive', true);
        dependentOfDeactivated.Dependent_On_Question__c = toDeactivate.Id;
        dependentOfDeactivated.Show_When_Value__c = 'Yes';
        insert dependentOfDeactivated;

        Question_Master__c backfill =
            buildQuestion(ASSESSMENT_TYPE, 3, 'Backfill', true);
        insert backfill;

        // Deactivate - active set becomes AlwaysActive(1), Backfill(now 2)
        toDeactivate.Active__c = false;
        update toDeactivate;

        System.assertEquals(
            2,
            [SELECT Sequence__c FROM Question_Master__c WHERE Id = :backfill.Id]
                .Sequence__c,
            'Backfill should have moved into the gap after deactivation'
        );

        Test.startTest();

        // Reactivate - should get folded back in and renumbered, and
        // its dependent should track wherever it lands.
        toDeactivate.Active__c = true;
        update toDeactivate;

        // Keep the dependent active too, matching the parent, since
        // it was never toggled itself in this test.
        Test.stopTest();

        Question_Master__c reactivated = [
            SELECT Sequence__c
            FROM Question_Master__c
            WHERE Id = :toDeactivate.Id
        ];

        Question_Master__c itsDependent = [
            SELECT Sequence__c
            FROM Question_Master__c
            WHERE Id = :dependentOfDeactivated.Id
        ];

        System.assertEquals(
            Math.floor(reactivated.Sequence__c) + 0.1,
            itsDependent.Sequence__c,
            'Dependent must be re-anchored to its parent\'s post-reactivation number'
        );
    }

    // ------------------------------------------------------------
    // Scenario 6: Undelete restores and renumbers correctly
    // ------------------------------------------------------------

    @isTest
    static void testUndeleteRenumbers() {

        Question_Master__c q1 = buildQuestion(ASSESSMENT_TYPE, 1, 'Q1', true);
        Question_Master__c q2 = buildQuestion(ASSESSMENT_TYPE, 2, 'Q2', true);
        insert new List<Question_Master__c>{ q1, q2 };

        delete q2;

        Test.startTest();
        undelete q2;
        Test.stopTest();

        Question_Master__c restored = [
            SELECT Sequence__c
            FROM Question_Master__c
            WHERE Id = :q2.Id
        ];

        System.assertNotEquals(
            null,
            restored.Sequence__c,
            'Undeleted record should be folded back into the active numbering'
        );
    }

    // ------------------------------------------------------------
    // Scenario 7: Recursion guard - the corrective update the
    // handler performs must not cause infinite re-processing
    // ------------------------------------------------------------

    @isTest
    static void testRenumberingUpdateDoesNotRecurse() {

        Test.startTest();

        // Insert with a deliberately "wrong" Sequence__c so the
        // handler is guaranteed to issue a corrective update.
        insert new List<Question_Master__c>{
            buildQuestion(ASSESSMENT_TYPE, 99, 'Q1', true),
            buildQuestion(ASSESSMENT_TYPE, 98, 'Q2', true)
        };

        Test.stopTest();

        // If recursion guard failed, this would have hit a
        // "maximum trigger depth exceeded" or similar governor
        // error before reaching this assertion.
        Map<String, Question_Master__c> byText =
            queryByText(ASSESSMENT_TYPE);

        System.assertEquals(1, byText.get('Q2').Sequence__c);
        System.assertEquals(2, byText.get('Q1').Sequence__c);
    }

    // ------------------------------------------------------------
    // Scenario 8: Different Assessment_Type__c values are numbered
    // independently and never cross-contaminate each other
    // ------------------------------------------------------------

    @isTest
    static void testAssessmentTypesAreIsolated() {

        Test.startTest();

        insert new List<Question_Master__c>{
            buildQuestion(ASSESSMENT_TYPE, 1, 'A-Q1', true),
            buildQuestion(ASSESSMENT_TYPE, 2, 'A-Q2', true),
            buildQuestion(OTHER_ASSESSMENT_TYPE, 1, 'B-Q1', true)
        };

        Test.stopTest();

        Question_Master__c bQ1 =
            queryByText(OTHER_ASSESSMENT_TYPE).get('B-Q1');

        System.assertEquals(
            1,
            bQ1.Sequence__c,
            'A separate Assessment_Type__c should number from 1 independently'
        );
    }

    // ------------------------------------------------------------
    // Scenario 9: Inactive questions are excluded from renumbering
    // entirely and are not touched
    // ------------------------------------------------------------

    @isTest
    static void testInactiveQuestionsAreIgnored() {

        Question_Master__c inactiveQ =
            buildQuestion(ASSESSMENT_TYPE, 50, 'InactiveQ', false);
        insert inactiveQ;

        Test.startTest();

        insert buildQuestion(ASSESSMENT_TYPE, 1, 'ActiveQ', true);

        Test.stopTest();

        Question_Master__c reQueried = [
            SELECT Sequence__c
            FROM Question_Master__c
            WHERE Id = :inactiveQ.Id
        ];

        System.assertEquals(
            50,
            reQueried.Sequence__c,
            'Inactive question must be left completely untouched'
        );
    }

    // ------------------------------------------------------------
    // Scenario 10: Editing an unrelated field (not Active__c) does
    // NOT trigger renumbering, per the stated requirement
    // ------------------------------------------------------------

    @isTest
    static void testNonActiveFieldEditDoesNotRenumber() {

        Question_Master__c q1 =
            buildQuestion(ASSESSMENT_TYPE, 5, 'Q1', true);
        insert q1;

        Test.startTest();

        q1.Question_Text__c = 'Q1 - edited text only';
        update q1;

        Test.stopTest();

        Question_Master__c reQueried = [
            SELECT Sequence__c
            FROM Question_Master__c
            WHERE Id = :q1.Id
        ];

        System.assertEquals(
            5,
            reQueried.Sequence__c,
            'A non-Active__c field edit must not trigger renumbering'
        );
    }

    // ------------------------------------------------------------
    // Scenario 11: Bulk insert (200 records) stays within governor
    // limits - single SOQL, single DML regardless of volume
    // ------------------------------------------------------------

    @isTest
    static void testBulkInsertStaysWithinLimits() {

        List<Question_Master__c> bulkQuestions =
            new List<Question_Master__c>();

        for (Integer i = 0; i < 200; i++) {
            bulkQuestions.add(
                buildQuestion(
                    ASSESSMENT_TYPE,
                    200 - i, // insert in reverse order on purpose
                    'BulkQ' + i,
                    true
                )
            );
        }

        Test.startTest();
        insert bulkQuestions;
        Test.stopTest();

        List<Question_Master__c> result = [
            SELECT Sequence__c
            FROM Question_Master__c
            WHERE Assessment_Type__c = :ASSESSMENT_TYPE
            ORDER BY Sequence__c ASC
        ];

        System.assertEquals(200, result.size());

        for (Integer i = 0; i < result.size(); i++) {
            System.assertEquals(
                i + 1,
                result[i].Sequence__c,
                'Sequence__c should be a clean 1..200 run with no gaps'
            );
        }
    }
}