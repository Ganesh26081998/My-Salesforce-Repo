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

const norm = (v) => (v || '').toString().toLowerCase().replace(/[^a-z0-9]/g, '');
const isBlank = (v) => v === null || v === undefined || (typeof v === 'string' && v.trim() === '');
const hasDigit = (v) => /\d/.test(v || '');

export default class WellSpringPatientHospitalizationAction extends LightningElement {
    @api recordId;

    isSaving = false;

    statusValue = null;
    admissionType = null;
    admissionDate = null;
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
        return !norm(this.statusValue).includes('hospitalized');
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

    handleStatusChange(e) {
        this.statusValue = e.detail?.value ?? null;
        this.errStatus = null;
        // Clear discharge date when status is not Closed - Discharged
        if (!norm(this.statusValue).includes('discharged')) {
            this.dischargeDate = null;
            this.errDischargeDate = null;
        }
    }
    handleAdmissionTypeChange(e) {
        this.admissionType = e.detail?.value ?? null;
        this.errAdmissionType = null;
    }
    handleAdmissionDateChange(e) {
        this.admissionDate = e.detail?.value ?? null;
        this.errAdmissionDate = null;
    }
    handleHospitalNameChange(e) {
        this.hospitalName = e.detail?.value ?? null;
        this.errHospitalName = null;
    }
    handlePrimaryDiagChange(e) {
        this.primaryDiag = e.detail?.value ?? null;
        this.errPrimaryDiag = null;
    }
    handleDischargeDateChange(e) {
        this.dischargeDate = e.detail?.value ?? null;
        this.errDischargeDate = null;
    }
    handleRoleChange(e) {
        this.roleValue = e.detail?.value ?? null;
        this.errRole = null;
    }
    handleReasonChange(e) {
        this.reason = e.detail?.value ?? null;
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
            // Discharge date is not allowed when status is Open - Hospitalized
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

        // Alpha-only checks that also apply when status is Closed - Discharged
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
            if (isBlank(this.roleValue)) {
                this.errRole = 'Role During Hospitalization is required.';
                hasErrors = true;
            }
        }

        if (this.admissionDate && this.dischargeDate && new Date(this.dischargeDate) < new Date(this.admissionDate)) {
            this.errDischargeDate = 'Discharge Date must be on or after Admission Date.';
            hasErrors = true;
        }

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
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch((err) => {
                this.isSaving = false;
                const msg = err?.body?.output?.errors?.[0]?.message || err?.body?.message || ERROR_MSG;
                console.error('createRecord error:', JSON.stringify(err));
                this.dispatchEvent(new ShowToastEvent({ title: ERROR_TITLE, message: msg, variant: 'error' }));
            });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    preventNativeSubmit(event) {
        event.preventDefault();
    }
}