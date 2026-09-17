import { LightningElement, track, api } from 'lwc';
import getVitalData from '@salesforce/apex/VitalBoardController.getVitalData';
import saveObservation from '@salesforce/apex/VitalBoardController.saveObservation';
import { NavigationMixin } from 'lightning/navigation';
import { registerRefreshHandler, unregisterRefreshHandler, RefreshEvent } from 'lightning/refresh';
import updateObservation from '@salesforce/apex/VitalBoardController.updateObservation';
import deleteObservation from '@salesforce/apex/VitalBoardController.deleteObservation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';

const PAGE_SIZE      = 10;
const LIST_PAGE_SIZE = 20;
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

const VITAL_CONFIG = {
    'Blood Glucose': {
        label: 'Blood Glucose', unit: 'mg/dL', inputType: 'number',
        placeholder: 'e.g. 90 mg/dL', helpText: 'Normal fasting: 70 – 100 mg/dL', min: 0, max: 1000
    },
    'Blood Pressure': {
        label: 'Blood Pressure', unit: 'mmHg', inputType: 'text',
        placeholder: 'e.g. 120/80 mmHg', helpText: 'Format: Systolic/Diastolic mmHg'
    },
    'Body Temperature': {
        label: 'Body Temperature', unit: '°F', inputType: 'number',
        placeholder: 'e.g. 98.6 °F', helpText: 'Normal: 97.0 – 99.0 °F', min: 86, max: 113
    },
    'Edema': {
        label: 'Edema', unit: 'Grade', inputType: 'picklist',
        helpText: 'Select severity level',
        options: ['0','1+','2+','3+','4+','5+','6+','7+','8+','9+','10+']
    },
    'Heart Rate': {
        label: 'Heart Rate', unit: 'bpm', inputType: 'number',
        placeholder: 'e.g. 72 bpm', helpText: 'Normal: 60 – 100 bpm', min: 30, max: 250
    },
    'Leg Circumference - Left': {
        label: 'Leg Circumference - Left', unit: 'cm', inputType: 'number',
        placeholder: 'e.g. 45 cm', helpText: 'Measure in centimeters', min: 0, max: 200
    },
    'Leg Circumference - Right': {
        label: 'Leg Circumference - Right', unit: 'cm', inputType: 'number',
        placeholder: 'e.g. 35 cm', helpText: 'Measure in centimeters', min: 0, max: 200
    },
    'Oxygen Saturation (SpO₂)': {
        label: 'Oxygen Saturation (SpO₂)', unit: '%', inputType: 'number',
        placeholder: 'e.g. 98 %', helpText: 'Normal: 95 – 100%', min: 0, max: 100
    },
    'Pain Score': {
        label: 'Pain Score', unit: 'Score', inputType: 'picklist',
        helpText: '0 = No pain, 10 = Worst pain',
        options: ['0','1','2','3','4','5','6','7','8','9','10']
    },
    'Respiratory Rate': {
        label: 'Respiratory Rate', unit: 'br/min', inputType: 'number',
        placeholder: 'e.g. 16 br/min', helpText: 'Normal: 12 – 20 br/min', min: 5, max: 60
    },
    // FIX: Added separate Water Intake and Bolus Intake to match picklist API names
    // 'Water and Bolus Intake': {
    //     label: 'Water and Bolus Intake', unit: 'ml', inputType: 'number',
    //     placeholder: 'e.g. 250 ml', helpText: 'Enter amount in milliliters', min: 0, max: 5000
    // },
    'Water Intake': {
        label: 'Water Intake', unit: 'ml', inputType: 'number',
        placeholder: 'e.g. 250 ml', helpText: 'Enter amount in milliliters', min: 0, max: 5000
    },
    'Bolus Intake': {
        label: 'Bolus Intake', unit: 'ml', inputType: 'number',
        placeholder: 'e.g. 250 ml', helpText: 'Enter amount in milliliters', min: 0, max: 5000
    },
    'Bowel Movements': {
        label: 'Bowel Movements', unit: '', inputType: 'number',
        placeholder: 'e.g. 2', helpText: 'Enter number of bowel movements', min: 0, max: 50
    },
    'Weight': {
        label: 'Weight', unit: 'lbs', inputType: 'number',
        placeholder: 'e.g. 150 lbs', helpText: 'Enter weight in pounds', min: 0, max: 1000
    }
};

