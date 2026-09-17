import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getPatientDetails from '@salesforce/apex/OutboundReferralController.getPatientDetails';
import getBusinessEmail from '@salesforce/apex/OutboundReferralController.getBusinessEmail';
import getBusinessReferralType from '@salesforce/apex/OutboundReferralController.getBusinessReferralType';
import getPatientContacts from '@salesforce/apex/OutboundReferralController.getPatientContacts';
import saveReferral from '@salesforce/apex/OutboundReferralController.saveReferral';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import REFERRAL_OBJECT from '@salesforce/schema/Referral__c';
import REFERRAL_TYPE_FIELD from '@salesforce/schema/Referral__c.Referral_Type__c';
import TIME_ZONE from '@salesforce/i18n/timeZone';

const REFERRAL_RT_DEV_NAME = 'Outbound'; 

export default class OutboundReferral extends LightningElement {
    isLoading = false;
    recordId;
    businessId;
    businessEmail = '';
    referralType = '';
    additionalEmails = '';
    referralReason = '';
    todayDate;
    patientName = '';
    patientPhone = '';
    patientEmail = '';
    patientDob = '';
    referralTypeOptions = [];
    contacts = [];
    contactOptions = [];
    selectedContactId;
    selectedContactPhone = '';
    selectedContactEmail = '';
    role = '';
    contactId;
    referralPicklistRecordTypeId = null;
    isSaving = false;

    @wire(CurrentPageReference)
    getStateParameters(pageRef) {
        if (pageRef) {
            this.recordId = pageRef.state.recordId;
        }
    }

    @wire(getObjectInfo, { objectApiName: REFERRAL_OBJECT })
    objectInfo({ data, error }) {
        if (data) {
            const rtInfos = data.recordTypeInfos;

            for (let rtId in rtInfos) {
                if (rtInfos[rtId].name === 'Outbound') {   
                    this.referralPicklistRecordTypeId = rtId;
                    break;
                }
            }
            if (!this.referralPicklistRecordTypeId) {
                this.referralPicklistRecordTypeId = data.defaultRecordTypeId;
            }

        } else if (error) {
            console.error('Error loading Referral ObjectInfo:', JSON.stringify(error));
        }
    }

    get referralRtIdForPicklist() {
        return this.referralPicklistRecordTypeId;
    }

    @wire(getPicklistValues, {
        recordTypeId: '$referralPicklistRecordTypeId',
        fieldApiName: REFERRAL_TYPE_FIELD
    })
    wiredReferralType({ data, error }) {
        

        if (data) {
            this.referralTypeOptions = (data.values || []).map(v => ({
                label: v.label,
                value: v.value
            }));

            if (this.referralType && !this.referralTypeOptions.some(o => o.value === this.referralType)) {
                this.referralType = '';
            }
        } else if (error) {
            console.error('Error loading Referral Type picklist:', JSON.stringify(error));
        }
    }

