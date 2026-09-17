import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord } from 'lightning/uiRecordApi';
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
    { label: 'Admission Date', fieldName: 'Admission_Date__c', type: 'date' },
    { label: 'Discharge Date', fieldName: 'Discharge_Date__c', type: 'date' },
    { label: 'Hospital', fieldName: 'Hospital_Name__c' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: ACTIONS,
            menuAlignment: 'auto'
        }
    }
];

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

    @wire(getHospitalizations, { accountId: '$recordId' })
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

    get hasHospitalizations() {
        return this.hospitalizations.length > 0;
    }

    get isModalOpen() {
        return !!this.selectedHospitalizationId;
    }

    get isEditModalOpen() {
        return !!this.editHospitalizationId;
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
            return;
        }

        if (actionName === 'delete') {
            this.handleDelete(row?.Id);
        }
    }

    closeModal() {
        this.selectedHospitalizationId = null;
        this.selectedHospitalizationName = null;
    }

    closeEditModal() {
        this.editHospitalizationId = null;
        this.editHospitalizationName = null;
    }

    handleEditSuccess() {
        this.closeEditModal();
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Hospitalization record updated.',
                variant: 'success'
            })
        );
        refreshApex(this.wiredHospitalizationsResult);
    }

    handleEditError(event) {
        const message = event?.detail?.detail || 'Unable to update hospitalization record.';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
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