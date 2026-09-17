import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
// import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ACCOUNT_NAME_FIELD from '@salesforce/schema/Account.Name';

import SECONDARY_ASSESSMENT_OBJECT
    from '@salesforce/schema/SecondaryAssessment__c';

import ASSESSMENT_TYPE_FIELD
    from '@salesforce/schema/SecondaryAssessment__c.Assessment_Type__c';

import getQuestions
    from '@salesforce/apex/SecondaryAssessmentController.getQuestions';

import saveAssessment
    from '@salesforce/apex/SecondaryAssessmentController.saveAssessment';

import getAssessmentData
    from '@salesforce/apex/SecondaryAssessmentController.getAssessmentData';

import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    closeTab
} from 'lightning/platformWorkspaceApi';

import {
    publish,
    MessageContext
} from 'lightning/messageService';

import SECONDARY_ASSESSMENT_REFRESH_CHANNEL
    from '@salesforce/messageChannel/secondaryAssessmentRefresh__c';

import MMSEPentagon from '@salesforce/resourceUrl/MMSEPentagon';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import LOCALE from '@salesforce/i18n/locale';

export default class SecondaryAssessmentCreate extends LightningElement  {

    @api recordId;

    @track questions = [];

    assessmentOptions = [];

    selectedAssessmentType;

    isLoading = false;

    showNoQuestions = false;

    recordTypeId;

    sections = [];

    activeSections = [];

    isCloneMode = false;
    
    cloneAssessmentId;

    pentagonImage = MMSEPentagon;

    contactOptions = [];

    BOOLEAN_OPTIONS = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    @wire(getObjectInfo, {
        objectApiName: SECONDARY_ASSESSMENT_OBJECT
    })
    objectInfo({ data, error }) {

        if (data) {

            this.recordTypeId =
                data.defaultRecordTypeId;

        }

        if (error) {

            console.error(error);

        }

    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: ASSESSMENT_TYPE_FIELD
    })
    assessmentTypePicklist({ data, error }) {

        if (data) {
            this.assessmentOptions = data.values;
        } else if (error) {
            console.error(error);
        }

    }

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [ACCOUNT_NAME_FIELD]
    })
    accountRecord;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageReference) {

        if (!pageReference) {
            return;
        }

        const cloneMode =
            pageReference.state?.c__cloneMode === 'true';

        this.isCloneMode = cloneMode;

        if (cloneMode) {

            this.cloneAssessmentId =
                pageReference.state?.c__recordId;

            this.loadCloneAssessment();

        } else {

            this.recordId =
                pageReference.state?.c__recordId;
        }
    }

    @wire(IsConsoleNavigation)
    isConsoleNavigation;

    @wire(MessageContext)
    messageContext;

    get clientName() {
        return getFieldValue(
            this.accountRecord.data,
            ACCOUNT_NAME_FIELD
        );
    }

    get assessmentDate() {
        return new Intl.DateTimeFormat('en-US').format(new Date());
    }

        get isGeriatricDepressionScale() {
            return this.selectedAssessmentType === 'Geriatric Depression Scale';
        }

        get isHomeSafetyAssessment() {
        return this.selectedAssessmentType ===
            'Home Safety Assessment';
    }

    get isHomeFromHospitalAssessment() {
        return this.selectedAssessmentType ===
            'Home from the Hospital Assessment';
    }

    get isSaveDisabled() {
        return !this.selectedAssessmentType ||
            this.questions.length === 0 ||
            this.isLoading;
    }

    get hasSections() {
        return this.sections.length > 0;
    }

    get isKatzADLAssessment() {
        return this.selectedAssessmentType ===
            'Katz ADL Assessment';
    }

    get isCaregiverAssessment() {
        return this.selectedAssessmentType ===
            'Caregiver Assessment';
    }

    get isFamilyCaregiverAssessment() {
    return this.selectedAssessmentType === 'Family Caregiver Assessment';
}

   get isMiniMentalStateExamination() {
    return this.selectedAssessmentType === 'Mini Mental State Examination';
}

get isQualityOfLifeTPA() {
    return this.selectedAssessmentType === 'Quality of Life Therapeutic Program Assessment';
}

get isMedicationManagementAssessment(){
    return this.selectedAssessmentType === 'Medication Management Assessment';
}


    get caregiverTriggerQuestion() {

        if (!this.isCaregiverAssessment) {
            return null;
        }

        return this.questions.find(
            question =>
                !question.section &&
                question.questionText ===
                    'What triggered the caregiver assessment?'
        );
    }

    get caregiverHourQuestions() {

    const dayMap = {
        M: 'Monday',
        T: 'Tuesday',
        W: 'Wednesday',
        Th: 'Thursday',
        Fri: 'Friday',
        S: 'Saturday',
        Su: 'Sunday'
    };

    const daysQuestion = this.questions.find(q => q.isCaregiverDaysQuestion);

    if (!daysQuestion || !Array.isArray(daysQuestion.answer)) {
        return [];
    }

    return daysQuestion.answer
        .map(day => {

            const fullDay = dayMap[day];

            const question = this.questions.find(q =>
                q.isCaregiverHourQuestion &&
                q.questionText &&
                q.questionText.endsWith(fullDay)
            );

            return question
                ? {
                    label: `${question.questionText}`,
                    question
                }
                : null;

        })
        .filter(item => item);

}


