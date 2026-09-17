import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import syncBillingToQB from '@salesforce/apex/BillingSyncController.syncBillingToQB';

// 👇 🚨 NEW: Define which fields to fetch 🚨 👇
const FIELDS = ['Billing__c.Is_Synced__c'];
// 👆 🚨 -------------------------------- 🚨 👆

export default class BillingSyncButton extends LightningElement {
    @api recordId;
    isSyncing = false;
    showSuccess = false;
    showError = false;
    successMessage = '';
    errorMessage = '';
    
    // 👇 🚨 NEW: Property to track if already synced 🚨 👇
    isAlreadySynced = false;
    // 👆 🚨 -------------------------------- 🚨 👆

    // 👇 🚨 NEW: Wire decorator to auto-fetch record data 🚨 👇
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredBilling({ error, data }) {
        if (data) {
            this.isAlreadySynced =
                data.fields.Is_Synced__c.value;
        }
    }
    // 👆 🚨 -------------------------------- 🚨 👆

    handleSync() {
        this.isSyncing = true;
        this.showSuccess = false;
        this.showError = false;
        
        // Call the Apex controller
        syncBillingToQB({ billingId: this.recordId })
            .then(result => {
                this.isSyncing = false;
                
                // Check if result contains 'Success'
                if (result.includes('Success')) {
                    this.showSuccess = true;
                    this.successMessage = result;
                    // Refresh page after 2 seconds
                    setTimeout(() => {
                        window.location.reload();
                    }, 2000);
                } else {
                    this.showError = true;
                    this.errorMessage = result;
                }
            })
            .catch(error => {
                this.isSyncing = false;
                this.showError = true;
                this.errorMessage = 'Error: ' + (error.body?.message || error.message);
            });
    }
}