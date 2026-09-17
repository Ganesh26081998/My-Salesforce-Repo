import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

import getHospitalizations from '@salesforce/apex/WellSpringHospitalizationController.getHospitalizations';
import deleteHospitalization from '@salesforce/apex/WellSpringHospitalizationController.deleteHospitalization';

import ACCOUNT_STATUS from '@salesforce/schema/Account.Account_Status__c';

const ACTIONS = [
    { label: 'Edit', name: 'edit' },
    { label: 'Delete', name: 'delete' }
];

const COLUMNS = [
    {
        label: 'Hospitalization',
        type: 'button',
        initialWidth: 180,
        typeAttributes: {
            label: { fieldName: 'Name' },
            name: 'open',
            variant: 'base'
        }
    },
    { label: 'Status', fieldName: 'Hospitalization_Status__c' },
    { label: 'Admission Date', fieldName: 'Admission_Date__c', type: 'text' },
    { label: 'Discharge Date', fieldName: 'Discharge_Date__c', type: 'text' },
    { label: 'Hospital', fieldName: 'Hospital_Name__c' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: ACTIONS,
            menuAlignment: 'auto'
        }
    }
];

const norm = (value) => (value || '').toString().toLowerCase().replace(/[^a-z0-9]/g, '');
const isBlank = (value) => value === null || value === undefined || (typeof value === 'string' && value.trim() === '');
const hasDigit = (value) => /\d/.test(value || '');
const extractErrorMessage = (error, fallback) =>
    error?.body?.output?.errors?.[0]?.message ||
    error?.body?.pageErrors?.[0]?.message ||
    error?.body?.message ||
    error?.message ||
    fallback;

export default class WellSpringPatientHospitalizations extends LightningElement {
    @api recordId;

    isCreateModalOpen = false;
    hospitalizations = [];
    rawHospitalizations = [];
    deleteConfirmId = null;
    deleteConfirmName = null;
    columns = COLUMNS;
    selectedHospitalizationId = null;
    selectedHospitalizationName = null;
    editHospitalizationId = null;
    editHospitalizationName = null;
    loadError = null;
    wiredHospitalizationsResult;

    editStatus = null;
    editAdmissionType = null;
    editAdmissionDate = null;
    editHospitalName = null;
    editPrimaryDiag = null;
    editDischargeDate = null;
    editRole = null;
    editReason = null;
    editIsSaving = false;

    errEditStatus = null;
    errEditAdmissionType = null;
    errEditAdmissionDate = null;
    errEditHospitalName = null;
    errEditPrimaryDiag = null;
    errEditDischargeDate = null;
    errEditRole = null;
    errEditReason = null;

    renderedCallback() {
        this.hideVisualRequiredMarkers();
    }

    @wire(getHospitalizations, { accountId: '$recordId' })
    wiredHospitalizations(result) {
        this.wiredHospitalizationsResult = result;
        const { data, error } = result;

        if (data) {
            this.rawHospitalizations = data;
            this.hospitalizations = data.map((record) => ({
                ...record,
                Admission_Date__c: this.formatDate(record.Admission_Date__c),
                Discharge_Date__c: this.formatDate(record.Discharge_Date__c)
            }));
            this.loadError = null;
        } else if (error) {
            this.hospitalizations = [];
            this.rawHospitalizations = [];
            this.loadError = 'Unable to load hospitalization records.';
            console.error('wiredHospitalizations error:', JSON.stringify(error));
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: [ACCOUNT_STATUS] })
    account;

    get isClient() {
        return this.account?.data?.fields?.Account_Status__c?.value === 'Client';
    }

    get hasHospitalizations() {
        return this.hospitalizations.length > 0;
    }

    get isModalOpen() {
        return !!this.selectedHospitalizationId;
    }

    get isEditModalOpen() {
        return !!this.editHospitalizationId;
    }

    get isEditDischargeDateDisabled() {
        return !norm(this.editStatus).includes('discharged');
    }

    get editStatusClass() {
        return this.errEditStatus ? 'fielderr' : '';
    }

