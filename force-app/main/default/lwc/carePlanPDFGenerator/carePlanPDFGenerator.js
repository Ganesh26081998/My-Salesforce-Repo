import { LightningElement, wire, track, api } from 'lwc';
import fetchAllCarePlanData from '@salesforce/apex/HealthCloudCarePlanController.fetchAllCarePlanData';
import saveCarePlan from '@salesforce/apex/HealthCloudCarePlanController.saveCarePlan';
import generatePDFPreview from '@salesforce/apex/HealthCloudCarePlanController.generatePDFPreview';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { CurrentPageReference } from 'lightning/navigation';
//import getCarePlanById from '@salesforce/apex/HealthCloudCarePlanController.getCarePlanById';
import getCarePlans from '@salesforce/apex/CarePlanCaseController.getCarePlans';
import getNextCarePlanTitle from '@salesforce/apex/CarePlanCaseController.getNextCarePlanTitle';
// Import fields - adjust these based on your object (Account, Contact, etc.)
import NAME_FIELD from '@salesforce/schema/Account.Name';
import ID_FIELD from '@salesforce/schema/Account.Id';
import { RefreshEvent } from 'lightning/refresh';
import { NavigationMixin } from 'lightning/navigation';
import { getFocusedTabInfo, closeTab } from 'lightning/platformWorkspaceApi';
import { publish, MessageContext } from 'lightning/messageService';
import CARE_PLAN_REFRESH_CHANNEL from '@salesforce/messageChannel/CarePlanRefreshChannel__c';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import QUARTERLY_GOAL_STATUS_FIELD from '@salesforce/schema/Case.Quarterly_Goal_Status__c';
import CLIENT_STABILITY_FIELD from '@salesforce/schema/Case.Overall_Client_Stability_This_Quarter__c';
import PLAN_ADJUSTMENT_FIELD from '@salesforce/schema/Case.Plan_Adjustment__c';
import getStakeholderContactsFromCCR from '@salesforce/apex/HealthCloudCarePlanController.getStakeholderContactsFromCCR';


const FIELDS = [NAME_FIELD, ID_FIELD];

export default class CarePlanBuilder extends  NavigationMixin(LightningElement) {

    @api recordId; // This will automatically get the record ID from the page
    @track carePlanTitle = '';  
    accountName = '';
    problems = [];
    longTermGoals = [];
    quarterlyGoals = [];
    @track carePlanTitleSuffix = '';  // User-editable part
    @track isSuffixEditing = false;
    @track isLoading = false;
    @track isAddActionInProgress = false;
    addActionUnlockTimeout;
    @track isScheduleDateRangeInvalid = false;
    @track longTermGoalSearchKey = '';
    @track querterlyGoalSearchKey='';
    @track problemSearchKey='';
    @track interventionSearchKey='';
    // Client Impact Review fields
    @track quarterlyGoalStatus = '';
    @track clientStability = '';
    @track outcomeSummary = '';
    @track planAdjustment = '';
    @track stakeholderContactOptions = [];


    // Picklist options
    @track quarterlyGoalStatusOptions = [];
    @track clientStabilityOptions = [];
    @track planAdjustmentOptions = [];

    // Case object info for picklist wire adapters
    caseObjectInfo;




    @track problemBlocks = [];
    @track longTermGoalBlocks = [];
    @track quarterlyGoalBlocks = [];
    @track stakeholderBlocks = [];
    tabInitialized = false;
    //isEdit = false;
    selectedRecordId = null;
    activeSections = ['problems', 'longTermGoals', 'quarterlyGoals', 'stakeholders', 'schedule','clientImpact'];

    // Schedule fields
    @track scheduleStartDate = '';
    @track scheduleReviewDate = '';
    @track scheduleFrequency = '';
    @track scheduleDuration = '';
    @track scheduleHoursPerWeek = '';

    // Record information
    recordName = '';
    accountId = null;

    // Schedule fields
    @track scheduleStartDate = '';
    @track scheduleReviewDate = '';
    @track scheduleFrequency = '';
    @track scheduleDuration = '';
    @track scheduleHoursPerWeek = '';

    severityOptions = [
        { label: 'Low', value: 'Low' },
        { label: 'Medium', value: 'Medium' },
        { label: 'High', value: 'High' }
    ];

    stakeholderTypeOptions = [
        { label: 'Family Member', value: 'Family Member' },
        { label: 'Guardian', value: 'Guardian' },
        { label: 'Healthcare Provider', value: 'Healthcare Provider' },
        { label: 'Social Worker', value: 'Social Worker' },
        { label: 'Therapist', value: 'Therapist' },
        { label: 'Case Manager', value: 'Case Manager' },
        { label: 'Other', value: 'Other' }
    ];

