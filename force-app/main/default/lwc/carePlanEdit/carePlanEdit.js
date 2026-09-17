import { LightningElement, api, wire, track } from 'lwc';
import fetchAllCarePlanData from '@salesforce/apex/HealthCloudCarePlanController.fetchAllCarePlanData';
import getCarePlanById from '@salesforce/apex/HealthCloudCarePlanController.getCarePlanById';
import getAccountIdFromCarePlan from '@salesforce/apex/HealthCloudCarePlanController.getAccountIdFromCarePlan';
import saveCarePlan from '@salesforce/apex/CarePlanCaseController.saveCarePlan';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { getFocusedTabInfo, closeTab } from 'lightning/platformWorkspaceApi';
import { publish, MessageContext } from 'lightning/messageService';
import CARE_PLAN_REFRESH_CHANNEL from '@salesforce/messageChannel/CarePlanRefreshChannel__c';
import getNextCarePlanTitle from '@salesforce/apex/CarePlanCaseController.getNextCarePlanTitle';
import generatePDFPreview from '@salesforce/apex/HealthCloudCarePlanController.generatePDFPreview';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import QUARTERLY_GOAL_STATUS_FIELD from '@salesforce/schema/Case.Quarterly_Goal_Status__c';
import CLIENT_STABILITY_FIELD from '@salesforce/schema/Case.Overall_Client_Stability_This_Quarter__c';
import PLAN_ADJUSTMENT_FIELD from '@salesforce/schema/Case.Plan_Adjustment__c';
import getStakeholderContactsFromCCR from '@salesforce/apex/HealthCloudCarePlanController.getStakeholderContactsFromCCR';
import { RefreshEvent } from 'lightning/refresh';


export default class CarePlanEdit extends NavigationMixin(LightningElement) {
    @api recordId; // Care Plan (Case) Id
    accountId; // Will be fetched from Care Plan
    @track isCloneMode = false;
    @track carePlanTitlePrefix = '';  // System-generated prefix (non-editable)
    @track carePlanTitleSuffix = '';  // User-editable part
    @track isSuffixEditing = false;
    @track isLoading = false;
    @track isAddActionInProgress = false;
    addActionUnlockTimeout;
    @track isScheduleDateRangeInvalid = false;
    @track longTermGoalSearchKey = '';
    @track quarterlyGoalSearchKey = '';
    @track problemSearchKey = '';
    @track interventionSearchKey = '';
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

    problems = [];
    longTermGoals = [];
    quarterlyGoals = [];
    activeSections = ['problems', 'longTermGoals', 'quarterlyGoals', 'stakeholders', 'schedule','clientImpact'];


    @track problemBlocks = [];
    @track longTermGoalBlocks = [];
    @track quarterlyGoalBlocks = [];
    @track stakeholderBlocks = [];

    @track carePlanTitle = '';
    @track scheduleStartDate = '';
    @track scheduleReviewDate = '';
    @track scheduleFrequency = '';
    @track scheduleDuration = '';
    @track scheduleHoursPerWeek = '';

    isDataLoaded = false;

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

