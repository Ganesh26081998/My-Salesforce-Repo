import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import CLIENT_USER_OBJECT from '@salesforce/schema/Client_User_Detail__c';
import ROLE_FIELD from '@salesforce/schema/Client_User_Detail__c.Role__c';
import MARKETING_FIELD from '@salesforce/schema/Client_User_Detail__c.Marketing_Attribution__c';
import getClientUsers from '@salesforce/apex/ClientAccountTeamController.getClientUsers';
import searchInternalUsers from '@salesforce/apex/ClientAccountTeamController.searchInternalUsers';
import saveClientUser from '@salesforce/apex/ClientAccountTeamController.saveClientUser';
import deleteClientUser from '@salesforce/apex/ClientAccountTeamController.deleteClientUser';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';

export default class ClientAccountTeamModal extends LightningModal {
    @api accountId;
    users = [];
    existingInternalUsers = [];
    existingExternalUsers = [];

    searchResults = [];
    roleOptions = [];    
    marketingOptions = [];
    recordTypeId;
    isSaving = false; 
    
    selectedUserId = null;
    selectedUserName = '';    
    internalRole = null;
    internalMarketing = null;
    showExternalForm = false;
    externalName = '';
    externalEmail = '';
    externalPhone = '';
    externalRole = null;
    externalMarketing = null;
    
    searchTimeout;
    isLoading = false;

    isEditMode = false;
    editRecordId = null;



