import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord, updateRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getHospitalizations from '@salesforce/apex/WellSpringHospitalizationController.getHospitalizations';

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

const norm = (v) => (v || '').toString().toLowerCase().replace(/[^a-z0-9]/g, '');
const isBlank = (v) => v === null || v === undefined || (typeof v === 'string' && v.trim() === '');
const hasDigit = (v) => /\d/.test(v || '');

export default class WellSpringPatientHospitalizations extends LightningElement {
    @api recordId;

    hospitalizations = [];
    columns = COLUMNS;
    selectedHospitalizationId = null;
    selectedHospitalizationName = null;
    editHospitalizationId = null;
    editHospitalizationName = null;
    loadError = null;
    wiredHospitalizationsResult;

    // Edit form tracked values
    editStatus = null;
    editAdmissionType = null;
    editAdmissionDate = null;
    editHospitalName = null;
    editPrimaryDiag = null;
    editDischargeDate = null;
    editRole = null;
    editReason = null;
    editIsSaving = false;

    // Edit form error messages
    errEditStatus = null;
    errEditAdmissionType = null;
    errEditAdmissionDate = null;
    errEditHospitalName = null;
    errEditPrimaryDiag = null;
    errEditDischargeDate = null;
    errEditRole = null;
    errEditReason = null;