get caregiverHourQuestionsLeft() {
    return this.caregiverHourQuestions.slice(0, 4);
}

get caregiverHourQuestionsRight() {
    return this.caregiverHourQuestions.slice(4);
}

get caregiverYearsQuestion() {
    return this.questions.find(q => q.isCaregiverYearsQuestion);
}

get caregiverMonthsQuestion() {
    return this.questions.find(q => q.isCaregiverMonthsQuestion);
}


get assessmentFooter() {

    switch (this.selectedAssessmentType) {

        case 'Balance & Gait Assessment':
            return 'Risk of Falls: 18 Points or Less = High Risk, 19–23 Points = Moderate Risk, 24 or More Points = Low Risk';

        default:
            return null;
    }
}

//     get activitiesQuestion() {

//     return this.questions.find(
//          q =>
//             q.questionText &&
//             q.questionText.includes(
//                 'Activities Checklist'
//             )
//     );
// }

// get selectedActivities() {

//     return Array.isArray(this.activitiesQuestion?.answer)
//         ? this.activitiesQuestion.answer
//         : [];
// }

getSelectedOptions(questionText) {

    const question = this.questions.find(
        q =>
            q.questionText &&
            q.questionText.includes(questionText)
    );

    return Array.isArray(question?.answer)
        ? question.answer
        : [];
}

    get formTitle() {
        return this.isCloneMode
            ? 'Clone Secondary Assessment'
            : 'New Secondary Assessment';
    }

    async loadCloneAssessment() {

        if (!this.cloneAssessmentId) {
            return;
        }

        this.isLoading = true;

        try {

            const result =
                await getAssessmentData({
                    assessmentId:
                        this.cloneAssessmentId
                });
            
            this.contactOptions = result.contactOptions || [];

            console.log('Contact Options:', JSON.stringify(this.contactOptions));

            // The NEW record must still use the same Account
            this.recordId =
                result.assessment.Account__c;

            // Prefill Assessment Type
            this.selectedAssessmentType =
                result.assessment.Assessment_Type__c;

            // Build source answer map
            const answerMap = {};

            result.answers.forEach(answer => {

                answerMap[
                    answer.Assessment_Question__c
                ] = answer;
            });

            let displaySequence = 1;

            this.questions =
                result.questions.map(q => {

                    const existing =
                        answerMap[q.Id];

                    const isMultiSelect =
                        q.Question_Type__c ===
                        'Multi-Select';

                    const optionsString = q.Answer_Options__c || '';

                    const delimiter = optionsString.includes('||')
                        ? '||'
                        : ';';

                    const answerOptions =
                        q.Answer_Options__c
                            ? q.Answer_Options__c
                                .split(delimiter)
                                .map(option =>
                                    option.trim()
                                )
                                .filter(option =>
                                    option
                                )
                                .map(option => ({
                                    label: option,
                                    value: option
                                }))
                            : [];

                    let answer = '';

                    if (existing?.Answer__c) {

                        answer =
                            isMultiSelect
                                ? existing.Answer__c
                                    .split(';')
                                    .map(value =>
                                        value.trim()
                                    )
                                    .filter(value =>
                                        value
                                    )
                                : existing.Answer__c;

                    } else if (isMultiSelect) {

                        answer = [];
                    }

                    const isChildQuestion =
    String(q.Sequence__c).includes('.');

const hideSequence =
    this.selectedAssessmentType === 'Caregiver Assessment' &&
    (
        q.Question_Text__c ===
            'What triggered the caregiver assessment?' ||
        (
            q.Question_Text__c &&
            q.Question_Text__c.startsWith('Hours per Day')
        )
    );

const shouldDisplaySequence =
    this.selectedAssessmentType === 'Caregiver Assessment' &&
    !hideSequence &&
    !isChildQuestion;

return {
    id: q.Id,
    questionText: q.Question_Text__c,
    sequence: q.Sequence__c,

    isChildQuestion,
    hideSequence,

    displaySequence:
        this.selectedAssessmentType === 'Caregiver Assessment'
            ? (
                shouldDisplaySequence
                    ? displaySequence++
                    : null
            )
            : q.Sequence__c,
                        section:
                            q.Section__c,
                        group: q.Group__c,
                        helpText:
                            q.HelpText__c,
                        type:
                            q.Question_Type__c,

                        answer: answer,

                        notes:
                            existing?.Notes__c || '',

                        isBoolean:
                            q.Question_Type__c ===
                            'Boolean',

                        // isText:
                        //     q.Question_Type__c === 'Text',
                        isContactPicker:
                            this.selectedAssessmentType === 'Caregiver Assessment' &&
                            q.Question_Text__c === 'Caregiver',

                        isText:
                            q.Question_Type__c === 'Text' &&
                            !(
                                this.selectedAssessmentType === 'Caregiver Assessment' &&
                                q.Question_Text__c === 'Caregiver'
                            ),
                            
                        isTextArea: q.Question_Type__c === 'Text Area',

                        isNumber:
                            q.Question_Type__c ===
                            'Number',

                        isPhone: q.Question_Type__c === 'Phone',
                        isEmail: q.Question_Type__c === 'Email',

                        isDate:
                            q.Question_Type__c ===
                            'Date',

                        isMultiSelect:
                            isMultiSelect,

                        isSingleSelect:
                            q.Question_Type__c ===
                            'Single-Select',

                        options:
                            q.Question_Type__c ===
                            'Boolean'
                                ? this.BOOLEAN_OPTIONS
                                : answerOptions.map(option => ({
                                    ...option,
                                    checked: false
                                })),
                        showNotes:
                           q.Show_Notes__c,
                        notesLabel:
                            q.Notes_Label__c || 'Notes', 

                        dependentQuestionId: q.Dependent_On_Question__c,
                        showWhenValue: q.Show_When_Value__c,
                        showPentagonImage:
                            this.selectedAssessmentType === 'Mini Mental State Examination' &&
                            q.Sequence__c === 11,
                        isCaregiverDaysQuestion:
                            this.selectedAssessmentType === 'Caregiver Assessment' &&
                            q.Question_Text__c === 'Days',

                        isCaregiverHourQuestion:
                            this.selectedAssessmentType === 'Caregiver Assessment' &&
                            q.Question_Text__c &&
                            q.Question_Text__c.startsWith('Hours per Day'),
                        isCaregiverYearsQuestion:
                            this.selectedAssessmentType === 'Caregiver Assessment' &&
                            q.Question_Text__c ===
                                'How long has caregiver been caring for care receiver - Years',

                        isCaregiverMonthsQuestion:
                            this.selectedAssessmentType === 'Caregiver Assessment' &&
                            q.Question_Text__c ===
                                'How long has caregiver been caring for care receiver - Months'
                    };
                });

            this.updateDependentQuestions();
            
            console.log('this.questions : ',JSON.stringify(this.questions));

            this.showNoQuestions =
                this.questions.length === 0;

        } catch (error) {

            console.error(
                'Load Clone Error:',
                error
            );

            this.showToast(
                'Error',
                error.body?.message ||
                    error.message ||
                    'Unable to load the assessment for cloning.',
                'error'
            );

        } finally {

            this.isLoading = false;
        }
    }

    handleAssessmentTypeChange(event) {

        this.selectedAssessmentType =
            event.detail.value;

        this.loadQuestions();

    }

    loadQuestions() {

        this.isLoading = true;

        this.questions = [];

        this.sections = [];

        this.activeSections = [];

        this.showNoQuestions = false;

        getQuestions({
            assessmentType: this.selectedAssessmentType,
            accountId: this.recordId
        })

        .then(result => {

            if (result.questions.length === 0) {

                this.showNoQuestions = true;

                return;

            }
            // console.log('result', JSON.stringify(result));
            this.contactOptions = result.contactOptions || [];

            // let displaySequence = 1;

            this.questions =  result.questions.map(q => {

                const optionsString = q.Answer_Options__c || '';

                const delimiter = optionsString.includes('||')
                    ? '||'
                    : ';';

                const answerOptions = q.Answer_Options__c
                    ? q.Answer_Options__c
                        .split(delimiter)
                        .map(option => option.trim())
                        .filter(option => option)
                        .map(option => ({
                            label: option,
                            value: option
                        }))
                    : [];

                const hideSequence =
    this.selectedAssessmentType === 'Caregiver Assessment' &&
    (
        q.Question_Text__c === 'What triggered the caregiver assessment?' ||
        q.Question_Text__c === 'How long has caregiver been caring for care receiver - Months' ||
        (q.Question_Text__c &&
         q.Question_Text__c.startsWith('Hours per Day'))
    );

                return {
                    id: q.Id,
                    questionText: q.Question_Text__c,
                    sequence: q.Sequence__c,
                    isChildQuestion: String(q.Sequence__c).includes('.'),
                    hideSequence: hideSequence,
                    // displaySequence:
                    // this.selectedAssessmentType === 'Caregiver Assessment'
                    //     ? (hideSequence ? null : displaySequence++)
                    //     : q.Sequence__c,
                    displaySequence: null,
                    section: q.Section__c,
                    group: q.Group__c,
                    helpText: q.HelpText__c,
                    type: q.Question_Type__c,

                    answer: q.Question_Type__c === 'Multi-Select'
                        ? []
                        : '',
                    notes: '',

                    isBoolean: q.Question_Type__c === 'Boolean',
                    // isText:
                        //     q.Question_Type__c === 'Text',
                        isContactPicker:
                            this.selectedAssessmentType === 'Caregiver Assessment' &&
                            q.Question_Text__c === 'Caregiver',

                        isText:
                            q.Question_Type__c === 'Text' &&
                            !(
                                this.selectedAssessmentType === 'Caregiver Assessment' &&
                                q.Question_Text__c === 'Caregiver'
                            ),
                    isTextArea: q.Question_Type__c === 'Text Area',
                    isNumber: q.Question_Type__c === 'Number',
                    isPhone: q.Question_Type__c === 'Phone',
                    isEmail: q.Question_Type__c === 'Email',
                    isDate: q.Question_Type__c === 'Date',
                    isMultiSelect: q.Question_Type__c === 'Multi-Select',
                    isSingleSelect: q.Question_Type__c === 'Single-Select',

                    options: q.Question_Type__c === 'Boolean'
                        ? this.BOOLEAN_OPTIONS
                        : answerOptions.map(option => ({
                            ...option,
                            checked: false
                        })),
                    showNotes:
                        q.Show_Notes__c,
                    notesLabel:
                        q.Notes_Label__c || 'Notes', 

                    dependentQuestionId: q.Dependent_On_Question__c,
                    showWhenValue: q.Show_When_Value__c,
                    showPentagonImage:
                        this.selectedAssessmentType === 'Mini Mental State Examination' &&
                        q.Sequence__c === 11,
                    isCaregiverDaysQuestion:
                        this.selectedAssessmentType === 'Caregiver Assessment' &&
                        q.Question_Text__c === 'Days',

                    isCaregiverHourQuestion:
                        this.selectedAssessmentType === 'Caregiver Assessment' &&
                        q.Question_Text__c &&
                        q.Question_Text__c.startsWith('Hours per Day'),
                    isCaregiverYearsQuestion:
    this.selectedAssessmentType === 'Caregiver Assessment' &&
    q.Question_Text__c ===
        'How long has caregiver been caring for care receiver - Years',

isCaregiverMonthsQuestion:
    this.selectedAssessmentType === 'Caregiver Assessment' &&
    q.Question_Text__c ===
        'How long has caregiver been caring for care receiver - Months',
        inlineChildren: [],
        
                };
            });

            console.log('this.questions 1: ',this.questions);
            console.log('this.questions 2: ', JSON.stringify(this.questions));

            this.updateDependentQuestions();

            // console.log( 'CHECK>> ',
            // JSON.stringify(
            //     this.questions.map(q => ({
            //         text: q.questionText,
            //         dependent: q.dependentActivity,
            //         show: q.showQuestion
            //     })))
            // );

        })

       .catch(error => {

            console.error(
                'Fetch Questions Error:',
                JSON.stringify(error)
            );

            console.error(
                'Error Body:',
                JSON.stringify(error.body)
            );

            console.error(
                'Message:',
                error?.body?.message
            );

            this.showToast(
                'Error',
                'Unable to fetch questions.',
                'error'
            );
        })

        .finally(() => {

            this.isLoading = false;

        });

    }

