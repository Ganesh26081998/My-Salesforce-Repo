import { LightningElement, api, wire } from 'lwc';
import BILLING_OBJECT from '@salesforce/schema/Billing__c';
import LOCATION_FIELD from '@salesforce/schema/Billing__c.Location_g__c';

import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import startBatchSync from '@salesforce/apex/BulkBillingSyncController.startBatchSync';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class BulkBillingSync extends LightningElement {

    @api startDate;
    @api endDate;
    @api selectedLocations = [];

    locationOptions = [];
    recordTypeId;

    get today() {
        return new Date().toISOString().split('T')[0];
    }

    // Fetch Object Info
    @wire(getObjectInfo, { objectApiName: BILLING_OBJECT })
    objectInfo({ data }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        }
    }

    // Fetch Picklist Values
    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: LOCATION_FIELD
    })
    picklist({ data }) {
        if (data) {
            this.locationOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        }
    }

    // 🔹 START DATE HANDLER (Auto +15 days)
    handleStartDate(event) {
        this.startDate = event.target.value;

        if (this.startDate) {
            const start = this.parseLocalDate(this.startDate);
            const futureDate = new Date(start);
            futureDate.setDate(start.getDate() + 13);
            const todayDate = this.parseLocalDate(this.today); 


            // ✅ Fix: Cap end date to today
            if (futureDate > todayDate) {
                this.endDate = this.formatDate(todayDate);
            } else {
                this.endDate = this.formatDate(futureDate);
            }
        }

        this.validateDateInputs();
    }

    handleLocationChange(event) {
        this.selectedLocations = event.detail.value;
        this.validateDateInputs();
    }

    handleClose() {
        window.location.href = '/lightning/o/Billing__c/list';
    }

    get isActionDisabled() {
        if (!this.startDate || !this.endDate || !this.selectedLocations?.length) {
            return true;
        }

        const today = this.parseLocalDate(this.today);
        const start = this.parseLocalDate(this.startDate);
        const end = this.parseLocalDate(this.endDate);

        return !(start <= end && start <= today && end <= today);
    }

    // 🔹 VALIDATION (Includes Sunday rule)
    validateDateInputs() {

        const startInput = this.template.querySelector('[data-id="startDate"]');
        const endInput = this.template.querySelector('[data-id="endDate"]');

        if (!startInput || !endInput) return false;

        let isValid = true;

        startInput.setCustomValidity('');
        endInput.setCustomValidity('');

        const today = this.today;

        // Required
        if (!this.startDate) {
            startInput.setCustomValidity('Start Date is required');
            isValid = false;
        }

        if (!this.endDate) {
            endInput.setCustomValidity('End Date is required');
            isValid = false;
        }

        if (this.startDate && this.endDate) {
            const start = this.parseLocalDate(this.startDate);
            const end = this.parseLocalDate(this.endDate);

            // 🔴 Sunday validation
            if (start.getDay() !== 0) {
                startInput.setCustomValidity('Start Date must be a Sunday');
                isValid = false;
            }

            if (start > end) {
                endInput.setCustomValidity('End Date must be greater than or equal to Start Date');
                isValid = false;
            }

            if (this.startDate > today) {
                startInput.setCustomValidity('Start Date cannot be in the future');
                isValid = false;
            }

            if (this.endDate > today) {
                endInput.setCustomValidity('End Date cannot be in the future');
                isValid = false;
            }
        }

        startInput.reportValidity();
        endInput.reportValidity();

        return isValid;
    }

    // 🔹 SHOW REPORT
    handleShowReport() {
        if (!this.validateDateInputs()) return;

        let baseUrl = '/lightning/r/Report/00Odz000004DqjFEAS/view';
        let params = [];

        if (this.selectedLocations?.length > 0) {
            params.push('fv0=' + encodeURIComponent(this.selectedLocations.join(',')));
        }

        if (this.startDate) {
            params.push('fv1=' + encodeURIComponent(this.formatDate(this.startDate)));
        }

        if (this.endDate) {
            params.push('fv2=' + encodeURIComponent(this.formatDate(this.endDate)));
        }

        let finalUrl = baseUrl + '?' + params.join('&');

        window.open(finalUrl, '_blank');
    }

    formatDate(dateValue) {
         let date = (dateValue instanceof Date)
            ? dateValue
            : this.parseLocalDate(dateValue);

        let yyyy = date.getFullYear();
        let mm = String(date.getMonth() + 1).padStart(2, '0');
        let dd = String(date.getDate()).padStart(2, '0');

        return `${yyyy}-${mm}-${dd}`;
    }

    parseLocalDate(dateStr) {
        if (!dateStr) return null;
        const [yyyy, mm, dd] = dateStr.split('-').map(Number);
        return new Date(yyyy, mm - 1, dd); // Local timezone, not UTC
    }

    // 🔹 START SYNC
    handleStartSync() {
        if (!this.validateDateInputs()) return;

        startBatchSync({
            startDate: this.startDate,
            endDate: this.endDate,
            locations: this.selectedLocations
        })
        .then(result => {
            this.showToast('Success', result, 'success');

            setTimeout(() => {
                window.location.href = '/lightning/o/Billing__c/list?filterName=Synced_Billing_Records';
            }, 5000);
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}