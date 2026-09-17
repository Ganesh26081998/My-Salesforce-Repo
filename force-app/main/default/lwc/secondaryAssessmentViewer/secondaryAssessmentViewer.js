import { LightningElement, api, wire } from 'lwc';
import LightningConfirm from 'lightning/confirm';

import getAssessmentData from '@salesforce/apex/SecondaryAssessmentController.getAssessmentData';
import saveAssessmentAnswers from '@salesforce/apex/SecondaryAssessmentController.saveAssessmentAnswers';
import deleteAssessment from '@salesforce/apex/SecondaryAssessmentController.deleteAssessment';
import generateAndAttachPdf
    from '@salesforce/apex/SecondaryAssessmentController.generateAndAttachPdf';
import completeAssessment
    from '@salesforce/apex/SecondaryAssessmentController.completeAssessment';

import {
    publish,
    MessageContext
} from 'lightning/messageService';

import SECONDARY_ASSESSMENT_REFRESH_CHANNEL
    from '@salesforce/messageChannel/secondaryAssessmentRefresh__c';

import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    closeTab,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

import { RefreshEvent }
    from 'lightning/refresh';

const MAX_NOTES_LENGTH = 131072;

import MMSEPentagon from '@salesforce/resourceUrl/MMSEPentagon';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import LOCALE from '@salesforce/i18n/locale';

export default class SecondaryAssessmentViewer extends NavigationMixin(LightningElement) {

    @api recordId;

    @api startInEditMode = false;

    @api isActionOverride = false;

    assessmentType;

    assessmentStatus;

    questions = [];

    sections = [];

    activeSections = [];

    isLoading = false;

    showNoQuestions = false;

    clientName;
    assessmentDate;
    lastModifiedDate;

    balanceScore = 0;
    gaitScore = 0;
    combinedScore = 0;
    riskLevel = '';

    pentagonImage = MMSEPentagon;

    BOOLEAN_OPTIONS = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    isEditMode = false;
    originalQuestions = [];

    get isReadOnly() {
        return !this.isEditMode;
    }

    connectedCallback() {

        this.loadAssessment();

    }

    @wire(MessageContext)
    messageContext;

    @wire(IsConsoleNavigation)
    isConsoleNavigation;

    
 

