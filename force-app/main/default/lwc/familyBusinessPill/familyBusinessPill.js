import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import FAMILY_FIELD from '@salesforce/schema/Account.Family_Business__c';

export default class FamilyBusinessPill extends LightningElement {

    @api recordId;
    isFamilyBusiness = false;

    @wire(getRecord, { recordId: '$recordId', fields: [FAMILY_FIELD] })
    wiredAccount({ error, data }) {
        if (data) {
            this.isFamilyBusiness = data.fields.Family_Business__c.value;
        } else if (error) {
            console.error('Error fetching account:', error);
        }
    }
}