    connectedCallback() {
        const options = { timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit' };
        const dtf = new Intl.DateTimeFormat('fr-CA', options);
        this.todayDate = dtf.format(new Date());
        this.loadPatientData();
    }

    get isSaveDisabled() {
        return !this.businessId || !this.referralType;
    }

    get businessFilter() {
        return {
            criteria: [
                { fieldPath: 'RecordType.DeveloperName', operator: 'eq', value: 'Business_Account' }
            ]
        };
    }

    loadPatientData() {
        this.isLoading = true;

        getPatientDetails({ patientId: this.recordId })
            .then(acc => {
                this.patientName = acc.Name;
                this.patientPhone = acc.Mobile_Phones__c || '';
                this.patientEmail = acc.PersonEmail || '';
                this.patientDob = acc.Date_Of_Birth__c ? acc.Date_Of_Birth__c.split('T')[0] : '';
                return getPatientContacts({ accountId: this.recordId });
            })
            .then(res => {
                this.contacts = res || [];
                this.prepareContactOptions();
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error) || 'Failed to load patient data', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    prepareContactOptions() {
        this.contactOptions = (this.contacts || [])
            .filter(c => c.HealthCloudGA__Contact__c)
            .map(c => ({
                label: c.HealthCloudGA__Contact__r.Name,
                value: c.HealthCloudGA__Contact__c
            }));
    }

    handleContactChange(event) {
        this.selectedContactId = event.detail.value;

        if (!this.selectedContactId) {
            this.role = '';
            this.contactId = null;
            this.selectedContactPhone = '';
            this.selectedContactEmail = '';
            return;
        }

        const acr = (this.contacts || []).find(
            c => c.HealthCloudGA__Contact__c === this.selectedContactId
        );

        this.role = acr?.HealthCloudGA__Role__r?.Name || '';
        this.contactId = acr?.HealthCloudGA__Contact__c || null;
        this.selectedContactPhone = acr?.HealthCloudGA__Contact__r?.MobilePhone || '';
        this.selectedContactEmail = acr?.HealthCloudGA__Contact__r?.Email || '';
    }

    handleReferralTypeChange(e) {
        this.referralType = e.detail.value;
    }

    handleAdditionalEmailChange(e) {
        this.additionalEmails = e.target.value;
        this.validateAdditionalEmailsUI();
    }

    handleReasonChange(e) {
        this.referralReason = e.detail.value;
    }

    handleBusinessChange(event) {
        this.businessId = event.detail.recordId;

        if (!this.businessId) {
            this.businessEmail = '';
            this.referralType = '';
            return;
        }


    getBusinessEmail({ businessId: this.businessId })
    .then(email => {
        this.businessEmail = email || '';

        
        requestAnimationFrame(() => {
            const input = this.template.querySelector('[data-id="businessEmail"]');
            if (input) {
                input.value = this.businessEmail;

                
                input.setCustomValidity('');
                input.reportValidity();
            }

            this.validateBusinessEmailUI();
        });
    })
    .catch(() => {
        this.businessEmail = '';
    });

        getBusinessReferralType({ accountId: this.businessId })
            .then(type => {
                if (type) {
                    this.referralType = type;
                }
            })
            .catch(() => {
                this.referralType = '';
            });
    }

    handleEmailChange(event) {
        this.businessEmail = event.target.value;
        this.validateBusinessEmailUI();
    }

    validateBusinessEmailUI() {
        const input = this.template.querySelector('[data-id="businessEmail"]');
        if (!input) return true;

        const email = (this.businessEmail || '').trim();
        if (!email) {
            input.setCustomValidity('');
            input.reportValidity();
            return true;
        }
        const ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
        input.setCustomValidity(ok ? '' : 'Enter a valid email address.');
        input.reportValidity();
        return ok;
    }

    validateAdditionalEmailsUI() {
        const input = this.template.querySelector('[data-id="additionalEmails"]');
        if (!input) return true;

        const raw = (this.additionalEmails || '').trim();
        if (!raw) {
            input.setCustomValidity('');
            input.reportValidity();
            return true;
        }

        const parts = raw.split(',').map(s => s.trim()).filter(Boolean);

        if (parts.length > 3) {
            input.setCustomValidity('You can enter a maximum of 3 email addresses.');
            input.reportValidity();
            return false;
        }

        const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        const bad = parts.find(e => !regex.test(e));
        if (bad) {
            input.setCustomValidity(`Invalid email format: ${bad}`);
            input.reportValidity();
            return false;
        }

        input.setCustomValidity('');
        input.reportValidity();
        return true;
    }

    validateBeforeSave() {
        let isValid = true;

        if (!this.businessId) {
        this.showToast('Error', 'Business (TO) is required.', 'error');
        isValid = false;
        }

        
        const combo = this.template.querySelector('lightning-combobox');
    if (!this.referralType && combo) {
        combo.setCustomValidity('Referral Type is required');
        combo.reportValidity();
        isValid = false;
    } else if (combo) {
        combo.setCustomValidity(''); 
        combo.reportValidity();
    }

        const ok1 = this.validateBusinessEmailUI();
        const ok2 = this.validateAdditionalEmailsUI();
        
        return  isValid && ok1 && ok2;
    }

    handleSave() {
        if (!this.validateBeforeSave()) {
            this.showToast('Error', 'Please fix validation errors before saving.', 'error');
            return;
        }

        this.isLoading = true;
        this.isSaving = true;

        saveReferral({
            businessAccountId: this.businessId,
            patientAccountId: this.recordId,
            referralType: this.referralType,
            businessEmail: this.businessEmail,
            additionalEmails: this.additionalEmails,
            referralReason: this.referralReason,
            role: this.role,
            contact: this.contactId,
            referralRecordTypeId: this.referralPicklistRecordTypeId
        })
            .then(() => {
                this.showToast('Success', 'Referral created successfully', 'success');
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(e => {
                console.log('errror E', e);
                this.showToast('Error', this.getErrorMessage(e) || 'Unexpected error', 'error');
            })
            .finally(() => {
                this.isLoading = false;
                this.isSaving = false;
            });
    }

    getErrorMessage(e) {
        if (!e) return '';
        if (Array.isArray(e.body)) return e.body.map(x => x.message).join(', ');
        if (e.body?.message) return e.body.message;
        if (e.message) return e.message;
        try { return JSON.stringify(e); } catch (err) { return ''; }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}