//     buildSections() {

//     const sectionMap = new Map();

//     this.questions.forEach(question => {

//         if (!question.section) {
//             return;
//         }

//         if (!sectionMap.has(question.section)) {

//             sectionMap.set(question.section, {
//                 name: question.section,
//                 questions: []
//             });
//         }

//         sectionMap
//             .get(question.section)
//             .questions
//             .push(question);
//     });

//     this.sections =
//         Array.from(sectionMap.values());
// }

// buildSections() {

//     const sectionMap = new Map();

//     this.questions.forEach(question => {

//         if (!question.section) {
//             return;
//         }

//         if (!sectionMap.has(question.section)) {

//             sectionMap.set(question.section, {
//                 name: question.section,
//                 questions: [],
//                 groups: [],
//                 isGrouped: false,
//                  isBalanceSection:
//         this.selectedAssessmentType ===
//             'Balance & Gait Assessment' &&
//         question.section ===
//             'Balance Assessment',

//     isGaitSection:
//         this.selectedAssessmentType ===
//             'Balance & Gait Assessment' &&
//         question.section ===
//             'Gait Assessment'
//             });
//         }

//         sectionMap
//             .get(question.section)
//             .questions
//             .push(question);
//     });

//     const informalSection =
//         'Informal Supports for Caregiver (friends, neighbors, family who help with ADL\'s and IADL\'s)';