    get editAdmTypeClass() {
        return this.errEditAdmissionType ? 'fielderr' : '';
    }

    get editAdmDateClass() {
        return this.errEditAdmissionDate ? 'fielderr' : '';
    }

    get editHospitalNameClass() {
        return this.errEditHospitalName ? 'fielderr' : '';
    }

    get editPrimaryDiagClass() {
        return this.errEditPrimaryDiag ? 'fielderr' : '';
    }

    get editDischDateClass() {
        return this.errEditDischargeDate ? 'fielderr' : '';
    }

    get editRoleClass() {
        return this.errEditRole ? 'fielderr' : '';
    }

    get editReasonClass() {
        return this.errEditReason ? 'fielderr' : '';
    }

    formatDate(dateStr) {
        if (!dateStr) {
            return null;
        }

        const [year, month, day] = dateStr.split('-');
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return `${months[parseInt(month, 10) - 1]} ${parseInt(day, 10)}, ${year}`;
    }

    handleRowAction(event) {
        const actionName = event.detail?.action?.name;
        const row = event.detail?.row;

        if (actionName === 'open') {
            this.selectedHospitalizationId = row?.Id || null;
            this.selectedHospitalizationName = row?.Name || null;
            return;
        }

        if (actionName === 'edit') {
            this.editHospitalizationId = row?.Id || null;
            this.editHospitalizationName = row?.Name || null;
            this.editStatus = row?.Hospitalization_Status__c || null;
            this.editAdmissionType = null;
            this.editAdmissionDate = null;
            this.editHospitalName = null;
            this.editPrimaryDiag = null;
            this.editDischargeDate = null;
            this.editRole = null;
            this.editReason = null;
            this.clearEditErrors();
            return;
        }

        if (actionName === 'delete') {
            this.deleteConfirmId = row?.Id || null;
            this.deleteConfirmName = row?.Name || null;
        }
    }

    clearEditErrors() {
        this.errEditStatus = null;
        this.errEditAdmissionType = null;
        this.errEditAdmissionDate = null;
        this.errEditHospitalName = null;
        this.errEditPrimaryDiag = null;
        this.errEditDischargeDate = null;
        this.errEditRole = null;
        this.errEditReason = null;
    }

    closeModal() {
        this.selectedHospitalizationId = null;
        this.selectedHospitalizationName = null;
    }

    closeEditModal() {
        this.editHospitalizationId = null;
        this.editHospitalizationName = null;
        this.clearEditErrors();
    }

    preventEditNativeSubmit(event) {
        event.preventDefault();
    }

    handleNewHospitalization() {
        this.isCreateModalOpen = true;
    }

    closeCreateModal() {
        this.isCreateModalOpen = false;
    }

    handleCreateSuccess(event) {
        this.isCreateModalOpen = false;
        if (event?.detail?.refresh) {
            refreshApex(this.wiredHospitalizationsResult);
        }
    }

    handleEditStatusChange(event) {
        this.editStatus = event.detail?.value ?? null;
        this.errEditStatus = null;
        if (!norm(this.editStatus).includes('discharged')) {
            this.editDischargeDate = null;
            this.errEditDischargeDate = null;
        }
    }

    handleEditAdmissionTypeChange(event) {
        this.editAdmissionType = event.detail?.value ?? null;
        this.errEditAdmissionType = null;
    }

    handleEditAdmissionDateChange(event) {
        this.editAdmissionDate = event.detail?.value ?? null;
        this.errEditAdmissionDate = null;
    }

    handleEditHospitalNameChange(event) {
        this.editHospitalName = event.detail?.value ?? null;
        this.errEditHospitalName = null;
    }

    handleEditPrimaryDiagChange(event) {
        this.editPrimaryDiag = event.detail?.value ?? null;
        this.errEditPrimaryDiag = null;
    }

    handleEditDischargeDateChange(event) {
        this.editDischargeDate = event.detail?.value ?? null;
        this.errEditDischargeDate = null;
    }

    handleEditRoleChange(event) {
        this.editRole = event.detail?.value ?? null;
        this.errEditRole = null;
    }

