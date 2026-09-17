import { LightningElement, api, wire } from 'lwc';
import getParentDetails from '@salesforce/apex/EventBillableController.getParentDetails';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';

export default class ParentDetailsViewer extends LightningElement {
    @api recordId; // Automatically gets the ID from the record page
    
    eventBillable;
    error;
    isLoading = true;

    // Fetch data from Apex
    @wire(getParentDetails, { recordId: '$recordId' })
    wiredRecord({ error, data }) {
        this.isLoading = true;
        if (data) {
            this.eventBillable = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.eventBillable = undefined;
            console.error('Error fetching parents:', error);
        }
        this.isLoading = false;
    }

    // Getters to make HTML cleaner and safer (prevents null errors)
    get billing() {
        return this.eventBillable?.Billing__r || {};
    }

    get eventWrapper() {
        return this.eventBillable?.Event_Wrapper__r || {};
    }

    // Helper to generate URLs for the names (so they are clickable)
    get billingUrl() {
        return this.eventBillable?.Billing__c ? `/${this.eventBillable.Billing__c}` : '#';
    }

    get eventUrl() {
        return this.eventBillable?.Event_Wrapper__c ? `/${this.eventBillable.Event_Wrapper__c}` : '#';
    }
}