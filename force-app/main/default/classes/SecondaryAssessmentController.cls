/*
Author          : Narayana Raja Bommidi
Class Name      : SecondaryAssessmentController
CreatedOn       : 7/2/2026
LastModifiedBy  : Narayana Raja Bommidi
LastModifiedOn  : 8/12/2026
Description     : This controller class manages Secondary Assessment operations,
                    including loading assessment questions and answers, creating
                    assessments, saving and updating assessment responses,
                    retrieving assessment data, calculating assessment scores,
                    and supporting assessment-related PDF generation and file
                    management.
*/

public with sharing class SecondaryAssessmentController {

    @AuraEnabled(cacheable=true)
    public static QuestionWrapper getQuestions(
        String assessmentType,
        Id accountId
    ) {

        QuestionWrapper wrapper = new QuestionWrapper();

wrapper.questions = [
    SELECT Id,
           Question_Text__c,
           Question_Type__c,
           Sequence__c,
           Answer_Options__c,
           Section__c,
           Group__c,
           HelpText__c,
           Dependent_On_Question__c,
           Dependent_On_Question__r.Question_Text__c,
           Show_When_Value__c,
           Show_Notes__c,
           Notes_Label__c
    FROM Question_Master__c
    WHERE Assessment_Type__c = :assessmentType
    AND Active__c = true
    ORDER BY Sequence__c
];

wrapper.contactOptions = new List<ContactOption>();

if (
    assessmentType == 'Caregiver Assessment' &&
    accountId != null
) {

    Account acct = [
        SELECT PersonContactId
        FROM Account
        WHERE Id = :accountId
        LIMIT 1
    ];

    for (HealthCloudGA__ContactContactRelation__c rel : [

        SELECT
        Id,
        Type__c,
        Relationship_to_Client__c,
        Family_Relationship__c,
        Other_Relationship_to_Client__c,
        HealthCloudGA__Contact__r.Name,
        HealthCloudGA__Contact__r.Title

        FROM HealthCloudGA__ContactContactRelation__c

        WHERE HealthCloudGA__RelatedContact__c =
            :acct.PersonContactId

        AND Type__c IN (
            'Family Contact',
            'Business Contact'
        )

        ORDER BY HealthCloudGA__Contact__r.Name
    ]) {

         String relation = '';

if (rel.Type__c == 'Family Contact') {

    if (rel.Relationship_to_Client__c == 'Family') {

        relation = rel.Family_Relationship__c;

    } else if (rel.Relationship_to_Client__c == 'Other') {

        relation = rel.Other_Relationship_to_Client__c;

    } else {

        // Friend/Neighbor, etc.
        relation = rel.Relationship_to_Client__c;
    }

} else {

    // Organization Contact
    relation = rel.HealthCloudGA__Contact__r.Title;
}

// Build label
String label = rel.HealthCloudGA__Contact__r.Name;

if (String.isNotBlank(relation)) {
    label += ' - ' + relation;
}

ContactOption option = new ContactOption();
option.label = label;
option.value = label;

wrapper.contactOptions.add(option);
    }
}

return wrapper;
    }

    @AuraEnabled
    public static Id saveAssessment(Id accountId,
                                    String assessmentType,
                                    List<QuestionAnswerWrapper> answers){
        if (answers == null) {
            answers = new List<QuestionAnswerWrapper>();
        }

        SecondaryAssessment__c assessment =
            new SecondaryAssessment__c();

        assessment.Account__c = accountId;
        assessment.Assessment_Type__c = assessmentType; 

        if (assessmentType == 'Family Caregiver Assessment') {

            Account acct = [
                SELECT PersonContactId
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];

            Integer familyContactCount = [
                SELECT COUNT()
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE HealthCloudGA__RelatedContact__c = :acct.PersonContactId
                AND Type__c = 'Family Contact'
            ];

            if (familyContactCount == 0) {
                throw new AuraHandledException(
                    'A Family Caregiver Assessment can only be created when the client has at least one Family Contact.'
                );
            }
        }       

        insert assessment;

        List<Assessment_Answer__c> answerList =
            new List<Assessment_Answer__c>();

        for(QuestionAnswerWrapper qa : answers){

            if (qa.questionId == null || 
            (
                String.isBlank(qa.answer) &&
                String.isBlank(qa.notes)
            )) {
                continue;
            }

            Assessment_Answer__c ans = new Assessment_Answer__c();

            ans.Secondary_Assessment__c = assessment.Id;
            ans.Assessment_Question__c = qa.questionId;
            ans.Answer__c = qa.answer;
            ans.Status__c = 'Completed';
            ans.Notes__c = qa.notes;
            answerList.add(ans);
        }

        if(!answerList.isEmpty()){
            insert answerList;
        }

        return assessment.Id;
    }

    @AuraEnabled(cacheable=true)
    public static List<SecondaryAssessment__c> getAssessments(Id accountId) {

        if(accountId == null){
            return new List<SecondaryAssessment__c>();
        }

        return [
            SELECT Id,
                Name,
                Assessment_Type__c,
                CreatedDate,
                CreatedBy.Name
            FROM SecondaryAssessment__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
        ];
    } 

    @AuraEnabled
    public static AssessmentViewerWrapper getAssessmentData(Id assessmentId){

        AssessmentViewerWrapper wrapper = new AssessmentViewerWrapper();

        wrapper.assessment = [

            SELECT Id,
                Assessment_Type__c,
                Account__c,
                Account__r.Name,
                Account__r.PersonContactId,
                CreatedDate,
                Status__c,
                LastModifiedDate
            FROM SecondaryAssessment__c

            WHERE Id=:assessmentId

            LIMIT 1
        ];

        wrapper.questions = [

            SELECT Id,
                Question_Text__c,
                Question_Type__c,
                Sequence__c,
                Answer_Options__c,
                Section__c,
                Group__c,
                HelpText__c,
                Dependent_On_Question__c,
                Dependent_On_Question__r.Question_Text__c,
                Show_When_Value__c,
                Show_Notes__c,
                Notes_Label__c
            FROM Question_Master__c

            WHERE Assessment_Type__c=:wrapper.assessment.Assessment_Type__c
            AND Active__c=true

            ORDER BY Sequence__c
        ];

        wrapper.answers = [

            SELECT Id,
                Assessment_Question__c,
                Answer__c,
                Notes__c
            FROM Assessment_Answer__c

            WHERE Secondary_Assessment__c=:assessmentId
        ];

        wrapper.contactOptions = new List<ContactOption>();

if (wrapper.assessment.Assessment_Type__c == 'Caregiver Assessment') {

    for (HealthCloudGA__ContactContactRelation__c rel : [

        SELECT
            Id,
            Type__c,
            Relationship_to_Client__c,
            Family_Relationship__c,
            Other_Relationship_to_Client__c,
            HealthCloudGA__Contact__r.Name,
            HealthCloudGA__Contact__r.Title

        FROM HealthCloudGA__ContactContactRelation__c

        WHERE HealthCloudGA__RelatedContact__c =
            :wrapper.assessment.Account__r.PersonContactId

        AND Type__c IN (
            'Family Contact',
            'Business Contact'
        )

        ORDER BY HealthCloudGA__Contact__r.Name

    ]) {

        String relation = '';

if (rel.Type__c == 'Family Contact') {

    if (rel.Relationship_to_Client__c == 'Family') {

        relation = rel.Family_Relationship__c;

    } else if (rel.Relationship_to_Client__c == 'Other') {

        relation = rel.Other_Relationship_to_Client__c;

    } else {

        // Friend/Neighbor, etc.
        relation = rel.Relationship_to_Client__c;
    }

} else {

    // Organization Contact
    relation = rel.HealthCloudGA__Contact__r.Title;
}

// Build label
String label = rel.HealthCloudGA__Contact__r.Name;

if (String.isNotBlank(relation)) {
    label += ' - ' + relation;
}

ContactOption option = new ContactOption();
option.label = label;
option.value = label;

wrapper.contactOptions.add(option);
    }
}

        if (
    wrapper.assessment.Assessment_Type__c ==
    'Balance & Gait Assessment'
) {

    Map<Id, Question_Master__c> questionMap =
        new Map<Id, Question_Master__c>(
            wrapper.questions
        );

    Integer balanceScore = 0;
    Integer gaitScore = 0;

    for (
        Assessment_Answer__c answer :
        wrapper.answers
    ) {

        Question_Master__c question =
            questionMap.get(
                answer.Assessment_Question__c
            );

        if (question == null) {
            continue;
        }

        Integer answerScore =
            getBalanceGaitAnswerScore(
                question.Question_Text__c,
                answer.Answer__c
            );

        if (answerScore == null) {
            continue;
        }

        if (
            question.Section__c ==
            'Balance Assessment'
        ) {
            balanceScore += answerScore;

        } else if (
            question.Section__c ==
            'Gait Assessment'
        ) {
            gaitScore += answerScore;
        }
    }

    wrapper.balanceScore = balanceScore;
    wrapper.gaitScore = gaitScore;
    wrapper.combinedScore =
        balanceScore + gaitScore;

    if (wrapper.combinedScore <= 18) {

        wrapper.riskLevel = 'High Risk';

    } else if (
        wrapper.combinedScore <= 23
    ) {

        wrapper.riskLevel =
            'Moderate Risk';

    } else {

        wrapper.riskLevel = 'Low Risk';
    }
}

        return wrapper;
    }

    @AuraEnabled
public static void completeAssessment(Id assessmentId) {

    if (assessmentId == null) {
        throw new AuraHandledException(
            'Assessment Id is required.'
        );
    }

    SecondaryAssessment__c assessment = [
        SELECT Id,
               Status__c
        FROM SecondaryAssessment__c
        WHERE Id = :assessmentId
        LIMIT 1
    ];

    assessment.Status__c = 'Completed';

    update assessment;
}

    @AuraEnabled
    public static void saveAssessmentAnswers(
        Id assessmentId,
        List<QuestionAnswerWrapper> answers
    ) {
        if (assessmentId == null) {
            throw new AuraHandledException('Assessment Id is required.');
        }

        if (answers == null || answers.isEmpty()) {
            return;
        }

        Map<Id, Assessment_Answer__c> existingAnswerMap =
            new Map<Id, Assessment_Answer__c>();

        for (Assessment_Answer__c answer : [
            SELECT Id,
                Assessment_Question__c,
                Answer__c,
                Notes__c
            FROM Assessment_Answer__c
            WHERE Secondary_Assessment__c = :assessmentId
        ]) {
            existingAnswerMap.put(
                answer.Assessment_Question__c,
                answer
            );
        }

        List<Assessment_Answer__c> answersToUpsert =
            new List<Assessment_Answer__c>();

        for (QuestionAnswerWrapper qa : answers) {

            // if (
            //     qa.questionId == null ||
            //     (
            //         String.isBlank(qa.answer) &&
            //         String.isBlank(qa.notes)
            //     )
            // ) {
            //     continue;
            // }

           if (qa.questionId == null) {
        continue;
        }

            if (existingAnswerMap.containsKey(qa.questionId)) {

                // Existing answer → Update
                Assessment_Answer__c existingAnswer =
                    existingAnswerMap.get(qa.questionId);

                existingAnswer.Answer__c = qa.answer;
                existingAnswer.Notes__c = qa.notes;

                answersToUpsert.add(existingAnswer);

            } else {

                if (
        String.isBlank(qa.answer) &&
        String.isBlank(qa.notes)
        ) {
            continue;
        }

                // Previously unanswered question → Insert
                Assessment_Answer__c newAnswer =
                    new Assessment_Answer__c();

                newAnswer.Secondary_Assessment__c =
                    assessmentId;

                newAnswer.Assessment_Question__c =
                    qa.questionId;

                newAnswer.Answer__c =
                    qa.answer;
                
                newAnswer.Notes__c =
                    qa.notes;

                newAnswer.Status__c =
                    'Completed';

                answersToUpsert.add(newAnswer);
            }
        }

        if (!answersToUpsert.isEmpty()) {
            upsert answersToUpsert;

            SecondaryAssessment__c assessment = new SecondaryAssessment__c(
                Id = assessmentId
            );

            update assessment;
        }
    }

    @AuraEnabled
    public static Id deleteAssessment(Id assessmentId) {

        if (assessmentId == null) {
            throw new AuraHandledException(
                'Assessment Id is required.'
            );
        }

        SecondaryAssessment__c assessment = [
            SELECT Id,
                Account__c
            FROM SecondaryAssessment__c
            WHERE Id = :assessmentId
            LIMIT 1
        ];

        Id accountId = assessment.Account__c;

        List<Assessment_Answer__c> answers = [
            SELECT Id
            FROM Assessment_Answer__c
            WHERE Secondary_Assessment__c = :assessmentId
        ];

        if (!answers.isEmpty()) {
            delete answers;
        }

        delete assessment;

        return accountId;
    }



//method for pdf
    @AuraEnabled
public static Boolean generateAndAttachPdf(Id assessmentId) {

    System.debug('generateAndAttachPdf');

    if (assessmentId == null) {
        throw new AuraHandledException(
            'Assessment Id is required.'
        );
    }

    Boolean isUpdate = false;

    SecondaryAssessment__c assessment = [
        SELECT Id,
               Name,
               Assessment_Type__c,
               Account__r.Name,
               CreatedDate,
               Name__c,
               PDF_Generated__c,
               Status__c,
               LastModifiedDate
        FROM SecondaryAssessment__c
        WHERE Id = :assessmentId
        LIMIT 1
    ];

    List<Question_Master__c> questions = [
        SELECT Id,
               Question_Text__c,
               Question_Type__c,
               Sequence__c,
               Section__c,
               Group__c,
               HelpText__c,
               Dependent_On_Question__c,
               Show_When_Value__c,
               Answer_Options__c
        FROM Question_Master__c
        WHERE Assessment_Type__c = :assessment.Assessment_Type__c
        AND Active__c = true
        ORDER BY Sequence__c
    ];

    Map<Id, Assessment_Answer__c> answerMap =
        new Map<Id, Assessment_Answer__c>();

    for (Assessment_Answer__c answer : [
        SELECT Id,
               Assessment_Question__c,
               Answer__c,
               Notes__c
        FROM Assessment_Answer__c
        WHERE Secondary_Assessment__c = :assessmentId
    ]) {
        answerMap.put(
            answer.Assessment_Question__c,
            answer
        );
    }

     Blob pdfBlob;

    try {

        System.debug('In try');

        System.debug('Step 1');
        String html = buildAssessmentPdfHtml(
            assessment,
            questions,
            answerMap
        );
    //     String html =
    // '<html><body>Test PDF</body></html>';

        System.debug('Step 2');

        pdfBlob = Blob.toPdf(html);

        System.debug('Step 3');

    } catch (Exception e) {
        System.debug('In Catch');

        System.debug('PDF ERROR: ' + e.getMessage());
        System.debug(e.getStackTraceString());

        throw e;
    }

    String fileName =        
        assessment.Name__c;

    List<ContentDocumentLink> existingLinks = [
    SELECT ContentDocumentId,
           ContentDocument.Title
    FROM ContentDocumentLink
    WHERE LinkedEntityId = :assessmentId
    AND ContentDocument.Title = :fileName
    LIMIT 1
];

    Id contentDocumentId;

if (!existingLinks.isEmpty()) {
     isUpdate = true;

    // Existing PDF → create a new version
    contentDocumentId =
        existingLinks[0].ContentDocumentId;

    ContentVersion newVersion = new ContentVersion(
        Title = fileName,
        PathOnClient = fileName + '.pdf',
        VersionData = pdfBlob,
        ContentDocumentId = contentDocumentId
    );

    insert newVersion;

} else {

    // First generation → create new File
    ContentVersion newFile = new ContentVersion(
        Title = fileName,
        PathOnClient = fileName + '.pdf',
        VersionData = pdfBlob
    );

    insert newFile;

    newFile = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :newFile.Id
    ];

    contentDocumentId =
        newFile.ContentDocumentId;

    insert new ContentDocumentLink(
        ContentDocumentId = contentDocumentId,
        LinkedEntityId = assessmentId,
        ShareType = 'V'
    );
}

assessment.PDF_Generated__c = true;
update assessment;

return isUpdate;
}