    handleEditReasonChange(event) {
        this.editReason = event.detail?.value ?? null;
        this.errEditReason = null;
    }

    handleEditLoad(event) {
        const records = event?.detail?.records;
        if (!records) {
            return;
        }

        const record = records[this.editHospitalizationId];
        if (!record) {
            return;
        }

        const fields = record.fields;
        if (fields.Hospitalization_Status__c !== undefined) this.editStatus = fields.Hospitalization_Status__c.value || null;
        if (fields.Admission_Type__c !== undefined) this.editAdmissionType = fields.Admission_Type__c.value || null;
        if (fields.Admission_Date__c !== undefined) this.editAdmissionDate = fields.Admission_Date__c.value || null;
        if (fields.Hospital_Name__c !== undefined) this.editHospitalName = fields.Hospital_Name__c.value || null;
        if (fields.Primary_diagnosis__c !== undefined) this.editPrimaryDiag = fields.Primary_diagnosis__c.value || null;
        if (fields.Discharge_Date__c !== undefined) this.editDischargeDate = fields.Discharge_Date__c.value || null;
        if (fields.Role_during_hospitalization__c !== undefined) this.editRole = fields.Role_during_hospitalization__c.value || null;
        if (fields.Reason_for_admission__c !== undefined) this.editReason = fields.Reason_for_admission__c.value || null;
    }

    readEditFieldValue(fieldName) {
        return this.template.querySelector(`lightning-input-field[field-name="${fieldName}"]`)?.value;
    }

    syncEditFormValues() {
        const status = this.readEditFieldValue('Hospitalization_Status__c');
        if (status !== undefined) this.editStatus = status || null;

        const admissionType = this.readEditFieldValue('Admission_Type__c');
        if (admissionType !== undefined) this.editAdmissionType = admissionType || null;

        const admissionDate = this.readEditFieldValue('Admission_Date__c');
        if (admissionDate !== undefined) this.editAdmissionDate = admissionDate || null;

        const hospitalName = this.readEditFieldValue('Hospital_Name__c');
        if (hospitalName !== undefined) this.editHospitalName = hospitalName || null;

        const primaryDiag = this.readEditFieldValue('Primary_diagnosis__c');
        if (primaryDiag !== undefined) this.editPrimaryDiag = primaryDiag || null;

        const dischargeDate = this.readEditFieldValue('Discharge_Date__c');
        if (dischargeDate !== undefined) this.editDischargeDate = dischargeDate || null;

        const role = this.readEditFieldValue('Role_during_hospitalization__c');
        if (role !== undefined) this.editRole = role || null;

        const reason = this.readEditFieldValue('Reason_for_admission__c');
        if (reason !== undefined) this.editReason = reason || null;
    }

