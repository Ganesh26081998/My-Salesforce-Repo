import LightningModal from 'lightning/modal';
import { api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPicklistValuesByRecordType, getObjectInfo } from 'lightning/uiObjectInfoApi';
import CONTACT_OBJECT from '@salesforce/schema/Contact';
import CCR_OBJECT from '@salesforce/schema/HealthCloudGA__ContactContactRelation__c';
import { getRecord } from 'lightning/uiRecordApi';
import TYPE_FIELD from '@salesforce/schema/Contact.ReferralType__c';
import updateFamilyCCR from '@salesforce/apex/PatientContactRelationshipController.updateFamilyCCR';
import updateBusinessCCR from '@salesforce/apex/PatientContactRelationshipController.updateBusinessCCR';
import updateCoupleHouseholdCCR from '@salesforce/apex/PatientContactRelationshipController.updateCoupleHouseholdCCR';
import hasExistingReferralCCR from '@salesforce/apex/PatientContactRelationshipController.hasExistingReferralCCR';

export default class PatientContactRelationshipEditModal extends LightningModal {

    @api relationshipId;
    @api contactId;
    @api contactName;
    @api ccrType;
    @api roleId;
    @api relatedAccountId;
    @api relationshipToClientInit;
    @api familyRelationshipInit;
    @api otherRelationshipToClientInit;
    @api businessTypeInit;
    @api isReferralInit;

    @track isLoading = true;
    @track isSaving  = false;

    @track relationshipToClient       = '';
    @track familyRelationship         = '';
    @track otherRelationshipToClient  = '';
    @track showFamilyRelationship     = false;
    @track showOtherRelationship      = false;
    @track relationshipToClientOptions = [];
    @track familyRelationshipOptions   = [];
    familyRelationshipAllValues        = [];
    familyRelationshipControllerValues = {};
    @track selectedRoleId = '';
    @track selectedBusinessType = '';
    @track businessTypeOptions  = [];
    @track isReferral = false;
    @track ccrRecordTypeId;
    @track contactRecordTypeId;
    _ccrPicklistsLoaded     = false;
    _contactPicklistsLoaded = false;

    @wire(getObjectInfo, { objectApiName: CCR_OBJECT })
    ccrObjectInfo({ data, error }) {
        if (data) {
            this.ccrRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.error('Error loading CCR ObjectInfo:', error);
        }
    }

    
    @wire(getObjectInfo, { objectApiName: CONTACT_OBJECT })
    contactObjectInfo({ data, error }) {
        if (data) {
            
            this.contactRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.error('Error loading Contact ObjectInfo:', error);
        }
    }

    
    @wire(getPicklistValuesByRecordType, {
        objectApiName: CCR_OBJECT,
        recordTypeId: '$ccrRecordTypeId'
    })
    wiredCcrPicklists({ data, error }) {
        if (data) {
            const relationshipField = data.picklistFieldValues.Relationship_to_Client__c;
            const familyField       = data.picklistFieldValues.Family_Relationship__c;

            this.relationshipToClientOptions   = relationshipField.values.map(item => ({
                label: item.label,
                value: item.value
            }));
            this.familyRelationshipAllValues        = familyField.values;
            this.familyRelationshipControllerValues = familyField.controllerValues || {};

            
            if (this.isFamilyType && this.showFamilyRelationship) {
                this._buildFamilyRelationshipOptions(this.relationshipToClient);
            }

            this._ccrPicklistsLoaded = true;
            this._checkStopLoading();
        } else if (error) {
            console.error('Error loading CCR picklists:', error);
            this._ccrPicklistsLoaded = true;
            this._checkStopLoading();
        }
    }

    
    @wire(getPicklistValuesByRecordType, {
        objectApiName: CONTACT_OBJECT,
        recordTypeId: '012WQ00000AIiPvYAL'
    })
    wiredContactPicklists({ data, error }) {
        if (data) {

        console.log('=== wiredContactPicklists fired ===');
        console.log('this.businessType at this point:', this.businessType);
        console.log('this.selectedBusinessType at this point:', this.selectedBusinessType);
            const typeField = data.picklistFieldValues.ReferralType__c;
            if (typeField) {
                this.businessTypeOptions = typeField.values.map(item => ({
                    label: item.label,
                    value: item.value
                }));

                 if (this.businessTypeInit) {
                this.selectedBusinessType = this.businessTypeInit;
            }
        
            }
            this._contactPicklistsLoaded = true;
            this._checkStopLoading();
        } else if (error) {
            console.error('Error loading Contact picklists:', error);
            this._contactPicklistsLoaded = true;
            this._checkStopLoading();
        }
    }

