import LightningModal from 'lightning/modal';
import { api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import { createRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

export default class CreateBusinessAccount extends LightningModal {

    @api recordTypeDeveloperName = 'Business_Account';
    @api addressCompoundApiName = 'Address__c';

    @track recordTypeId ;

    @track street = '';
    @track city = '';
    @track state = '';
    @track postalCode = '';
    @track country = '';
    @track stateCode = '';
    @track countryCode = '';

    @track showContractType = false;


    //new
    @track showDuplicateWarning = false;
    pendingDuplicateFields = null;

    handleContractChange(event) {
        const value = event.detail.value;

        
        this.showContractType = value === 'Yes';
    }

   

        @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
        wiredAccountInfo({ data }) {
            if (data) {
                const rtInfos = data.recordTypeInfos;

                this.recordTypeId = Object.keys(rtInfos).find(
                    rtId => rtInfos[rtId].name === 'Business Account'
                );

            } 
        }



    handleAddressChange(event) {
    const detail = event.detail || {};
    const target = event.target || {};

    this.street = detail.street || target.street || "";
    this.city = detail.city || target.city || "";
    this.state = detail.province || target.province || "";
    this.postalCode = detail.postalCode || target.postalCode || "";
    this.country = detail.country || target.country || "";
    this.stateCode = detail.provinceCode || target.provinceCode || "";
    this.countryCode = detail.countryCode || target.countryCode || "";
  }

    



    handleSubmit() {
    const form = this.template.querySelector('lightning-record-edit-form');
    const fields = {};
    [...form.querySelectorAll('lightning-input-field')].forEach((field) => {
        if (field.fieldName) {
            fields[field.fieldName] = field.value;
        }
    });

    if (this.recordTypeId) {
        fields.RecordTypeId = this.recordTypeId;
    }
    fields.Name = fields.Organization_Name__c;

    let stateCode   = this.stateCode;
    let countryCode = this.countryCode;

    if (!stateCode && this.state && this.state.length === 2) {   
        stateCode = this.state.toUpperCase();
    }
    if (!countryCode && this.country && this.country.length === 2) {  
        countryCode = this.country.toUpperCase();
    }

    fields.Address__Street__s     = this.street;       
    fields.Address__City__s       = this.city;         
    fields.Address__PostalCode__s = this.postalCode;   
    // if (this.state)   { fields.Address__State__s     = this.state; }      
    // if (stateCode)    { fields.Address__StateCode__s = stateCode; }
    //if (this.country) { fields.Address__Country__s   = this.country; }    
    //if (countryCode)  { fields.Address__CountryCode__s = countryCode; }

    this.pendingDuplicateFields = fields;

    createRecord({
        apiName: 'Account',
        fields,
        allowSaveOnDuplicate: false
    })
    .then(record => {
        this.handleSuccess({ detail: { id: record.id } });
    })
    .catch(error => {
        this.handleError({ detail: error?.body || error });
    });
}

    handleSuccess(event) {

        const accountId = event.detail.id;

        this.close(accountId);   
    }

    handleCancel() {
        this.close();
    }

    handleDuplicateConfirm() {

        createRecord({
            apiName: 'Account',
            fields: this.pendingDuplicateFields,
            allowSaveOnDuplicate: true
        })
        .then(record => {
            this.showDuplicateWarning = false;
            this.pendingDuplicateFields = null;

            this.handleSuccess({ detail: { id: record.id } });
        })
        .catch(error => {
            this.handleError({ detail: error?.body || error });

        
         });
    }

    handleDuplicateCancel() {
        this.showDuplicateWarning = false;
        this.pendingDuplicateFields = null;
    }


handleError(event) {
    console.log('Full error:', JSON.stringify(event.detail));
    const detail = event.detail || {};

    // 1. Duplicate check
    const duplicateError = detail?.output?.errors?.find(
        e => e.errorCode === 'DUPLICATES_DETECTED'
    );
    if (duplicateError) {
        this.showDuplicateWarning = true;
        return;
    }

    const messages = [];

    // 2. Field-level errors (required fields, format errors)
    const fieldErrors = detail?.output?.fieldErrors || {};
    Object.keys(fieldErrors).forEach(field => {
        fieldErrors[field].forEach(err => messages.push(err.message));
    });

    // 3. Record-level errors (validation rules, triggers)
    const recordErrors = detail?.output?.errors || [];
    recordErrors.forEach(err => {
        if (err.errorCode !== 'DUPLICATES_DETECTED') {
            messages.push(err.message);
        }
    });

    // 4. Fallback
    if (messages.length === 0) {
        messages.push(
            detail?.message ||
            detail?.detail ||
            'Account creation failed'
        );
    }

    this.dispatchEvent(new ShowToastEvent({
        title: 'Error',
        message: messages.join(' | '),
        variant: 'error'
    }));
}
}