    get saveButtonLabel() {
    return this.isCloneMode ? 'Clone & Save' : 'Update';
}
get fullCarePlanTitle() {
    const suffix = this.carePlanTitleSuffix ? ' ' + this.carePlanTitleSuffix.trim() : '';
    return this.carePlanTitlePrefix + suffix;
}

get suffixMaxLength() {
    return 60 - (this.carePlanTitlePrefix ? this.carePlanTitlePrefix.length + 1 : 0);
}

get suffixHelpText() {
    return `Max ${this.suffixMaxLength} characters. The full name is stored in the Case Subject field.`;
}
handleTitleSuffixChange(e) {
    this.carePlanTitleSuffix = e.detail.value;
}
handleSuffixEditClick() {
    this.isSuffixEditing = true;
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
//helper methods for search functionality in comboboxes
handleLongTermGoalSearch(event) {
    this.longTermGoalSearchKey = (event.target.value || '').toLowerCase().trim();
}

handleProblemSearch(event) {
    this.problemSearchKey = (event.target.value || '').toLowerCase().trim();
}

handleQuarterlyGoalSearch(event) {
    this.quarterlyGoalSearchKey = (event.target.value || '').toLowerCase().trim();
}

handleInterventionSearch(event) {
    this.interventionSearchKey = (event.target.value || '').toLowerCase().trim();
}

    // Wire to fetch master data
    @wire(fetchAllCarePlanData)
    wiredData({ data, error }) {
        if (data) {
            this.problems = data.problems.map(p => ({ label: p.problemName, value: p.problemId }));

            data.goals.forEach(g => {
                const goalObj = {
                    id: g.goalId,
                    label: g.goalName,
                    value: g.goalId,
                    tasks: g.tasks.map(t => ({ label: t.taskName, value: t.taskId }))
                };

                if (g.type === 'Long Terms Goals' || g.type === 'Long Terms Goal' ||
                    g.type === 'long terms goals' || g.type === 'LongTermGoals' ||
                    g.type === 'Long Term') {
                    this.longTermGoals.push(goalObj);
                }
                if (g.type === 'Quarterly Goals' || g.type === 'Quarterly Goal' ||
                    g.type === 'quarterly goals' || g.type === 'QuarterlyGoals' ||
                    g.type === 'Quarterly') {
                    this.quarterlyGoals.push(goalObj);
                }
            });

            console.log('Master data loaded:', {
                problems: this.problems.length,
                longTermGoals: this.longTermGoals.length,
                quarterlyGoals: this.quarterlyGoals.length
            });

            // After master data loads, get account ID and load care plan
            if (this.recordId && !this.isDataLoaded) {
                this.getAccountAndLoadCarePlan();
            }
        }
        if (error) {
            console.error('Error fetching master data:', error);
        }
    }

    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef?.state?.c__carePlanId) {
            this.recordId = pageRef.state.c__carePlanId;
            this.isCloneMode = pageRef.state.c__mode === 'clone';
            console.log('Is Clone Mode:', this.isCloneMode);
            this.getAccountAndLoadCarePlan();
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
        console.log('Default Record Type ID:', data.defaultRecordTypeId);
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
        console.log('Quarterly Goal Status picklist data:', data);
        this.quarterlyGoalStatusOptions = data.values.map(item => ({
            label: item.label,
            value: item.value
        }));
    } else if (error) {
        console.error('Error fetching Quarterly Goal Status picklist:', error);
        console.error('Field API Name:', QUARTERLY_GOAL_STATUS_FIELD);
    }
}

// Wire Client Stability picklist
@wire(getPicklistValues, {
    recordTypeId: '$caseObjectInfo.defaultRecordTypeId',
    fieldApiName: CLIENT_STABILITY_FIELD
})
wiredClientStability({ data, error }) {
    if (data) {
        console.log('Client Stability picklist data:', data);
        this.clientStabilityOptions = data.values.map(item => ({
            label: item.label,
            value: item.value
        }));
    } else if (error) {
        console.error('Error fetching Client Stability picklist:', error);
        console.error('Field API Name:', CLIENT_STABILITY_FIELD);
    }
}

