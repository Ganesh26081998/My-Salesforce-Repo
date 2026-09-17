import LightningModal from 'lightning/modal';
import { api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createCallerCCR   from '@salesforce/apex/PatientContactRelationshipController.createCallerCCR';
import createPatientCCR  from '@salesforce/apex/PatientContactRelationshipController.createPatientCCR';
import createBusinessCCR from '@salesforce/apex/PatientContactRelationshipController.createBusinessCCR';
import getHouseholdAccountForPerson from '@salesforce/apex/PatientContactRelationshipController.getHouseholdAccountForPerson';
import CONTACT_OBJECT    from '@salesforce/schema/Contact';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import CCR_OBJECT from '@salesforce/schema/HealthCloudGA__ContactContactRelation__c';
import { updateRecord, createRecord } from 'lightning/uiRecordApi';
import PREFERREED_NAME_FIELD      from '@salesforce/schema/Contact.Preferred_Name__c';
import PHONE_FIELD                from '@salesforce/schema/Contact.Phone';
import HOMEPHONE_FIELD            from '@salesforce/schema/Contact.HomePhone';
import EMAIL_FIELD                from '@salesforce/schema/Contact.Email';
import MOBILEPHONE_FIELD          from '@salesforce/schema/Contact.MobilePhone';
import BIRTHDATE_FIELD            from '@salesforce/schema/Contact.Birthdate';
import TITLE_FIELD                from '@salesforce/schema/Contact.Title';
import METHOD_OF_OUTREACH_FIELD   from '@salesforce/schema/Contact.Method_of_Outreach__c';
import BEST_WAY_TO_CONTACT_FIELD  from '@salesforce/schema/Contact.Best_way_to_contact__c';
import hasExistingReferralCCR from '@salesforce/apex/PatientContactRelationshipController.hasExistingReferralCCR';

import BusinessAccountCreate from 'c/createBusinessAccount';

export default class PatientContactRelationshipModal extends LightningModal {

    @api recordId;
    @track isLoadingForNewBusiness = false;
    @track activeTab          = 'caller';
    @track isLoadingForCaller = true;
    @track isSaving           = false;
    @track defaultAccountId;

    @track recordTypeId;
    hasLoadedHousehold = false;

    @track selectedPatientId;
    @track selectedRoleId;

    @track selectedBusinessContactId;
    @track selectedRoleOfBusinessId;

    @track businessMode = 'existing';
    @track newBusinessContactId;
    @track businessRecordTypeId;
    @track showAccountCreate = false;

    whatTheyWantToKnow;
    howTheyPreferToCommunicate;
    howOftenTheyPreferUpdates;

    showOtherWhatToKnow = false;
    showOtherHowCommunicate = false;
    showOtherHowOften = false;

    @track createBusinessWithoutAccount = false;
    @track disableBusinessAccount = false;
    @track showBusinessAccountError = false;

    @track street = "";
    @track city = "";
    @track state = "";
    @track postalCode = "";
    @track country = "";
    @track stateCode = "";
    @track countryCode = "";
    @track bstreet = "";
    @track bcity = "";
    @track bstate = "";
    @track bpostalCode = "";
    @track bcountry = "";
    @track bstateCode = "";
    @track bcountryCode = "";

    @track selectedBusinessType = '';
    @track newBusinessType = '';

    @track createAsCaller = false;

    @track relationshipToClient = '';
    @track familyRelationship = '';
    @track otherRelationshipToClient = '';

    @track showFamilyRelationship = false;
    @track showOtherRelationship = false;

    @track ccrRecordTypeId;
    @track relationshipToClientOptions = [];
    @track familyRelationshipOptions = [];

    familyRelationshipAllValues = [];
    familyRelationshipControllerValues = {};

    @track familyMode = 'new';
    @track selectedExistingFamilyContactId;

    @track isReferral = false;

    @track newBusinessContactCreatedId = null;
    @track newFamilyContactCreatedId = null;

    @track showDuplicateWarning = false;
    @track pendingDuplicateFields = null;
    @track pendingDuplicateContext = null;

    @track selectedBusinessAccountId;

    leftFields  = [PREFERREED_NAME_FIELD, TITLE_FIELD];
    rightFields = [PHONE_FIELD, HOMEPHONE_FIELD, MOBILEPHONE_FIELD, EMAIL_FIELD, BIRTHDATE_FIELD, METHOD_OF_OUTREACH_FIELD, BEST_WAY_TO_CONTACT_FIELD];

    @wire(getObjectInfo, { objectApiName: CONTACT_OBJECT })
    objectInfo({ data, error }) {
        if (data) {
            const rtInfos = data.recordTypeInfos;
            for (let rtId in rtInfos) {
                if (rtInfos[rtId].name === 'Family Contact') {
                    this.recordTypeId = rtId;
                }
                if (rtInfos[rtId].name === 'Business') {
                    this.businessRecordTypeId = rtId;
                   
                }
            }
        }
        
    }

    @wire(getObjectInfo, { objectApiName: CCR_OBJECT })
    ccrObjectInfo({ data, error }) {
        if (data) {
            this.ccrRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
        
        }
    }

    @wire(getPicklistValuesByRecordType, {
        objectApiName: CCR_OBJECT,
        recordTypeId: '$ccrRecordTypeId'
    })
    wiredCcrPicklists({ data, error }) {
        if (data) {
            const relationshipField = data.picklistFieldValues.Relationship_to_Client__c;
            const familyField = data.picklistFieldValues.Family_Relationship__c;
            
            this.relationshipToClientOptions = relationshipField.values.map(item => ({
                label: item.label,
                value: item.value
            }));
            this.familyRelationshipAllValues = familyField.values;
            this.familyRelationshipControllerValues = familyField.controllerValues || {};
        } else if (error) {
        
        }
    }

    connectedCallback() {
        if (this.hasLoadedHousehold || !this.recordId) {
            return;
        }
        this.hasLoadedHousehold = true;
        this.loadHouseholdAccount();
    }

    loadHouseholdAccount() {
        getHouseholdAccountForPerson({ personAccountId: this.recordId })
            .then(accId => {
                this.defaultAccountId = accId;                
            })
            .catch(error => {
               
            });
    }

    get personAccountFilter() {
        return {
            criteria: [
                { fieldPath: 'IsPersonAccount', operator: 'eq', value: true },
                { fieldPath: 'Id', operator: 'ne', value: this.recordId }
            ]
        };
    }

    get businessContactFilter() {
        return { criteria: [{ fieldPath: 'RecordType.DeveloperName', operator: 'eq', value: 'IndustriesBusiness' }] };
    }

    get businessModeOptions() {
        return [
            { label: 'Select Existing', value: 'existing' },
            { label: 'Create New', value: 'new' }
        ];
    }

    get businessAccountFilter() {
    return {
        criteria: [
            {
                fieldPath: 'RecordType.DeveloperName',
                operator: 'eq',
                value: 'Business_Account'
            }
        ]
    };
    }

    get isExistingBusiness() {
        return this.businessMode === 'existing';
    }

    get isNewBusiness() {
        return this.businessMode === 'new';
    }

    get familyModeOptions() {
        return [
            { label: 'Select Existing', value: 'existing' },
            { label: 'Create New', value: 'new' }
        ];
    }

    get isExistingFamily() {
        return this.familyMode === 'existing';
    }

    get isNewFamily() {
        return this.familyMode === 'new';
    }

    get familyContactFilter() {
        return {
            criteria: [
                { fieldPath: 'RecordType.Name', operator: 'eq', value: 'Family Contact' }
            ]
        };
    }

    getCallerRoleName() {
        if (this.relationshipToClient === 'Family') {
            return this.familyRelationship;
        }
        if (this.relationshipToClient === 'Friend/Neighbor') {
            return 'Friend/Neighbor';
        }
        if (this.relationshipToClient === 'Other') {
            return 'Other';
        }
        return '';
    }

    startSaving() {
        if (this.isSaving) return false;
        this.isSaving = true;
        return true;
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
        this.newBusinessContactCreatedId = null;
        this.newFamilyContactCreatedId = null;
    }

    handleLoad() {
        this.isLoadingForCaller = false;
    }

    handleIsReferralChange(event) {
        this.isReferral = event.target.checked;
    }

    handleBusinessAccountChange(event) {
        this.selectedBusinessAccountId = event.detail.recordId;
    }

    handleBusinessModeChange(event) {
        this.businessMode = event.detail.value;
        this.newBusinessContactCreatedId = null;

        this.selectedBusinessContactId = null;
        this.newBusinessContactId = null;
        this.selectedBusinessType = '';
        this.isReferral = false;
        this.newBusinessContactCreatedId = null;

        this.isLoadingForNewBusiness = (this.businessMode === 'new');
    }

    handleFamilyModeChange(event) {
        this.familyMode = event.detail.value;
        this.selectedExistingFamilyContactId = null;

        this.relationshipToClient = '';
        this.familyRelationship = '';
        this.otherRelationshipToClient = '';
        this.showFamilyRelationship = false;
        this.showOtherRelationship = false;
        this.familyRelationshipOptions = [];
        this.newFamilyContactCreatedId = null;
    }

    handleExistingFamilyContactChange(event) {
        this.selectedExistingFamilyContactId = event.detail.recordId;

        const picker = this.template.querySelector(
            'lightning-record-picker[data-id="existingFamilyContact"]'
        );

        if (picker) {
            picker.setCustomValidity(this.selectedExistingFamilyContactId ? '' : 'Please select Family Contact');
            picker.reportValidity();
        }
    }

    handleCreateAsCallerToggle(event) {
        this.createAsCaller = event.target.checked;
    }

    handleRelationshipToClientChange(event) {
        this.relationshipToClient = event.detail.value;
        this.showFamilyRelationship = this.relationshipToClient === 'Family';
        this.showOtherRelationship = this.relationshipToClient === 'Other';

        this.familyRelationship = '';
        this.otherRelationshipToClient = '';
        this.familyRelationshipOptions = [];

        if (this.showFamilyRelationship) {
            const controllerKey =
                this.familyRelationshipControllerValues[this.relationshipToClient];

            this.familyRelationshipOptions = this.familyRelationshipAllValues
                .filter(option => option.validFor.includes(controllerKey))
                .map(option => ({
                    label: option.label,
                    value: option.value
                }));
        }
    }

    handleFamilyRelationshipChange(event) {
        this.familyRelationship = event.detail.value;
    }

    handleOtherRelationshipChange(event) {
        this.otherRelationshipToClient = event.target.value;
    }

    validateCallerRelationship() {
        let isValid = true;

        const relationshipField = this.template.querySelector(
            'lightning-combobox[data-id="relationshipToClient"]'
        );

        if (!this.relationshipToClient) {
            relationshipField?.reportValidity();
            isValid = false;
        }

        if (this.relationshipToClient === 'Family') {
            const familyField = this.template.querySelector(
                'lightning-combobox[data-id="familyRelationship"]'
            );
            if (!this.familyRelationship) {
                familyField?.reportValidity();
                isValid = false;
            }
        }

        if (this.relationshipToClient === 'Other') {
            const otherField = this.template.querySelector(
                'lightning-input[data-id="otherRelationshipToClient"]'
            );
            if (!this.otherRelationshipToClient?.trim()) {
                otherField?.reportValidity();
                isValid = false;
            }
        }

        return isValid;
    }

    validateCallerFormFields() {
        const form = this.template.querySelector('lightning-record-edit-form[data-id="callerForm"]');
        if (!form) return false;

        return [...form.querySelectorAll('lightning-input-field')]
            .reduce((valid, field) => valid && field.reportValidity(), true);
    }

    handlePatientChange(event) {
        this.selectedPatientId = event.detail.recordId;

        const picker = this.template.querySelector(
            'lightning-record-picker[data-id="patientAccount"]'
        );

        if (!picker) return;

        if (!this.selectedPatientId) {
            picker.setCustomValidity('Couple Household is required');
        } else if (this.selectedPatientId === this.recordId) {
            picker.setCustomValidity('You cannot relate a patient to itself.');
            this.selectedPatientId = null;
        } else {
            picker.setCustomValidity('');
        }

        picker.reportValidity();
    }

    handleRoleChange(event) {
        this.selectedRoleId = event.detail.value;

        const field = this.template.querySelector(
            'lightning-input-field[data-id="patientRoleField"]'
        );
        if (field) {
            field.reportValidity();
        }
    }

    handleAddressChange(event) {
        const detail = event.detail || {};
        const target = event.target || {};
        this.street      = detail.street       || target.street       || "";
        this.city        = detail.city         || target.city         || "";
        this.state       = detail.province     || target.province     || "";
        this.postalCode  = detail.postalCode   || target.postalCode   || "";
        this.country     = detail.country      || target.country      || "";
        this.stateCode   = detail.provinceCode || target.provinceCode || "";
        this.countryCode = detail.countryCode  || target.countryCode  || "";
    }

    bhandleAddressChange(event) {
        const detail = event.detail || {};
        const target = event.target || {};
        this.bstreet      = detail.street       || target.street       || "";
        this.bcity        = detail.city         || target.city         || "";
        this.bstate       = detail.province     || target.province     || "";
        this.bpostalCode  = detail.postalCode   || target.postalCode   || "";
        this.bcountry     = detail.country      || target.country      || "";
        this.bstateCode   = detail.provinceCode || target.provinceCode || "";
        this.bcountryCode = detail.countryCode  || target.countryCode  || "";
    }

    bapplyCallerAddressToFields(fields) {

    const addressInput = this.template.querySelector('lightning-input-address[data-id="businessAddress"]');

    const street      = addressInput?.street       || this.bstreet;
    const city        = addressInput?.city         || this.bcity;
    const state       = addressInput?.province     || this.bstate;
    const country     = addressInput?.country      || this.bcountry;
    let stateCode     = addressInput?.provinceCode || this.bstateCode;
    let countryCode   = addressInput?.countryCode  || this.bcountryCode;
    const postalCode  = (addressInput?.postalCode  || this.bpostalCode || '').toString().trim();

    if (!stateCode && state && state.length === 2) {
        stateCode = state.toUpperCase();
    }
    if (!countryCode && country && country.length === 2) {
        countryCode = country.toUpperCase();
    }

    fields.Address__Street__s     = street;
    fields.Address__City__s       = city;
    fields.Address__PostalCode__s = postalCode;
    //if (stateCode)   { fields.Address__StateCode__s   = stateCode; }  
    //if (countryCode) { fields.Address__CountryCode__s = countryCode; }

    
    }



    applyCallerAddressToFields(fields) {
    
    const addressInput = this.template.querySelector('lightning-input-address[data-id="callerAddress"]');
    
    const street      = addressInput?.street       || this.bstreet;
    const city        = addressInput?.city         || this.bcity;
    const state       = addressInput?.province     || this.bstate;
    const country     = addressInput?.country      || this.bcountry;
    let stateCode     = addressInput?.provinceCode || this.bstateCode;
    let countryCode   = addressInput?.countryCode  || this.bcountryCode;
    const postalCode  = (addressInput?.postalCode  || this.bpostalCode || '').toString().trim();

    if (!stateCode && state && state.length === 2) {
        stateCode = state.toUpperCase();
    }
    if (!countryCode && country && country.length === 2) {
        countryCode = country.toUpperCase();
    }

        fields.Address__Street__s     = street;
        fields.Address__City__s       = city;
        fields.Address__PostalCode__s = postalCode;
        //if (stateCode)   { fields.Address__StateCode__s   = stateCode; }   
        //if (countryCode) { fields.Address__CountryCode__s = countryCode; } 

    }

  
    handleBusinessContactChange(event) {
        this.selectedBusinessContactId = event.detail.recordId;
        this.selectedBusinessType = '';
        this.isReferral = false;
    }

    handleExistingBusinessTypeChange(event) {
        this.selectedBusinessType = event.detail.value || '';
    }

    handleBusinessRoleChange(event) {
        this.selectedRoleOfBusinessId = event.detail.recordId;
        const picker = this.template.querySelector('lightning-record-picker[data-id="businessRole"]');
        if (picker) {
            picker.setCustomValidity(this.selectedRoleOfBusinessId ? '' : 'Role is required');
            picker.reportValidity();
        }
    }

    handlePicklistChange(event) {
        const field = event.target.fieldName;
        const value = event.detail.value;

        if (field === 'WhatTheyWantToKnow__c') {
            this.showOtherWhatToKnow = value === 'Other';
        }
        if (field === 'HowTheyPreferToCommunicate__c') {
            this.showOtherHowCommunicate = value === 'Other';
        }
        if (field === 'HowOftenTheyPreferToReceiveUpdates__c') {
            this.showOtherHowOften = value === 'Other';
        }
    }

    handleBusinessWithoutAccountToggle(event) {
        this.createBusinessWithoutAccount = event.target.checked;
        this.disableBusinessAccount = this.createBusinessWithoutAccount;
        this.showBusinessAccountError = false;

        if (this.createBusinessWithoutAccount) {
            const accountField = this.template.querySelector(
                'lightning-input-field[field-name="AccountId"]'
            );
            if (accountField) {
                accountField.value = null;
            }
        }
    }

    handleNewBusinessLoad() {
        this.isLoadingForNewBusiness = false;
    }

    handleNewBusinessModeChangeToNew() {
        this.isLoadingForNewBusiness = true;
    }

    handleCancel() {
        this.close();
    }

    handleSave() {
        if (this.activeTab === 'caller') {
        
            this.handleSaveCaller();
        } else if (this.activeTab === 'patient') {
            if (this.validatePatientTab()) this.handleSavePatient();
        } else if (this.activeTab === 'business') {
            this.handleSaveBusiness();
        }
    }

    handleSaveCaller() {
        if (this.isSaving) return;
        this.isSaving = true;

        const isRelationshipValid = this.validateCallerRelationship();

        if (this.isExistingFamily) {
            if (!this.selectedExistingFamilyContactId) {
                const picker = this.template.querySelector(
                    'lightning-record-picker[data-id="existingFamilyContact"]'
                );
                picker?.setCustomValidity('Please select Family Contact');
                picker?.reportValidity();

                this.isSaving = false;
                return;
            }

            if (!isRelationshipValid) {
                
                this.showToast('Error', 'Review all error messages before saving.', 'error');
                this.isSaving = false;
                return;
            }

            this.createExistingFamilyCCR();
            return;
        }

        if (this.newFamilyContactCreatedId) {
            const roleName = this.getCallerRoleName();
            createCallerCCR({
                callerContactId: this.newFamilyContactCreatedId,
                relatedAccountId: this.recordId,
                roleName: roleName,
                createAsCaller: this.createAsCaller,
                relationshipToClient: this.relationshipToClient,
                familyRelationship: this.familyRelationship,
                otherRelationshipToClient: this.otherRelationshipToClient
            })
            .then(() => {
                this.newFamilyContactCreatedId = null;
                this.showToast('Success', 'Family Relationship Created', 'success');
                this.close('saved');
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Failed to create relationship', 'error');
            })
            .finally(() => { this.isSaving = false; });
            return;
        }

        const isFormValid = this.validateCallerFormFields();

        if (!isFormValid || !isRelationshipValid) {
            
            this.showToast('Error', 'Review all error messages before saving.', 'error');
            this.isSaving = false;
            return;
        }

        const form = this.template.querySelector('lightning-record-edit-form[data-id="callerForm"]');

        if (form) {
            const fields = {};
            [...form.querySelectorAll('lightning-input-field')].forEach((field) => {
                if (field.fieldName) {
                    fields[field.fieldName] = field.value;
                }
            });

            this.applyCallerAddressToFields(fields);

            if (this.recordTypeId) {
                fields.RecordTypeId = this.recordTypeId;
            }

            this.pendingDuplicateFields = fields;
            this.pendingDuplicateContext = 'caller';
        
            createRecord({
                apiName: 'Contact',
                fields,
                allowSaveOnDuplicate: false
            })
            .then(record => {
                this.handleSuccess({ detail: { id: record.id } });
            })
            .catch(error => {
                
                this.handleError({ detail: error?.body || error });
            });
        } else {
            this.isSaving = false;
        }
    }

    createExistingFamilyCCR() {
        const roleName = this.getCallerRoleName();

        createCallerCCR({
            callerContactId: this.selectedExistingFamilyContactId,
            relatedAccountId: this.recordId,
            roleName: roleName,
            createAsCaller: this.createAsCaller,
            relationshipToClient: this.relationshipToClient,
            familyRelationship: this.familyRelationship,
            otherRelationshipToClient: this.otherRelationshipToClient
        })
        .then(() => {
            this.showToast('Success', 'Family Relationship Created', 'success');
            this.close('saved');
        })
        .catch(error => {
            
            this.showToast('Error', error.body?.message || 'Failed to create relationship', 'error');
        })
        .finally(() => {
            this.isSaving = false;
        });
    }

    validateFields() {
        return [...this.template.querySelectorAll('lightning-input-field')]
            .reduce((valid, field) => valid && field.reportValidity(), true);
    }

    validateNewBusinessFields() {
        const form = this.template.querySelector(
            'lightning-record-edit-form[data-id="newBusinessForm"]'
        );
        if (!form) return false;

        return [...form.querySelectorAll('lightning-input-field')]
            .reduce((valid, field) => valid && field.reportValidity(), true);
    }

    handleSubmit(event) {
        event.preventDefault();
        if (!this.validateFields() || !this.validateCallerRelationship()) {
            this.isSaving = false;
            return;
        }
        this.template.querySelector('lightning-record-edit-form').submit(event.detail.fields);
    }

    handleSuccess(event) {
        this.newFamilyContactCreatedId = event.detail.id;

        const roleName = this.getCallerRoleName();
        createCallerCCR({
            callerContactId  : event.detail.id,
            relatedAccountId : this.recordId,
            roleName: roleName,
            createAsCaller: this.createAsCaller,
            relationshipToClient: this.relationshipToClient,
            familyRelationship: this.familyRelationship,
            otherRelationshipToClient: this.otherRelationshipToClient
        })
        .then(() => {
            this.showToast('Success', 'Family Relationship Created', 'success');
            this.close('saved');
        })
        .catch(error => {
        
            this.showToast('Error', error.body?.message || 'Failed to create relationship', 'error');
        })
        .finally(() => { this.isSaving = false; });
    }

    handleError(event) {
        
        this.isSaving = false;
        this.isLoadingForNewBusiness = false;

        const detail = event.detail;
        

        const errors = detail?.output?.errors || detail?.errors || [];

        const duplicateError = event.detail?.output?.errors?.find(
            e => e.errorCode === 'DUPLICATES_DETECTED'
        );
        
        if (duplicateError) {
            this.showDuplicateWarning = true;
            return;
        }

        const fieldErrors = detail?.output?.fieldErrors || detail?.fieldErrors || {};
        if (Object.keys(fieldErrors).length > 0) {
            

             let messages = [];

        Object.keys(fieldErrors).forEach(field => {

            fieldErrors[field].forEach(err => {
                messages.push(err.message);
            });

        });

             this.dispatchEvent(
            new ShowToastEvent({
                title: 'Validation Error',
                message: messages.join(', '),
                variant: 'error'
            })
        );

        return;
    

        }

        const message = event.detail?.output?.errors?.[0]?.message
                     || event.detail?.message
                     || 'Something went wrong';
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error Creating Contact',
            message,
            variant: 'error'
        }));
    }

    handleSavePatient() {
        if (this.isSaving) return;
        this.isSaving = true;

        const roleField = this.template.querySelector(
            'lightning-input-field[data-id="patientRoleField"]'
        );
        this.selectedRoleId = roleField?.value;

        createPatientCCR({
            patientAccountId : this.selectedPatientId,
            relatedAccountId : this.recordId,
            roleId           : this.selectedRoleId
        })
        .then(() => {
            this.showToast('Success', 'Couple Household Relationship Created', 'success');
            this.close('saved');
        })
        .catch(error => {
        
            this.showToast('Error', error.body?.message || 'Failed to create relationship', 'error');
        })
        .finally(() => { this.isSaving = false; });
    }

    async handleSaveBusiness() {
        

        if (this.isSaving) {
        
            return;
        }

        this.isSaving = true;

        try {
            

            if (this.isNewBusiness) {

                if (this.newBusinessContactCreatedId) {
                    
                    await this._createNewBusinessCCR(this.newBusinessContactCreatedId);
                    return;
                }

                const form = this.template.querySelector(
                    'lightning-record-edit-form[data-id="newBusinessForm"]'
                );

                

                if (!form) {
                    
                    this.isSaving = false;
                    return;
                }

                const isValid = this.validateNewBusinessFields();
                

                if (!isValid) {
                    
                    this.showToast('Error', 'Please fill all required Business fields', 'error');
                    this.isSaving = false;
                    return;
                }

                const fields = {};
                const inputFields = form.querySelectorAll('lightning-input-field');

                

                inputFields.forEach(field => {
                    if (field.fieldName) {
                        fields[field.fieldName] = field.value;
                    }
                });

                fields.AccountId = this.selectedBusinessAccountId;

                const typeField = form.querySelector(
                    'lightning-input-field[data-id="newBusinessType"]'
                );

                

                const selectedType = typeField?.value;
                

                if (!selectedType) {
                    
                    typeField?.reportValidity();
                    this.showToast('Error', 'Type is required', 'error');
                    this.isSaving = false;
                    return;
                }

                if (this.isReferral) {
                    

                    const alreadyExists = await hasExistingReferralCCR({
                        relatedAccountId: this.recordId
                    });

                    

                    if (alreadyExists) {
                        
                        this.showToast(
                            'Error',
                            'A referral Business Contact already exists for this client.',
                            'error'
                        );
                        this.isSaving = false;
                        return;
                    }
                }

                this.newBusinessType = selectedType;
                fields.ReferralType__c = selectedType;              
                
                this.bapplyCallerAddressToFields(fields);                

                if (this.createBusinessWithoutAccount) {
                    

                    if (!this.defaultAccountId) {
                        
                        this.showToast('Error', 'Default account not available', 'error');
                        this.isSaving = false;
                        return;
                    }
                }

                this.showBusinessAccountError = false;

                if (this.businessRecordTypeId) {
                    fields.RecordTypeId = this.businessRecordTypeId;
                    
                } 

                this.pendingDuplicateFields = fields;
                this.pendingDuplicateContext = 'business';

                

                try {
                    const created = await createRecord({
                        apiName: 'Contact',
                        fields,
                        allowSaveOnDuplicate: false
                    });

                    

                    this.handleNewBusinessSuccess({ detail: { id: created.id } });

                } catch (error) {
                    
                    this.handleError({ detail: error?.body || error });
                }

                return;
            }

            

            if (!this.selectedBusinessContactId) {
                
                this.showToast('Error', 'Please select Business Contact', 'error');
                this.isSaving = false;
                return;
            }

            const existingTypeField = this.template.querySelector(
                'lightning-input-field[data-id="existingBusinessType"]'
            );

            const selectedType = existingTypeField?.value;

            

            if (!selectedType) {
                
                existingTypeField?.reportValidity();
                this.showToast('Error', 'Please select Type', 'error');
                this.isSaving = false;
                return;
            }

            

            await updateRecord({
                fields: {
                    Id: this.selectedBusinessContactId,
                    ReferralType__c: selectedType
                }
            });

            

            await createBusinessCCR({
                businessContactId: this.selectedBusinessContactId,
                relatedAccountId: this.recordId,
                roleName: selectedType,
                isReferral: this.isReferral
            });

            

            this.showToast('Success', 'Business Relationship Created', 'success');
            this.close('saved');

        } catch (error) {
            
            this.showToast('Error', error.body?.message || 'Failed to save', 'error');
            this.isSaving = false;
        }
    }

    handleDuplicateConfirm() {
        this.showDuplicateWarning = false;
        this.isSaving = true;

        createRecord({
            apiName: 'Contact',
            fields: this.pendingDuplicateFields,
            allowSaveOnDuplicate: true
        })
        .then(record => {
            if (this.pendingDuplicateContext === 'caller') {
                this.handleSuccess({ detail: { id: record.id } });
            } else {
                this.handleNewBusinessSuccess({ detail: { id: record.id } });
            }
        })
        .catch(error => {
            this.showToast('Error', error.body?.message || 'Failed to save', 'error');
            this.isSaving = false;
        })
        .finally(() => {
            this.pendingDuplicateFields = null;
            this.pendingDuplicateContext = null;
        });
    }

    handleDuplicateCancel() {
        this.showDuplicateWarning = false;
        this.pendingDuplicateFields = null;
        this.pendingDuplicateContext = null;
        this.isSaving = false;
    }

    handleNewBusinessSuccess(event) {
        const businessContactId = event.detail.id;

        this.newBusinessContactCreatedId = businessContactId;

        

        if (!this.newBusinessType) {
            this.showToast('Error', 'Type is required', 'error');
            this.isSaving = false;
            return;
        }

        createBusinessCCR({
            businessContactId,
            relatedAccountId: this.recordId,
            roleName: this.newBusinessType,
            isReferral: this.isReferral
        })
        .then(() => {
            this.showToast('Success', 'Business Relationship Created', 'success');
            this.close('saved');
        })
        .catch(error => {
            this.showToast('Error', error.body?.message || 'Failed to create relationship', 'error');
        })
        .finally(() => {
            this.isSaving = false;
            this.newBusinessType = '';
            this.isReferral = false;
        });
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
        this.newBusinessContactCreatedId = null;
        this.newFamilyContactCreatedId = null;
        this.showDuplicateWarning = false;
        this.pendingDuplicateFields = null;
        this.pendingDuplicateContext = null;
    }

    validatePatientTab() {
        let isValid = true;

        const patientPicker = this.template.querySelector(
            'lightning-record-picker[data-id="patientAccount"]'
        );

        const roleField = this.template.querySelector(
            'lightning-input-field[data-id="patientRoleField"]'
        );

        const roleId = roleField?.value;
        this.selectedRoleId = roleId;

        if (!this.selectedPatientId) {
            patientPicker?.setCustomValidity('Couple Household is required');
            patientPicker?.reportValidity();
            isValid = false;
        } else if (this.selectedPatientId === this.recordId) {
            patientPicker?.setCustomValidity('You cannot relate a patient to itself.');
            isValid = false;
        } else {
            patientPicker?.setCustomValidity('');
            patientPicker?.reportValidity();
        }

        if (!roleId) {
            roleField?.reportValidity();
            isValid = false;
        } else {
            roleField?.reportValidity();
        }

        return isValid;
    }

    validateBusinessTab() {
        let isValid = true;
        const contactPicker = this.template.querySelector('lightning-record-picker[data-id="businessContact"]');
        const rolePicker    = this.template.querySelector('lightning-record-picker[data-id="businessRole"]');

        if (!this.selectedBusinessContactId) {
            contactPicker.setCustomValidity('Business contact is required');
            contactPicker.reportValidity();
            isValid = false;
        } else {
            contactPicker.setCustomValidity('');
            contactPicker.reportValidity();
        }

        if (!this.selectedRoleOfBusinessId) {
            rolePicker.setCustomValidity('Role is required');
            rolePicker.reportValidity();
            isValid = false;
        } else {
            rolePicker.setCustomValidity('');
            rolePicker.reportValidity();
        }

        return isValid;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    async handleOpenAccountCreate() {
        
        const accountId = await BusinessAccountCreate.open({
            size: 'medium'
        });

        if (accountId) {
            const accountField = this.template.querySelector(
                'lightning-input-field[data-id="businessAccountField"]'
            );

            if (accountField) {
                accountField.value = accountId;
            }
        }
    }
}