//     const formalSection =
//         'Present Formal Supports to help Caregivers';

//     this.sections =
//         Array.from(sectionMap.values())
//             .map(section => {

//                 if (section.name === informalSection) {

//                     section.isGrouped = true;

//                     section.groups = [
//                         {
//                             name: 'Support 1',
//                             questions:
//                                 section.questions.slice(0, 5)
//                         },
//                         {
//                             name: 'Support 2',
//                             questions:
//                                 section.questions.slice(5, 10)
//                         },
//                         {
//                             name: 'Support 3',
//                             questions:
//                                 section.questions.slice(10, 15)
//                         }
//                     ];

//                 } else if (
//                     section.name === formalSection
//                 ) {

//                     section.isGrouped = true;

//                     section.groups = [
//                         {
//                             name: 'Support 1',
//                             questions:
//                                 section.questions.slice(0, 2)
//                         },
//                         {
//                             name: 'Support 2',
//                             questions:
//                                 section.questions.slice(2, 4)
//                         },
//                         {
//                             name: 'Support 3',
//                             questions:
//                                 section.questions.slice(4, 6)
//                         }
//                     ];
//                 }

//                 return section;
//             });

//     if (
//         this.activeSections.length === 0 &&
//         this.sections.length > 0
//     ) {
//         this.activeSections = [
//             this.sections[0].name
//         ];
//     }
// }