    @wire(getRecord, { 
    recordId: '$contactId', 
    fields: [TYPE_FIELD] 
    })
    wiredContact({ data, error }) {
    if (data) {
        const typeValue = data.fields.ReferralType__c.value;
         console.log('=== wiredContact fired ===');
        console.log('typeValue from LDS:', typeValue);
        console.log('this.businessType prop:', this.businessType);
        console.log('this.selectedBusinessType before guard:', this.selectedBusinessType);

        
        if ( !this.businessTypeInit && typeValue) {
            this.selectedBusinessType = typeValue;
        }

        
        } else if (error) {
            console.error('Error fetching contact type:', error);
        }
    }

    
    _checkStopLoading() {
        if (this.isFamilyType && this._ccrPicklistsLoaded) {
            this.isLoading = false;
        } else if (this.isBusinessType && this._contactPicklistsLoaded) {
            this.isLoading = false;
        } else if (this.isCoupleHouseholdType) {
            this.isLoading = false; 
        }
    }

    
    connectedCallback() {
       
        console.log('=== connectedCallback ===');
        console.log('businessType prop:', this.businessType);
        console.log('isReferralInit prop:', this.isReferralInit);
        this.selectedRoleId       = this.roleId           || '';
        this.isReferral           = this.isReferralInit   || false;
        this.selectedBusinessType =   this.businessTypeInit || '';
        
        console.log('selectedBusinessType:', this.businessType);
         console.log('selectedBusinessType after connectedCallback:', this.selectedBusinessType);

        if (this.isFamilyType) {
            this.relationshipToClient      = this.relationshipToClientInit      || '';
            this.familyRelationship        = this.familyRelationshipInit        || '';
            this.otherRelationshipToClient = this.otherRelationshipToClientInit || '';
            this.showFamilyRelationship    = this.relationshipToClient === 'Family';
            this.showOtherRelationship     = this.relationshipToClient === 'Other';
        }

        
        if (this.isCoupleHouseholdType) {
            this.isLoading = false;
        }
    }

    
    _buildFamilyRelationshipOptions(controllerValue) {
        const controllerKey = this.familyRelationshipControllerValues[controllerValue];
        this.familyRelationshipOptions = this.familyRelationshipAllValues
            .filter(option => option.validFor.includes(controllerKey))
            .map(option => ({ label: option.label, value: option.value }));
    }

    
    get isFamilyType() {
        return this.ccrType === 'Family Contact' || this.ccrType === 'Caller';
    }
    get isCoupleHouseholdType() {
        return this.ccrType === 'Couple Household';
    }
    get isBusinessType() {
        return this.ccrType === 'Business Contact';
    }

    
    handleRelationshipToClientChange(event) {
        this.relationshipToClient      = event.detail.value;
        this.showFamilyRelationship    = this.relationshipToClient === 'Family';
        this.showOtherRelationship     = this.relationshipToClient === 'Other';
        this.familyRelationship        = '';
        this.otherRelationshipToClient = '';
        this.familyRelationshipOptions = [];

        if (this.showFamilyRelationship) {
            this._buildFamilyRelationshipOptions(this.relationshipToClient);
        }
    }

    handleFamilyRelationshipChange(event) {
        this.familyRelationship = event.detail.value;
    }

    handleOtherRelationshipChange(event) {
        this.otherRelationshipToClient = event.target.value;
    }

    
    handleRoleChange(event) {
        this.selectedRoleId = event.detail.value;
    }

   
    handleBusinessTypeChange(event) {
        this.selectedBusinessType = event.detail.value || '';
    }

