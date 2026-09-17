import { LightningElement, track, wire } from 'lwc';
import { subscribe, MessageContext } from 'lightning/messageService';
import BILLING_DATE_FILTER_CHANNEL from '@salesforce/messageChannel/billingDateFilter__c';
import runJob from '@salesforce/apex/EventBillingController.runJob';
import getJobStatus from '@salesforce/apex/EventBillingController.getJobStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class EventBillingJobUI extends LightningElement {

    @track status = 'Not Started';
    @track isRunning = false;
    @track jobId;
    @track lastRun;

    // ✅ ADDED: Dates received from the shared filter in EventPendingBillingList
    startDate;
    endDate;

    // ✅ ADDED: Message Service subscription
    subscription = null;

    @wire(MessageContext)
    messageContext;

    intervalId;

    connectedCallback() {
        this.refreshStatus();
        this.startAutoRefresh();
        // ✅ ADDED: Subscribe to date filter messages published by EventPendingBillingList
        this.subscribeToDateFilter();
    }

    disconnectedCallback() {
        clearInterval(this.intervalId);
    }

    // ✅ ADDED: Subscribe to Lightning Message Channel to receive shared dates
    subscribeToDateFilter() {
        if (this.subscription) return;
        this.subscription = subscribe(
            this.messageContext,
            BILLING_DATE_FILTER_CHANNEL,
            (message) => {
                // When user clicks Apply Filter in EventPendingBillingList,
                // these dates are automatically updated here too
                this.startDate = message.startDate;
                this.endDate = message.endDate;
            }
        );
    }

    // AUTO REFRESH EVERY 5 SEC — NO CHANGES
    startAutoRefresh() {
        this.intervalId = setInterval(() => {
            this.refreshStatus();
        }, 5000);
    }

    // ✅ CHANGED: Uses dates received from the shared filter via message channel
    handleRun() {
        if (!this.startDate || !this.endDate) {
            this.showToast('Error', 'Please select both Start Date and End Date using the filter below before running the job.', 'error');
            return;
        }

        this.isRunning = true;

        runJob({ startDate: this.startDate, endDate: this.endDate })
            .then(result => {
                if (result === 'ALREADY_RUNNING') {
                    this.showToast('Warning', 'Job already running', 'warning');
                    this.isRunning = true;
                    return;
                }

                this.jobId = result;
                this.showToast('Success', 'Job Started. ID: ' + result, 'success');
                this.refreshStatus();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
                this.isRunning = false;
            });
    }

    // NO CHANGES
    handleManualRefresh() {
        if (this.status === 'Completed' || this.status === 'Failed') {
            this.status = 'Not Started';
            this.jobId = null;
            this.isRunning = false;
            return;
        }
        this.refreshStatus();
    }

    // NO CHANGES
    refreshStatus() {
        if (!this.jobId) return;

        getJobStatus({ jobId: this.jobId })
            .then(result => {
                this.status = result.status;
                this.lastRun = result.createdDate;

                if (result === 'Processing' || result === 'Queued') {
                    this.isRunning = true;
                } else {
                    this.isRunning = false;
                }
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    // NO CHANGES
    get statusClass() {
        if (this.status === 'Completed') return 'slds-text-color_success';
        if (this.status === 'Failed') return 'slds-text-color_error';
        if (this.status === 'Processing' || this.status === 'Queued') return 'slds-text-color_warning';
        return '';
    }

    // NO CHANGES
    get lastRunTime() {
        if (!this.lastRun) return '-';
        return new Date(this.lastRun).toLocaleString('en-US', {
            timeZone: 'America/Chicago',
            timeZoneName: 'short'
        });
    }

    // NO CHANGES
    get statusPillClass() {
        let base = 'slds-badge slds-p-around_x-small status-pill ';
        if (this.status === 'Completed') return base + 'success';
        if (this.status === 'Failed') return base + 'error';
        if (this.status === 'Processing' || this.status === 'Queued') return base + 'warning';
        return base;
    }

    // NO CHANGES
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}