buildSections() {

    const sectionMap = new Map();

    const questionMap = new Map();

this.questions.forEach(question => {

    question.inlineChildren = [];

    if (question.isMultiSelect && question.options) {

        question.options = question.options.map(option => ({
            ...option,
            children: []
        }));

    }

    questionMap.set(question.id, question);

});

this.questions.forEach(question => {

    if (question.dependentQuestionId) {

        const parent =
            questionMap.get(question.dependentQuestionId);

        if (parent) {

    parent.inlineChildren.push(question);

    if (parent.isMultiSelect && parent.options) {

        const option = parent.options.find(
            o => o.value === question.showWhenValue
        );

        if (option) {
            option.children.push(question);
        }

    }

}
    }
});

console.log('debug: ',
JSON.stringify(
    this.questions.map(q => ({
        question: q.questionText,
        dependent: q.dependentQuestionId,
        children: q.inlineChildren?.map(c => c.questionText)
    })))
);

    this.questions.forEach(question => {

        if (!question.section) {
            return;
        }

        if (!sectionMap.has(question.section)) {

            sectionMap.set(question.section, {
                name: question.section,
                questions: [],
                groups: [],
                isGrouped: false,
                isBalanceSection:
                    this.selectedAssessmentType ===
                        'Balance & Gait Assessment' &&
                    question.section === 'Balance Assessment',

                isGaitSection:
                    this.selectedAssessmentType ===
                        'Balance & Gait Assessment' &&
                    question.section === 'Gait Assessment'
            });
        }

        if (!question.dependentQuestionId) {

    sectionMap
        .get(question.section)
        .questions
        .push(question);
}
    });

    this.sections = Array.from(sectionMap.values()).map(section => {

        // Metadata-driven grouping
        // const groupedQuestions = section.questions.filter(q => q.group);
        // const ungroupedQuestions = section.questions.filter(q => !q.group);

        // if (groupedQuestions.length > 0) {

        //     section.isGrouped = true;

        //     const groupMap = new Map();

        //     groupedQuestions.forEach(question => {

        //         // if (!groupMap.has(question.group)) {
        //         //     groupMap.set(question.group, {
        //         //         name: question.group,
        //         //         questions: []
        //         //     });
        //         // }

        //         // groupMap
        //         //     .get(question.group)
        //         //     .questions
        //         //     .push(question);
        //         if (!groupMap.has(question.group)) {
        //             groupMap.set(question.group, {
        //                 name: question.group,
        //                 rows: []
        //             });
        //         }

        //         const group = groupMap.get(question.group);

        //         if (!question.isChildQuestion) {

        //             group.rows.push({
        //                 parent: question,
        //                 children: []
        //             });

        //         } else {

        //             const lastRow = group.rows[group.rows.length - 1];

        //             if (lastRow) {
        //                 lastRow.children.push(question);
        //             }
        //         }
        //     });

        //     section.groups = Array.from(groupMap.values());

        //     // Keep any questions without Group__c
        //     section.questions = ungroupedQuestions;

        //     section.hasQuestions = section.questions.length > 0;
        //     section.hasGroups = section.groups.length > 0;
        // } else if (groupedQuestions.length === 0) {
        //     section.hasQuestions = section.questions.length > 0;
        //     section.hasGroups = false;
        // }

        const groupMap = new Map();

section.questions.forEach(question => {

    if (!question.group) {
        return;
    }

    if (!groupMap.has(question.group)) {

        groupMap.set(question.group, {
            name: question.group,
            rows: []
        });
    }

    const group = groupMap.get(question.group);

    if (!question.isChildQuestion) {

        group.rows.push({
            parent: question,
            children: []
        });

    } else {

        const lastRow = group.rows[group.rows.length - 1];

        if (lastRow) {
            lastRow.children.push(question);
        }
    }
});

section.items = [];

const renderedGroups = new Set();

section.questions
    .sort((a, b) => a.sequence - b.sequence)
    .forEach(question => {

        if (!question.group) {

            section.items.push({
                question: question
            });

        } else if (
            !question.isChildQuestion &&
            !renderedGroups.has(question.group)
        ) {

            renderedGroups.add(question.group);

            section.items.push({
                group: groupMap.get(question.group)
            });
        }
    });

section.hasItems = section.items.length > 0;

        return section;
    });

    let displaySequence = 1;

this.sections.forEach(section => {

    section.items.forEach(item => {

        if (item.question) {

            if (item.question.hideSequence) {
                item.question.displaySequence = null;
            } else {
                item.question.displaySequence = displaySequence++;
            }

        } else if (item.group) {

            item.group.rows.forEach(row => {

                if (row.parent.hideSequence) {
                    row.parent.displaySequence = null;
                } else {
                    row.parent.displaySequence = displaySequence++;
                }

            });

        }

    });

});

    if (
        this.activeSections.length === 0 &&
        this.sections.length > 0
    ) {
        this.activeSections = [
            this.sections[0].name
        ];
    }
}

    handleAnswerChange(event) {

        const input = event.target;

        if (input.type === 'number' &&  input.classList.contains('caregiver-hours')) {
            const hours = Number(input.value);

            if (hours < 0 || hours > 24) {
                input.setCustomValidity('Hours must be between 0 and 24.');
            } else {
                input.setCustomValidity('');
            }

            input.reportValidity();

            if (!input.checkValidity()) {
                return;
            }
        }

        if (input.classList.contains('amount-question')) {
    const value = input.value;

    if (value && !/^\d+(\.\d{1,2})?$/.test(value)) {
        input.setCustomValidity('Please enter up to 2 decimal places only.');
    } else {
        input.setCustomValidity('');
    }

    input.reportValidity();

    if (!input.checkValidity()) {
        return;
    }
}

        if (input.type === 'tel') {
    const value = input.value || '';
    const phoneRegex = /^(\+1\s?)?(\(\d{3}\)|\d{3})[- ]?\d{3}[- ]?\d{4}$/;

    if (value && !phoneRegex.test(value)) {
        input.setCustomValidity(
            'Please enter a valid phone number.'
        );
    } else {
        input.setCustomValidity('');
    }

    input.reportValidity();
}

        if (input.type === 'text') {
    if (input.value.length > 255) {
        input.setCustomValidity('Maximum 255 characters are allowed.');
    } else {
        input.setCustomValidity('');
    }

    input.reportValidity();

    if (!input.checkValidity()) {
        return;
    }
}

if (input.type === 'email') {
    const value = input.value || '';
    const emailRegex =
/^(?!.*\.\.)(?!\.)(?!.*\.$)[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;

    if (value && !emailRegex.test(value)) {
        input.setCustomValidity(
            'Please enter a valid email address.'
        );
    } else {
        input.setCustomValidity('');
    }

    input.reportValidity();

    if (!input.checkValidity()) {
        return;
    }
}

        const questionId = event.currentTarget.dataset.id;
        // const value = event.detail.value;
        const value = event.target.value;

        console.log('Question Id:', questionId);
        console.log('Value:', JSON.stringify(value));

        this.questions = this.questions.map(question => {

            if (question.id === questionId) {
                console.log('Matched:', question.questionText);
                return {
                    ...question,
                    answer: value
                };
            }

            return question;

        });

        this.updateDependentQuestions();

    //     console.log(
    // JSON.stringify(
    //     this.questions.map(q => ({
    //         question: q.questionText,
    //         show: q.showQuestion
    //     }))
    // )
// );

    }

    shouldShowDependentQuestion(question) {

    if (!question.dependentActivity) {
        return true;
    }

    return this.selectedActivities.includes(
        question.dependentActivity
    );
}

handleCheckboxChange(event) {

    const questionId = event.target.dataset.id;
    const optionValue = event.target.dataset.value;
    const checked = event.target.checked;

    this.questions = this.questions.map(question => {

        if (question.id !== questionId) {
            return question;
        }

        let answers = [...(question.answer || [])];

        if (checked) {

            if (!answers.includes(optionValue)) {
                answers.push(optionValue);
            }

        } else {

            answers =
                answers.filter(value => value !== optionValue);

        }

        return {
            ...question,
            answer: answers
        };

    });

    this.updateDependentQuestions();
}

updateDependentQuestions() {

    this.questions = this.questions.map(question => {        

        let showQuestion = true;

        if (question.dependentQuestionId) {

            const parentQuestion = this.questions.find(
                q => q.id === question.dependentQuestionId
            );

            showQuestion = false;

            if (parentQuestion) {

                if (Array.isArray(parentQuestion.answer)) {

                    showQuestion = parentQuestion.answer.includes(
                        question.showWhenValue
                    );

                } else {

                    showQuestion =
                        parentQuestion.answer === question.showWhenValue;
                }
            }
        }

        if (question.isMultiSelect) {

    question.options = question.options.map(option => ({
        ...option,
        checked:
            Array.isArray(question.answer) &&
            question.answer.includes(option.value)
    }));
}

        return {
            ...question,
            showQuestion
        };
    });

    this.buildSections();
}

    handleNotesChange(event) {

    const questionId =
        event.currentTarget.dataset.id;

    const value =
        event.target.value;

    // if (value.length > MAX_NOTES_LENGTH) {

    //     event.target.setCustomValidity(
    //         'Maximum 131,072 characters are allowed.'
    //     );

    // } else {

    //     event.target.setCustomValidity('');
    // }

    // event.target.reportValidity();

    this.questions =
        this.questions.map(question => {

            if (question.id === questionId) {

                return {
                    ...question,
                    notes: value
                };
            }

            return question;
        });

    this.buildSections();
}

    buildAnswerPayload() {

    return this.questions
        .filter(question => {

            const hasAnswer = question.isMultiSelect
                ? Array.isArray(question.answer) &&
                    question.answer.length > 0
                : question.answer !== null &&
                    question.answer !== undefined &&
                    question.answer !== '';

            const hasNotes =
                question.notes !== null &&
                question.notes !== undefined &&
                question.notes.trim() !== '';

            return hasAnswer || hasNotes;
        })
        .map(question => {

            return {
                questionId: question.id,

                answer: question.isMultiSelect
                    ? question.answer.join(';')
                    : question.answer,

                notes: question.notes
            };
        });
}

    validate() {

        if (!this.selectedAssessmentType) {

            this.showToast(
                'Error',
                'Please select Assessment Type.',
                'error'
            );

            return false;

        }

        const invalidInput =
    [...this.template.querySelectorAll('lightning-textarea')]
        .some(textarea =>
            (textarea.value || '').length > 131072
        );

        // console.log('invalidInput : ',invalidInput);

        if (invalidInput) {

            this.showToast(
                'Error',
                'Description/Notes cannot exceed 131,072 characters.',
                'error'
            );

            return;
        }

 console.log('before this.selectedAssessmentType>>',this.selectedAssessmentType);
        if (this.selectedAssessmentType !== 'Home Safety Assessment') {
    console.log('after this.selectedAssessmentType>>',this.selectedAssessmentType);
        console.log('validation');
        const hasAtLeastOneAnswer =
            this.questions.some(question => {

                if (question.isMultiSelect) {
                    return Array.isArray(question.answer) &&
                        question.answer.length > 0;
                }

                return question.answer !== null &&
                    question.answer !== undefined &&
                    String(question.answer).trim() !== '';
            });

        if (!hasAtLeastOneAnswer) {

            this.showToast(
                'Error',
                'Please answer at least one question before saving.',
                'error'
            );

            return false;
        }

    }


        // const hasAtLeastOneAnswer =
        //     this.questions.some(question => {

        //         if (question.isMultiSelect) {
        //             return Array.isArray(question.answer) &&
        //                 question.answer.length > 0;
        //         }

        //         return question.answer !== null &&
        //             question.answer !== undefined &&
        //             String(question.answer).trim() !== '';
        //     });

        // if (!hasAtLeastOneAnswer) {

        //     this.showToast(
        //         'Error',
        //         'Please answer at least one question before saving.',
        //         'error'
        //     );

        //     return false;
        // }

        return true;

    }

    showToast(title, message, variant) {

        this.dispatchEvent(

            new ShowToastEvent({

                title,
                message,
                variant

            })

        );

    }

    
get score() {

    const scoringAnswers = {
        1: 'No',
        2: 'Yes',
        3: 'Yes',
        4: 'Yes',
        5: 'No',
        6: 'Yes',
        7: 'No',
        8: 'Yes',
        9: 'Yes',
        10: 'Yes',
        11: 'No',
        12: 'Yes',
        13: 'No',
        14: 'Yes',
        15: 'Yes'
    };

    return this.questions.reduce((total, question) => {

        const scoringAnswer =
            scoringAnswers[question.sequence];

        if (
            question.answer &&
            question.answer === scoringAnswer
        ) {
            return total + 1;
        }

        return total;

    }, 0);
}

get geriatricDepressionscoreResult() {
    return 'A score of 0-5 is normal. A score of above 5 suggests depression.';
}

get geriatricLeftColumn() {
    return [
        { question: 'Q1', answer: 'No' },
        { question: 'Q2', answer: 'Yes' },
        { question: 'Q3', answer: 'Yes' },
        { question: 'Q4', answer: 'Yes' },
        { question: 'Q5', answer: 'No' },
        { question: 'Q6', answer: 'Yes' },
        { question: 'Q7', answer: 'No' },
        { question: 'Q8', answer: 'Yes' }
    ];
}

get geriatricRightColumn() {
    return [
        { question: 'Q9', answer: 'Yes' },
        { question: 'Q10', answer: 'Yes' },
        { question: 'Q11', answer: 'No' },
        { question: 'Q12', answer: 'Yes' },
        { question: 'Q13', answer: 'No' },
        { question: 'Q14', answer: 'Yes' },
        { question: 'Q15', answer: 'Yes' }
    ];
}


    async handleCancel() {

    try {

        const focusedTab =
            await getFocusedTabInfo();

        await closeTab(
            focusedTab.tabId
        );

    } catch (error) {

        console.error(
            'Close Create Subtab Error:',
            error
        );
    }
}

validateCaregiverHours() {

    const hourInputs = this.template.querySelectorAll('.caregiver-hours');
    const invalidDays = [];

    hourInputs.forEach(input => {
        const value = input.value;

        if (value !== '' && value !== null) {
            const hours = Number(value);

            if (hours < 0 || hours > 24) {
                invalidDays.push(input.label);
            }
        }
    });

    if (invalidDays.length > 0) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Invalid Hours',
                message: `Hours must be between 0 and 24 for: ${invalidDays.join(', ')}`,
                variant: 'error'
            })
        );

        return false;
    }

    return true;
}

