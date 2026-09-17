import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue, createRecord } from 'lightning/uiRecordApi';

import ACCOUNT_NAME_FIELD from '@salesforce/schema/Account.Name';

import HOSPITALIZATION_OBJECT from '@salesforce/schema/Hospitalization__c';
import ACCOUNT_LOOKUP_FIELD from '@salesforce/schema/Hospitalization__c.Account__c';
import STATUS_FIELD from '@salesforce/schema/Hospitalization__c.Hospitalization_Status__c';
import ADMISSION_TYPE_FIELD from '@salesforce/schema/Hospitalization__c.Admission_Type__c';
import ADMISSION_DATE_FIELD from '@salesforce/schema/Hospitalization__c.Admission_Date__c';
import HOSPITAL_NAME_FIELD from '@salesforce/schema/Hospitalization__c.Hospital_Name__c';
import PRIMARY_DIAG_FIELD from '@salesforce/schema/Hospitalization__c.Primary_diagnosis__c';
import DISCHARGE_DATE_FIELD from '@salesforce/schema/Hospitalization__c.Discharge_Date__c';
import ROLE_FIELD from '@salesforce/schema/Hospitalization__c.Role_during_hospitalization__c';
import REASON_FIELD from '@salesforce/schema/Hospitalization__c.Reason_for_admission__c';
import CURRENT_HOSPITALIZATION_FIELD from '@salesforce/schema/Hospitalization__c.Current_Hospitalization__c';

import LABEL_CLIENT from '@salesforce/label/c.Hosp_Action_Client_Label';
import LABEL_CANCEL from '@salesforce/label/c.Hosp_Action_Cancel';
import LABEL_SAVE from '@salesforce/label/c.Hosp_Action_Save';
import SUCCESS_TITLE from '@salesforce/label/c.Hosp_Action_Success_Title';
import SUCCESS_MSG from '@salesforce/label/c.Hosp_Action_Success_Message';
import ERROR_TITLE from '@salesforce/label/c.Hosp_Action_Error_Title';
import ERROR_MSG from '@salesforce/label/c.Hosp_Action_Error_Message';

const WIRE_FIELDS = [ACCOUNT_NAME_FIELD];

const norm = (value) => (value || '').toString().toLowerCase().replace(/[^a-z0-9]/g, '');
const isBlank = (value) => value === null || value === undefined || (typeof value === 'string' && value.trim() === '');
const hasDigit = (value) => /\d/.test(value || '');

const todayYmdInTimeZone = (timeZone) => {
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
    }).formatToParts(new Date()).reduce((values, part) => {
        if (part.type !== 'literal') {
            values[part.type] = part.value;
        }
        return values;
    }, {});

    return `${parts.year}-${parts.month}-${parts.day}`;
};

const extractErrorMessage = (error, fallback) =>
    error?.body?.output?.errors?.[0]?.message ||
    error?.body?.pageErrors?.[0]?.message ||
    error?.body?.message ||
    error?.message ||
    fallback;

export default class WellSpringPatientHospitalizationAction extends LightningElement {
    @api recordId;
    @api existingHospitalizations = [];

    isSaving = false;

    statusValue = null;
    admissionType = null;
    admissionDate = todayYmdInTimeZone('America/Chicago');
    hospitalName = null;
    primaryDiag = null;
    dischargeDate = null;
    roleValue = null;
    reason = null;

    errStatus = null;
    errAdmissionType = null;
    errAdmissionDate = null;
    errHospitalName = null;
    errPrimaryDiag = null;
    errDischargeDate = null;
    errRole = null;
    errReason = null;

    _recordData = null;

    labels = { client: LABEL_CLIENT, cancel: LABEL_CANCEL, save: LABEL_SAVE };

    renderedCallback() {
        this.hideVisualRequiredMarkers();
    }

    @wire(getRecord, { recordId: '$recordId', fields: WIRE_FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this._recordData = data;
        }
        if (error) {
            console.error('wiredRecord error:', JSON.stringify(error));
        }
    }

    get clientName() {
        return getFieldValue(this._recordData, ACCOUNT_NAME_FIELD);
    }

    get isAdmissionDateDisabled() {
        const status = norm(this.statusValue);
        return !(status.includes('hospitalized') || status.includes('discharged'));
    }

    get isDischargeDateDisabled() {
        return !norm(this.statusValue).includes('discharged');
    }

    get statusClass() {
        return this.errStatus ? 'fielderr' : '';
    }

