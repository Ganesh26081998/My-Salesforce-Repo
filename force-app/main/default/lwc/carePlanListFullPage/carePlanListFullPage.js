import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getCarePlans from '@salesforce/apex/CarePlanCaseController.getCarePlans';
import { refreshApex } from '@salesforce/apex';
import { deleteRecord,getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IS_DEACTIVATED_FIELD from '@salesforce/schema/Account.Is_Deactivated__c';

const COLUMNS = [
    {
        label: 'Care Plan Name',
        fieldName: 'Subject',
        type: 'text'
    },
    {
        label: 'Created By',
        fieldName: 'createdByName',
        type: 'text'
    },
    {
        label: 'Created Date',
        fieldName: 'CreatedDate',
        type: 'date'
    },
    {
        label: 'Last Modified By',
        fieldName: 'lastModifiedByName',
        type: 'text'
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

export default class CarePlanListFullPage extends LightningElement {
    columns = COLUMNS;
    carePlans = [];
    wiredResult;
    accountId;
    showDeleteModal = false;
    recordToDelete;
    showEditModal = false;
    selectedRecordId;
    selectedRecordTitle = '';
    isAccountDeactivated = false;

    // ⭐ Get Account ID from URL state
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.accountId = currentPageReference.state?.c__accountId;
            console.log('Account ID from URL:', this.accountId);
        }
    }

    // ⭐ Fetch Care Plans using the Account ID
    @wire(getCarePlans, { accountId: '$accountId' })
    wiredCarePlans(result) {
        this.wiredResult = result;
        console.log('Fetching care plans for account:', this.accountId);
        
        if (result.data) {
            this.carePlans = result.data.map(cp => ({
                ...cp,
                createdByName: cp.CreatedBy.Name,
                lastModifiedByName: cp.LastModifiedBy.Name
            }));
            console.log('Care Plans loaded:', this.carePlans);
        } else if (result.error) {
            console.error('Error fetching care plans:', result.error);
        }
    }
    @wire(getRecord, { recordId: '$accountId', fields: [IS_DEACTIVATED_FIELD] })
    wiredAccount({ data, error }) {
        if (data) {
            this.isAccountDeactivated = !!getFieldValue(data, IS_DEACTIVATED_FIELD);
        } else if (error) {
            this.isAccountDeactivated = false;
            console.error('Error fetching account deactivation flag:', error);
        }
    }

    showDeactivatedToast(actionLabel) {
    this.dispatchEvent(
        new ShowToastEvent({
            title: 'Not Allowed',
            message: `Account is deactivated. ${actionLabel} Care Plan is not allowed.`,
            variant: 'error'
        })
    );
}


    // Handle row actions (Edit/Delete)
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'delete') {
            if (this.isAccountDeactivated) {
            this.showDeactivatedToast('Deleting');
            return;
        }
            this.recordToDelete = row.Id;
            this.showDeleteModal = true;
        }

        if (actionName === 'edit') {
            if (this.isAccountDeactivated) {
            this.showDeactivatedToast('Editing');
            return;
        }
            this.selectedRecordId = row.Id;
            this.selectedRecordTitle = row.Subject;
            this.showEditModal = true;
        }
    }

    // Delete modal handlers
    closeModal() {
        this.showDeleteModal = false;
        this.recordToDelete = null;
    }

    confirmDelete() {
        deleteRecord(this.recordToDelete)
            .then(() => {
                this.showDeleteModal = false;
                this.recordToDelete = null;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Care Plan deleted successfully!',
                        variant: 'success'
                    })
                );

                return refreshApex(this.wiredResult);
            })
            .catch(error => {
                console.error('Delete failed', error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Failed to delete Care Plan',
                        variant: 'error'
                    })
                );
            });
    }

    // Edit modal handlers
    closeEditModal() {
        this.showEditModal = false;
        this.selectedRecordId = null;
    }

    handleEditClose() {
        this.showEditModal = false;
        this.selectedRecordId = null;
        // Refresh the list after edit
        refreshApex(this.wiredResult);
    }
}