    loadAssessment() {

        this.isLoading = true;
        this.sections = [];
        this.activeSections = [];

        getAssessmentData({

            assessmentId: this.recordId

        })

        .then(result => {

            this.contactOptions = result.contactOptions || [];

            this.clientName =
                result.assessment.Account__r.Name;

            // this.assessmentDate =
            //     new Intl.DateTimeFormat('en-US').format(
            //         new Date(result.assessment.CreatedDate)
            //     );

            // this.lastModifiedDate =
            //     new Intl.DateTimeFormat('en-US').format(
            //         new Date(result.assessment.LastModifiedDate)
            //     );

             const localizeDateTime = (utcString) => {
                if (!utcString) return '';
                return new Intl.DateTimeFormat(LOCALE, {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    // hour: '2-digit',
                    // minute: '2-digit',
                    //second: '2-digit',
                    hour12: true,
                    timeZone: TIME_ZONE // This forces the conversion to the user's CDT profile setting
                }).format(new Date(utcString));
            };

            this.assessmentDate = localizeDateTime(result.assessment.CreatedDate);
            this.lastModifiedDate = localizeDateTime(result.assessment.LastModifiedDate);

            this.assessmentType =
                result.assessment.Assessment_Type__c;

            this.assessmentStatus =
                result.assessment.Status__c;
                        
                        this.balanceScore =
                result.balanceScore ?? 0;

            this.gaitScore =
                result.gaitScore ?? 0;

            this.combinedScore =
                result.combinedScore ?? 0;

            this.riskLevel =
                result.riskLevel || '';

            let answerMap = {};

            result.answers.forEach(ans => {

                answerMap[ans.Assessment_Question__c] = ans;

            });

            let displaySequence = 1;

            this.questions = result.questions.map(q => {

    const existing = answerMap[q.Id];

    const hideSequence =
    this.assessmentType === 'Caregiver Assessment' &&
    (
        q.Question_Text__c === 'What triggered the caregiver assessment?' ||
        q.Question_Text__c === 'How long has caregiver been caring for care receiver - Months' ||
        (q.Question_Text__c &&
         q.Question_Text__c.startsWith('Hours per Day'))
    );

    const isChildQuestion =
    String(q.Sequence__c).includes('.');   

    const isMultiSelect =
        q.Question_Type__c === 'Multi-Select';

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

    let answer = '';

    if (existing?.Answer__c) {

        answer = isMultiSelect
            ? existing.Answer__c
                .split(';')
                .map(value => value.trim())
                .filter(value => value)
            : existing.Answer__c;
    }
    else if (isMultiSelect) {
        answer = [];
    }

    return {
    id: q.Id,

    answerId:
        existing ? existing.Id : null,

    questionText:
        q.Question_Text__c,

    sequence:
        q.Sequence__c,
    
    hideSequence,
    displaySequence:
    this.assessmentType === 'Caregiver Assessment'
        ? (
            hideSequence || isChildQuestion
                ? null
                : displaySequence++
        )
        : q.Sequence__c,

    section:
        q.Section__c,
    group: q.Group__c,
    isChildQuestion: String(q.Sequence__c).includes('.'),

    helpText: q.HelpText__c,

    type:
        q.Question_Type__c,

    answer: answer,

    notes:
        existing?.Notes__c || '',

    isBoolean:
        q.Question_Type__c === 'Boolean',

    // isText:
    //     q.Question_Type__c === 'Text',
    isContactPicker:
        this.assessmentType === 'Caregiver Assessment' &&
        q.Question_Text__c === 'Caregiver',

    isText:
        q.Question_Type__c === 'Text' &&
        !(
            this.assessmentType === 'Caregiver Assessment' &&
            q.Question_Text__c === 'Caregiver'
        ),
        
    isTextArea: q.Question_Type__c === 'Text Area',

    isNumber:
        q.Question_Type__c === 'Number',
    
    isPhone: q.Question_Type__c === 'Phone',
    isEmail: q.Question_Type__c === 'Email',

    isDate:
        q.Question_Type__c === 'Date',

    isMultiSelect:
        isMultiSelect,

    isSingleSelect:
        q.Question_Type__c === 'Single-Select',

    options: q.Question_Type__c === 'Boolean'
            ? this.BOOLEAN_OPTIONS
            : answerOptions,
    
    showNotes: q.Show_Notes__c,

    notesLabel:
        q.Notes_Label__c || 'Notes',
        
    dependentQuestionId: q.Dependent_On_Question__c,
    showWhenValue: q.Show_When_Value__c,
    showPentagonImage:
        this.assessmentType === 'Mini Mental State Examination' &&
        q.Sequence__c === 11,
    isCaregiverDaysQuestion:
    this.assessmentType === 'Caregiver Assessment' &&
    q.Question_Text__c === 'Days',

    isCaregiverHourQuestion:
        this.assessmentType === 'Caregiver Assessment' &&
        q.Question_Text__c &&
        q.Question_Text__c.startsWith('Hours per Day'),
    isCaregiverYearsQuestion:
    this.assessmentType === 'Caregiver Assessment' &&
    q.Question_Text__c ===
        'How long has caregiver been caring for care receiver - Years',

isCaregiverMonthsQuestion:
    this.assessmentType === 'Caregiver Assessment' &&
    q.Question_Text__c ===
        'How long has caregiver been caring for care receiver - Months'
    }
});

this.updateDependentQuestions();

console.log('this.questions ',JSON.stringify(this.questions));

           this.originalQuestions = this.questions.map(question => ({
    ...question,

    answer: Array.isArray(question.answer)
        ? [...question.answer]
        : question.answer,
    
    notes: question.notes,

    options: question.options
        ? question.options.map(option => ({
            ...option
        }))
        : []
}));
            this.showNoQuestions =
                this.questions.length === 0;

            if (this.startInEditMode) {
                this.isEditMode = true;
            }

        })

        .catch(error => {

            console.error(error);

        })

        .finally(() => {

            this.isLoading = false;

        });

    }