    communicationPreferenceOptions = [
        { label: 'Phone', value: 'Phone' },
        { label: 'Email', value: 'Email' },
        { label: 'Text Message', value: 'Text Message' },
        { label: 'In-Person', value: 'In-Person' },
        { label: 'Video Call', value: 'Video Call' }
    ];
    frequencyOptions = [
    { label: 'Weekly', value: 'Weekly' },
    { label: 'Bi-Weekly', value: 'Bi-Weekly' },
    { label: 'Monthly', value: 'Monthly' },
    { label: 'As Needed', value: 'As Needed' },
    { label: 'Other', value: 'Other' }
];

communicationFrequencyOptions = [
    { label: 'Weekly', value: 'Weekly' },
    { label: 'Monthly', value: 'Monthly' },
    { label: 'As Needed', value: 'As Needed' },
    { label: 'At Each Interaction', value: 'At Each Interaction' }
];

interventionFrequencyOptions = [
    { label: 'As needed', value: 'As needed' },
    { label: '1x/week', value: '1x/week' },
    { label: '2–3x/week', value: '2–3x/week' },
    { label: 'Monthly', value: 'Monthly' }
];

connectedCallback() {
    this.initializeStartDate();
}
initializeStartDate() {
    if (!this.scheduleStartDate) {
        const today = new Date();
        this.scheduleStartDate = today.toISOString().split('T')[0];

        const reviewDate = new Date(today);
        reviewDate.setMonth(reviewDate.getMonth() + 3);
        this.scheduleReviewDate = reviewDate.toISOString().split('T')[0];
    }
}

get carePlanPrefix() {
    return this.carePlanTitle; // System-generated: "AccountName - CP 0001"
}

get fullCarePlanTitle() {
    const suffix = this.carePlanTitleSuffix ? ' ' + this.carePlanTitleSuffix.trim() : '';
    return this.carePlanPrefix + suffix;
}

get suffixMaxLength() {
    return 60 - (this.carePlanPrefix ? this.carePlanPrefix.length + 1 : 0); // +1 for the space
}

get suffixHelpText() {
    return `Max ${this.suffixMaxLength} characters. The full name is stored in the Case Subject field.`;
}
handleTitleSuffixChange(e) {
    this.carePlanTitleSuffix = e.detail.value;
}
// Add these methods 
handleSuffixEditClick() {
    this.isSuffixEditing = true;
    // Auto-focus the input after it renders
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
        const input = this.template.querySelector('.suffix-inline-input');
        if (input) {
            input.focus();
        }
    }, 50);
}

handleSuffixBlur() {
    this.isSuffixEditing = false;
}

handleTitleSuffixChange(e) {
    this.carePlanTitleSuffix = e.detail.value;
}

handleLongTermGoalSearch(event) {
    this.longTermGoalSearchKey = (event.target.value || '').toLowerCase().trim();
}



get filteredAvailableLongTermGoalOptions() {
    const base = this.availableLongTermGoalOptions || []; // existing getter
    const term = this.longTermGoalSearchKey;

    // remove already-selected items from left panel (they are disabled in base)
    const availableOnly = base.filter(opt => !opt.disabled);

    if (!term) return availableOnly;

    // case-insensitive partial match
    return availableOnly.filter(opt =>
        (opt.label || '').toLowerCase().includes(term)
    );
}

get showLongTermTemplateSearch() {
    // Show search only when at least one template long-term goal picker is open
    return this.longTermGoalBlocks.some(
        b => !b.isCustom && !b.isSelected
    );
}

handleProblemSearch(event) {
    this.problemSearchKey = (event.target.value || '').toLowerCase().trim();
}

get filteredAvailableProblemOptions() {
    const base = this.availableProblemOptions || [];
    const term = this.problemSearchKey;
    //const availableOnly = base.filter(opt => !opt.disabled);

    if (!term) return base;

    return base.filter(opt =>
        (opt.label || '').toLowerCase().includes(term)
    );
}

get showProblemTemplateSearch() {
    return this.problemBlocks.some(
        b => !b.isCustom && !b.isSelected
    );
}

handleQuarterlyGoalSearch(event) {
    this.querterlyGoalSearchKey = (event.target.value || '').toLowerCase().trim();
}

get filteredAvailableQuarterlyGoalOptions() {
    const base = this.availableQuarterlyGoalOptions || [];
    const term = this.querterlyGoalSearchKey;
    //const availableOnly = base.filter(opt => !opt.disabled);

    if (!term) return base;

    return base.filter(opt =>
        (opt.label || '').toLowerCase().includes(term)
    );
}

get showQuarterlyGoalTemplateSearch() {
    return this.quarterlyGoalBlocks.some(
        b => !b.isCustom && !b.isSelected
    );
}

handleInterventionSearch(event) {
    this.interventionSearchKey = (event.target.value || '').toLowerCase().trim();
}

get filteredAvailableInterventionOptions() {
    const base = this.availableInterventionOptions || [];
    const term = this.interventionSearchKey;
    //const availableOnly = base.filter(opt => !opt.disabled);

    if (!term) return base;

    return base.filter(opt =>
        (opt.label || '').toLowerCase().includes(term)
    );
}