    handleIsReferralChange(event) {
        this.isReferral = event.target.checked;
    }

    
    _validateFamilyFields() {
        let isValid = true;

        if (!this.relationshipToClient) {
            this.template.querySelector(
                'lightning-combobox[data-id="relationshipToClient"]'
            )?.reportValidity();
            isValid = false;
        }
        if (this.relationshipToClient === 'Family' && !this.familyRelationship) {
            this.template.querySelector(
                'lightning-combobox[data-id="familyRelationship"]'
            )?.reportValidity();
            isValid = false;
        }
        if (this.relationshipToClient === 'Other' && !this.otherRelationshipToClient?.trim()) {
            this.template.querySelector(
                'lightning-input[data-id="otherRelationshipToClient"]'
            )?.reportValidity();
            isValid = false;
        }
        return isValid;
    }

    _validateCoupleHouseholdFields() {
        const roleField = this.template.querySelector(
            'lightning-input-field[data-id="patientRoleField"]'
        );
        this.selectedRoleId = roleField?.value;
        if (!this.selectedRoleId) {
            roleField?.reportValidity();
            return false;
        }
        return true;
    }

    _validateBusinessFields() {
        if (!this.selectedBusinessType) {
            this.template.querySelector(
                'lightning-combobox[data-id="businessType"]'
            )?.reportValidity();
            return false;
        }
        return true;
    }

    
    handleCancel() {
        this.close();
    }

    async handleSave() {
        if (this.isSaving) return;

        
        if (this.isFamilyType) {
            if (!this._validateFamilyFields()) {
                this._toast('Error', 'Review all error messages before saving.', 'error');
                return;
            }
            this.isSaving = true;

            let roleName = '';
            if (this.relationshipToClient === 'Family') {
                roleName = this.familyRelationship;
            } else if (this.relationshipToClient === 'Friend/Neighbor') {
                roleName = 'Friend/Neighbor';
            } else if (this.relationshipToClient === 'Other') {
                roleName = 'Other';
            }

            try {
                await updateFamilyCCR({
                    relationshipId           : this.relationshipId,
                    roleName,
                    relationshipToClient     : this.relationshipToClient,
                    familyRelationship       : this.familyRelationship,
                    otherRelationshipToClient: this.otherRelationshipToClient
                });
                this._toast('Success', 'Family Relationship updated', 'success');
                this.close('saved');
            } catch (e) {
                this._toast('Error', e.body?.message || 'Failed to update', 'error');
            } finally {
                this.isSaving = false;
            }
            return;
        }

        
        if (this.isCoupleHouseholdType) {
            if (!this._validateCoupleHouseholdFields()) {
                this._toast('Error', 'Role is required.', 'error');
                return;
            }
            this.isSaving = true;
            try {
                await updateCoupleHouseholdCCR({
                    relationshipId: this.relationshipId,
                    roleId        : this.selectedRoleId
                });
                this._toast('Success', 'Couple Household Relationship updated', 'success');
                this.close('saved');
            } catch (e) {
                this._toast('Error', e.body?.message || 'Failed to update', 'error');
            } finally {
                this.isSaving = false;
            }
            return;
        }

        
        if (this.isBusinessType) {
            if (!this._validateBusinessFields()) {
                this._toast('Error', 'Type is required.', 'error');
                return;
            }
            this.isSaving = true;

            
            if (this.isReferral && !this.isReferralInit) {
                try {
                    const exists = await hasExistingReferralCCR({
                        relatedAccountId: this.relatedAccountId
                    });
                    if (exists) {
                        this._toast(
                            'Error',
                            'A referral Business Contact already exists for this client.',
                            'error'
                        );
                        this.isSaving = false;
                        return;
                    }
                } catch (e) {
                    this._toast('Error', e.body?.message || 'Failed to check referral', 'error');
                    this.isSaving = false;
                    return;
                }
            }

            try {
                await updateBusinessCCR({
                    relationshipId  : this.relationshipId,
                    contactId       : this.contactId,
                    businessType    : this.selectedBusinessType,
                    isReferral      : this.isReferral,
                    relatedAccountId: this.relatedAccountId
                });
                this._toast('Success', 'Business Relationship updated', 'success');
                this.close('saved');
            } catch (e) {
                this._toast('Error', e.body?.message || 'Failed to update', 'error');
            } finally {
                this.isSaving = false;
            }
        }
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}