    handleEditSave() {
        if (this.editIsSaving) {
            return;
        }

        this.clearEditErrors();
        this.syncEditFormValues();

        const normStatus = norm(this.editStatus);
        let hasErrors = false;

        if (isBlank(this.editStatus)) {
            this.errEditStatus = 'Hospitalization Status is required.';
            hasErrors = true;
        }

        if (normStatus.includes('hospitalized')) {
            this.editDischargeDate = null;

            if (isBlank(this.editAdmissionType)) {
                this.errEditAdmissionType = 'Admission Type is required.';
                hasErrors = true;
            }
            if (isBlank(this.editAdmissionDate)) {
                this.errEditAdmissionDate = 'Admission Date is required.';
                hasErrors = true;
            }
            if (isBlank(this.editHospitalName)) {
                this.errEditHospitalName = 'Hospital Name is required.';
                hasErrors = true;
            } else if (hasDigit(this.editHospitalName)) {
                this.errEditHospitalName = 'Hospital Name must contain letters only, no numbers.';
                hasErrors = true;
            }
            if (isBlank(this.editPrimaryDiag)) {
                this.errEditPrimaryDiag = 'Primary Diagnosis is required.';
                hasErrors = true;
            }
            if (isBlank(this.editReason)) {
                this.errEditReason = 'Reason for Admission is required.';
                hasErrors = true;
            } else if (hasDigit(this.editReason)) {
                this.errEditReason = 'Reason for Admission must contain letters only, no numbers.';
                hasErrors = true;
            }
        }

        if (!this.errEditHospitalName && !isBlank(this.editHospitalName) && hasDigit(this.editHospitalName)) {
            this.errEditHospitalName = 'Hospital Name must contain letters only, no numbers.';
            hasErrors = true;
        }
        if (!this.errEditReason && !isBlank(this.editReason) && hasDigit(this.editReason)) {
            this.errEditReason = 'Reason for Admission must contain letters only, no numbers.';
            hasErrors = true;
        }

        if (normStatus.includes('discharged')) {
            if (isBlank(this.editAdmissionDate)) {
                this.errEditAdmissionDate = 'Admission Date is required.';
                hasErrors = true;
            }
            if (!this.errEditHospitalName && isBlank(this.editHospitalName)) {
                this.errEditHospitalName = 'Hospital Name is required.';
                hasErrors = true;
            }
            if (isBlank(this.editDischargeDate)) {
                this.errEditDischargeDate = 'Discharge Date is required.';
                hasErrors = true;
            }
            if (!this.errEditReason && isBlank(this.editReason)) {
                this.errEditReason = 'Reason for Admission is required.';
                hasErrors = true;
            }
        }

        if (
            this.editAdmissionDate &&
            this.editDischargeDate &&
            new Date(this.editDischargeDate) < new Date(this.editAdmissionDate)
        ) {
            this.errEditDischargeDate = 'Discharge Date must be on or after Admission Date.';
            hasErrors = true;
        }

      //  if (!this.errEditAdmissionDate && this.editAdmissionDate && this.rawHospitalizations.length > 0) {
      //      const isDuplicate = this.rawHospitalizations.some(
      //          h => h.Id !== this.editHospitalizationId && h.Admission_Date__c === this.editAdmissionDate
      //      );
      //      if (isDuplicate) {
      //          this.errEditAdmissionDate = 'A hospitalization record already exists for this date. Duplicate records are not allowed.';
      //          hasErrors = true;
      //      }
      //  }

        if (hasErrors) {
            return;
        }

        const isCurrentHospitalization =
            normStatus.includes('hospitalized') &&
            !isBlank(this.editAdmissionDate) &&
            isBlank(this.editDischargeDate);

        this.editIsSaving = true;

        const fields = {
            Id: this.editHospitalizationId,
            Hospitalization_Status__c: this.editStatus,
            Admission_Type__c: this.editAdmissionType || null,
            Admission_Date__c: this.editAdmissionDate || null,
            Hospital_Name__c: this.editHospitalName || null,
            Primary_diagnosis__c: this.editPrimaryDiag || null,
            Discharge_Date__c: normStatus.includes('hospitalized') ? null : (this.editDischargeDate || null),
            Role_during_hospitalization__c: this.editRole || null,
            Reason_for_admission__c: this.editReason || null,
            Current_Hospitalization__c: isCurrentHospitalization
        };

        updateRecord({ fields })
            .then(() => {
                this.editIsSaving = false;
                this.closeEditModal();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Hospitalization record updated.',
                        variant: 'success'
                    })
                );
                refreshApex(this.wiredHospitalizationsResult);
            })
            .catch((error) => {
                this.editIsSaving = false;
                const message = extractErrorMessage(error, 'Unable to update hospitalization record.');
                console.error('updateRecord error:', JSON.stringify(error));
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message,
                        variant: 'error'
                    })
                );
            });
    }

    cancelDelete() {
        this.deleteConfirmId = null;
        this.deleteConfirmName = null;
    }

    confirmDelete() {
        const recordId = this.deleteConfirmId;
        this.deleteConfirmId = null;
        this.deleteConfirmName = null;

        deleteHospitalization({ hospitalizationId: recordId })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Hospitalization record deleted.',
                        variant: 'success'
                    })
                );
                refreshApex(this.wiredHospitalizationsResult);
            })
            .catch((error) => {
                const message = extractErrorMessage(error, 'Unable to delete hospitalization record.');
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message,
                        variant: 'error'
                    })
                );
            });
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