get showInterventionTemplateSearch() {
    return this.quarterlyGoalBlocks.some(qg =>
        qg.isSelected &&
        Array.isArray(qg.interventions) &&
        qg.interventions.some(i => !i.isCustom && !i.isSelected)
    );
}



    // Wire to get record data
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.recordName = getFieldValue(data, NAME_FIELD);
            this.accountId = getFieldValue(data, ID_FIELD);
            console.log('Record Name:', this.recordName);
            console.log('Account ID:', this.accountId);
            console.log('RecordId available:', this.recordId);
            this.loadStakeholderContactOptions();

           
        } else if (error) {
            console.error('Error loading record:', error);
        }
    }

    @wire(fetchAllCarePlanData)
    wiredData({ data, error }) {
        if (data) {
            console.log('Fetched Data:', JSON.stringify(data));

            this.problems = data.problems.map(p => ({ label: p.problemName, value: p.problemId }));
            console.log('Problems:', this.problems);

            data.goals.forEach(g => {
                console.log('Processing Goal:', g.goalName, 'Type:', g.type);

                const goalObj = {
                    id: g.goalId,
                    label: g.goalName,
                    value: g.goalId,
                    tasks: g.tasks.map(t => ({ label: t.taskName, value: t.taskId }))
                };

                // Check for exact match and variations
                if (g.type === 'Long Terms Goals' || g.type === 'Long Terms Goal' ||
                    g.type === 'long terms goals' || g.type === 'LongTermGoals') {
                    this.longTermGoals.push(goalObj);
                    console.log('Added to Long Term Goals');
                }
                if (g.type === 'Quarterly Goals' || g.type === 'Quarterly Goal' ||
                    g.type === 'quarterly goals' || g.type === 'QuarterlyGoals') {
                    this.quarterlyGoals.push(goalObj);
                    console.log('Added to Quarterly Goals');
                }
            });

            console.log('Long Term Goals Count:', this.longTermGoals.length);
            console.log('Quarterly Goals Count:', this.quarterlyGoals.length);
        }
        if (error) {
            console.error('Error fetching data:', error);
        }
    }

   

    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef?.state?.recordId) {
            this.recordId = pageRef.state.recordId;
            console.log('Record ID from page reference:', this.recordId);
            this.loadData();
        } else if (pageRef?.state?.c__recordId) {
            this.recordId = pageRef.state.c__recordId;
            console.log('Record ID from c__recordId:', this.recordId);
            this.loadData();
        }
    }

    @wire(MessageContext)
    messageContext;

    // Wire Case object info
@wire(getObjectInfo, { objectApiName: CASE_OBJECT })
wiredCaseObjectInfo({ data, error }) {
    if (data) {
        this.caseObjectInfo = data;
        console.log('Case Object Info loaded:', data);
    } else if (error) {
        console.error('Error loading Case object info:', error);
    }
}

// Wire Quarterly Goal Status picklist
@wire(getPicklistValues, {
    recordTypeId: '$caseObjectInfo.defaultRecordTypeId',
    fieldApiName: QUARTERLY_GOAL_STATUS_FIELD
})
wiredQuarterlyGoalStatus({ data, error }) {
    if (data) {
        this.quarterlyGoalStatusOptions = data.values.map(item => ({
            label: item.label,
            value: item.value
        }));
    } else if (error) {
        console.error('Error fetching Quarterly Goal Status picklist:', error);
    }
}

// Wire Client Stability picklist
@wire(getPicklistValues, {
    recordTypeId: '$caseObjectInfo.defaultRecordTypeId',
    fieldApiName: CLIENT_STABILITY_FIELD
})
wiredClientStability({ data, error }) {
    if (data) {
        this.clientStabilityOptions = data.values.map(item => ({
            label: item.label,
            value: item.value
        }));
    } else if (error) {
        console.error('Error fetching Client Stability picklist:', error);
    }
}

// Wire Plan Adjustment picklist
@wire(getPicklistValues, {
    recordTypeId: '$caseObjectInfo.defaultRecordTypeId',
    fieldApiName: PLAN_ADJUSTMENT_FIELD
})
wiredPlanAdjustment({ data, error }) {
    if (data) {
        this.planAdjustmentOptions = data.values.map(item => ({
            label: item.label,
            value: item.value
        }));
    } else if (error) {
        console.error('Error fetching Plan Adjustment picklist:', error);
    }
}

// Client Impact Review handlers
handleQuarterlyGoalStatus(e) {
    this.quarterlyGoalStatus = e.target.value;
}

handleClientStability(e) {
    this.clientStability = e.target.value;
}

handleOutcomeSummary(e) {
    this.outcomeSummary = e.detail.value;
}

handlePlanAdjustment(e) {
    this.planAdjustment = e.target.value;
}

    loadData() {
        console.log('Record Id ready:', this.recordId);
        this.generateCarePlanTitle();
        
    }

    loadStakeholderContactOptions() {
    if (!this.accountId) return;
    getStakeholderContactsFromCCR({ accountId: this.accountId })
        .then(data => {
            this.stakeholderContactOptions = (data || []).map(x => ({
                label: x.label,
                value: x.value
            }));
        })
        .catch(error => {
            console.error('Error loading stakeholder contacts:', error);
            this.stakeholderContactOptions = [];
        });
}


    

   

    generateCarePlanTitle() {
        getNextCarePlanTitle({ accountId: this.recordId })
            .then(title => {
                this.carePlanTitle = title;
                console.log('Generated Care Plan Title:', this.carePlanTitle);
            })
            .catch(error => {
                console.error('Error generating title:', error);
            });
    }



    handleTitleChange(e) {
        this.carePlanTitle = e.detail.value;
    }


 

  

            /* ================= CUSTOM ADD HANDLERS ================= */

addCustomProblem() {
    this.runAddAction(() => {
    this.problemBlocks = [ {
        id: crypto.randomUUID(),
        selectedIds: [],
        isSelected: true,      // Skip template picker — go straight to card
        isCustom: true,         // Flag as custom entry
        selectedName: '',       // User will type this
        severity: '',
        description: ''
    },...this.problemBlocks];
});
}

addCustomLongTermGoal() {
    this.runAddAction(() => {
    this.longTermGoalBlocks = [ {
        id: crypto.randomUUID(),
        selectedIds: [],
        isSelected: true,
        isCustom: true,
        selectedName: '',
        category: '',
        description: '',
        successCriteria: ''
    },...this.longTermGoalBlocks];
});
}