// FIX: Helper — given a raw "value + unit" string from Apex and a VITAL_CONFIG entry,
// returns just the bare value so modal inputs display correctly.
function stripUnit(rawValue, cfg) {
    if (!rawValue || rawValue === '—') return '';

    // Picklist: find the option that is a prefix of the stored string
    // e.g. "1+ Grade" → match option "1+"
    if (cfg && cfg.inputType === 'picklist' && Array.isArray(cfg.options)) {
        // Exact match first
        if (cfg.options.includes(rawValue)) return rawValue;
        // Option followed by a space then anything (the unit suffix)
        const match = cfg.options.find(opt => rawValue.startsWith(opt + ' '));
        if (match !== undefined) return match;
        // Fallback: return as-is (unknown format)
        return rawValue;
    }

    



    // Number / text: strip known unit suffix from config
    if (cfg && cfg.unit) {
        const suffix = ' ' + cfg.unit;
        if (rawValue.endsWith(suffix)) {
            return rawValue.slice(0, -suffix.length).trim();
        }
    }

    // Fallback: strip any trailing non-numeric word
    // e.g. "120/50 mg/dL" → "120/50"  |  "98 bpm" → "98"
    const lastSpaceIdx = rawValue.lastIndexOf(' ');
    if (lastSpaceIdx !== -1) {
        const potentialUnit  = rawValue.substring(lastSpaceIdx + 1);
        const potentialValue = rawValue.substring(0, lastSpaceIdx).trim();
        // Unit-like: contains at least one letter and no spaces
        if (potentialValue && /[a-zA-Z%°]/.test(potentialUnit) && !/\s/.test(potentialUnit)) {
            return potentialValue;
        }
    }

    return rawValue;
}
function utcStringToDate(isoStr) {
        if (!isoStr) return null;
        const hasOffset = isoStr.endsWith('Z') || /[+-]\d{2}:\d{2}$/.test(isoStr);
        return new Date(hasOffset ? isoStr : isoStr + 'Z');
    }

    function formatDisplayTime(isoStr) {
    if (!isoStr) return '';

    const d = utcStringToDate(isoStr);
    if (!d || isNaN(d)) return '';

    return d.toLocaleTimeString('en-US', {
        timeZone: 'America/Chicago',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true
    });
}

    function formatDisplayDate(isoStr) {
    if (!isoStr) return '';

    const d = utcStringToDate(isoStr);
    if (!d || isNaN(d)) return '';

    return d.toLocaleDateString('en-US', {
        timeZone: 'America/Chicago',
        day: '2-digit',
        month: 'short',
        year: 'numeric'
    });
}

    function utcIsoToLocalInputValue(isoStr) {
        if (!isoStr) return '';
        const d = utcStringToDate(isoStr);
        if (!d || isNaN(d)) return '';
        const pad = n => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

export default class VitalBoard extends NavigationMixin(LightningElement) {

    // ─── view state ───────────────────────────────────────────────────────────
    @track currentView      = 'list';
    @track isViewMenuOpen   = false;

    // ─── edit mode state ──────────────────────────────────────────────────────
    @track isEditMode    = false;
    @track editingRecordId = '';

    get isListView()     { return this.currentView === 'list'; }
    get isCalendarView() { return this.currentView === 'calendar'; }

    get currentViewIcon() {
        return this.isListView ? 'utility:list' : 'utility:date_input';
    }

    get listViewOptionClass() {
        return this.isListView ? 'view-option view-option-active' : 'view-option';
    }
    get calendarViewOptionClass() {
        return this.isCalendarView ? 'view-option view-option-active' : 'view-option';
    }

    toggleViewMenu()     { this.isViewMenuOpen = !this.isViewMenuOpen; }
    selectListView()     { this.currentView = 'list';     this.isViewMenuOpen = false; }
    selectCalendarView() { this.currentView = 'calendar'; this.isViewMenuOpen = false; }

    // ─── data ─────────────────────────────────────────────────────────────────
    @track tableData      = [];
    @track allDates       = [];
    @track patientOptions = [];
    @track isLoading      = false;

    // ─── modal ────────────────────────────────────────────────────────────────
    @track isModalOpen   = false;
    @track modalCategory = '';
    @track modalValue    = '';
    @track modalDateTime = '';
    @track modalError    = '';
    @track isSaving      = false;
    modalDateTimeOffset  = '';

    // ─── applied filters ──────────────────────────────────────────────────────
    appliedPatientId  = '';
    appliedQuickRange = '';
    appliedCategory   = '';
    appliedFromDate   = null;
    appliedToDate     = null;

    // ─── pending (UI) filters ─────────────────────────────────────────────────
    @track pendingPatientId  = '';
    @track pendingQuickRange = '';
    @track pendingCategory   = '';
    @track pendingFromDate   = null;
    @track pendingToDate     = null;

    // ─── pagination ───────────────────────────────────────────────────────────
    currentPage     = 0;
    listCurrentPage = 0;

    _isConnected      = false;
    _recordId         = '';
    _refreshHandlerID = null;

    // ─── recordId ─────────────────────────────────────────────────────────────
    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        const normalizedRecordId = value || '';
        const hasChanged = normalizedRecordId !== this._recordId;
        this._recordId = normalizedRecordId;
        if (!hasChanged) return;
        const defaultPatient = this.isRecordPageContext ? this._recordId : '';
        this.appliedPatientId = defaultPatient;
        this.pendingPatientId = defaultPatient;
        if (this._isConnected) { this.currentPage = 0; this.loadData(); }
    }

    connectedCallback() {
        this._isConnected = true;
        const defaultPatient = this.isRecordPageContext ? this.recordId : '';
        this.appliedPatientId = defaultPatient;
        this.pendingPatientId = defaultPatient;
        this._refreshHandlerID = registerRefreshHandler(this, this.handleRefresh.bind(this));
        this.loadData();
    }

    disconnectedCallback() {
        if (this._refreshHandlerID) unregisterRefreshHandler(this._refreshHandlerID);
    }

    get isRecordPageContext() { return !!this._recordId; }

    // ─── pending filter getters ───────────────────────────────────────────────
    get selectedPatientId()  { return this.pendingPatientId; }
    get selectedQuickRange() { return this.pendingQuickRange; }
    get selectedCategory()   { return this.pendingCategory; }
    get fromDate()           { return this.pendingFromDate; }
    get toDate()             { return this.pendingToDate; }

    // ─── modal config ─────────────────────────────────────────────────────────
    get modalCategoryOptions() {
        return Object.keys(VITAL_CONFIG)
            .sort((a, b) => a.localeCompare(b))
            .map(k => ({ label: VITAL_CONFIG[k].label, value: k }));
    }
    get activeConfig()        { return this.modalCategory ? VITAL_CONFIG[this.modalCategory] || {} : {}; }
    get isNumberInput()       { return this.activeConfig.inputType === 'number'; }
    get isTextInput()         { return this.activeConfig.inputType === 'text'; }
    get isPicklistInput()     { return this.activeConfig.inputType === 'picklist'; }
    get activePicklistOptions() {
        if (!this.activeConfig.options) return [];
        return this.activeConfig.options.map(o => ({ label: o, value: o }));
    }

    get modalTitle() {
        return this.isEditMode ? 'Edit Care Observation' : 'New Care Observation';
    }

    // ─── modal open / close ───────────────────────────────────────────────────
    openModal() {
        const now = new Date();
        const pad = n => String(n).padStart(2, '0');
        const tzOffset = -now.getTimezoneOffset();
        const sign = tzOffset >= 0 ? '+' : '-';
        const absOffset = Math.abs(tzOffset);
        const offsetStr = `${sign}${pad(Math.floor(absOffset / 60))}:${pad(absOffset % 60)}`;
        this.modalDateTimeOffset = offsetStr;
        this.modalDateTime = `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
        this.modalCategory   = '';
        this.modalValue      = '';
        this.modalError      = '';
        this.isSaving        = false;
        this.isEditMode      = false;
        this.editingRecordId = '';
        this.isModalOpen     = true;
    }

    closeModal() { this.isModalOpen = false; }

    // ─── modal field handlers ─────────────────────────────────────────────────
    handleModalDateTime(event) {
        const inputField = event.target;
        this.modalDateTime = inputField.value;
        if (!this.modalDateTime) {
            inputField.setCustomValidity('Please select an effective date and time.');
            inputField.reportValidity();
            return;
        }
        // const now = new Date();
        // const pad = n => String(n).padStart(2, '0');
        // const nowStr = `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
        // if (this.modalDateTime > nowStr) {
        //     inputField.setCustomValidity('Effective Date & Time cannot be in the future.');
        // } else {
        //     inputField.setCustomValidity('');
        // }
        // inputField.reportValidity();
        const selectedDate = new Date(this.modalDateTime);
        const currentDate = new Date();

        if (selectedDate > currentDate) {
            inputField.setCustomValidity(
                'Effective Date & Time cannot be in the future.'
            );
        } else {
            inputField.setCustomValidity('');
        }

        inputField.reportValidity();
    }

    // FIX: Only clear modalValue when the user actively changes the category,
    // not during the initial programmatic set in handleEdit.
    handleModalCategory(e) {
        const newCat = e.detail.value;
        if (newCat !== this.modalCategory) {
            // User genuinely changed the category — reset value
            this.modalValue = '';
        }
        this.modalCategory = newCat;
        this.modalError    = '';
    }

    handleModalValue(event) {
        const inputField = event.target;
        const value = event.target.value ? String(event.target.value).trim() : '';
        this.modalValue = value;
        inputField.setCustomValidity('');

        if (this.modalCategory === 'Blood Pressure') {
            const bpRegex = /^\d{2,3}\/\d{2,3}$/;
            if (!value) {
                inputField.setCustomValidity('Please enter a blood pressure value.');
            } else if (value.includes('-')) {
                inputField.setCustomValidity('Blood pressure values cannot be negative.');
            } else if (!bpRegex.test(value)) {
                inputField.setCustomValidity('Enter blood pressure in the format Systolic/Diastolic (e.g., 120/80).');
            } else {
                const [systolic, diastolic] = value.split('/').map(Number);
                if (systolic <= 0 || diastolic <= 0) {
                    inputField.setCustomValidity('Blood pressure values must be positive numbers.');
                } else if (systolic < 50 || systolic > 250) {
                    inputField.setCustomValidity('Systolic value must be between 50 and 250 mmHg.');
                } else if (diastolic < 30 || diastolic > 150) {
                    inputField.setCustomValidity('Diastolic value must be between 30 and 150 mmHg.');
                } else if (systolic <= diastolic) {
                    inputField.setCustomValidity('Systolic value must be greater than diastolic value.');
                }
            }
        }
        inputField.reportValidity();
    }

    // FIX: Robust edit handler using the stripUnit helper
    handleEdit(event) {
        const record = event.currentTarget.dataset;

        this.isEditMode      = true;
        this.editingRecordId = record.id;
        this.modalError      = '';
        this.isSaving        = false;

        // Parse ISO datetime directly — avoid new Date() timezone shift
        //const parts    = (record.datetime || '').split('T');
        //const datePart = parts[0] || '';
        //const timePart = parts.length > 1 ? parts[1].substring(0, 5) : '00:00';
        //this.modalDateTime = datePart ? `${datePart}T${timePart}` : '';
        this.modalDateTime = utcIsoToLocalInputValue(record.datetime || '');
        // FIX: Use stripUnit helper to handle all unit-stripping cases robustly,
        // including picklist values (Edema "1+ Grade" → "1+", Pain Score "5 Score" → "5")
        const cfg    = VITAL_CONFIG[record.vital] || {};
        const rawVal = stripUnit(record.value || '', cfg);

        // FIX: Set value BEFORE category.
        // handleModalCategory only clears value when newCat !== this.modalCategory,
        // so we pre-set modalCategory to the same value first to prevent the clear.
        this.modalCategory = record.vital;   // set first so handleModalCategory sees no change
        this.modalValue    = rawVal;         // then set value — category combobox already matches

        this.isModalOpen = true;
    }

    async handleDelete(event) {
        const recordId = event.currentTarget.dataset.id;

        const confirmed = await LightningConfirm.open({
            message: 'Are you sure you want to delete this record?',
            label: 'Confirm Deletion',
            theme: 'warning'
        });

        if (!confirmed) return;

        deleteObservation({ observationId: recordId })
            .then(() => {
                this.showToast('Success', 'Record deleted successfully', 'success');
                this.loadData();
            })
            .catch(err => {
                this.showToast('Error', err.body?.message || 'Delete failed', 'error');
            });
    }

    handleBpKeyPress(event) {
        const char = String.fromCharCode(event.which);
        if (!/[0-9/]/.test(char)) event.preventDefault();
    }

    validateModalInputs() {
        const inputs = this.template.querySelectorAll(
            '.modal-content lightning-input, .modal-content lightning-combobox'
        );
        let isValid = true;
        inputs.forEach(input => {
            if (!input.checkValidity()) { input.reportValidity(); isValid = false; }
        });
        return isValid;
    }

    handleSave() {
        this.modalError = '';
        if (!this.validateModalInputs()) {
            this.showToast('Error', 'Please fix the highlighted errors before saving.', 'error');
            return;
        }
        if (!this.modalDateTime) {
            this.showToast('Error', 'Please select an effective date and time.', 'error');
            return;
        }
        const now = new Date();
        const pad = n => String(n).padStart(2, '0');
        const nowStr = `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
        if (this.modalDateTime > nowStr) {
            this.showToast('Error', 'Effective Date & Time cannot be in the future.', 'error');
            return;
        }
        if (!this.modalCategory) {
            this.showToast('Error', 'Please select a category.', 'error');
            return;
        }
        if (!this.modalValue && this.modalValue !== 0) {
            this.showToast('Error', 'Please enter a value.', 'error');
            return;
        }
        const cfg = this.activeConfig;
        if (cfg.inputType === 'number') {
            const num = parseFloat(this.modalValue);
            if (isNaN(num)) { this.showToast('Error', 'Please enter a valid number.', 'error'); return; }
            if (cfg.min !== undefined && num < cfg.min) { this.showToast('Error', `Value must be at least ${cfg.min}.`, 'error'); return; }
            if (cfg.max !== undefined && num > cfg.max) { this.showToast('Error', `Value must be at most ${cfg.max}.`, 'error'); return; }
        }
        const patientId = this.selectedPatientId || this.recordId;
        if (!patientId) { this.showToast('Error', 'No patient selected.', 'error'); return; }

        this.isSaving = true;
        const effectiveDateTime = new Date(this.modalDateTime).toISOString();
        let finalValue = String(this.modalValue || '').trim();

        // Remove ALL possible known units first
        const allUnits = Object.values(VITAL_CONFIG)
            .map(v => v.unit)
            .filter(Boolean);

        allUnits.forEach(unit => {
            const suffix = ` ${unit}`;

            if (finalValue.endsWith(suffix)) {
                finalValue = finalValue.slice(0, -suffix.length).trim();
            }
        });

        // Append only current category unit
        if (cfg.unit) {
            finalValue = `${finalValue} ${cfg.unit}`.trim();
        }

        const action = this.isEditMode
            ? updateObservation({
                observationId    : this.editingRecordId,
                category         : this.modalCategory,
                value            : finalValue,
                effectiveDateTime
            })
            : saveObservation({
                patientId,
                category         : this.modalCategory,
                value            : finalValue,
                effectiveDateTime
            });

        action
            .then(() => {
                this.isModalOpen     = false;
                this.isEditMode      = false;
                this.editingRecordId = '';
                this.showToast('Success', 'Care Observation saved successfully.', 'success');
                this.dispatchEvent(new RefreshEvent());
                this.handleRefresh();
            })
            .catch(err => {
                console.error('vital signs error', err);
                const msg = err.body?.message || 'An error occurred while saving.';
                this.showToast('Error', msg, 'error');
                this.modalError = msg;
            })
            .finally(() => { this.isSaving = false; });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    convertToInputDateTime(dt) {
        if (!dt) return '';
        const parts    = dt.split('T');
        const datePart = parts[0] || '';
        const timePart = parts.length > 1 ? parts[1].substring(0, 5) : '00:00';
        return datePart ? `${datePart}T${timePart}` : '';
    }

    // ─── filter options ───────────────────────────────────────────────────────
    get quickRangeOptions() {
        return [
            { label: 'Today',        value: 'today'     },
            { label: 'Yesterday',    value: 'yesterday' },
            { label: 'Last 7 Days',  value: 'last7'     },
            { label: 'Last 15 Days', value: 'last15'    },
            { label: 'Last Month',   value: 'lastMonth' }
        ];
    }

    get categoryOptions() {
        const categories = new Set();
        this.tableData.forEach(p => p.vitals.forEach(v => categories.add(v.vital)));
        return [
            { label: 'All Categories', value: '' },
            ...Array.from(categories).sort().map(c => ({ label: c, value: c }))
        ];
    }

    // ─── filter handlers ──────────────────────────────────────────────────────
    handleCategoryChange(e) { this.pendingCategory = e.detail.value; }

    get isManualDateDisabled() { return !!this.selectedQuickRange; }

    handleQuickRangeChange(event) {
        this.pendingQuickRange = event.detail.value;
        let today   = new Date();
        let current = new Date(today.getFullYear(), today.getMonth(), today.getDate());
        let from, to;
        switch (this.pendingQuickRange) {
            case 'today':
                from = to = current; break;
            case 'yesterday':
                from = new Date(current); from.setDate(from.getDate() - 1); to = new Date(from); break;
            case 'last7':
                to = current; from = new Date(current); from.setDate(from.getDate() - 6); break;
            case 'last15':
                to = current; from = new Date(current); from.setDate(from.getDate() - 14); break;
            case 'lastMonth':
                from = new Date(current.getFullYear(), current.getMonth() - 1, 1);
                to   = new Date(current.getFullYear(), current.getMonth(), 0);
                break;
            default: break;
        }
        this.pendingFromDate = this.formatDateLocal(from);
        this.pendingToDate   = this.formatDateLocal(to);
    }

    formatDateLocal(d) {
        return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
    }
    parseDateLocal(str) {
        const [y, m, d] = str.split('-').map(Number);
        return new Date(y, m - 1, d);
    }

    // ─── data load ────────────────────────────────────────────────────────────
    loadData() {
        this.isLoading = true;
        const startTime = Date.now();
        getVitalData({
            patientId: this.appliedPatientId || null,
            fromDate : this.appliedFromDate  || null,
            toDate   : this.appliedToDate    || null
        })
        .then(result => { this.processData(result); })
        .catch(error => console.error(error))
        .finally(() => {
            const remaining = 2000 - (Date.now() - startTime);
            if (remaining > 0) {
                setTimeout(() => { this.isLoading = false; }, remaining);
            } else {
                this.isLoading = false;
            }
        });
    }

    processData(data) {
        let patientMap = new Map();
        let dataDateSet = new Set();

        // data.forEach(item => {
        //     Object.keys(item.values).forEach(k => dataDateSet.add(k.split('T')[0]));
        // });
        data.forEach(item => {
            Object.keys(item.values).forEach(k => {
                
                const d = utcStringToDate(k);
                if (d && !isNaN(d)) {
                    dataDateSet.add(this.formatDateLocal(d));
                } else {
                    dataDateSet.add(k.split('T')[0]);
                }
            });
        });

        let rangeStart, rangeEnd;
        if (this.appliedFromDate && this.appliedToDate) {
            rangeStart = this.parseDateLocal(this.appliedFromDate);
            rangeEnd   = this.parseDateLocal(this.appliedToDate);
        } else {
            let sorted = Array.from(dataDateSet).sort();
            if (sorted.length) {
                rangeStart = this.parseDateLocal(sorted[0]);
                rangeEnd   = this.parseDateLocal(sorted.at(-1));
            }
        }

        let fullDates = [];
        if (rangeStart && rangeEnd) {
            let cur = new Date(rangeStart);
            while (cur <= rangeEnd) {
                fullDates.push(this.formatDateLocal(cur));
                cur.setDate(cur.getDate() + 1);
            }
        }

        this.allDates    = fullDates;
        this.currentPage = 0;

        let grouped = new Map();

        data.forEach(item => {
            patientMap.set(item.patientId, item.patientName);
            let dateTimeMap = {};
            // Object.keys(item.values).forEach(k => {
            //     let datePart = k.split('T')[0];
            //     let timePart = this.extractTime(k);
            //     if (!dateTimeMap[datePart]) dateTimeMap[datePart] = [];
            //     dateTimeMap[datePart].push({ time: timePart, value: item.values[k] });
            // });
            Object.keys(item.values).forEach(k => {
                const d = utcStringToDate(k);
                const localDate = (d && !isNaN(d)) ? this.formatDateLocal(d) : k.split('T')[0];
                const localTime = (d && !isNaN(d)) ? formatDisplayTime(k) : '';
                if (!dateTimeMap[localDate]) dateTimeMap[localDate] = [];
                dateTimeMap[localDate].push({ time: localTime, value: item.values[k] });
            });

            let maxEntries = Math.max(...Object.values(dateTimeMap).map(arr => arr.length), 1);
            for (let i = 0; i < maxEntries; i++) {
                let rowKey   = `${item.patientId}-${item.vital}-${i}`;
                let valueMap = {};
                fullDates.forEach(date => {
                    let entries = dateTimeMap[date] || [];
                    if (entries[i]) {
                        valueMap[date]            = entries[i].value;
                        valueMap[`${date}__time`] = entries[i].time;
                    }
                });
                if (!grouped.has(item.patientId)) {
                    grouped.set(item.patientId, { patientId: item.patientId, patientName: item.patientName, vitals: [] });
                }
                grouped.get(item.patientId).vitals.push({
                    key        : rowKey,
                    patientId  : item.patientId,
                    patientName: item.patientName,
                    vital      : item.vital,
                    rowIndex   : i,
                    valueMap,
                    timeMap    : Object.fromEntries(
                        fullDates.map(date => {
                            let entries = dateTimeMap[date] || [];
                            return [date, entries[i] ? entries[i].time : ''];
                        })
                    )
                });
            }
        });

        this.tableData = Array.from(grouped.values());
        this.patientOptions = [
            { label: 'All Client', value: '' },
            ...Array.from(patientMap, ([id, name]) => ({ label: name, value: id }))
        ];
    }

    // extractTime(isoString) {
    //     if (!isoString || !isoString.includes('T')) return '';
    //     let timePart = isoString.split('T')[1];
    //     if (!timePart) return '';
    //     let [h, m] = timePart.split(':').map(Number);
    //     let ampm = h >= 12 ? 'PM' : 'AM';
    //     let hour = h % 12 || 12;
    //     return `${hour}:${String(m).padStart(2, '0')} ${ampm}`;
    // }

    // ─── Calendar View getters ────────────────────────────────────────────────
    get displayDates() {
        let start = this.currentPage * PAGE_SIZE;
        return this.allDates.slice(start, start + PAGE_SIZE).map(date => {
            let [y, m, d] = date.split('-');
            return { full: date, day: d, month: MONTHS[m - 1] };
        });
    }

    get paginatedTableData() {
        let start = this.currentPage * PAGE_SIZE;
        let keys  = this.allDates.slice(start, start + PAGE_SIZE);
        return this.tableData
            .map(p => {
                const filteredVitals = p.vitals.filter(v => !this.appliedCategory || v.vital === this.appliedCategory);
                return {
                    ...p,
                    vitals: filteredVitals.map((v, index) => ({
                        ...v,
                        showPatientName: index === 0,
                        rowspan        : filteredVitals.length,
                        values         : keys.map(date => {
                            let entry   = v.valueMap[date];
                            let isEmpty = !entry;
                            return {
                                date,
                                value    : isEmpty ? '—' : entry.value,
                                valueList: isEmpty ? [] : entry.value.split(' | '),
                                time     : isEmpty ? '' : entry.effectiveDateTime?.split('T')[1]?.slice(0, 5) || '',
                                isEmpty
                            };
                        })
                    }))
                };
            })
            .filter(p => p.vitals.length > 0);
    }

    get isPrevDisabled() { return this.currentPage === 0; }
    get isNextDisabled() { return (this.currentPage + 1) * PAGE_SIZE >= this.allDates.length; }
    get pageInfo() {
        if (!this.allDates.length) return 'No dates';
        let start = this.currentPage * PAGE_SIZE + 1;
        let end   = Math.min((this.currentPage + 1) * PAGE_SIZE, this.allDates.length);
        return `${start} – ${end} of ${this.allDates.length} dates`;
    }
    handlePrev() { if (!this.isPrevDisabled) this.currentPage--; }
    handleNext() { if (!this.isNextDisabled) this.currentPage++; }
    get hasData() { return this.paginatedTableData.length > 0; }

    // ─── List View getters ────────────────────────────────────────────────────
    get allListData() {
        let rows = [];
        this.tableData.forEach(patient => {
            patient.vitals.forEach(vr => {
                if (this.appliedCategory && vr.vital !== this.appliedCategory) return;

                this.allDates.forEach(date => {
                    let entry = vr.valueMap[date];
                    if (!entry) return;

                    // let [y, m, d] = date.split('-');
                    // let displayDate = `${d} ${MONTHS[parseInt(m, 10) - 1]} ${y}`;
                    // let time = this.extractTime(entry.createdDateTime || entry.effectiveDateTime || '');
                    const displayDate = entry.effectiveDateTime
                        ? formatDisplayDate(entry.effectiveDateTime)
                        : date.split('-').reverse();  // fallback only
                    console.log('datetime',displayDate);
                    const time = entry.effectiveDateTime
                        ? formatDisplayTime(entry.effectiveDateTime)
                        : '';
                    rows.push({
                        id           : `${vr.key}-${date}`,
                        recordId     : entry.recordId || '',
                        vital        : vr.vital,
                        value        : entry.value,
                        displayDate,
                        time,
                        fullDateTime : entry.effectiveDateTime || `${date}T00:00`,
                        editDateTime : entry.lastModifiedDateTime || entry.createdDateTime || '',
                        patientName  : patient.patientName,
                        categoryClass: 'list-badge cat-default'
                    });
                });
            });
        });

        //rows.sort((a, b) => b.fullDateTime > a.fullDateTime ? -1 : 1);
        rows.sort((a, b) => {
            const da = utcStringToDate(a.fullDateTime);
            const db = utcStringToDate(b.fullDateTime);
            return db - da;
        });
        return rows;
    }

    get paginatedListData() {
        let start = this.listCurrentPage * LIST_PAGE_SIZE;
        return this.allListData.slice(start, start + LIST_PAGE_SIZE);
    }

    get hasListData()        { return this.allListData.length > 0; }
    get isListPrevDisabled() { return this.listCurrentPage === 0; }
    get isListNextDisabled() { return (this.listCurrentPage + 1) * LIST_PAGE_SIZE >= this.allListData.length; }
    get listPageInfo() {
        const total = this.allListData.length;
        if (!total) return 'No records';
        const start = this.listCurrentPage * LIST_PAGE_SIZE + 1;
        const end   = Math.min((this.listCurrentPage + 1) * LIST_PAGE_SIZE, total);
        return `${start} – ${end} of ${total} records`;
    }
    handleListPrev() { if (!this.isListPrevDisabled) this.listCurrentPage--; }
    handleListNext() { if (!this.isListNextDisabled) this.listCurrentPage++; }

    // ─── filter handlers (date / patient) ────────────────────────────────────
    handlePatientChange(e) {
        if (this.isRecordPageContext) return;
        this.pendingPatientId = e.detail.value;
    }

    handleFromDate(e) {
        let selected = e.detail.value;
        let today    = this.formatDateLocal(new Date());
        if (selected > today) {
            e.target.setCustomValidity('From Date cannot be in the future');
            e.target.reportValidity(); return;
        }
        if (this.toDate && selected > this.toDate) {
            e.target.setCustomValidity('From Date cannot be greater than To Date');
            e.target.reportValidity(); return;
        }
        e.target.setCustomValidity(''); e.target.reportValidity();
        this.pendingFromDate   = selected;
        this.pendingQuickRange = '';
    }

    handleToDate(e) {
        let selected = e.detail.value;
        let today    = this.formatDateLocal(new Date());
        if (selected > today) {
            e.target.setCustomValidity('To Date cannot be in the future');
            e.target.reportValidity(); return;
        }
        if (this.fromDate && selected < this.fromDate) {
            e.target.setCustomValidity('To Date cannot be less than From Date');
            e.target.reportValidity(); return;
        }
        e.target.setCustomValidity(''); e.target.reportValidity();
        this.pendingToDate     = selected;
        this.pendingQuickRange = '';
    }

    applyFilter() {
        if (this.pendingFromDate && !this.pendingToDate) {
            this.showToast('Error', 'Please select the To Date.', 'error'); return;
        }
        if (!this.pendingFromDate && this.pendingToDate) {
            this.showToast('Error', 'Please select the From Date.', 'error'); return;
        }
        this.appliedPatientId  = this.pendingPatientId;
        this.appliedQuickRange = this.pendingQuickRange;
        this.appliedCategory   = this.pendingCategory;
        this.appliedFromDate   = this.pendingFromDate;
        this.appliedToDate     = this.pendingToDate;
        this.currentPage     = 0;
        this.listCurrentPage = 0;
        this.loadData();
    }

    handleClear() {
        const defaultPatient = this.isRecordPageContext ? this.recordId : '';
        this.pendingPatientId  = defaultPatient;
        this.pendingQuickRange = '';
        this.pendingCategory   = '';
        this.pendingFromDate   = null;
        this.pendingToDate     = null;
        this.appliedPatientId  = defaultPatient;
        this.appliedQuickRange = '';
        this.appliedCategory   = '';
        this.appliedFromDate   = null;
        this.appliedToDate     = null;
        this.currentPage     = 0;
        this.listCurrentPage = 0;

        const fromDateField = this.template.querySelector('.from-date');
        const toDateField   = this.template.querySelector('.to-date');
        if (fromDateField) { fromDateField.value = null; fromDateField.setCustomValidity(''); fromDateField.reportValidity(); }
        if (toDateField)   { toDateField.value   = null; toDateField.setCustomValidity('');   toDateField.reportValidity(); }

        this.loadData();
    }

    handleRefresh() { this.currentPage = 0; this.listCurrentPage = 0; this.loadData(); }

    // ─── apply/clear button states ────────────────────────────────────────────
    get isFilterChanged() {
        return (
            this.pendingPatientId  !== this.appliedPatientId  ||
            this.pendingQuickRange !== this.appliedQuickRange  ||
            this.pendingCategory   !== this.appliedCategory    ||
            (this.pendingFromDate || '') !== (this.appliedFromDate || '') ||
            (this.pendingToDate   || '') !== (this.appliedToDate   || '')
        );
    }
    get isApplyDisabled() { return this.isLoading || !this.isFilterChanged; }
    get isClearDisabled() {
        const atDefault =
            !this.pendingQuickRange &&
            !this.pendingFromDate   &&
            !this.pendingToDate     &&
            !this.pendingCategory   &&
            (this.pendingPatientId === (this.isRecordPageContext ? this.recordId : ''));
        return this.isLoading || atDefault;
    }
}