private static String buildAssessmentPdfHtml(
    SecondaryAssessment__c assessment,
    List<Question_Master__c> questions,
    Map<Id, Assessment_Answer__c> answerMap
) {

    String html = '';

    html += '<html>';
    html += '<head>';

    html += '<style>';

    html += '@page {';
    html += '    size: A4;';
    html += '    margin: 35px;';
    html += '}';

    html += 'body {';
    html += '    font-family: Arial, sans-serif;';
    html += '    font-size: 12px;';
    html += '    color: #181818;';
    html += '}';

    html += '.title {';
    html += '    text-align: center;';
    html += '    font-size: 20px;';
    html += '    font-weight: bold;';
    html += '    margin-bottom: 25px;';
    html += '}';

    html += '.header-table {';
    html += '    width: 100%;';
    html += '    margin-bottom: 20px;';
    html += '}';

    html += '.header-table td {';
    html += '    width: 50%;';
    html += '}';

    html += '.question {';
html += '    border: 1px solid #dddddd;';
html += '    padding: 10px;';
html += '    margin-bottom: 10px;';
html += '    page-break-inside: avoid;';
html += '    break-inside: avoid;';
html += '}';

    html += '.question-text {';
    html += '    font-weight: bold;';
    html += '    margin-bottom: 6px;';
    html += '}';

    html += '.answer {';
html += '    margin-left: 15px;';
html += '    width: 100%;';
html += '    word-break: break-all;';
html += '    white-space: normal;';
html += '}';

    html += '.score {';
    html += '    background: #f3f3f3;';
    html += '    border: 1px solid #dddddd;';
    html += '    padding: 12px;';
    html += '    margin-top: 20px;';
    html += '}';

    html += '.section-title {';
    html += '    font-size: 16px;';
    html += '    font-weight: bold;';
    html += '    background: #f3f3f3;';
    html += '    border-bottom: 2px solid #444444;';
    html += '    padding: 8px;';
    html += '    margin-top: 20px;';
    html += '    margin-bottom: 10px;';
    html += '}';

    html += '.notes {';
    html += '    margin-top: 8px;';
    html += '    padding-top: 6px;';
    html += '    border-top: 1px solid #eeeeee;';
    html += '}';

    html += '</style>';
    html += '</head>';

    html += '<body>';

    // Title
    html += '<div class="title">';
    html += escapeHtml(assessment.Assessment_Type__c);
    html += '</div>';

    // Client Name and Date
    html += '<table class="header-table">';
    html += '<tr>';

    html += '<td>';
    html += '<b>Client\'s Name:</b> ';
    html += escapeHtml(assessment.Account__r.Name);
    html += '</td>';

    html += '<td style="text-align:right;">';
    html += '<b>Created Date:</b> ';
    html += assessment.CreatedDate.format('MM/dd/yyyy');
    html += '</td>';

    html += '</tr>';
    html += '<tr>';

    html += '<td>';
    html += '<b>Status:</b> ';
    html += escapeHtml(assessment.Status__c);
    html += '</td>';

    html += '<td style="text-align:right;">';
    html += '<b>Last Modified:</b> ';
    html += assessment.LastModifiedDate.format('MM/dd/yyyy');
    html += '</td>';

    html += '</tr>';
    html += '</table>';

    // Geriatric instruction
    if (
        assessment.Assessment_Type__c ==
        'Geriatric Depression Scale'
    ) {
        html += '<p>';
        html += 'Please select the best answer for how you\'ve felt ';
        html += 'over the past week.';
        html += '</p>';
    }

    if (
        assessment.Assessment_Type__c ==
        'Home from the Hospital Assessment'
    ) {
        html += '<p style="margin-bottom:15px;">';
        html += '<b>';
        html += 'Please score 1-5 (1 = excellent, 2 = good, 3 = fair, 4 = average,  5 = poor)';
        html += '</b>';
        html += '</p>';
    }
    


if (assessment.Assessment_Type__c == 'Family Caregiver Assessment') {

    html += '<div style="margin-bottom:10px;">';
    html += '<b>Please indicate on a scale of 1–5 ';
    html += '(1 = Excellent, 2 = Good, 3 = Fair, 4 = Average, 5 = Poor)</b>';
    html += '</div>';
}

if (assessment.Assessment_Type__c == 'Quality of Life Therapeutic Program Assessment') {

    html += '<div style="margin-bottom:10px;">';
    html += '<b>Personal Interest Inventory</b>';
    html += '</div>';
}

if (assessment.Assessment_Type__c == 'Medication Management Assessment') {

    html += '<div style="margin-bottom:15px;">';
    html += '<b>Use this tool at intake, quarterly care plan updates, or with any change in condition. Your role is to identify risks, educate the client/family, and flag issues. You are not expected to solve medication problems directly. If issues are identified, ask the client/family whether they want the care manager to reach out to the prescribing provider or pharmacy.</b><br/>';
    html += '</div>';
}

    Integer score = 0;
    Integer balanceScore = 0;
    Integer gaitScore = 0;
    Integer mmseTotalScore = 0;

    Map<Integer, String> scoringAnswers =
        getGeriatricScoringAnswers();

    String currentSection;

//     String informalSection =
//     'Informal Supports for Caregiver (friends, neighbors, family who help with ADL\'s and IADL\'s)';

// String formalSection =
//     'Present Formal Supports to help Caregivers';

// Integer informalQuestionIndex = 0;
// Integer formalQuestionIndex = 0;

// Integer lastRenderedInformalSupport = 0;
// Integer lastRenderedFormalSupport = 0;

Map<String, Question_Master__c> caregiverHourQuestionMap =
    new Map<String, Question_Master__c>();

Map<String, Question_Master__c> caregiverDurationQuestionMap =
    new Map<String, Question_Master__c>();

    Map<String, Integer> groupNumberMap = new Map<String, Integer>();

// Total number of PARENT (whole-number sequence) rows per Group__c,
// so a group with only one row can skip the "1"/"2"/"3" numbering.
Map<String, Integer> groupParentCountMap = new Map<String, Integer>();

for (Question_Master__c q : questions) {

    if (String.isBlank(q.Group__c)) {
        continue;
    }

    if (String.valueOf(q.Sequence__c).contains('.')) {
        continue;
    }

    Integer currentCount =
        groupParentCountMap.containsKey(q.Group__c)
            ? groupParentCountMap.get(q.Group__c)
            : 0;

    groupParentCountMap.put(q.Group__c, currentCount + 1);
}

// Map of "parentQuestionId|optionValue" -> dependent child question,
// so a Multi-Select's selected option can show its linked question inline.
Map<String, Question_Master__c> multiSelectChildMap =
    new Map<String, Question_Master__c>();

for (Question_Master__c q : questions) {

    if (
        q.Dependent_On_Question__c != null &&
        String.isNotBlank(q.Show_When_Value__c)
    ) {
        String key =
            q.Dependent_On_Question__c + '|' + q.Show_When_Value__c;

        multiSelectChildMap.put(key, q);
    }
}

for (Question_Master__c q : questions) {

    if (assessment.Assessment_Type__c != 'Caregiver Assessment') {
        break;
    }

    if (q.Question_Text__c != null &&
        q.Question_Text__c.startsWith('Hours per Day')) {

        caregiverHourQuestionMap.put(q.Question_Text__c, q);
    }

    if (q.Question_Text__c != null &&
        (
            q.Question_Text__c == 'How long has caregiver been caring for care receiver - Years' ||
            q.Question_Text__c == 'How long has caregiver been caring for care receiver - Months'
        )
    ) {
        caregiverDurationQuestionMap.put(q.Question_Text__c, q);
    }
}

Boolean hasAnyAnswer = false;

for (Assessment_Answer__c ans : answerMap.values()) {

    if (
        String.isNotBlank(ans.Answer__c) ||
        String.isNotBlank(ans.Notes__c)
    ) {
        hasAnyAnswer = true;
        break;
    }
}

    // Questions
    for (Question_Master__c question : questions) {

        // Dependent questions (e.g. the "Amount" tied to a specific
        // Income/Assets checkbox) are rendered inline under their parent
        // Multi-Select's selected option instead of as their own box.
        if (question.Dependent_On_Question__c != null) {
            continue;
        }
        
        Boolean isScoreQuestion =
        (
            assessment.Assessment_Type__c ==
                'Family Caregiver Assessment' ||
            assessment.Assessment_Type__c ==
                'Home from the Hospital Assessment'
        ) &&
        question.Question_Type__c == 'Single-Select';

        Assessment_Answer__c existingAnswer =
            answerMap.get(question.Id);

        String answerValue =
            existingAnswer != null
                ? existingAnswer.Answer__c
                : '';
        
        if (
            assessment.Assessment_Type__c ==
                'Mini Mental State Examination' &&
            String.isNotBlank(answerValue)
        ) {
            mmseTotalScore += Integer.valueOf(answerValue);
        }

        String notesValue =
            existingAnswer != null
                ? existingAnswer.Notes__c
                : '';

                Boolean isGroupedQuestion =
    String.isNotBlank(question.Group__c);

Boolean isParentQuestion =
    isGroupedQuestion &&
    !String.valueOf(question.Sequence__c).contains('.');

// if (isGroupedQuestion &&
//     String.valueOf(question.Sequence__c).contains('.')) {
//     continue;
// }
if (String.isNotBlank(question.Group__c) &&
    String.valueOf(question.Sequence__c).contains('.')) {
    continue;
}

if (isParentQuestion) {

    Boolean hasGroupData = String.isNotBlank(answerValue);

for (Question_Master__c child : questions) {

    if (child.Group__c != question.Group__c) {
        continue;
    }

    if (!String.valueOf(child.Sequence__c).contains('.')) {
        continue;
    }

    if (Math.floor(child.Sequence__c) != question.Sequence__c) {
        continue;
    }

    Assessment_Answer__c childAnswer = answerMap.get(child.Id);

    if (childAnswer != null &&
        String.isNotBlank(childAnswer.Answer__c)) {

        hasGroupData = true;
        break;
    }
}

if (!hasGroupData) {
    continue;
}

    if (!groupNumberMap.containsKey(question.Group__c)) {
    groupNumberMap.put(question.Group__c, 1);
} else {
    groupNumberMap.put(
        question.Group__c,
        groupNumberMap.get(question.Group__c) + 1
    );
}

Integer groupInstanceNumber =
    groupNumberMap.get(question.Group__c);

Boolean groupHasMultipleRows =
    groupParentCountMap.containsKey(question.Group__c) &&
    groupParentCountMap.get(question.Group__c) > 1;

if (String.isNotBlank(question.Section__c) &&
    question.Section__c != currentSection) {

    currentSection = question.Section__c;

    html += '<div class="section-title">';
    html += escapeHtml(currentSection);
    html += '</div>';
}

html += '<div class="question">';
html += '<b>';
html += escapeHtml(question.Group__c);

if (groupHasMultipleRows) {
    html += ' ';
    html += String.valueOf(groupInstanceNumber);
}

html += ':</b>';

html += '<div style="margin-left:18px; margin-top:6px;">';
html += '<b>' + escapeHtml(question.Question_Text__c) + ':</b> ';
html += wrapLongText(answerValue);
html += '</div>';

    // for (Question_Master__c child : questions) {

    //     if (child.Group__c == question.Group__c &&
    //         String.valueOf(child.Sequence__c).contains('.')) {

    //         Assessment_Answer__c childAnswer =
    //             answerMap.get(child.Id);

    //         html += '&nbsp;&nbsp;&nbsp;';
    //         html += '<b>' + escapeHtml(child.Question_Text__c) + ':</b> ';
    //         html += escapeHtml(
    //             childAnswer != null
    //                 ? childAnswer.Answer__c
    //                 : ''
    //         );
    //     }
    // }

    Decimal parentSeq = question.Sequence__c;
    

for (Question_Master__c child : questions) {

    if (child.Group__c != question.Group__c) {
        continue;
    }

    if (!String.valueOf(child.Sequence__c).contains('.')) {
        continue;
    }

    Decimal childSeq = child.Sequence__c;

    // Child belongs to this parent only
    if (Math.floor(childSeq) != parentSeq) {
        continue;
    }

    Assessment_Answer__c childAnswer = answerMap.get(child.Id);

   html += '<div style="margin-left:18px; margin-top:6px;">';
    html += '<b>' + escapeHtml(child.Question_Text__c) + ':</b> ';
    html += wrapLongText(childAnswer != null ? childAnswer.Answer__c : '');
    html += '</div>';
}

    html += '</div>';

    continue;
}
        
    //     Integer supportNumber;

    // if (question.Section__c == informalSection) {

    //     informalQuestionIndex++;

    //     if (informalQuestionIndex <= 5) {
    //         supportNumber = 1;
    //     } else if (informalQuestionIndex <= 10) {
    //         supportNumber = 2;
    //     } else {
    //         supportNumber = 3;
    //     }

    // } else if (question.Section__c == formalSection) {

    //     formalQuestionIndex++;

    //     if (formalQuestionIndex <= 2) {
    //         supportNumber = 1;
    //     } else if (formalQuestionIndex <= 4) {
    //         supportNumber = 2;
    //     } else {
    //         supportNumber = 3;
    //     }
    // }

         // Skip incomplete questions
    Boolean isCompleted =
        String.isNotBlank(answerValue) ||
        String.isNotBlank(notesValue);

    if (
        assessment.Assessment_Type__c ==
            'Balance & Gait Assessment' &&
        String.isNotBlank(answerValue)
    ) {

        Integer answerScore =
            getBalanceGaitAnswerScore(
                question.Question_Text__c,
                answerValue
            );

        if (answerScore != null) {

            if (
                question.Section__c ==
                    'Balance Assessment'
            ) {
                balanceScore += answerScore;

            } else if (
                question.Section__c ==
                    'Gait Assessment'
            ) {
                gaitScore += answerScore;
            }
        }
    }

    // if (!isCompleted) {
    //     continue;
    //     }
    Boolean showBlankAssessment =
    assessment.Assessment_Type__c ==
        'Home Safety Assessment'
    && !hasAnyAnswer;

if (!isCompleted && !showBlankAssessment) {
    continue;
}

            // Section Heading
            if (
                String.isNotBlank(question.Section__c) &&
                question.Section__c != currentSection
            ) {

                currentSection = question.Section__c;

                html += '<div class="section-title">';
                html += escapeHtml(currentSection);
                html += '</div>';
            

            if (
                assessment.Assessment_Type__c ==
                    'Balance & Gait Assessment'
                ) {

                    if (currentSection == 'Balance Assessment') {

                        html += '<p style="margin-bottom:10px;">';
                        html += 'To perform this assessment, seat the patient in a hard, armless chair.';
                        html += '</p>';

                    } else if (currentSection == 'Gait Assessment') {

                        html += '<p style="margin-bottom:10px;">';
                        html += 'Stand with the patient. Walk across the room (+/- aids) at a usual pace, then rapidly.';
                        html += '</p>';
                    }
                }
            }

// if (
//     assessment.Assessment_Type__c ==
//         'Caregiver Assessment' &&
//     supportNumber != null
// ) {

//     Boolean showSupportHeading = false;

//     if (
//         question.Section__c == informalSection &&
//         supportNumber != lastRenderedInformalSupport
//     ) {
//         showSupportHeading = true;
//         lastRenderedInformalSupport = supportNumber;
//     }

//     if (
//         question.Section__c == formalSection &&
//         supportNumber != lastRenderedFormalSupport
//     ) {
//         showSupportHeading = true;
//         lastRenderedFormalSupport = supportNumber;
//     }

//     if (showSupportHeading) {

//         html += '<div style="';
//         html += 'font-size:14px;';
//         html += 'font-weight:bold;';
//         html += 'margin-top:12px;';
//         html += 'margin-bottom:8px;';
//         html += '">';

//         html += 'Support ';
//         html += String.valueOf(supportNumber);

//         html += '</div>';
//     }
// }

if (
    assessment.Assessment_Type__c == 'Caregiver Assessment' &&
    question.Question_Text__c != null &&
    (
        question.Question_Text__c.startsWith('Hours per Day') ||
        question.Question_Text__c ==
            'How long has caregiver been caring for care receiver - Months'
    )
) {
    continue;
}

        

        html += '<div class="question">';

        html += '<div class="question-text">';
        // html += String.valueOf(question.Sequence__c);
        // html += '. ';
        if (
    assessment.Assessment_Type__c == 'Caregiver Assessment' &&
    question.Question_Text__c ==
        'How long has caregiver been caring for care receiver - Years'
) {
    html += 'How long has caregiver been caring for care receiver';
} else {
    html += escapeHtml(question.Question_Text__c);
}
        html += '</div>';

        if (String.isNotBlank(question.HelpText__c)) {

    html += '<div style="';
    html += 'font-size:11px;';
    html += 'color:#555555;';
    html += 'margin-bottom:6px;';
    html += '">';

    html += '(';
    html += escapeHtml(question.HelpText__c);
    html += ')';

    html += '</div>';
    }

    if (
    assessment.Assessment_Type__c ==
        'Mini Mental State Examination' &&
    question.Sequence__c == 11
) {

    html += '<br/>';

    html += '<img src="';

    html += URL.getOrgDomainUrl().toExternalForm();
    html += '/resource/MMSEPentagon';

    html += '" width="170"/>';

}

        if (
    assessment.Assessment_Type__c == 'Caregiver Assessment' &&
    question.Question_Text__c == 'Days'
) {

    List<String> selectedAnswers = answerValue.split(';');

    html += '<table style="width:100%;border-collapse:collapse;">';
    html += '<tr>';

    // Days
    html += '<td style="width:25%;vertical-align:top;">';

    for (String day : selectedAnswers) {
        html += '&#8226; ';
        html += escapeHtml(day.trim());
        html += '<br/>';
    }

    html += '</td>';

    

    // Left Hours
    html += '<td style="width:37%;vertical-align:top;">';

    for (Integer i = 0; i < Math.min(4, selectedAnswers.size()); i++) {

        String fullDay = new Map<String,String>{
            'M'=>'Monday',
            'T'=>'Tuesday',
            'W'=>'Wednesday',
            'Th'=>'Thursday',
            'Fri'=>'Friday',
            'S'=>'Saturday',
            'Su'=>'Sunday'
        }.get(selectedAnswers[i].trim());

        Question_Master__c q =
            caregiverHourQuestionMap.get(
                'Hours per Day - ' + fullDay
            );

        if (q != null) {

            Assessment_Answer__c ans = answerMap.get(q.Id);

            html += '<b>';
            html += escapeHtml(q.Question_Text__c);
            html += ': </b>';

            html += escapeHtml(ans != null ? ans.Answer__c : '');

            html += '<br/><br/>';
        }
    }

    html += '</td>';

    // Right Hours
    html += '<td style="width:38%;vertical-align:top;">';

    for (Integer i = 4; i < selectedAnswers.size(); i++) {

        String fullDay = new Map<String,String>{
            'M'=>'Monday',
            'T'=>'Tuesday',
            'W'=>'Wednesday',
            'Th'=>'Thursday',
            'Fri'=>'Friday',
            'S'=>'Saturday',
            'Su'=>'Sunday'
        }.get(selectedAnswers[i].trim());

        Question_Master__c q =
            caregiverHourQuestionMap.get(
                'Hours per Day - ' + fullDay
            );

        if (q != null) {

            Assessment_Answer__c ans = answerMap.get(q.Id);

            html += '<b>';
            html += escapeHtml(q.Question_Text__c);
            html += ': </b>';

            html += escapeHtml(ans != null ? ans.Answer__c : '');

            html += '<br/><br/>';
        }
    }

    html += '</td>';

    html += '</tr>';
    html += '</table>';

}
else if (
    question.Question_Type__c == 'Multi-Select' &&
    String.isNotBlank(answerValue)
) {

    List<String> selectedAnswers =
        answerValue.split(';');

    html += '<div class="answer">';

    for (String selectedAnswer : selectedAnswers) {

        String trimmedAnswer = selectedAnswer.trim();

        html += '&#8226; ';
        html += escapeHtml(trimmedAnswer);

        Question_Master__c childQuestion =
            multiSelectChildMap.get(
                question.Id + '|' + trimmedAnswer
            );

        if (childQuestion != null) {

            Assessment_Answer__c childAnswer =
                answerMap.get(childQuestion.Id);

            String childAnswerValue =
                childAnswer != null
                    ? childAnswer.Answer__c
                    : '';

            if (String.isNotBlank(childAnswerValue)) {

                html += ' &ndash; ';
                if (childQuestion.Question_Text__c == 'Amount') {

                    Decimal amountValue;

                    try {
                        amountValue =
                            Decimal.valueOf(childAnswerValue);

                        amountValue = amountValue.setScale(2);

                        String[] parts =
                            String.valueOf(amountValue).split('\\.');

                        String wholePart = parts[0];
                        String decimalPart =
                            parts.size() > 1
                                ? parts[1]
                                : '00';

                        while (decimalPart.length() < 2) {
                            decimalPart += '0';
                        }

                        // Add commas
                        String formattedWhole = '';
                        Integer count = 0;

                        for (Integer i = wholePart.length() - 1; i >= 0; i--) {

                            formattedWhole =
                                wholePart.substring(i, i + 1) +
                                formattedWhole;

                            count++;

                            if (
                                Math.mod(count, 3) == 0 &&
                                i > 0 &&
                                wholePart.substring(0, 1) != '-'
                            ) {
                                formattedWhole = ',' + formattedWhole;
                            }
                        }

                        childAnswerValue =
                            formattedWhole + '.' + decimalPart;

                    } catch (Exception e) {
                        // Keep original value if it is not numeric
                    }

                    html += escapeHtml(childAnswerValue);

                } else {
                    html += escapeHtml(childAnswerValue);
                }
            }
        }

        html += '<br/>';
    }

    html += '</div>';
}
else if (
    assessment.Assessment_Type__c == 'Caregiver Assessment' &&
    question.Question_Text__c ==
        'How long has caregiver been caring for care receiver - Years'
) {

    Assessment_Answer__c monthsAnswer =
        answerMap.get(
            caregiverDurationQuestionMap.get(
                'How long has caregiver been caring for care receiver - Months'
            ).Id
        );

    html += '<table style="width:100%;">';
    html += '<tr>';

    html += '<td style="width:50%;">';
    html += '<b>Years:</b> ';
    html += escapeHtml(answerValue);
    html += '</td>';

    html += '<td style="width:50%;">';
    html += '<b>Months:</b> ';
    html += escapeHtml(
        monthsAnswer != null ? monthsAnswer.Answer__c : ''
    );
    html += '</td>';

    html += '</tr>';
    html += '</table>';
} else if (
    String.isNotBlank(answerValue) ||
    showBlankAssessment
) {

    html += '<div class="answer">';

String displayValue =
    String.isNotBlank(answerValue)
        ? answerValue
        : '';

if (
    !(
        showBlankAssessment &&
        String.isBlank(answerValue)
    )
) {

    html += '<b>';
    html += isScoreQuestion
        ? 'Score: '
        : 'Answer: ';
    html += '</b>';
}

//         if (
//     showBlankAssessment &&
//     String.isBlank(answerValue)
// ) {

    // if (
    //     question.Question_Type__c == 'Single-Select' &&
    //     String.isNotBlank(question.Answer_Options__c)
    // ) {

    //     html += '<div class="answer">';

    //     for (String option :
    //         question.Answer_Options__c.split(';')) {

    //         html += '&#9633; ';
    //         html += escapeHtml(option.trim());
    //         html += '<br/>';
    //     }

    //     html += '</div>';
    //     html += '</div>';

    //     continue;
    // }
// }

if (
    showBlankAssessment &&
    String.isBlank(answerValue) &&
    question.Question_Type__c == 'Single-Select' &&
    String.isNotBlank(question.Answer_Options__c)
) {

    html += '<table style="margin-top:6px;">';
    html += '<tr>';

    for (String option :
        question.Answer_Options__c.split(';')) {

        html += '<td style="padding-right:30px;">';

        // Empty radio button
        html += 'O ';

        html += escapeHtml(option.trim());

        html += '</td>';
    }

    html += '</tr>';
    html += '</table>';

    html += '<div style="margin-top:12px;">';
html += '<b>Notes:</b><br/>';

html += '<div style="';
html += 'height:45px;';
html += 'border:1px solid #cccccc;';
html += 'margin-top:4px;';
html += 'margin-right:10px;';
html += '"></div>';

html += '</div>';

}  else {

    html += wrapLongText(displayValue);

    if (
        assessment.Assessment_Type__c ==
            'Balance & Gait Assessment'
    ) {

        Integer selectedScore =
            getBalanceGaitAnswerScore(
                question.Question_Text__c,
                answerValue
            );

        if (selectedScore != null) {

            html += '<br/>';
            html += '<b>Score:</b> ';
            html += String.valueOf(selectedScore);
        }
    }
}

if (
    assessment.Assessment_Type__c == 'Family Caregiver Assessment' ||
    assessment.Assessment_Type__c == 'Home from the Hospital Assessment'
) {
    Map<String, String> scoreLabels = new Map<String, String>{
        '1' => 'Excellent',
        '2' => 'Good',
        '3' => 'Fair',
        '4' => 'Average',
        '5' => 'Poor'
    };

    if (scoreLabels.containsKey(answerValue)) {
        displayValue += ' (' + scoreLabels.get(answerValue) + ')';
    }
}

// html += wrapLongText(displayValue);

//     if (
//     assessment.Assessment_Type__c ==
//         'Balance & Gait Assessment'
// ) {

//     Integer selectedScore =
//         getBalanceGaitAnswerScore(
//             question.Question_Text__c,
//             answerValue
//         );

//     if (selectedScore != null) {
//         html += '<br/>';
//         html += '<b>Score:</b> ';
//         html += String.valueOf(selectedScore);
//     }
// }

    html += '</div>';
}

        // Notes
        if (String.isNotBlank(notesValue)) {

            html += '<div class="notes">';

            String notesLabel = 'Notes';

if (
    assessment.Assessment_Type__c ==
        'Caregiver Assessment' &&
    question.Section__c ==
        'Limitations of Caregiver'
) {
    notesLabel = 'Details';
} else if (
    assessment.Assessment_Type__c ==
        'Nursing Assessment'
) {
    notesLabel = 'Description';
}

html += '<b>';
html += notesLabel;
html += ':</b> ';
            html += escapeHtml(notesValue);

            html += '</div>';
        }

        html += '</div>';
        

        // Calculate Geriatric score
        if (
            assessment.Assessment_Type__c ==
                'Geriatric Depression Scale' &&
            scoringAnswers.containsKey(
                Integer.valueOf(question.Sequence__c)
            ) &&
            answerValue ==
                scoringAnswers.get(
                    Integer.valueOf(question.Sequence__c)
                )
        ) {
            score++;
        }
    }

     if (
    assessment.Assessment_Type__c ==
        'Balance & Gait Assessment'
) {

    Integer combinedScore =
        balanceScore + gaitScore;

    String riskLevel = 'Risk of Falls: 18 Points or Less = High Risk, 19–23 Points = Moderate Risk, 24 or More Points = Low Risk';

    html += '<div class="score">';

    html += '<b>Balance Score: ';
    html += String.valueOf(balanceScore);
    html += ' / 16</b>';

    html += '<br/><br/>';

    html += '<b>Gait Score: ';
    html += String.valueOf(gaitScore);
    html += ' / 12</b>';

    html += '<br/><br/>';

    html += '<b>Combined Score: ';
    html += String.valueOf(combinedScore);
    html += ' / 28</b>';

    html += '<br/><br/>';

    html += '<b>';
    html += escapeHtml(riskLevel);
    html += '</b>';

    html += '</div>';
}

    // Geriatric score
    if (
    assessment.Assessment_Type__c ==
        'Geriatric Depression Scale'
) {

    html += '<div class="score">';

    html += '<b>Score: ';
    html += String.valueOf(score);
    html += ' / 15</b>';

    html += '<br/><br/>';

    // Reference Answers
    html += '<div style="margin-bottom:15px;">';

    html += '<div style="font-size:16px;font-weight:bold;">';
    html += 'Score';
    html += '</div>';

    html += 'Assign one point for each match between your answer to a particular question and the answer listed for that question below:';

    html += '<br/><br/>';

    html += '<table style="width:100%;">';
    html += '<tr>';

    html += '<td style="width:50%;vertical-align:top;">';

    for (Integer i = 1; i <= 8; i++) {

        html += '<b>Q' + i + ':</b> ';
        html += escapeHtml(scoringAnswers.get(i));
        html += '<br/>';
    }

    html += '</td>';

    html += '<td style="width:50%;vertical-align:top;">';

    for (Integer i = 9; i <= 15; i++) {

        html += '<b>Q' + i + ':</b> ';
        html += escapeHtml(scoringAnswers.get(i));
        html += '<br/>';
    }

    html += '</td>';

    html += '</tr>';
    html += '</table>';

    html += '<br/>';

    html += 'A score of 0-5 is normal. A score of above 5 suggests depression.';

    html += '</div>';

    html += '</div>';
}

    if (
    assessment.Assessment_Type__c ==
        'Caregiver Assessment'
) {

    html += '<div style="';
    html += 'margin-top:25px;';
    html += 'font-weight:bold;';
    html += '">';

    html += '** Use details collected here to create ';
    html += 'care management plan for Caregiver';

    html += '</div>';
}


if (
    assessment.Assessment_Type__c ==
        'Mini Mental State Examination'
) {

    html += '<div class="score">';
    html += '<b>Total Score: ';
    html += String.valueOf(mmseTotalScore);
    html += ' / 30</b>';
    html += '</div>';

    html += '<br/><br/>';

html += '<h3 style="font-size:16px;font-weight:bold;">';
html += 'Interpretation of the MMSE';
html += '</h3>';

html += '<table style="width:100%;border-collapse:collapse;border:1px solid #000;">';

html += '<tr style="background:#f3f3f3;font-weight:bold;">';
html += '<th style="border:1px solid #000;padding:6px;">Method</th>';
html += '<th style="border:1px solid #000;padding:6px;text-align:center;">Score</th>';
html += '<th style="border:1px solid #000;padding:6px;">Interpretation</th>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;">Single Cutoff</td>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">&lt;24</td>';
html += '<td style="border:1px solid #000;padding:6px;">Abnormal</td>';
html += '</tr>';

html += '<tr>';
html += '<td rowspan="2" style="border:1px solid #000;padding:6px;vertical-align:middle;">Range</td>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">&lt;21</td>';
html += '<td style="border:1px solid #000;padding:6px;">Increased odds of dementia</td>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">&gt;25</td>';
html += '<td style="border:1px solid #000;padding:6px;">Decreased odds of dementia</td>';
html += '</tr>';

html += '<tr>';
html += '<td rowspan="3" style="border:1px solid #000;padding:6px;vertical-align:middle;">Education</td>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">21</td>';
html += '<td style="border:1px solid #000;padding:6px;">Abnormal for 8th grade education</td>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">&lt;23</td>';
html += '<td style="border:1px solid #000;padding:6px;">Abnormal for high school education</td>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">&lt;24</td>';
html += '<td style="border:1px solid #000;padding:6px;">Abnormal for college education</td>';
html += '</tr>';

html += '<tr>';
html += '<td rowspan="3" style="border:1px solid #000;padding:6px;vertical-align:middle;">Severity</td>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">24-30</td>';
html += '<td style="border:1px solid #000;padding:6px;">No cognitive impairment</td>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">18-23</td>';
html += '<td style="border:1px solid #000;padding:6px;">Mild cognitive impairment</td>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;text-align:center;">0-17</td>';
html += '<td style="border:1px solid #000;padding:6px;">Severe cognitive impairment</td>';
html += '</tr>';

html += '</table>';

html += '<br/><br/>';

html += '<h3 style="font-size:16px;font-weight:bold;">';
html += 'Interpretation of the MMSE Scores';
html += '</h3>';

html += '<table style="width:100%;border-collapse:collapse;border:1px solid #000;">';

html += '<tr style="background:#f3f3f3;font-weight:bold;">';
html += '<th style="border:1px solid #000;padding:6px;width:10%;">Score</th>';
html += '<th style="border:1px solid #000;padding:6px;width:15%;">Degree of<br/>Impairment</th>';
html += '<th style="border:1px solid #000;padding:6px;width:35%;">Formal Psychometric Assessment</th>';
html += '<th style="border:1px solid #000;padding:6px;width:40%;">Day-to-Day Functioning</th>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;">25-30</td>';
html += '<td style="border:1px solid #000;padding:6px;">Questionably significant</td>';
html += '<td style="border:1px solid #000;padding:6px;">If clinical signs of cognitive impairment are present, formal assessment of cognition may be valuable.</td>';
html += '<td style="border:1px solid #000;padding:6px;">May have clinically significant but mild deficits. Likely to affect only the most demanding activities of daily living.</td>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;">20-25</td>';
html += '<td style="border:1px solid #000;padding:6px;">Mild</td>';
html += '<td style="border:1px solid #000;padding:6px;">Formal assessment may be helpful to better determine pattern and extent of deficits.</td>';
html += '<td style="border:1px solid #000;padding:6px;">Significant effect. May require some supervision, support and assistance.</td>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;">10-20</td>';
html += '<td style="border:1px solid #000;padding:6px;">Moderate</td>';
html += '<td style="border:1px solid #000;padding:6px;">Formal assessment may be helpful if there are specific clinical indications.</td>';
html += '<td style="border:1px solid #000;padding:6px;">Clear impairment. May require 24-hour supervision.</td>';
html += '</tr>';

html += '<tr>';
html += '<td style="border:1px solid #000;padding:6px;">0-10</td>';
html += '<td style="border:1px solid #000;padding:6px;">Severe</td>';
html += '<td style="border:1px solid #000;padding:6px;">Patient not likely to be testable.</td>';
html += '<td style="border:1px solid #000;padding:6px;">Marked impairment. Likely to require 24-hour supervision and assistance with ADL.</td>';
html += '</tr>';

html += '</table>';
}



    html += '</body>';
    html += '</html>';

    return html;
}