addCustomQuarterlyGoal() {
    this.runAddAction(() => {
    this.quarterlyGoalBlocks = [ {
        id: crypto.randomUUID(),
        selectedIds: [],
        interventions: [],
        isSelected: true,
        isCustom: true,
        selectedName: '',
        category: '',
        description: '',
        successCriteria: ''
    },...this.quarterlyGoalBlocks];
});
}


addCustomIntervention(event) {
    this.runAddAction(() => {
    const goalId = event.currentTarget.dataset.id;
    const goal = this.quarterlyGoalBlocks.find(g => g.id === goalId);
    goal.interventions = [{
        id: crypto.randomUUID(),
        selectedIds: [],
        isSelected: true,
        isCustom: true,
        selectedName: '',
        category: '',
        specificIntervention: '',
        frequency: '',
        duration: '',
        details: ''
    }, ...goal.interventions];
    this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
});
}

/* ================= CUSTOM NAME CHANGE HANDLERS ================= */

handleCustomProblemName(e) {
    const block = this.problemBlocks.find(b => b.id === e.target.dataset.id);
    block.selectedName = e.detail.value;
    this.problemBlocks = [...this.problemBlocks];
}

handleCustomLongTermGoalName(e) {
    const block = this.longTermGoalBlocks.find(b => b.id === e.target.dataset.id);
    block.selectedName = e.detail.value;
    this.longTermGoalBlocks = [...this.longTermGoalBlocks];
}

handleCustomQuarterlyGoalName(e) {
    const block = this.quarterlyGoalBlocks.find(b => b.id === e.target.dataset.id);
    block.selectedName = e.detail.value;
    this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
}

