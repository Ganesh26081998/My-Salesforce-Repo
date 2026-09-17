import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

// Schema imports
import ACCOUNT_NAME_FIELD from '@salesforce/schema/Account.Name';
import ROLE_FIELD from '@salesforce/schema/Account.Role_during_hospitalization__c';

// Custom labels
import LABEL_CLIENT         from '@salesforce/label/c.Hosp_Action_Client_Label';
import LABEL_CANCEL         from '@salesforce/label/c.Hosp_Action_Cancel';
import LABEL_SAVE           from '@salesforce/label/c.Hosp_Action_Save';
import SUCCESS_TITLE        from '@salesforce/label/c.Hosp_Action_Success_Title';
import SUCCESS_MSG          from '@salesforce/label/c.Hosp_Action_Success_Message';
import ERROR_TITLE          from '@salesforce/label/c.Hosp_Action_Error_Title';
import ERROR_MSG            from '@salesforce/label/c.Hosp_Action_Error_Message';
import VALIDATION_TITLE     from '@salesforce/label/c.Hosp_Action_Validation_Title';
import VALIDATION_MSG       from '@salesforce/label/c.Hosp_Action_Validation_Message';

// Picklist API value constants (not labels — these are data values, not display text)
const STATUS_HOSPITALIZED = 'Open-Hospitalized';
const STATUS_DISCHARGED   = 'Closed-Discharged';
const ROLE_OTHER          = 'Other';

export default class PatientHospitalizationAction extends LightningElement {

    @api recordId;

    // Tracks user's in-form role selection.
    // undefined = user has not changed the field yet (wire data is used instead)
    selectedRoleValue = undefined;

    hospitalizationStatusValue;
    admissionDateValue;
    dischargeDateValue;

    // Expose labels as a single object so the template can reference {labels.xxx}
    labels = {
        client         : LABEL_CLIENT,
        cancel         : LABEL_CANCEL,
        save           : LABEL_SAVE
    };

    @wire(getRecord, { recordId: '$recordId', fields: [ACCOUNT_NAME_FIELD, ROLE_FIELD] })
    accountRecord;

    // ── Getters ──────────────────────────────────────────────────────────────

    get clientName() {
        return getFieldValue(this.accountRecord.data, ACCOUNT_NAME_FIELD);
    }

    get showNotes() {
        const role = this.selectedRoleValue !== undefined
            ? this.selectedRoleValue
            : getFieldValue(this.accountRecord.data, ROLE_FIELD);
        return (role || '').toLowerCase() === ROLE_OTHER.toLowerCase();
    }

    get isAdmissionDateDisabled() {
        return this.hospitalizationStatusValue !== STATUS_HOSPITALIZED;
    }

    get isDischargeDateDisabled() {
        return this.hospitalizationStatusValue !== STATUS_DISCHARGED;
    }

    // ── Event handlers ───────────────────────────────────────────────────────

    handleLoad(event) {
        const record = Object.values(event.detail?.records || {})[0];
        const fields = record?.fields || {};
        this.hospitalizationStatusValue = fields.Hospitalization_Status__c?.value ?? null;
        this.admissionDateValue         = fields.Admission_Date__c?.value          ?? null;
        this.dischargeDateValue         = fields.Discharge_Date__c?.value          ?? null;
    }

    handleStatusChange(event) {
        this.hospitalizationStatusValue = event.detail?.value ?? null;
    }

    handleAdmissionDateChange(event) {
        this.admissionDateValue = event.detail?.value ?? null;
    }

    handleDischargeDateChange(event) {
        this.dischargeDateValue = event.detail?.value ?? null;
    }

    handleRoleChange(event) {
        this.selectedRoleValue = event.detail?.value ?? null;
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        fields.Hospitalize__c = true;

        const status       = fields.Hospitalization_Status__c || this.hospitalizationStatusValue;
        const admissionDate = fields.Admission_Date__c        || this.admissionDateValue;
        const dischargeDate = fields.Discharge_Date__c        || this.dischargeDateValue;

        if (status === STATUS_DISCHARGED && admissionDate && dischargeDate) {
            if (new Date(dischargeDate) <= new Date(admissionDate)) {
                this.showToast(VALIDATION_TITLE, VALIDATION_MSG, 'error');
                return;
            }
        }

        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSuccess() {
        this.showToast(SUCCESS_TITLE, SUCCESS_MSG, 'success');
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleError(event) {
        const message = event.detail?.output?.errors?.[0]?.message
                     || event.detail?.message
                     || ERROR_MSG;
        this.showToast(ERROR_TITLE, message, 'error');
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}