private static Map<Integer, String>
    getGeriatricScoringAnswers() {

    return new Map<Integer, String>{
        1  => 'No',
        2  => 'Yes',
        3  => 'Yes',
        4  => 'Yes',
        5  => 'No',
        6  => 'Yes',
        7  => 'No',
        8  => 'Yes',
        9  => 'Yes',
        10 => 'Yes',
        11 => 'No',
        12 => 'Yes',
        13 => 'No',
        14 => 'Yes',
        15 => 'Yes'
    };
}

private static Integer getBalanceGaitAnswerScore(
    String questionText,
    String answer
) {

    if (
        String.isBlank(questionText) ||
        String.isBlank(answer)
    ) {
        return 0;
    }

    Map<String, Integer> scoreMap =
        new Map<String, Integer>{

            // Balance Assessment
            'Sitting Balance|Leans or slides in chair' => 0,
            'Sitting Balance|Steady, safe' => 1,

            'Rises From Chair|Unable to rise without help' => 0,
            'Rises From Chair|Able to rise using arms to help' => 1,
            'Rises From Chair|Able to rise without using arms to help' => 2,

            'Attempts To Rise|Unable to rise without help' => 0,
            'Attempts To Rise|Able to rise, requires more than one attempt' => 1,
            'Attempts To Rise|Able to rise, requires one attempt' => 2,

            'Standing Balance (1st 5 Seconds)|Unsteady (staggers, moves feet, trunk sways)' => 0,
            'Standing Balance (1st 5 Seconds)|Steady, but uses walker or other support' => 1,
            'Standing Balance (1st 5 Seconds)|Steady without walker or other support' => 2,

            'Standing Balance|Unsteady' => 0,
            'Standing Balance|Steady, but with wide stance and uses support' => 1,
            'Standing Balance|Narrow stance without support' => 2,

            'Nudged|Begins to fall' => 0,
            'Nudged|Staggers, grabs, catches self' => 1,
            'Nudged|Steady' => 2,

            'Eyes Closed|Unsteady' => 0,
            'Eyes Closed|Steady' => 1,

            'Turning 360 Degrees - Steps|Discontinuous steps' => 0,
            'Turning 360 Degrees - Steps|Continuous steps' => 1,

            'Turning 360 Degrees - Stability|Unsteady (grabs, staggers)' => 0,
            'Turning 360 Degrees - Stability|Steady' => 1,

            'Sitting Down (Getting Seated)|Unsafe (misjudged distance, falls into chair)' => 0,
            'Sitting Down (Getting Seated)|Uses arms or not a smooth motion' => 1,
            'Sitting Down (Getting Seated)|Safe, smooth motion' => 2,

            // Gait Assessment
            'Indication of Gait|Any hesitancy or multiple attempts' => 0,
            'Indication of Gait|No hesitancy' => 1,

            'Step Length & Height|Step to' => 0,
            'Step Length & Height|Step through right' => 1,
            'Step Length & Height|Step through left' => 1,

            'Foot Clearance|Foot drop' => 0,
            'Foot Clearance|Left foot clears the floor' => 1,
            'Foot Clearance|Right foot clears the floor' => 1,

            'Step Symmetry|Right and left step length are not equal' => 0,
            'Step Symmetry|Right and left step length appear equal' => 1,

            'Step Continuity|Stopping of discontinuity between steps' => 0,
            'Step Continuity|Steps appear continuous' => 1,

            'Path|Marked deviation' => 0,
            'Path|Mild/moderate deviation or uses a walking aid' => 1,
            'Path|Straight without a walking aid' => 2,

            'Trunk|Marked sway or uses a walking aid' => 0,
            'Trunk|No sway, flexes knees/back/uses arms to balance' => 1,
            'Trunk|No sway, no flexion of knees or back use of arms, or walking aid' => 2,

            'Walking Time|Heels apart' => 0,
            'Walking Time|Heels almost touching while walking' => 1
        };

    String key =
        questionText.trim() +
        '|' +
        answer.trim();

    return scoreMap.get(key);
}