    getSelectedOptions(questionText) {

    const question = this.questions.find(
        q => q.questionText && q.questionText.includes(questionText)
    );

    return Array.isArray(question?.answer)
        ? question.answer
        : [];
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


//     buildSections() {

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
//                 isBalanceSection:
//      this.assessmentType ===
//         'Balance & Gait Assessment' &&
//     question.section === 'Balance Assessment',

// isGaitSection:
//      this.assessmentType ===
//         'Balance & Gait Assessment' &&
//     question.section === 'Gait Assessment'
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

    // Build parent -> inline child mapping
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

    // Build sections
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
                    this.assessmentType ===
                        'Balance & Gait Assessment' &&
                    question.section ===
                        'Balance Assessment',

                isGaitSection:
                    this.assessmentType ===
                        'Balance & Gait Assessment' &&
                    question.section ===
                        'Gait Assessment'
            });
        }

        // Don't render dependent questions separately
        if (!question.dependentQuestionId) {

            sectionMap
                .get(question.section)
                .questions
                .push(question);
        }
    });

    this.sections = Array.from(sectionMap.values()).map(section => {

        // const groupedQuestions =
        //     section.questions.filter(q => q.group);

        // const ungroupedQuestions =
        //     section.questions.filter(q => !q.group);

        // if (groupedQuestions.length > 0) {

        //     section.isGrouped = true;

        //     const groupMap = new Map();

        //     groupedQuestions.forEach(question => {

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

        //             const lastRow =
        //                 group.rows[group.rows.length - 1];

        //             if (lastRow) {
        //                 lastRow.children.push(question);
        //             }
        //         }
        //     });

        //     section.groups =
        //         Array.from(groupMap.values());

        //     // Keep questions without Group__c
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
                type: 'question',
                question: question
            });

        } else if (!question.isChildQuestion &&
                   !renderedGroups.has(question.group)) {

            renderedGroups.add(question.group);

            section.items.push({
                type: 'group',
                group: groupMap.get(question.group)
            });
        }

    });

section.hasItems = section.items.length > 0;

        return section;
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

get hasSections() {
    return this.sections.length > 0;
}

    get isGeriatricDepressionScale() {
    return this.assessmentType === 'Geriatric Depression Scale';
}

get isHomeSafetyAssessment() {
    return this.assessmentType ===
        'Home Safety Assessment';
}

get isHomeFromHospitalAssessment() {
    return this.assessmentType ===
        'Home from the Hospital Assessment';
}

 get isKatzADLAssessment() {
        return this.assessmentType ===
            'Katz ADL Assessment';
    }

get isBalanceGaitAssessment() {
    return this.assessmentType ===
        'Balance & Gait Assessment';
}

get isCaregiverAssessment() {
    return this.assessmentType ===
        'Caregiver Assessment';
}

get isFamilyCaregiverAssessment() {
    return this.assessmentType === 'Family Caregiver Assessment';
}

get isMiniMentalStateExamination() {
    return this.assessmentType === 'Mini Mental State Examination';
}

get isQualityOfLifeTPA() {
    return this.assessmentType === 'Quality of Life Therapeutic Program Assessment';
}