  columns = [
        { label: 'Name', fieldName: 'name' },
        { label: 'Email', fieldName: 'email' },
        { label: 'Phone', fieldName: 'phone' },
        { label: 'Role', fieldName: 'role' },
        { label: 'Marketing Attribution', fieldName: 'marketing' },
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

    @wire(getClientUsers, { accountId: '$accountId' })
    wiredExisting({ data, error }) {
        if (data) {
            this.users = data;
            this.existingInternalUsers = data[0];
            this.existingExternalUsers = data[1];            
        } else if (error) {
            this.showToast('Error', 'Failed to load users', 'error');
        }
    }

    @wire(getObjectInfo, { objectApiName: CLIENT_USER_OBJECT })
    objectInfo({ data }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: ROLE_FIELD })
    wiredRoles({ data }) {
        if (data) {
            this.roleOptions = data.values;
        }
    }
    
    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: MARKETING_FIELD })
    wiredMarketing({ data }) { 
        if (data) {
            this.marketingOptions = data.values;
        }
    }
    get hasSearchResults() {
        return this.searchResults && this.searchResults.length > 0;
    }

    get isInternalUserSelected() {
        return this.selectedUserId != null;
    }

    get isSaveDisabled() {
        
        if (this.isInternalUserSelected) {
            return false
        }
        
        if (this.showExternalForm) {
            return !this.externalName;
        }
        return true;
    }

    get hasTeamMembers() {
        return  (
            (this.existingInternalUsers?.length > 0) ||
            (this.existingExternalUsers?.length > 0)
        );
    }

    get showNoResultsMessage() {
        return this.searchKey && this.searchResults.length === 0;
    }



    get tableData() {
    const internal = (this.existingInternalUsers || []).map(u => ({
        Id: u.Id,
        name: u.External_User_Name__c,
        email: u.User__r?.Email,
        phone: u.User__r?.Phone,
        role: u.Role__c,
        marketing: u.Marketing_Attribution__c
    }));

    const external = (this.existingExternalUsers || []).map(u => ({
        Id: u.Id,
        name: u.External_User_Name__c,
        email: u.External_User_Email__c,
        phone: u.External_User_Phone__c,
        role: u.Role__c,
        marketing: u.Marketing_Attribution__c
    }));

        return [...internal, ...external];
    }
    
    handleSearchChange(event) {
        const searchKey = event.target.value;
        clearTimeout(this.searchTimeout);

        this.searchTimeout = setTimeout(() => {
            if (searchKey && searchKey.length >= 1) {
                this.performSearch(searchKey);
            } else {
                this.searchResults = [];
            }
        }, 300);
    }

   handleRoleChange(event) {
        if (this.showExternalForm) {
            this.externalRole = event.detail.value;
        } else {
            this.internalRole = event.detail.value;
        }
    }
     handleMarketingChange(event) { 
        const value = event.detail.value;
        if (this.showExternalForm) {
            this.externalMarketing = value;
        } else {
            this.internalMarketing = value;
        }
    }


    performSearch(searchKey) {
        this.isLoading = true;
        searchInternalUsers({ searchKey })
            .then(data => {
                const existingUserIds = this.users
                    .filter(u => u.User__c)
                    .map(u => u.User__c);

                this.searchResults = data.filter(u => !existingUserIds.includes(u.Id));
            })
            .catch(error => {
                this.showToast('Error', 'Search failed', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSelectInternalUser(event) {
        this.selectedUserId = event.currentTarget.dataset.id;
        this.selectedUserName = event.currentTarget.dataset.name;
        this.searchResults = [];
        
        this.showExternalForm = false;
        this.externalRole = null;
        this.externalMarketing = null;
        this.clearExternalForm();
    }

    handleClearInternalSelection() {
        this.selectedUserId = null;
        this.selectedUserName = '';
        this.internalRole  = null;
        this.internalMarketing = null;
    }
    
    handleAddExternalUser() {
        this.showExternalForm = true;
        
        this.selectedUserId = null;
        this.selectedUserName = '';
        this.internalRole = null;
        this.internalMarketing = null;
        this.searchResults = [];

    }

    handleCancelExternalForm() {
        this.showExternalForm = false;
        this.clearExternalForm();
        this.externalRole = null;
        this.externalMarketing = null;
    }

    handleExternalNameChange(event) {
        this.externalName = event.target.value;
        event.target.setCustomValidity('');
    }

    

    handleExternalEmailChange(event) {
        this.externalEmail = event.target.value;

        const email = (this.externalEmail || '').trim();
        const emailRegex = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i;

        let msg = '';
        if (email && !emailRegex.test(email)) {
            msg = 'Please enter a valid email address (example: name@domain.com)';
        }

        event.target.setCustomValidity(msg);
        event.target.reportValidity();
    }

    handleExternalPhoneChange(event) {
        this.externalPhone = event.target.value;

        const phone = (this.externalPhone || '').trim();
        const phoneRegex = /^[0-9]{10}$/;

        let msg = '';
        if (phone && !phoneRegex.test(phone)) {
            msg = 'Please enter a valid 10-digit phone number (e.g., 1234567890)';
        }

        event.target.setCustomValidity(msg);
        event.target.reportValidity();
    }


    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'delete') {
            
            this.handleDelete({
                currentTarget: {
                    dataset: { id: row.Id }
                }
            });
        }

        if (actionName === 'edit') {
            this.handleEditRow(row);
        }
    }


    handleEditRow(row) {
        const record = [...this.existingInternalUsers, ...this.existingExternalUsers]
            .find(u => u.Id === row.Id);

        this.isEditMode = true;
        this.editRecordId = row.Id;

        if (record.User__c) {
        
            this.selectedUserId = record.User__c;
            this.selectedUserName = record.External_User_Name__c;
            this.internalRole = record.Role__c;
            this.internalMarketing = record.Marketing_Attribution__c;
            this.showExternalForm = false;

        } else {
        
            this.showExternalForm = true;
            this.externalName = record.External_User_Name__c;
            this.externalEmail = record.External_User_Email__c;
            this.externalPhone = record.External_User_Phone__c;
            this.externalRole = record.Role__c;
            this.externalMarketing = record.Marketing_Attribution__c;
        }
    }



    
    clearExternalForm() {
        this.externalName = '';
        this.externalEmail = '';
        this.externalPhone = '';
    }

    getExternalInput(field) {
        return this.template.querySelector(`.external-form lightning-input[data-field="${field}"]`);
    }

    validateExternalForm() {
        let isValid = true;

        const nameEl  = this.getExternalInput('externalName');
        const emailEl = this.getExternalInput('externalEmail');
        const phoneEl = this.getExternalInput('externalPhone');

       
        if (nameEl) {
            nameEl.setCustomValidity(this.externalName?.trim() ? '' : 'Name is required');
            if (!nameEl.reportValidity()) isValid = false;
        }

        
        if (emailEl) {
            const email = (this.externalEmail || '').trim();
            const emailRegex = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i;

            let msg = '';
            if (email && !emailRegex.test(email)) {
                msg = 'Please enter a valid email address (example: name@domain.com)';
            }
            emailEl.setCustomValidity(msg);
            if (!emailEl.reportValidity()) isValid = false;
        }

        
        if (phoneEl) {
            const phone = (this.externalPhone || '').trim();
            const phoneRegex = /^[0-9]{10}$/;

            let msg = '';
            if (phone && !phoneRegex.test(phone)) {
                msg = 'Please enter a valid 10-digit phone number (e.g., 1234567890)';
            }
            phoneEl.setCustomValidity(msg);
            if (!phoneEl.reportValidity()) isValid = false;
        }

        return isValid;
    }

    
    async handleSave() {
    if (this.isSaving) return;

    
    if (this.showExternalForm && !this.validateExternalForm()) {
        return;
    }

    this.isSaving = true;

    try {
        if (this.isInternalUserSelected) {
            await saveClientUser({
                clientId: this.accountId,
                userId: this.selectedUserId,
                role: this.internalRole,
                marketingAttribution: this.internalMarketing,
                externalName: null,
                externalEmail: null,
                externalPhone: null,
                recordId: this.editRecordId
            });
            
                    const message = this.editRecordId
                    ? 'Internal user updated successfully'
                    : 'Internal user added successfully';

                this.showToast('Success', message, 'success');
        } else if (this.showExternalForm) {
            await saveClientUser({
                clientId: this.accountId,
                userId: null,
                role: this.externalRole,
                marketingAttribution: this.externalMarketing,
                externalName: this.externalName,
                externalEmail: this.externalEmail,
                externalPhone: this.externalPhone,
                recordId: this.editRecordId
            });
            

            const message = this.editRecordId
                ? 'External user updated successfully'
                : 'External user added successfully';

            this.showToast('Success', message, 'success');
        }

        this.close('refresh');

    } catch (error) {
        this.showToast('Error', error?.body?.message || 'Failed to save', 'error');
    } finally {
        this.isSaving = false;
    }
}
    
    async handleDelete(event) {
        const recordId = event.currentTarget.dataset.id;

        const confirmed = await LightningConfirm.open({
        message: 'Are you sure you want to remove this team member?',
        label: 'Confirm Deletion',
        theme: 'warning'
    });

    if (!confirmed) {
        return; 
    }
        this.isSaving = true;

        try {
            await deleteClientUser({ recordId });
            this.users = this.users.filter(u => u.Id !== recordId);
            this.existingInternalUsers = this.existingInternalUsers.filter(u => u.Id !== recordId);
            this.existingExternalUsers = this.existingExternalUsers.filter(u => u.Id !== recordId);
            this.showToast('Success', 'User removed successfully', 'success');
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to delete user', 'error');
        } finally {        
        this.isSaving = false;
        }
    }

    async loadTeamMembers() {
        const result = await getClientUsers({ accountId: this.accountId });
        this.internalUsers = result[0];
        this.externalUsers = result[1];

        
        this.teamMembers = [...this.internalUsers, ...this.externalUsers];
    }

    handleClose() {
        this.close('refresh');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}