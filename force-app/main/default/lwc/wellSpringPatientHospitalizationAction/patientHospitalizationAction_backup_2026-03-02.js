import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ACCOUNT_NAME_FIELD from '@salesforce/schema/Account.Name';
import ROLE_FIELD from '@salesforce/schema/Account.Role_during_hospitalization__c';

export default class PatientHospitalizationAction extends LightningElement {
    @api recordId;
    selectedRoleValue = undefined; // undefined = not yet changed by user; any other value = user-selected
    hospitalizationStatusValue;
    admissionDateValue;
    dischargeDateValue;
    @wire(getRecord, { recordId: '$recordId', fields: [ACCOUNT_NAME_FIELD, ROLE_FIELD] })
    accountRecord;

    get clientName() {
        return getFieldValue(this.accountRecord.data, ACCOUNT_NAME_FIELD);
    }

    get showAdditionalNotes() {
        // Prefer user's in-form selection; fall back to wire-loaded record value
        const role = this.selectedRoleValue !== undefined
            ? this.selectedRoleValue
            : getFieldValue(this.accountRecord.data, ROLE_FIELD);
        return (role || '').toLowerCase() === 'other';
    }

    get isAdmissionDateDisabled() {
        return this.hospitalizationStatusValue !== 'Open-Hospitalized';
    }

    get isDischargeDateDisabled() {
        return this.hospitalizationStatusValue !== 'Closed-Discharged';
    }

    handleLoad(event) {
        const records = event.detail?.records || {};
        const record = records[this.recordId] || Object.values(records)[0];
        const fields = record?.fields || {};

        this.hospitalizationStatusValue = fields.Hospitalization_Status__c?.value || null;
        this.admissionDateValue = fields.Admission_Date__c?.value || null;
        this.dischargeDateValue = fields.Discharge_Date__c?.value || null;
    }

    handleRoleChange(event) {
        // Use ?? (not ||) so that null/empty string also overrides the wire value
        this.selectedRoleValue = event.detail?.value ?? null;
    }

    handleStatusChange(event) {
        this.hospitalizationStatusValue = event.detail?.value || null;
    }

    handleAdmissionDateChange(event) {
        this.admissionDateValue = event.detail?.value || null;
    }

    handleDischargeDateChange(event) {
        this.dischargeDateValue = event.detail?.value || null;
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        fields.Hospitalize__c = true;

        const status = fields.Hospitalization_Status__c || this.hospitalizationStatusValue;
        const admissionDate = fields.Admission_Date__c || this.admissionDateValue;
        const dischargeDate = fields.Discharge_Date__c || this.dischargeDateValue;

        if (status === 'Closed-Discharged' && admissionDate && dischargeDate) {
            const admissionMs = new Date(admissionDate).getTime();
            const dischargeMs = new Date(dischargeDate).getTime();
            if (dischargeMs <= admissionMs) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Validation Error',
                    message: 'Discharge Date must be greater than Admission Date for Closed-Discharged status.',
                    variant: 'error'
                }));
                return;
            }
        }

        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSuccess() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: 'Hospitalization details saved successfully.',
            variant: 'success'
        }));
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleError(event) {
        let message = 'Something went wrong while saving.';

        if (event.detail?.message) {
            message = event.detail.message;
        }
        if (event.detail?.output?.errors?.length) {
            message = event.detail.output.errors[0].message;
        }

        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: message,
            variant: 'error'
        }));
    }
}