    get admTypeClass() {
        return this.errAdmissionType ? 'fielderr' : '';
    }

    get admDateClass() {
        return this.errAdmissionDate ? 'fielderr' : '';
    }

    get hospitalNameClass() {
        return this.errHospitalName ? 'fielderr' : '';
    }

    get primaryDiagClass() {
        return this.errPrimaryDiag ? 'fielderr' : '';
    }

    get dischDateClass() {
        return this.errDischargeDate ? 'fielderr' : '';
    }

    get roleClass() {
        return this.errRole ? 'fielderr' : '';
    }

    get reasonClass() {
        return this.errReason ? 'fielderr' : '';
    }

    handleStatusChange(event) {
        this.statusValue = event.detail?.value ?? null;
        this.errStatus = null;

        if (!norm(this.statusValue).includes('discharged')) {
            this.dischargeDate = null;
            this.errDischargeDate = null;
        }
    }

    handleAdmissionTypeChange(event) {
        this.admissionType = event.detail?.value ?? null;
        this.errAdmissionType = null;
    }

    handleAdmissionDateChange(event) {
        this.admissionDate = event.detail?.value ?? null;
        this.errAdmissionDate = null;
        // if (this.admissionDate && this.admissionDate < todayYmdInTimeZone('America/Chicago')) {
        //     this.errAdmissionDate = 'Admission Date cannot be a past date.';
        // }
    }

    handleHospitalNameChange(event) {
        this.hospitalName = event.detail?.value ?? null;
        this.errHospitalName = null;
    }

    handlePrimaryDiagChange(event) {
        this.primaryDiag = event.detail?.value ?? null;
        this.errPrimaryDiag = null;
    }

    handleDischargeDateChange(event) {
        this.dischargeDate = event.detail?.value ?? null;
        this.errDischargeDate = null;
    }

    handleRoleChange(event) {
        this.roleValue = event.detail?.value ?? null;
        this.errRole = null;
    }

    handleReasonChange(event) {
        this.reason = event.detail?.value ?? null;
        this.errReason = null;
    }

    readFieldValue(fieldName) {
        return this.template.querySelector(`lightning-input-field[field-name="${fieldName}"]`)?.value;
    }

    syncFormValuesFromInputs() {
        this.statusValue = this.readFieldValue('Hospitalization_Status__c') ?? this.statusValue;
        this.admissionType = this.readFieldValue('Admission_Type__c') ?? this.admissionType;
        this.admissionDate = this.readFieldValue('Admission_Date__c') ?? this.admissionDate;
        this.hospitalName = this.readFieldValue('Hospital_Name__c') ?? this.hospitalName;
        this.primaryDiag = this.readFieldValue('Primary_diagnosis__c') ?? this.primaryDiag;
        this.dischargeDate = this.readFieldValue('Discharge_Date__c') ?? this.dischargeDate;
        this.roleValue = this.readFieldValue('Role_during_hospitalization__c') ?? this.roleValue;
        this.reason = this.readFieldValue('Reason_for_admission__c') ?? this.reason;
    }