validatePhoneNumbers() {
    let isValid = true;

    this.template.querySelectorAll('.phone-question').forEach(input => {
        const value = input.value || '';

        const phoneRegex = /^(\+1\s?)?(\(\d{3}\)|\d{3})[- ]?\d{3}[- ]?\d{4}$/;

if (value && !phoneRegex.test(value)) {
    input.setCustomValidity(
        'Please enter a valid phone number.'
    );
    isValid = false;
} else {
    input.setCustomValidity('');
}

        input.reportValidity();
    });

    if (!isValid) {
        this.showToast(
            'Error',
            'Please correct the invalid phone number(s).',
            'error'
        );
    }

    return isValid;
}

validateEmailAddresses() {
    let isValid = true;

    this.template.querySelectorAll('.email-question').forEach(input => {
        const value = input.value || '';
        const emailRegex = /^(?!.*\.\.)(?!\.)(?!.*\.$)[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;

        if (value && !emailRegex.test(value)) {
            input.setCustomValidity('Please enter a valid email address.');
            isValid = false;
        } else {
            input.setCustomValidity('');
        }

        input.reportValidity();
    });

    if (!isValid) {
        this.showToast(
            'Error',
            'Please correct the invalid email address(es).',
            'error'
        );
    }

    return isValid;
}

validateAmounts() {
    let isValid = true;

    this.template.querySelectorAll('.amount-question').forEach(input => {
        const value = input.value || '';

        if (value && !/^\d+(\.\d{1,2})?$/.test(value)) {
            input.setCustomValidity('Please enter up to 2 decimal places only.');
            isValid = false;
        } else {
            input.setCustomValidity('');
        }

        input.reportValidity();
    });

    if (!isValid) {
        this.showToast(
            'Error',
            'Please correct the invalid data.',
            'error'
        );
    }

    return isValid;
}

    handleSave() {
        if (!this.validateEmailAddresses()) {
    return;
}

        if (!this.validatePhoneNumbers()) {
    return;
}

if (!this.validateAmounts()) {   // add this
        return;
    }

        if (!this.validateCaregiverHours()) {
            return;
        }

        if (!this.validate()) {
            return;
        }

        const textInputs =
    this.template.querySelectorAll('.text-question');


let hasError = false;

textInputs.forEach(input => {

    if (input.value && input.value.length > 255) {
        input.setCustomValidity('Maximum 255 characters are allowed.');
        hasError = true;
    } else {
        input.setCustomValidity('');
    }

    input.reportValidity();
});

if (hasError) {
    this.showToast(
        'Error',
        'Please correct the highlighted fields before saving.',
        'error'
    );
    return;
}

        this.isLoading = true;

        const answers = this.buildAnswerPayload();

        // console.log('answers ',JSON.stringify(answers));

        saveAssessment({
            accountId: this.recordId,
            assessmentType: this.selectedAssessmentType,
            answers: answers
        })
        .then(async assessmentId => {

            publish(
        this.messageContext,
        SECONDARY_ASSESSMENT_REFRESH_CHANNEL,
        {
            accountId: this.recordId
        }
    );

    this.showToast(
    'Success',
    this.isCloneMode
        ? 'Record saved and cloned successfully.'
        : 'Secondary Assessment created successfully.',
    'success'
);

    const focusedTab =
        await getFocusedTabInfo();

    const parentTabId =
        focusedTab.isSubtab
            ? focusedTab.parentTabId
            : focusedTab.tabId;    

    // Open created assessment as a new subtab
    await openSubtab(
        parentTabId,
        {
            recordId: assessmentId,
            focus: true
        }
    );

    // Close Create subtab
    await closeTab(
        focusedTab.tabId
    );

})
        .catch(error => {

            console.error(JSON.stringify(error));

            let message = 'Unknown Error';

            if (error.body && error.body.message) {
                message = error.body.message;
            }

            this.showToast(
                'Error',
                message,
                'error'
            );

        })
        .finally(() => {

            this.isLoading = false;

        });

    }
    

}