   /* @wire(getHospitalizations, { accountId: '$recordId' })
    wiredHospitalizations(result) {
        this.wiredHospitalizationsResult = result;
        const { data, error } = result;
        if (data) {
            this.hospitalizations = data;
            this.loadError = null;
        } else if (error) {
            this.hospitalizations = [];
            this.loadError = 'Unable to load hospitalization records.';
            // eslint-disable-next-line no-console
            console.error('wiredHospitalizations error:', JSON.stringify(error));
        }
    }
*/

@wire(getHospitalizations, { accountId: '$recordId' })
wiredHospitalizations(result) {
    this.wiredHospitalizationsResult = result;
    const { data, error } = result;
   if (data) {
    console.log('Raw date value:', data[0]?.Admission_Date__c); // ADD THIS
    this.hospitalizations = data.map(record => ({
            ...record,
            Admission_Date__c: this.formatDate(record.Admission_Date__c),
            Discharge_Date__c: this.formatDate(record.Discharge_Date__c)
        }));
        this.loadError = null;
    } else if (error) {
        this.hospitalizations = [];
        this.loadError = 'Unable to load hospitalization records.';
        console.error('wiredHospitalizations error:', JSON.stringify(error));
    }
}

formatDate(dateStr) {
    if (!dateStr) return null;
    const [year, month, day] = dateStr.split('-');
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return `${months[parseInt(month, 10) - 1]} ${parseInt(day, 10)}, ${year}`;
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

    // CSS class getters for edit form error highlighting
    get editStatusClass() { return this.errEditStatus ? 'fielderr' : ''; }
    get editAdmTypeClass() { return this.errEditAdmissionType ? 'fielderr' : ''; }
    get editAdmDateClass() { return this.errEditAdmissionDate ? 'fielderr' : ''; }
    get editHospitalNameClass() { return this.errEditHospitalName ? 'fielderr' : ''; }
    get editPrimaryDiagClass() { return this.errEditPrimaryDiag ? 'fielderr' : ''; }
    get editDischDateClass() { return this.errEditDischargeDate ? 'fielderr' : ''; }
    get editRoleClass() { return this.errEditRole ? 'fielderr' : ''; }
    get editReasonClass() { return this.errEditReason ? 'fielderr' : ''; }

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
            // Seed status from row so discharge date disabled state is correct on open
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
            this.handleDelete(row?.Id);
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

    // Edit form change handlers
    handleEditStatusChange(e) {
        this.editStatus = e.detail?.value ?? null;
        this.errEditStatus = null;
        if (!norm(this.editStatus).includes('discharged')) {
            this.editDischargeDate = null;
            this.errEditDischargeDate = null;
        }
    }
    handleEditAdmissionTypeChange(e) {
        this.editAdmissionType = e.detail?.value ?? null;
        this.errEditAdmissionType = null;
    }
    handleEditAdmissionDateChange(e) {
        this.editAdmissionDate = e.detail?.value ?? null;
        this.errEditAdmissionDate = null;
    }
    handleEditHospitalNameChange(e) {
        this.editHospitalName = e.detail?.value ?? null;
        this.errEditHospitalName = null;
    }
    handleEditPrimaryDiagChange(e) {
        this.editPrimaryDiag = e.detail?.value ?? null;
        this.errEditPrimaryDiag = null;
    }
    handleEditDischargeDateChange(e) {
        this.editDischargeDate = e.detail?.value ?? null;
        this.errEditDischargeDate = null;
    }
    handleEditRoleChange(e) {
        this.editRole = e.detail?.value ?? null;
        this.errEditRole = null;
    }
    handleEditReasonChange(e) {
        this.editReason = e.detail?.value ?? null;
        this.errEditReason = null;
    }

    // Fires when lightning-record-edit-form loads the record â€” captures pre-populated values
    // so validation works on fields the user has NOT explicitly changed yet.
    handleEditLoad(event) {
        const records = event?.detail?.records;
        if (!records) return;
        const record = records[this.editHospitalizationId];
        if (!record) return;
        const f = record.fields;
        if (f.Hospitalization_Status__c !== undefined) this.editStatus = f.Hospitalization_Status__c.value || null;
        if (f.Admission_Type__c !== undefined)         this.editAdmissionType = f.Admission_Type__c.value || null;
        if (f.Admission_Date__c !== undefined)         this.editAdmissionDate = f.Admission_Date__c.value || null;
        if (f.Hospital_Name__c !== undefined)          this.editHospitalName = f.Hospital_Name__c.value || null;
        if (f.Primary_diagnosis__c !== undefined)      this.editPrimaryDiag = f.Primary_diagnosis__c.value || null;
        if (f.Discharge_Date__c !== undefined)         this.editDischargeDate = f.Discharge_Date__c.value || null;
        if (f.Role_during_hospitalization__c !== undefined) this.editRole = f.Role_during_hospitalization__c.value || null;
        if (f.Reason_for_admission__c !== undefined)   this.editReason = f.Reason_for_admission__c.value || null;
    }

    readEditFieldValue(fieldName) {
        return this.template.querySelector(`lightning-input-field[field-name="${fieldName}"]`)?.value;
    }

    syncEditFormValues() {
        // Read current DOM values â€” lightning-record-edit-form pre-populates from the record,
        // so unchanged fields still carry their original values here.
        const s = this.readEditFieldValue('Hospitalization_Status__c');
        if (s !== undefined) this.editStatus = s || null;

        const at = this.readEditFieldValue('Admission_Type__c');
        if (at !== undefined) this.editAdmissionType = at || null;

        const ad = this.readEditFieldValue('Admission_Date__c');
        if (ad !== undefined) this.editAdmissionDate = ad || null;

        const hn = this.readEditFieldValue('Hospital_Name__c');
        if (hn !== undefined) this.editHospitalName = hn || null;

        const pd = this.readEditFieldValue('Primary_diagnosis__c');
        if (pd !== undefined) this.editPrimaryDiag = pd || null;

        const dd = this.readEditFieldValue('Discharge_Date__c');
        if (dd !== undefined) this.editDischargeDate = dd || null;

        const r = this.readEditFieldValue('Role_during_hospitalization__c');
        if (r !== undefined) this.editRole = r || null;

        const re = this.readEditFieldValue('Reason_for_admission__c');
        if (re !== undefined) this.editReason = re || null;
    }

    handleEditSave() {
        this.clearEditErrors();
        this.syncEditFormValues();

        const normStatus = norm(this.editStatus);
        let hasErrors = false;

        if (isBlank(this.editStatus)) {
            this.errEditStatus = 'Hospitalization Status is required.';
            hasErrors = true;
        }

        if (normStatus.includes('hospitalized')) {
            // Discharge date must be cleared when status is Open - Hospitalized
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

        // Alpha-only also applies when status is Closed - Discharged
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
            if (isBlank(this.editRole)) {
                this.errEditRole = 'Role During Hospitalization is required.';
                hasErrors = true;
            }
            if (!this.errEditReason && isBlank(this.editReason)) {
                this.errEditReason = 'Reason for Admission is required.';
                hasErrors = true;
            }
        }

        if (this.editAdmissionDate && this.editDischargeDate &&
            new Date(this.editDischargeDate) < new Date(this.editAdmissionDate)) {
            this.errEditDischargeDate = 'Discharge Date must be on or after Admission Date.';
            hasErrors = true;
        }

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
            .catch((err) => {
                this.editIsSaving = false;
                const message = err?.body?.output?.errors?.[0]?.message || err?.body?.message || 'Unable to update hospitalization record.';
                // eslint-disable-next-line no-console
                console.error('updateRecord error:', JSON.stringify(err));
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message,
                        variant: 'error'
                    })
                );
            });
    }

    handleDelete(recordId) {
        if (!recordId) {
            return;
        }
        // eslint-disable-next-line no-alert
        const confirmed = confirm('Are you sure you want to delete this hospitalization record?');
        if (!confirmed) {
            return;
        }

        deleteRecord(recordId)
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
                const message = error?.body?.message || 'Unable to delete hospitalization record.';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message,
                        variant: 'error'
                    })
                );
            });
    }
}