// Wire Plan Adjustment picklist
@wire(getPicklistValues, {
    recordTypeId: '$caseObjectInfo.defaultRecordTypeId',
    fieldApiName: PLAN_ADJUSTMENT_FIELD
})
wiredPlanAdjustment({ data, error }) {
    if (data) {
        console.log('Plan Adjustment picklist data:', data);
        this.planAdjustmentOptions = data.values.map(item => ({
            label: item.label,
            value: item.value
        }));
    } else if (error) {
        console.error('Error fetching Plan Adjustment picklist:', error);
        console.error('Field API Name:', PLAN_ADJUSTMENT_FIELD);
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
    this.outcomeSummary = e.target.value;
}

handlePlanAdjustment(e) {
    this.planAdjustment = e.target.value;
}

    // Get Account ID from Care Plan ID, then load care plan
    getAccountAndLoadCarePlan() {
        console.log('Getting Account ID for Care Plan:', this.recordId);

        getAccountIdFromCarePlan({ carePlanId: this.recordId })
            .then(accountId => {
                console.log('Account ID retrieved:', accountId);
                this.accountId = accountId;
                this.loadCarePlan();
                this.loadStakeholderContactOptions();

            })
            .catch(error => {
                console.error('Error getting Account ID:', error);
                this.showToast('Error', 'Failed to load Care Plan', 'error');
            });
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


    /* ================= CUSTOM ADD HANDLERS ================= */

addCustomProblem() {
    this.runAddAction(() => {
    this.problemBlocks = [ {
        id: 'temp-' + Date.now() + '-' + Math.random(),
        selectedIds: [],
        isSelected: true,
        isCustom: true,
        selectedName: '',
        severity: '',
        description: ''
    },...this.problemBlocks];
});
}

addCustomLongTermGoal() {
    this.runAddAction(() => {
    this.longTermGoalBlocks = [ {
        id: 'temp-' + Date.now() + '-' + Math.random(),
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
        id: 'temp-' + Date.now() + '-' + Math.random(),
        selectedIds: [],
        interventions: [],
        isSelected: true,
        isCustom: true,
        selectedName: '',
        category: '',
        description: '',
        successCriteria: ''
    },...this.quarterlyGoalBlocks,];
});
}

addCustomIntervention(event) {
    this.runAddAction(() => {
    const goalId = event.currentTarget.dataset.id;
    this.quarterlyGoalBlocks = this.quarterlyGoalBlocks.map(g => {
        if (g.id !== goalId) return { ...g, interventions: (g.interventions || []).map(i => ({ ...i })) };
        const oldInterventions = g.interventions || [];
        const newInterventions = [
            
            {
                id: 'temp-' + Date.now() + '-' + Math.random(),
                selectedIds: [],
                isSelected: true,
                isCustom: true,
                selectedName: '',
                category: '',
                specificIntervention: '',
                frequency: '',
                duration: '',
                details: ''
            },...oldInterventions.map(i => ({ ...i }))
        ];
        return { ...g, interventions: newInterventions };
    });
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
    const goalId = e.target.dataset.goal;
    const intvId = e.target.dataset.id;
    this.updateIntervention(goalId, intvId, { selectedName: e.detail.value });
}

    // Load existing care plan data using Account ID
    loadCarePlan() {
        console.log('Loading Care Plan for Account:', this.accountId);

        getCarePlanById({ carePlanId: this.recordId })
            .then(result => {
                console.log('Loaded Care Plan Data:', JSON.stringify(result, null, 2));

               
               
                // Use dedicated suffix field — no more regex parsing
            const subjectStr = result.caseSubject || '';
            const suffix = result.carePlanSuffix || '';
            this.carePlanTitleSuffix = suffix;
            // Derive prefix by removing suffix from end of subject
            if (suffix && subjectStr.endsWith(suffix)) {
                this.carePlanTitlePrefix = subjectStr.substring(0, subjectStr.length - suffix.length).trim();
            } else {
                this.carePlanTitlePrefix = subjectStr;
            }
            this.carePlanTitle = subjectStr;
               

                // Load problems
                if (result.problems && result.problems.length > 0) {
                    this.problemBlocks = result.problems.map(p => ({
                        ...p,
                        isSelected: true,
                        isCustom: p.isCustom || false,
                        id: p.id,
                        //selectedIds: p.templateId ? [p.templateId] : (p.selectedIds || [])
                        selectedIds: p.isCustom ? [] : (p.templateId ? [p.templateId] :
                        (this.getTemplateIdByName(p.selectedName, this.problems) ? [this.getTemplateIdByName(p.selectedName, this.problems)] : [])
)

                    }));
                }

                // Load long term goals
                if (result.longTermGoals && result.longTermGoals.length > 0) {
                    this.longTermGoalBlocks = result.longTermGoals.map(g => ({
                        ...g,
                        isSelected: true,
                        isCustom: g.isCustom || false,
                        id: g.id,
                        //selectedIds: g.templateId ? [g.templateId] : (g.selectedIds || [])
                        selectedIds: g.isCustom ? [] : (g.templateId ? [g.templateId] :
    (this.getTemplateIdByName(g.selectedName, this.longTermGoals) ? [this.getTemplateIdByName(g.selectedName, this.longTermGoals)] : [])
)

                    }));
                }

                // Load quarterly goals
                if (result.quarterlyGoals && result.quarterlyGoals.length > 0) {
                    this.quarterlyGoalBlocks = result.quarterlyGoals.map(g => ({
                        ...g,
                        isSelected: true,
                        isCustom: g.isCustom || false,
                        id: g.id,
                        //selectedIds: g.templateId ? [g.templateId] : (g.selectedIds || []),
                        selectedIds: g.isCustom ? [] : (
    g.templateId ? [g.templateId] :
    (this.getTemplateIdByName(g.selectedName, this.quarterlyGoals) ? [this.getTemplateIdByName(g.selectedName, this.quarterlyGoals)] : [])
),

                        interventions: (g.interventions || []).map(i => ({
                            ...i,
                            isSelected: true,
                            id: i.id,
                            isCustom: i.isCustom || false,
                            //selectedIds: i.templateId ? [i.templateId] : (i.selectedIds || []),
                            selectedIds: i.isCustom ? [] : (i.templateId ? [i.templateId] :
    (this.getTemplateIdByName(i.selectedName, this.availableInterventionOptions) ? [this.getTemplateIdByName(i.selectedName, this.availableInterventionOptions)] : [])
),
                            selectedName: i.selectedName,
                            //selectedIds: i.selectedIds,
                            frequency: i.frequency,
                            duration: i.duration,
                            details: i.details
                        }))
                    }));
                }

                // Load stakeholders
                if (result.stakeholders && result.stakeholders.length > 0) {
                    this.stakeholderBlocks = result.stakeholders.map(s => ({
                        ...s,
                        id: s.id || 'temp-' + Date.now() + '-' + Math.random(),  // ✅ Ensure ID exists
                        isNew: false
                    }));
                }

                // Load schedule
                if (result.schedule) {
                    this.scheduleStartDate = result.schedule.startDate || '';
                    this.scheduleReviewDate = result.schedule.reviewDate || '';
                    this.scheduleFrequency = result.schedule.frequency || '';
                    this.scheduleDuration = result.schedule.duration || '';
                    this.scheduleHoursPerWeek = result.schedule.hoursPerWeek || '';
                }

                // Load Client Impact Review fields
                    this.quarterlyGoalStatus = result.clientImpact?.quarterlyGoalStatus || '';
                    this.clientStability = result.clientImpact?.clientStability || '';
                    this.outcomeSummary = result.clientImpact?.outcomeSummary || '';
                    this.planAdjustment = result.clientImpact?.planAdjustment || '';

                this.isDataLoaded = true;
                // If clone mode, strip all Salesforce IDs so save creates new records
if (this.isCloneMode) {
    console.log('Clone mode - stripping IDs for new record creation');
    
    // Generate new title
    getNextCarePlanTitle({ accountId: this.accountId })
        .then(title => {
            this.carePlanTitlePrefix = title;
            this.carePlanTitleSuffix = '';  // Clear suffix for clone
            this.carePlanTitle = title;
            console.log('Clone - new title:', this.carePlanTitle);
        })
        .catch(err => {
            console.error('Error generating clone title:', err);
        });

    // Strip IDs from problems
    this.problemBlocks = this.problemBlocks.map(p => ({
        ...p,
        id: 'temp-' + Date.now() + '-' + Math.random()
    }));

    // Strip IDs from long term goals
    this.longTermGoalBlocks = this.longTermGoalBlocks.map(g => ({
        ...g,
        id: 'temp-' + Date.now() + '-' + Math.random()
    }));

    // Strip IDs from quarterly goals and their interventions
    this.quarterlyGoalBlocks = this.quarterlyGoalBlocks.map(g => ({
        ...g,
        id: 'temp-' + Date.now() + '-' + Math.random(),
        interventions: (g.interventions || []).map(i => ({
            ...i,
            id: 'temp-' + Date.now() + '-' + Math.random()
        }))
    }));

    // Strip IDs from stakeholders and mark as new
    this.stakeholderBlocks = this.stakeholderBlocks.map(s => ({
        ...s,
        id: 'temp-' + Date.now() + '-' + Math.random(),
        isNew: true
    }));
}
                console.log('Care Plan loaded successfully');
            console.log('loadCarePlan interventions:', this.quarterlyGoalBlocks.map(qg => qg.interventions));

            })
            .catch(error => {
                console.error('Error loading care plan:', error);
                this.showToast('Error', 'Failed to load Care Plan data', 'error');
            });
    }

    /* ================= OPTIONS ================= */
    get availableProblemOptions() {
        //const used = this.problemBlocks.flatMap(b => b.selectedIds || []);
        return this.problems.map(p => ({ ...p }));
    }

    get availableLongTermGoalOptions() {
        //const used = this.longTermGoalBlocks.flatMap(b => b.selectedIds || []);
        return this.longTermGoals.map(g => ({ ...g }));
    }

    get availableQuarterlyGoalOptions() {
        //const used = this.quarterlyGoalBlocks.flatMap(b => b.selectedIds || []);
        return this.quarterlyGoals.map(g => ({ ...g }));
    }

    get availableInterventionOptions() {
       
        return this.quarterlyGoals
            .flatMap(g => g.tasks)
            .map(t => ({ ...t }));
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

get filteredAvailableLongTermGoalOptions() {
    const base = this.availableLongTermGoalOptions || [];
    const term = this.longTermGoalSearchKey;
    //const availableOnly = base.filter(opt => !opt.disabled);

    if (!term) return base;

    return base.filter(opt =>
        (opt.label || '').toLowerCase().includes(term)
    );
}

get showLongTermTemplateSearch() {
    return this.longTermGoalBlocks.some(
        b => !b.isCustom && !b.isSelected
    );
}

get filteredAvailableQuarterlyGoalOptions() {
    const base = this.availableQuarterlyGoalOptions || [];
    const term = this.quarterlyGoalSearchKey;
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


    //These are helper methods for spinner for every button.
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
        this.problemBlocks = [ {
            //id: null, 
            id: 'temp-' + Date.now() + '-' + Math.random(),
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
        this.longTermGoalBlocks = [ {
            id: 'temp-' + Date.now() + '-' + Math.random(),
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
        this.quarterlyGoalBlocks = [
            
            {
                id: 'temp-' + Date.now() + '-' + Math.random(),
                selectedIds: [],
                interventions: [],
                isSelected: false,
                selectedName: '',
                category: '',
                description: '',
                successCriteria: ''
            },...this.quarterlyGoalBlocks
        ];
            console.log('addQuarterlyGoal interventions:', this.quarterlyGoalBlocks.map(qg => qg.interventions));

    });
}

   addIntervention(event) {
    this.runAddAction(() => {
    const goalId = event.currentTarget.dataset.id;

    // Build new copy of quarterlyGoalBlocks, deep-copied
    this.quarterlyGoalBlocks = this.quarterlyGoalBlocks.map(g => {
        if (g.id !== goalId) return {...g, interventions: (g.interventions || []).map(i => ({ ...i }))};
        // Create new interventions array with added intervention
        const oldInterventions = g.interventions || [];
        const newInterventions = [
             // clone existing
            {
                id: 'temp-' + Date.now() + '-' + Math.random(),
                selectedIds: [],
                isSelected: false,
                selectedName: '',
                category: '',
                specificIntervention: '',
                frequency: '',
                duration: '',
                details: ''
            },...oldInterventions.map(i => ({ ...i }))
        ];
        return {...g,interventions: newInterventions};
    });
});
   }

    addStakeholder() {
        this.runAddAction(() => {
        this.stakeholderBlocks = [ {
            id: 'temp-' + Date.now() + '-' + Math.random(),  // ✅ Generate temp ID for event handlers
            isNew: true,
            stakeholderType: '',
            //contactName: '',
            //userId: null,
            contactId: null,
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
    this.quarterlyGoalBlocks = this.quarterlyGoalBlocks.map(g => {
        if (g.id !== goalId) return {...g, interventions: (g.interventions || []).map(i => ({ ...i }))};
        // clone interventions array, filter out the deleted one
        return {
            ...g,
            interventions: (g.interventions || []).filter(i => i.id !== intvId).map(i => ({ ...i })) // clone remaining
        };
    });
}

    deleteStakeholder(event) {
        const id = event.currentTarget.dataset.id;
        this.stakeholderBlocks = this.stakeholderBlocks.filter(b => b.id !== id);
    }

   


normalize(v = '') {
    return String(v).trim().toLowerCase();
}
getTemplateIdByName(name, options = []) {
    const key = this.normalize(name);
    if (!key) return null;
    const match = options.find(o => this.normalize(o.label) === key);
    return match ? match.value : null;
}


isDuplicateTemplateProblem(selectedProblemId, currentBlockId) {
    if (!selectedProblemId) return false;

    console.log('=== DUPLICATE CHECK ===');
    console.log('Checking for:', selectedProblemId);
    console.log('Current block ID:', currentBlockId);
    console.log('All problem blocks:', JSON.stringify(this.problemBlocks.map(b => ({
        id: b.id,
        isCustom: b.isCustom,
        selectedIds: b.selectedIds,
        selectedName: b.selectedName
    }))));

    const count = this.problemBlocks.filter(b =>
        b.id !== currentBlockId &&
        !b.isCustom &&
        Array.isArray(b.selectedIds) &&
        b.selectedIds.includes(selectedProblemId)
    ).length;

    console.log('Duplicate count:', count);
    return count > 0;
}


isDuplicateTemplateLongTermGoal(selectedGoalId, currentBlockId) {
    if (!selectedGoalId) return false;
    return this.longTermGoalBlocks.some(b =>
        b.id !== currentBlockId &&
        !b.isCustom &&
        Array.isArray(b.selectedIds) &&
        b.selectedIds.includes(selectedGoalId)
    );
}

isDuplicateTemplateQuarterlyGoal(selectedGoalId, currentBlockId) {
    if (!selectedGoalId) return false;
    return this.quarterlyGoalBlocks.some(b =>
        b.id !== currentBlockId &&
        !b.isCustom &&
        Array.isArray(b.selectedIds) &&
        b.selectedIds.includes(selectedGoalId)
    );
}

isDuplicateTemplateIntervention(selectedTaskId, goalId, intvId) {
    if (!selectedTaskId) return false;
    const goal = this.quarterlyGoalBlocks.find(g => g.id === goalId);
    if (!goal || !Array.isArray(goal.interventions)) return false;
    return goal.interventions.some(i =>
        i.id !== intvId &&
        !i.isCustom &&
        Array.isArray(i.selectedIds) &&
        i.selectedIds.includes(selectedTaskId)
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

    block.category = block.category || '';
    block.successCriteria = block.successCriteria || '';
    block.description = block.description || '';
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
        const selectedGoal = this.quarterlyGoals.find(g => g.value === block.selectedIds[0]);
        block.selectedName = selectedGoal ? selectedGoal.label : '';
    } else {
        block.selectedName = '';
    }
    // Initialize fields (matching long-term goal handler)
    block.category = block.category || '';
    block.successCriteria = block.successCriteria || '';
    block.description = block.description || '';

    this.quarterlyGoalBlocks = [...this.quarterlyGoalBlocks];
}



   

handleInterventionChange(e) {
    const goalId = e.target.dataset.goal;
    const intvId = e.target.dataset.id;
    const selectedIds = e.detail.value || [];
    const selectedTaskId = selectedIds[0];

    if (this.isDuplicateTemplateIntervention(selectedTaskId, goalId, intvId)) {
        this.showToast(
            'Validation Error',
            'The same template intervention cannot be added multiple times to a single Care Plan.',
            'error'
        );
        this.updateIntervention(goalId, intvId, { selectedIds: [], isSelected: false, selectedName: '' });
        return;
    }

    const isSelected = selectedIds.length > 0;
    let selectedName = '';
    if (isSelected) {
        const selectedTask = this.quarterlyGoals.flatMap(g => g.tasks).find(t => t.value === selectedTaskId);
        selectedName = selectedTask ? selectedTask.label : '';
    }

    this.updateIntervention(goalId, intvId, { selectedIds, isSelected, selectedName });
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

   // Use this helper for every intervention field update:
updateIntervention(goalId, intvId, updates) {
    this.quarterlyGoalBlocks = this.quarterlyGoalBlocks.map(g => {
        if (g.id !== goalId) return {...g, interventions: (g.interventions || []).map(i => ({ ...i }))};
        return {
            ...g,
            interventions: (g.interventions || []).map(i =>
                i.id === intvId ? { ...i, ...updates } : { ...i }
            )
        };
    });
}

handleInterventionCategory(e) {
    const goalId = e.target.dataset.goal;
    const intvId = e.target.dataset.id;
    this.updateIntervention(goalId, intvId, { category: e.detail.value });
}
handleInterventionSpecific(e) {
    const goalId = e.target.dataset.goal;
    const intvId = e.target.dataset.id;
    this.updateIntervention(goalId, intvId, { specificIntervention: e.detail.value });
}
handleInterventionFrequency(e) {
    const goalId = e.target.dataset.goal;
    const intvId = e.target.dataset.id;
    this.updateIntervention(goalId, intvId, { frequency: e.detail.value });
}
handleInterventionDuration(e) {
    const goalId = e.target.dataset.goal;
    const intvId = e.target.dataset.id;
    this.updateIntervention(goalId, intvId, { duration: e.detail.value });
}
handleInterventionDetails(e) {
    const goalId = e.target.dataset.goal;
    const intvId = e.target.dataset.id;
    this.updateIntervention(goalId, intvId, { details: e.detail.value });
}
    /* ================= STAKEHOLDER FIELD HANDLERS ================= */
    handleStakeholderType(e) {
        const block = this.stakeholderBlocks.find(b => b.id === e.target.dataset.id);
        block.stakeholderType = e.detail.value;
        console.log('Stakeholder Type updated:', block.stakeholderType);
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
        console.log('Role in Care updated:', block.roleInCare);
        this.stakeholderBlocks = [...this.stakeholderBlocks];
    }

    handleStakeholderCommPref(e) {
        const block = this.stakeholderBlocks.find(b => b.id === e.target.dataset.id);
        block.communicationPreference = e.detail.value;
        console.log('Communication Preference updated:', block.communicationPreference);
        this.stakeholderBlocks = [...this.stakeholderBlocks];
    }

    handleStakeholderCommFreq(e) {
        const block = this.stakeholderBlocks.find(b => b.id === e.target.dataset.id);
        block.communicationFrequency = e.detail.value;
        console.log('Communication Frequency updated:', block.communicationFrequency);
        this.stakeholderBlocks = [...this.stakeholderBlocks];
    }
//This helper method is used to validate the start date and review date
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



    /* ================= SCHEDULE FIELD HANDLERS ================= */
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


    /* ================= ACTION HANDLERS ================= */
//     async handleCancel() {
//     try {
//         // ⭐ Get current tab info
//         const tabInfo = await getFocusedTabInfo();

//         // ⭐ Navigate to Account record page
//         this[NavigationMixin.Navigate]({
//             type: 'standard__recordPage',
//             attributes: {
//                 recordId: this.accountId,
//                 objectApiName: 'Account',
//                 actionName: 'view'
//             }
//         });

//         // ⭐ Close the Care Plan subtab
//         if (tabInfo?.isSubtab && tabInfo?.tabId) {
//             setTimeout(async () => {
//                 try {
//                     await closeTab(tabInfo.tabId);
//                 } catch (error) {
//                     console.error('Error closing tab:', error);
//                 }
//             }, 500);
//         }
//         else {
   
//              this.dispatchEvent(new RefreshEvent());
//         }
//     } catch (error) {
//         console.error('Cancel navigation error:', error);
//     }
// }

//bhanu changes add for cancel

    

    async handleCancel() {
        try {
            let tabInfo;

            try {
                tabInfo = await getFocusedTabInfo();
            } catch (e) {
                
                tabInfo = null;
            }

            const isSubtab = tabInfo?.isSubtab;
            const tabId = tabInfo?.tabId;

            if (isSubtab && tabId) {
                
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.accountId,
                        objectApiName: 'Account',
                        actionName: 'view'
                    }
                });

                setTimeout(async () => {
                    try {
                        await closeTab(tabId);
                    } catch (error) {
                        console.error('Error closing tab:', error);
                    }
                }, 300);

            } else {
                
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.accountId,
                        objectApiName: 'Account',
                        actionName: 'view'
                    }
                }, true); 
            }

        } catch (error) {
            console.error('Cancel navigation error:', error);
        }
    }

// changes end for cancel


  

          /* ================= PREVIEW PDF ================= */
handlePreviewPDF() {
    // Collect all care plan data
    const carePlanData = {
        problems: this.problemBlocks.filter(p => p.isSelected),
        longTermGoals: this.longTermGoalBlocks.filter(g => g.isSelected),
        quarterlyGoals: this.quarterlyGoalBlocks.filter(g => g.isSelected).map(qg => ({
            ...qg,
            interventions: (qg.interventions || []).filter(i => i.isSelected)
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

hasDuplicateTemplateProblems() {
    const seen = new Set();
    for (const b of this.problemBlocks) {
        if (b.isCustom) continue;
        const id = b.selectedIds?.[0];
        if (!id) continue;
        if (seen.has(id)) return true;
        seen.add(id);
    }
    return false;
}



//save method
    async handleSave() {
    this.isLoading = true;

    // Validate required fields
    const selectedProblems = this.problemBlocks.filter(p => p.isSelected);
    const hasProblems = selectedProblems.length > 0;

    if (!hasProblems) {
        this.showToast('Validation Error', 'Please add at least one problem', 'error');
        this.isLoading = false;
        return;
    }

    // NEW: Validate that all problems have severity
    const problemsWithoutSeverity = selectedProblems.filter(p => !p.severity || p.severity.trim() === '');
    if (problemsWithoutSeverity.length > 0) {
        this.showToast('Validation Error', 'Please select Severity for all problems', 'error');
        this.isLoading = false;
        return;
    }

    if (!this.validateScheduleDateRange(true)) {
    this.isLoading = false;
    return;
    }


    const carePlanData = {
        problems: this.problemBlocks.filter(p => p.isSelected).map(p => ({
            ...p,
            isCustom: p.isCustom || false
    })),
        longTermGoals: this.longTermGoalBlocks.filter(g => g.isSelected).map(g => ({
            ...g,
            isCustom: g.isCustom || false
        })),
        quarterlyGoals: this.quarterlyGoalBlocks.filter(g => g.isSelected).map(qg => ({
            ...qg,
            isCustom: qg.isCustom || false,
            
            interventions: (qg.interventions || []).filter(i => {
    // Keep existing Salesforce records (any valid 15 or 18 char ID that's not temp)
    const isExistingRecord = i.id && 
                            (i.id.length === 18 || i.id.length === 15) && 
                            !i.id.startsWith('temp-');
    
    // Keep new records that are properly filled out
    const isNewValidRecord = (!i.id || i.id.startsWith('temp-')) &&
                            i.isSelected &&
                            i.selectedName && 
                            i.selectedName.trim() !== '';
    
    return isExistingRecord || isNewValidRecord;
}).map(i => ({
                id: i.id,
                isCustom: i.isCustom || false,
                selectedIds: i.selectedIds,
                selectedName: i.selectedName,
                frequency: i.frequency,
                duration: i.duration,
                details: i.details
            }))
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

    if (this.hasDuplicateTemplateProblems()) {
    this.showToast('Validation Error', 'You cannot select the same template problem twice in this care plan.', 'error');
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






    // ⭐ Get tab info BEFORE any navigation
        const tabInfo = await getFocusedTabInfo();
        console.log('Tab Info:', JSON.stringify(tabInfo));
 
    saveCarePlan({
        carePlanDataJson: JSON.stringify(carePlanData),
        accountId: this.accountId,
        accountName: this.carePlanTitlePrefix,
        carePlanSuffix: this.carePlanTitleSuffix || '',
        //accountName: this.fullCarePlanTitle,
        //accountName: this.carePlanTitle,
        carePlanId: this.isCloneMode ? null :this.recordId
    })
        .then(result => {
            this.isLoading = false;
            if (result.success) {
                //this.showToast('Success', 'Care Plan updated successfully', 'success');
                this.showToast('Success', this.isCloneMode ? 'Care Plan cloned successfully' : 'Care Plan updated successfully', 'success');
                this.loadCarePlan();
                this.dispatchEvent(new CustomEvent('close'));
                // ⭐ Simply navigate to Account record page
                this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.accountId,
                    objectApiName: 'Account',
                    actionName: 'view'
                }
            });

            // Step 2: Publish LMS message after delay so carePlanList is mounted
        setTimeout(() => {
            try {
                const payload = {
                    refreshList: true,
                    accountId: this.accountId
                };
                console.log('Publishing LMS after edit save:', payload);
                publish(this.messageContext, CARE_PLAN_REFRESH_CHANNEL, payload);
                console.log('MESSAGE PUBLISHED SUCCESSFULLY FROM EDIT');
            } catch (publishError) {
                console.error('PUBLISH ERROR:', publishError);
            }
            
            // Step 3: Close the subtab AFTER publishing
            if (tabInfo?.isSubtab && tabInfo?.tabId) {
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
        }, 2000);
            } else {
                this.showToast('Error', result.message, 'error');
            }
        })
        .catch(err => {
            this.isLoading = false;
            console.error('Error saving:', err);
            this.showToast('Error', err.body?.message || 'Failed to save Care Plan', 'error');
        });
}

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}