handleCustomInterventionName(e) {
    const goal = this.quarterlyGoalBlocks.find(g => g.id === e.target.dataset.goal);
    const intv = goal.interventions.find(i => i.id === e.target.dataset.id);
    intv.selectedName = e.detail.value;
    this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
}

    /* ================= OPTIONS ================= */

    get availableProblemOptions() {
        //const used = this.problemBlocks.flatMap(b => b.selectedIds);
        return this.problems.map(p => ({ ...p }));
    }

    get availableLongTermGoalOptions() {
        //const used = this.longTermGoalBlocks.flatMap(b => b.selectedIds);
        return this.longTermGoals.map(g => ({ ...g }));
    }

    get availableQuarterlyGoalOptions() {
        //const used = this.quarterlyGoalBlocks.flatMap(b => b.selectedIds);
        return this.quarterlyGoals.map(g => ({ ...g }));
    }

    get availableInterventionOptions() {

        return this.quarterlyGoals
            .flatMap(g => g.tasks)
            .map(t => ({ ...t }));
    }

    get addButtonClass() {
    return this.isAddActionInProgress ? 'add-more add-more-disabled' : 'add-more';
    }

    get addCustomButtonClass() {
        return this.isAddActionInProgress ? 'add-more add-custom add-more-disabled' : 'add-more add-custom';
    }

    runAddAction(actionFn) {
    if (this.isAddActionInProgress) return;

    this.isAddActionInProgress = true;
    actionFn();

    clearTimeout(this.addActionUnlockTimeout);
    this.addActionUnlockTimeout = setTimeout(() => {
        this.isAddActionInProgress = false;
    }, 350);
}


    /* ================= ADD HANDLERS ================= */

    addProblem() {
        this.runAddAction(() => {
        this.problemSearchKey = ''; // optional: reset search
        this.problemBlocks = [ {
            id: crypto.randomUUID(),
            selectedIds: [],
            isSelected: false,
            selectedName: '',
            severity: '',
            description: ''
        },...this.problemBlocks];
    });
}

    addLongTermGoal() {
        this.runAddAction(() => {
        this.longTermGoalSearchKey = ''; // optional: reset search
        this.longTermGoalBlocks = [ {
            id: crypto.randomUUID(),
            selectedIds: [],
            isSelected: false,
            selectedName: '',
            category: '',
            description: '',
            successCriteria: ''
        },...this.longTermGoalBlocks];
    });
}

    addQuarterlyGoal() {
        this.runAddAction(() => {
        this.querterlyGoalSearchKey = '';
        this.quarterlyGoalBlocks = [
            
            {
                id: crypto.randomUUID(),
                selectedIds: [],
                interventions: [],
                isSelected: false,
                selectedName: '',
                category: '',
                description: '',
                successCriteria: ''
            },...this.quarterlyGoalBlocks
        ];
    });
}

    addIntervention(event) {
        this.runAddAction(() => {
        this.interventionSearchKey = '';
        const goalId = event.currentTarget.dataset.id;
        const goal = this.quarterlyGoalBlocks.find(g => g.id === goalId);
        goal.interventions.push({
            id: crypto.randomUUID(),
            selectedIds: [],
            isSelected: false,
            selectedName: '',
            category: '',
            specificIntervention: '',
            frequency: '',
            duration: '',
            details: ''
        });
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    });
}

    addStakeholder() {
        this.runAddAction(() => {
        this.stakeholderBlocks = [ {
            id: crypto.randomUUID(),
            stakeholderType: '',
            //contactName: '',
            contactId: null,
            //userId: null,  
            roleInCare: '',
            communicationPreference: '',
            communicationFrequency: ''
        },...this.stakeholderBlocks];
    });
}

    /* ================= DELETE HANDLERS ================= */

    deleteProblem(event) {
        const id = event.currentTarget.dataset.id;
        this.problemBlocks = this.problemBlocks.filter(b => b.id !== id);
    }

    deleteLongTermGoal(event) {
        const id = event.currentTarget.dataset.id;
        this.longTermGoalBlocks = this.longTermGoalBlocks.filter(b => b.id !== id);
    }

    deleteQuarterlyGoal(event) {
        const id = event.currentTarget.dataset.id;
        this.quarterlyGoalBlocks = this.quarterlyGoalBlocks.filter(b => b.id !== id);
    }

    deleteIntervention(event) {
        const goalId = event.currentTarget.dataset.goal;
        const intvId = event.currentTarget.dataset.id;
        const goal = this.quarterlyGoalBlocks.find(g => g.id === goalId);
        goal.interventions = goal.interventions.filter(i => i.id !== intvId);
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    deleteStakeholder(event) {
        const id = event.currentTarget.dataset.id;
        this.stakeholderBlocks = this.stakeholderBlocks.filter(b => b.id !== id);
    }

    isDuplicateTemplateProblem(selectedProblemId, currentBlockId) {
    if (!selectedProblemId) return false;
    return this.problemBlocks.some(b =>
        b.id !== currentBlockId &&
        !b.isCustom &&
        Array.isArray(b.selectedIds) &&
        b.selectedIds.includes(selectedProblemId)
    );
}

isDuplicateTemplateLongTermGoal(selectedGoalId, currentBlockId) {
    if (!selectedGoalId) return false;
    return this.longTermGoalBlocks.some(b =>
        b.id !== currentBlockId &&
        !b.isCustom && // custom long-term goals are excluded
        Array.isArray(b.selectedIds) &&
        b.selectedIds.includes(selectedGoalId)
    );
}

isDuplicateTemplateQuarterlyGoal(selectedGoalId, currentBlockId) {
    if (!selectedGoalId) return false;
    return this.quarterlyGoalBlocks.some(b =>
        b.id !== currentBlockId &&
        !b.isCustom && // custom quarterly goals are excluded
        Array.isArray(b.selectedIds) &&
        b.selectedIds.includes(selectedGoalId)
    );
}


handleProblemChange(e) {
    const block = this.problemBlocks.find(b => b.id === e.target.dataset.id);
    const selectedIds = e.detail.value || [];
    const selectedProblemId = selectedIds[0];

    if (this.isDuplicateTemplateProblem(selectedProblemId, block.id)) {
        this.showToast(
            'Validation Error',
            'The same template problem cannot be added multiple times to a single Care Plan.',
            'error'
        );
        block.selectedIds = [];
        block.selectedName = '';
        block.isSelected = false;
        this.problemBlocks = [...this.problemBlocks];
        return;
    }

    block.selectedIds = selectedIds;
    block.isSelected = selectedIds.length > 0;
    if (block.isSelected) {
        const selectedProblem = this.problems.find(p => p.value === selectedProblemId);
        block.selectedName = selectedProblem ? selectedProblem.label : '';
    } else {
        block.selectedName = '';
    }
    this.problemBlocks = [...this.problemBlocks];
}



    /* ================= CHANGE HANDLERS ================= */
  

    
   

    handleLongTermGoalChange(e) {
    const block = this.longTermGoalBlocks.find(b => b.id === e.target.dataset.id);
    const selectedIds = e.detail.value || [];
    const selectedGoalId = selectedIds[0];

    if (this.isDuplicateTemplateLongTermGoal(selectedGoalId, block.id)) {
        this.showToast(
            'Validation Error',
            'The same template long term goal cannot be added multiple times to a single Care Plan.',
            'error'
        );
        block.selectedIds = [];
        block.selectedName = '';
        block.isSelected = false;
        this.longTermGoalBlocks = [...this.longTermGoalBlocks];
        return;
    }

    block.selectedIds = selectedIds;
    block.isSelected = selectedIds.length > 0;

    if (block.isSelected) {
        const selectedGoal = this.longTermGoals.find(g => g.value === selectedGoalId);
        block.selectedName = selectedGoal ? selectedGoal.label : '';
    } else {
        block.selectedName = '';
    }

    this.longTermGoalBlocks = [...this.longTermGoalBlocks];
}

handleQuarterlyGoalChange(e) {
    const block = this.quarterlyGoalBlocks.find(b => b.id === e.target.dataset.id);
    const selectedIds = e.detail.value || [];
    const selectedGoalId = selectedIds[0];

    if (this.isDuplicateTemplateQuarterlyGoal(selectedGoalId, block.id)) {
        this.showToast(
            'Validation Error',
            'The same template quarterly goal cannot be added multiple times to a single Care Plan.',
            'error'
        );
        block.selectedIds = [];
        block.selectedName = '';
        block.isSelected = false;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
        return;
    }

    block.selectedIds = selectedIds;
    block.isSelected = selectedIds.length > 0;

    if (block.isSelected) {
        const selectedGoal = this.quarterlyGoals.find(g => g.value === selectedGoalId);
        block.selectedName = selectedGoal ? selectedGoal.label : '';
    } else {
        block.selectedName = '';
    }

    this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
}



    handleInterventionChange(e) {
        const goal = this.quarterlyGoalBlocks.find(g => g.id === e.target.dataset.goal);
        const intv = goal.interventions.find(i => i.id === e.target.dataset.id);
        intv.selectedIds = e.detail.value;
        if (intv.selectedIds.length > 0) {
            intv.isSelected = true;
            const selectedTask = this.quarterlyGoals
                .flatMap(g => g.tasks)
                .find(t => t.value === intv.selectedIds[0]);
            intv.selectedName = selectedTask ? selectedTask.label : '';
        }
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    /* ================= PROBLEM FIELD HANDLERS ================= */

    handleProblemSeverity(e) {
        const block = this.problemBlocks.find(b => b.id === e.target.dataset.id);
        block.severity = e.detail.value;
        this.problemBlocks = [...this.problemBlocks];
    }

    handleProblemDescription(e) {
        const block = this.problemBlocks.find(b => b.id === e.target.dataset.id);
        block.description = e.detail.value;
        this.problemBlocks = [...this.problemBlocks];
    }

    /* ================= LONG TERM GOAL FIELD HANDLERS ================= */

    handleLongTermGoalCategory(e) {
        const block = this.longTermGoalBlocks.find(b => b.id === e.target.dataset.id);
        block.category = e.detail.value;
        this.longTermGoalBlocks = [...this.longTermGoalBlocks];
    }

    handleLongTermGoalDescription(e) {
        const block = this.longTermGoalBlocks.find(b => b.id === e.target.dataset.id);
        block.description = e.detail.value;
        this.longTermGoalBlocks = [...this.longTermGoalBlocks];
    }

    handleLongTermGoalSuccessCriteria(e) {
        const block = this.longTermGoalBlocks.find(b => b.id === e.target.dataset.id);
        block.successCriteria = e.detail.value;
        this.longTermGoalBlocks = [...this.longTermGoalBlocks];
    }

    /* ================= QUARTERLY GOAL FIELD HANDLERS ================= */

    handleQuarterlyGoalCategory(e) {
        const block = this.quarterlyGoalBlocks.find(b => b.id === e.target.dataset.id);
        block.category = e.detail.value;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    handleQuarterlyGoalDescription(e) {
        const block = this.quarterlyGoalBlocks.find(b => b.id === e.target.dataset.id);
        block.description = e.detail.value;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    handleQuarterlyGoalSuccessCriteria(e) {
        const block = this.quarterlyGoalBlocks.find(b => b.id === e.target.dataset.id);
        block.successCriteria = e.detail.value;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    /* ================= INTERVENTION FIELD HANDLERS ================= */

    handleInterventionCategory(e) {
        const goal = this.quarterlyGoalBlocks.find(g => g.id === e.target.dataset.goal);
        const intv = goal.interventions.find(i => i.id === e.target.dataset.id);
        intv.category = e.detail.value;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    handleInterventionSpecific(e) {
        const goal = this.quarterlyGoalBlocks.find(g => g.id === e.target.dataset.goal);
        const intv = goal.interventions.find(i => i.id === e.target.dataset.id);
        intv.specificIntervention = e.detail.value;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    handleInterventionFrequency(e) {
        const goal = this.quarterlyGoalBlocks.find(g => g.id === e.target.dataset.goal);
        const intv = goal.interventions.find(i => i.id === e.target.dataset.id);
        intv.frequency = e.detail.value;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    handleInterventionDuration(e) {
        const goal = this.quarterlyGoalBlocks.find(g => g.id === e.target.dataset.goal);
        const intv = goal.interventions.find(i => i.id === e.target.dataset.id);
        intv.duration = e.detail.value;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    handleInterventionDetails(e) {
        const goal = this.quarterlyGoalBlocks.find(g => g.id === e.target.dataset.goal);
        const intv = goal.interventions.find(i => i.id === e.target.dataset.id);
        intv.details = e.detail.value;
        this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
    }

    /* ================= STAKEHOLDER FIELD HANDLERS ================= */

    handleStakeholderType(e) {
        const block = this.stakeholderBlocks.find(b => b.id === e.target.dataset.id);
        block.stakeholderType = e.detail.value;
        this.stakeholderBlocks = [...this.stakeholderBlocks];
    }

    

    
handleStakeholderContactChange(event) {
    const stakeholderId = event.target.dataset.id;
    const selectedContactId = event.detail.value;

    const block = this.stakeholderBlocks.find(b => b.id === stakeholderId);
    if (block) {
        block.contactId = selectedContactId;
    }
    this.stakeholderBlocks = [...this.stakeholderBlocks];
}


    handleStakeholderRole(e) {
        const block = this.stakeholderBlocks.find(b => b.id === e.target.dataset.id);
        block.roleInCare = e.detail.value;
        this.stakeholderBlocks = [...this.stakeholderBlocks];
    }

    handleStakeholderCommPref(e) {
        const block = this.stakeholderBlocks.find(b => b.id === e.target.dataset.id);
        block.communicationPreference = e.detail.value;
        this.stakeholderBlocks = [...this.stakeholderBlocks];
    }

    handleStakeholderCommFreq(e) {
        const block = this.stakeholderBlocks.find(b => b.id === e.target.dataset.id);
        block.communicationFrequency = e.detail.value;
        this.stakeholderBlocks = [...this.stakeholderBlocks];
    }

    /* ================= SCHEDULE FIELD HANDLERS ================= */

    validateScheduleDateRange(showToast = false) {
    const hasBothDates = this.scheduleStartDate && this.scheduleReviewDate;
    this.isScheduleDateRangeInvalid =
        hasBothDates && this.scheduleStartDate > this.scheduleReviewDate;

    if (this.isScheduleDateRangeInvalid && showToast) {
        this.showToast(
            'Validation Error',
            'Start Date must be less than or equal to Review Date.',
            'error'
        );
    }

    return !this.isScheduleDateRangeInvalid;
}


   

handleScheduleStartDate(e) {
    this.scheduleStartDate = e.detail.value;
    this.validateScheduleDateRange(true);
    // ✅ AUTO-CALCULATE REVIEW DATE (3 months from start date)
    if (this.scheduleStartDate) {
        const startDate = new Date(this.scheduleStartDate);
        const reviewDate = new Date(startDate);
        reviewDate.setMonth(startDate.getMonth() + 3); // Add 3 months
        
        // Format as YYYY-MM-DD for lightning-input type="date"
        this.scheduleReviewDate = reviewDate.toISOString().split('T')[0];
    }
}

handleScheduleReviewDate(e) {
    this.scheduleReviewDate = e.detail.value;
    this.validateScheduleDateRange(true);
}



    handleScheduleFrequency(e) {
        this.scheduleFrequency = e.detail.value;
    }

   

  
handleScheduleDuration(e) {
    this.scheduleDuration = e.detail.value;
}


    handleScheduleHoursPerWeek(e) {
    const value = e.detail.value;
    this.scheduleHoursPerWeek = value;

    if (value === '' || value === null || value === undefined) {
        return;
    }

    const num = Number(value);
    if (!Number.isFinite(num) || num <= 0 || Object.is(num, -0)) {
        this.showToast('Validation Error', 'Hours per week must be a positive number greater than 0.', 'error');
    }
}


    /* ================= ACTION BUTTON HANDLERS ================= */

    handlePreviewPDF() {
        // Collect all care plan data
        const carePlanData = {
            problems: this.problemBlocks.filter(p => p.isSelected),
            longTermGoals: this.longTermGoalBlocks.filter(g => g.isSelected),
            quarterlyGoals: this.quarterlyGoalBlocks.filter(g => g.isSelected).map(qg => ({
                ...qg,
                interventions: qg.interventions.filter(i => i.isSelected)
            })),
            stakeholders: this.stakeholderBlocks,
            schedule: {
                startDate: this.scheduleStartDate,
                reviewDate: this.scheduleReviewDate,
                frequency: this.scheduleFrequency,
                duration: this.scheduleDuration,
                hoursPerWeek: this.scheduleHoursPerWeek
            },
            clientImpact: {
                quarterlyGoalStatus: this.quarterlyGoalStatus,
                clientStability: this.clientStability,
                outcomeSummary: this.outcomeSummary,
                planAdjustment: this.planAdjustment
            }
        };

        console.log('Preview PDF - Care Plan Data:', JSON.stringify(carePlanData, null, 2));

        // Call Apex to generate PDF preview
        generatePDFPreview({ carePlanDataJson: JSON.stringify(carePlanData) })
            .then(pdfBase64 => {
                // Convert base64 to Blob and open as PDF
                console.log('pdfBase64 length:', pdfBase64?.length);
                const byteCharacters = atob(pdfBase64);
                const byteNumbers = new Array(byteCharacters.length);
                for (let i = 0; i < byteCharacters.length; i++) {
                    byteNumbers[i] = byteCharacters.charCodeAt(i);
                }
                const byteArray = new Uint8Array(byteNumbers);
                const blob = new Blob([byteArray], { type: 'application/pdf' });
                const blobUrl = URL.createObjectURL(blob);
                window.open(blobUrl, '_blank');
                setTimeout(() => URL.revokeObjectURL(blobUrl), 60000);

                this.showToast('Success', 'PDF preview generated successfully', 'success');
            })
            .catch(error => {
                console.error('Error generating PDF preview:', error);
                this.showToast('Error', 'Error generating PDF preview: ' + (error.body?.message || error.message), 'error');
            });
    }




    async handleSaveCarePlan() {
        this.isLoading = true;
        console.log('🔵 Message Context:', this.messageContext);
        // Validate required fields
        const selectedProblems = this.problemBlocks.filter(p => p.isSelected);
        const hasProblems = selectedProblems.length > 0;
        //const hasStakeholderNames = this.stakeholderBlocks.every(sh => sh.contactName);
        const hasStakeholderUsers = this.stakeholderBlocks.every(sh => sh.userId);
        //const hasScheduleFrequency = this.scheduleFrequency;
        console.log('users in stakeholders:', this.stakeholderBlocks.map(sh => sh.userId));
        //console.log('contact names in stakeholders:', this.stakeholderBlocks.map(sh => sh.contactName)); 

        if (!hasProblems) {
            this.showToast('Validation Error', 'Please add at least one problem', 'error');
            this.isLoading = false;
            return;
        }

       

        
        // NEW: Validate that all problems have severity
        const problemsWithoutSeverity = selectedProblems.filter(p => !p.severity || p.severity.trim() === '');
        if (problemsWithoutSeverity.length > 0) {
            this.showToast('Validation Error', 'Please select Priority for all problems', 'error');
            this.isLoading = false;
            return;
        }

        // Validate custom problem name is mandatory
        const customProblemsWithoutName = selectedProblems.filter(
            p => p.isCustom && (!p.selectedName || !p.selectedName.trim())
        );

        if (customProblemsWithoutName.length > 0) {
            this.showToast('Validation Error', 'Please enter a name for all custom problems.', 'error');
            this.isLoading = false;
            return;
        }

        // Keep selected lists once
        const selectedLongTermGoals = this.longTermGoalBlocks.filter(g => g.isSelected);
        const selectedQuarterlyGoals = this.quarterlyGoalBlocks.filter(g => g.isSelected);

        // Validate custom long-term goal name
        const customLongTermGoalsWithoutName = selectedLongTermGoals.filter(
            g => g.isCustom && (!g.selectedName || !g.selectedName.trim())
        );
        if (customLongTermGoalsWithoutName.length > 0) {
            this.showToast('Validation Error', 'Please enter a name for all custom long term goals.', 'error');
            this.isLoading = false;
            return;
        }

        // Validate custom quarterly goal name
        const customQuarterlyGoalsWithoutName = selectedQuarterlyGoals.filter(
            g => g.isCustom && (!g.selectedName || !g.selectedName.trim())
        );
        if (customQuarterlyGoalsWithoutName.length > 0) {
            this.showToast('Validation Error', 'Please enter a name for all custom quarterly goals.', 'error');
            this.isLoading = false;
            return;
        }

       
        const stakeholderContactIds = (this.stakeholderBlocks || [])
            .map(sh => sh.contactId)
            .filter(Boolean);

        const hasDuplicateStakeholderContacts =
            new Set(stakeholderContactIds).size !== stakeholderContactIds.length;

        if (hasDuplicateStakeholderContacts) {
            this.showToast(
                'Validation Error',
                'Duplicate contacts are not allowed in the same Care Plan.',
                'error'
            );
            this.isLoading = false;
            return;
        }


        if (!this.validateScheduleDateRange(true)) {
            this.isLoading = false;
            return;
    }

    

if (this.scheduleHoursPerWeek !== '' && this.scheduleHoursPerWeek !== null && this.scheduleHoursPerWeek !== undefined) {
    const hoursNum = Number(this.scheduleHoursPerWeek);
    if (!Number.isFinite(hoursNum) || hoursNum <= 0 || Object.is(hoursNum, -0)) {
        this.showToast('Validation Error', 'Hours per week must be a positive number greater than 0.', 'error');
        this.isLoading = false;
        return;
    }
}





      

       

        // Collect all care plan data (only selected items)
        const carePlanData = {
            problems: selectedProblems,
            longTermGoals: this.longTermGoalBlocks.filter(g => g.isSelected),
            quarterlyGoals: this.quarterlyGoalBlocks.filter(g => g.isSelected).map(qg => ({
                ...qg,
                interventions: qg.interventions.filter(i => i.isSelected)
            })),
            stakeholders: this.stakeholderBlocks,
            schedule: {
                startDate: this.scheduleStartDate,
                reviewDate: this.scheduleReviewDate,
                frequency: this.scheduleFrequency,
                duration: this.scheduleDuration,
                hoursPerWeek: this.scheduleHoursPerWeek
            },
             clientImpact: {
                quarterlyGoalStatus: this.quarterlyGoalStatus,
                clientStability: this.clientStability,
                outcomeSummary: this.outcomeSummary,
                planAdjustment: this.planAdjustment
            }
        };

        console.log('Save Care Plan - Data:', JSON.stringify(carePlanData, null, 2));
        console.log('Record ID for Save:', this.recordId);
        // ⭐ Capture tab info BEFORE save
        const tabInfo = await getFocusedTabInfo();
        console.log('Create Tab Info:', JSON.stringify(tabInfo));

        // Call Apex method to save to Sal  esforce
        saveCarePlan({
            carePlanDataJson: JSON.stringify(carePlanData),
            accountId: this.accountId, // Pass the Account ID from the current record
           
            accountName: this.carePlanPrefix,
            carePlanSuffix: this.carePlanTitleSuffix || '',
            //accountName: this.fullCarePlanTitle, // Pass the full care plan title with suffix for Case subject
            carePlanId: this.isEdit ? this.recordId : null  // Pass ID for updates
            //carePlanId: null  // Pass existing care plan ID if updating
        })
        
           .then(result => {
            this.isLoading = false;
    if (result.success) {
        this.showToast('Success', result.message, 'success');
        this.dispatchEvent(new CustomEvent('close'));
        console.log('Care Plan ID:', result.carePlanId);
        console.log('PDF Document ID:', result.pdfContentDocumentId);

        // Step 1: Navigate to Account page FIRST
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });

        // Step 2: After navigation, publish LMS message with delay so carePlanList is mounted
        setTimeout(() => {
            try {
                const payload = {
                    refreshList: true,
                    accountId: this.accountId
                };
                console.log('Publishing LMS after navigation delay:', payload);
                publish(this.messageContext, CARE_PLAN_REFRESH_CHANNEL, payload);
                console.log('MESSAGE PUBLISHED SUCCESSFULLY');
            } catch (publishError) {
                console.error('PUBLISH ERROR:', publishError);
            }

            // Step 3: Close the subtab AFTER publishing
            if (tabInfo?.tabId) {
                setTimeout(async () => {
                    try {
                        console.log('Attempting to close tab:', tabInfo.tabId);
                        await closeTab(tabInfo.tabId);
                        console.log('Tab closed successfully');
                    } catch (error) {
                        console.error('Error closing tab:', error);
                    }
                }, 1500);
            }
        }, 2000); // 2 second delay to let Account page & carePlanList render

    } else {
        this.showToast('Error', result.message, 'error');
    }
})
            .catch(error => {
                this.isLoading = false;
                console.error('Error saving care plan:', error);
                this.showToast('Error', 'Error saving care plan: ' + (error.body?.message || error.message), 'error');
            });
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}