get isMedicationManagementAssessment(){
    return this.assessmentType === 'Medication Management Assessment';
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

    const daysQuestion = this.questions.find(
        q => q.isCaregiverDaysQuestion
    );

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

get caregiverMonthsQuestion() {
    return this.questions.find(
        q => q.isCaregiverMonthsQuestion
    );
}

get isCompleted() {
    return this.assessmentStatus === 'Completed';
}

get isDraft() {

    return this.assessmentStatus === 'Draft';

}

get mmseTotalScore() {
    if (!this.questions) {
        return 0;
    }

    return this.questions.reduce((total, question) => {
        const score = parseInt(question.answer, 10);
        return total + (isNaN(score) ? 0 : score);
    }, 0);
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

    const questionId =
        event.currentTarget.dataset.id;

    const value =
        event.detail.value;

    this.questions =
        this.questions.map(question => {

            if (question.id === questionId) {
                return {
                    ...question,
                    answer: value
                };
            }

            return question;
        });

    this.updateDependentQuestions();
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


handleNotesChange(event) {

    const questionId =
        event.currentTarget.dataset.id;

    const value =
        event.target.value;

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

const textInputs =
    this.template.querySelectorAll('.text-question');
console.log('textInputs ',textInputs);

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

        const answers = this.questions.map(question => {

    return {
        questionId: question.id,

        answer: question.isMultiSelect
            ? question.answer.join(';')
            : question.answer,

        notes: question.notes
    };
});

console.log('answers: ',JSON.stringify(answers));

const hasAnswer = answers.some(a =>
    (a.answer && String(a.answer).trim() !== '') ||
    (a.notes && String(a.notes).trim() !== '')
);

if (
    !hasAnswer &&
    this.assessmentType !== 'Home Safety Assessment'
) {

    this.showToast(
        'Error',
        'There are no answers to save.',
        'error'
    );

    return;
}

            // if (answers.length === 0) {
            //     this.showToast(
            //         'Error',
            //         'There are no answers to save.',
            //         'error'
            //     );
            //     return;
            // }

            this.isLoading = true;

            saveAssessmentAnswers({
                assessmentId: this.recordId,
                answers: answers
            })
            .then(async () => {

                this.showToast(
                    'Success',
                    'Assessment answers updated successfully.',
                    'success'
                );

                if (this.isActionOverride) {

                    const tabInfo = await getFocusedTabInfo();

                    await closeTab(tabInfo.tabId);

                } else {

                    this.isEditMode = false;
                    this.loadAssessment();

                }

                

            })
            .catch(error => {

                console.error(
                    'Save Error:',
                    JSON.stringify(error)
                );

                let message = 'Unable to save assessment answers.';

                if (error.body?.message) {
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

handleEdit() {

    if (this.isCompleted) {

    this.showToast(
        'Info',
        'Completed assessments cannot be edited.',
        'info'
    );

    return;
}

this.originalQuestions = this.questions.map(question => ({
    ...question,

    answer: Array.isArray(question.answer)
        ? [...question.answer]
        : question.answer,

    notes: question.notes,

    options: question.options
        ? question.options.map(option => ({
            ...option
        }))
        : []
}));
    this.isEditMode = true;
}

    async handleCancelEdit() {
    try {
        if (this.isActionOverride) {
            const tabInfo = await getFocusedTabInfo();
            console.log('Tab Info:', JSON.stringify(tabInfo));

            await closeTab(tabInfo.tabId);
            return;
        }

        console.log(
        this.originalQuestions.find(
            q => q.questionText === 'Hours per Day - Monday'
        )?.answer
    );

        // this.questions = this.originalQuestions.map(question => ({
        //     ...question,
        //     answer: Array.isArray(question.answer)
        //         ? [...question.answer]
        //         : question.answer,
        //     notes: question.notes,
        //     options: question.options
        //         ? question.options.map(option => ({ ...option }))
        //         : []
        // }));

        // this.buildSections();
        // this.isEditMode = false;

        this.isEditMode = false;
this.loadAssessment();

        // Clear all validation messages
requestAnimationFrame(() => {

    this.template
        .querySelectorAll('lightning-input')
        .forEach(input => {
            input.setCustomValidity('');
            input.reportValidity();
        });

    this.template
        .querySelectorAll('lightning-textarea')
        .forEach(textarea => {
            textarea.setCustomValidity('');
            textarea.reportValidity();
        });

});

    } catch (error) {
        console.error('Cancel Error:', error);
        console.error('Message:', error?.message);
        console.error('Body:', JSON.stringify(error));
    }
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

async handleClone() {

    try {

        const tabInfo =
            await getFocusedTabInfo();

        const parentTabId =
            tabInfo.isSubtab
                ? tabInfo.parentTabId
                : tabInfo.tabId;

        const cloneTabId =
            await openSubtab(
                parentTabId,
                {
                    pageReference: {
                        type: 'standard__component',
                        attributes: {
                            componentName:
                                'c__secondaryAssessmentCreate'
                        },
                        state: {
                            c__recordId:
                                this.recordId,

                            c__cloneMode:
                                'true'
                        }
                    },
                    focus: true
                }
            );

        // Set the label exactly like your New subtab fix
        await setTabLabel(
            cloneTabId,
            'Clone Secondary Assessment'
        );

        await setTabIcon(
            cloneTabId,
            'custom:custom27',
            {
                iconAlt: 'Secondary Assessment'
            }
        );

    } catch (error) {

        console.error(
            'Open Clone Subtab Error:',
            error
        );

        console.error(
            'Error Message:',
            error?.message
        );
    }
}

async handleDelete() {

    const confirmed = await LightningConfirm.open({
        message:
            'Are you sure you want to delete this Secondary Assessment?',
        label: 'Delete Secondary Assessment',
        theme: 'warning'
    });

    if (!confirmed) {
        return;
    }

    this.isLoading = true;

    try {

        const accountId = await deleteAssessment({
            assessmentId: this.recordId
        });
        console.log('Publishing LMS for Account:', accountId);

        publish(
            this.messageContext,
            SECONDARY_ASSESSMENT_REFRESH_CHANNEL,
            {
                accountId: accountId
            }
        );

        this.showToast(
            'Success',
            'Secondary Assessment deleted successfully.',
            'success'
        );

         if (this.isConsoleNavigation) {

            const tabInfo = await getFocusedTabInfo();

            await closeTab(tabInfo.tabId);

        } else {

            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: accountId,
                    objectApiName: 'Account',
                    actionName: 'view'
                }
            });
        }

    } catch (error) {

        console.error(
            'Delete Error:',
            JSON.stringify(error)
        );

        let message =
            'Unable to delete the Secondary Assessment.';

        if (error.body?.message) {
            message = error.body.message;
        }

        this.showToast(
            'Error',
            message,
            'error'
        );

    } finally {

        this.isLoading = false;
    }
}

async handleGeneratePdf() {
    console.log('In handleGeneratePdf');

    this.isLoading = true;

    try {
        console.log('try - In handleGeneratePdf');
        console.log('this.isLoading: ',this.isLoading);

        const isUpdate =
    await generateAndAttachPdf({
        assessmentId: this.recordId
    });

     console.log('isUpdate ',isUpdate);

        this.dispatchEvent(
    new RefreshEvent()
);


        this.showToast(
    'Success',
    isUpdate
        ? 'Assessment PDF updated successfully.'
        : 'Assessment PDF generated and attached successfully.',
    'success'
);

    } catch (error) {

        console.error(
            'PDF Generation Error:',
            JSON.stringify(error)
        );

        this.showToast(
            'Error',
            error.body?.message ||
                'Unable to generate the Assessment PDF.',
            'error'
        );

    } finally {

        this.isLoading = false;
    }
}

async handleComplete() {

    const confirmed =
        await LightningConfirm.open({

            message:
                'Are you sure you want to complete this assessment? Once completed, it will become read-only.',

            label:
                'Complete Assessment',

            theme: 'warning'
        });

    if (!confirmed) {
        return;
    }

    this.isLoading = true;

    try {

        await completeAssessment({
            assessmentId: this.recordId
        });

        this.showToast(
            'Success',
            'Assessment completed successfully.',
            'success'
        );

        this.loadAssessment();

    } catch (error) {

        console.error(
            'Complete Assessment Error:',
            JSON.stringify(error)
        );

        this.showToast(
            'Error',
            error.body?.message ||
                'Unable to complete the assessment.',
            'error'
        );

    } finally {

        this.isLoading = false;

    }
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

}