private static String escapeHtml(String value) {

    if (value == null) {
        return '';
    }

    return value
        .replace('&', '&amp;')
        .replace('<', '&lt;')
        .replace('>', '&gt;')
        .replace('"', '&quot;');
}

private static String wrapLongText(String text) {

    if (String.isBlank(text)) {
        return '';
    }

    Integer chunkSize = 30;
    String result = '';

    for (Integer i = 0; i < text.length(); i += chunkSize) {
        Integer endIndex = Math.min(i + chunkSize, text.length());
        result += escapeHtml(text.substring(i, endIndex)) + '<wbr/>';
    }

    return result;
}

    public class QuestionAnswerWrapper{

        @AuraEnabled
        public Id questionId { get; set; }

        @AuraEnabled
        public String answer { get; set; }

        @AuraEnabled
        public String notes { get; set; }
    }

    public class AssessmentViewerWrapper {

        @AuraEnabled
        public SecondaryAssessment__c assessment { get; set; }

        @AuraEnabled
        public List<Question_Master__c> questions { get; set; }

        @AuraEnabled
        public List<Assessment_Answer__c> answers { get; set; }

        @AuraEnabled
        public Integer balanceScore { get; set; }

        @AuraEnabled
        public Integer gaitScore { get; set; }

        @AuraEnabled
        public Integer combinedScore { get; set; }

        @AuraEnabled
        public String riskLevel { get; set; }

        @AuraEnabled
        public List<ContactOption> contactOptions {get;set;}
    }

    public class ContactOption {

        @AuraEnabled
        public String label {get;set;}

        @AuraEnabled
        public String value {get;set;}
    }

    public class QuestionWrapper {
        @AuraEnabled public List<Question_Master__c> questions;
        @AuraEnabled public List<ContactOption> contactOptions;
    }


}