    handleSave() {
        if (this.isSaving) {
            return;
        }

        this.errStatus = this.errAdmissionType = this.errAdmissionDate = null;
        this.errHospitalName = this.errPrimaryDiag = this.errDischargeDate = null;
        this.errRole = this.errReason = null;
        this.syncFormValuesFromInputs();

        const normStatus = norm(this.statusValue);
        let hasErrors = false;

        if (isBlank(this.statusValue)) {
            this.errStatus = 'Hospitalization Status is required.';
            hasErrors = true;
        }

        if (normStatus.includes('hospitalized')) {
            this.dischargeDate = null;

            if (isBlank(this.admissionType)) {
                this.errAdmissionType = 'Admission Type is required.';
                hasErrors = true;
            }
            if (isBlank(this.admissionDate)) {
                this.errAdmissionDate = 'Admission Date is required.';
                hasErrors = true;
            }
            if (isBlank(this.hospitalName)) {
                this.errHospitalName = 'Hospital Name is required.';
                hasErrors = true;
            } else if (hasDigit(this.hospitalName)) {
                this.errHospitalName = 'Hospital Name must contain letters only, no numbers.';
                hasErrors = true;
            }
            if (isBlank(this.primaryDiag)) {
                this.errPrimaryDiag = 'Primary Diagnosis is required.';
                hasErrors = true;
            }
            if (isBlank(this.reason)) {
                this.errReason = 'Reason for Admission is required.';
                hasErrors = true;
            } else if (hasDigit(this.reason)) {
                this.errReason = 'Reason for Admission must contain letters only, no numbers.';
                hasErrors = true;
            }
        }

        if (!this.errHospitalName && !isBlank(this.hospitalName) && hasDigit(this.hospitalName)) {
            this.errHospitalName = 'Hospital Name must contain letters only, no numbers.';
            hasErrors = true;
        }
        if (!this.errReason && !isBlank(this.reason) && hasDigit(this.reason)) {
            this.errReason = 'Reason for Admission must contain letters only, no numbers.';
            hasErrors = true;
        }

        if (normStatus.includes('discharged')) {
            if (isBlank(this.admissionDate)) {
                this.errAdmissionDate = 'Admission Date is required.';
                hasErrors = true;
            }
            if (!this.errHospitalName && isBlank(this.hospitalName)) {
                this.errHospitalName = 'Hospital Name is required.';
                hasErrors = true;
            }
            if (isBlank(this.dischargeDate)) {
                this.errDischargeDate = 'Discharge Date is required.';
                hasErrors = true;
            }
        }

        // if (!this.errAdmissionDate && this.admissionDate && this.admissionDate < todayYmdInTimeZone('America/Chicago')) {
        //     this.errAdmissionDate = 'Admission Date cannot be a past date.';
        //     hasErrors = true;
        // }

        if (this.admissionDate && this.dischargeDate && new Date(this.dischargeDate) < new Date(this.admissionDate)) {
            this.errDischargeDate = 'Discharge Date must be on or after Admission Date.';
            hasErrors = true;
        }

        // if (!this.errAdmissionDate && this.admissionDate && Array.isArray(this.existingHospitalizations)) {
        //     const isDuplicate = this.existingHospitalizations.some(h => h.Admission_Date__c === this.admissionDate);
        //     if (isDuplicate) {
        //         this.errAdmissionDate = 'A hospitalization record already exists for this date. Duplicate records are not allowed.';
        //         hasErrors = true;
        //     }
        // }

        if (hasErrors) {
            return;
        }

        this.isSaving = true;
        const isCurrentHospitalization =
            normStatus.includes('hospitalized') && !isBlank(this.admissionDate) && isBlank(this.dischargeDate);

        const fields = {
            [ACCOUNT_LOOKUP_FIELD.fieldApiName]: this.recordId,
            [STATUS_FIELD.fieldApiName]: this.statusValue,
            [ADMISSION_TYPE_FIELD.fieldApiName]: this.admissionType,
            [ADMISSION_DATE_FIELD.fieldApiName]: this.admissionDate,
            [HOSPITAL_NAME_FIELD.fieldApiName]: this.hospitalName,
            [PRIMARY_DIAG_FIELD.fieldApiName]: this.primaryDiag,
            [DISCHARGE_DATE_FIELD.fieldApiName]: this.dischargeDate,
            [ROLE_FIELD.fieldApiName]: this.roleValue,
            [REASON_FIELD.fieldApiName]: this.reason,
            [CURRENT_HOSPITALIZATION_FIELD.fieldApiName]: isCurrentHospitalization
        };

        createRecord({ apiName: HOSPITALIZATION_OBJECT.objectApiName, fields })
            .then(() => {
                this.isSaving = false;
                this.dispatchEvent(
                    new ShowToastEvent({ title: SUCCESS_TITLE, message: SUCCESS_MSG, variant: 'success' })
                );
                this.dispatchEvent(
                    new CustomEvent('close', {
                        detail: { refresh: true }
                    })
                );
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch((error) => {
                this.isSaving = false;
                const message = extractErrorMessage(error, ERROR_MSG);
                console.error('createRecord error:', JSON.stringify(error));
                this.dispatchEvent(new ShowToastEvent({ title: ERROR_TITLE, message, variant: 'error' }));
            });
    }

    handleCancel() {
        this.dispatchEvent(
            new CustomEvent('close', {
                detail: { refresh: false }
            })
        );
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    preventNativeSubmit(event) {
        event.preventDefault();
    }

    hideVisualRequiredMarkers() {
        this.template.querySelectorAll('lightning-input-field').forEach((field) => {
            if (field.getAttribute('field-name') === 'Admission_Date__c') return;
            const marker = field.shadowRoot?.querySelector('.slds-required');
            if (marker) {
                marker.style.display = 'none';
            }
        });
    }
}