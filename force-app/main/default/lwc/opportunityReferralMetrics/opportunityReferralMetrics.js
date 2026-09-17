import { LightningElement, api, wire, track } from 'lwc';
import getOpportunityMetrics from '@salesforce/apex/OpportunityMetricsController.getOpportunityMetrics';
import runBatch from '@salesforce/apex/OpportunityMetricsController.runOpportunityBatch';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';

export default class OpportunityReferralMetrics extends LightningElement {
    @api recordId;

    @track opportunity;
    loading = false;
    wiredResult;

    @wire(getOpportunityMetrics, { opportunityId: '$recordId' })
    wiredOpportunity(result) {
        this.wiredResult = result;

        if (result.data) {
            this.opportunity = result.data;
        } else if (result.error) {
            this.opportunity = null;
            this.showToast('Error', 'Failed to load metrics', 'error');
            console.error(result.error);
        }
    }

    // get formattedDate() {
    //     return this.opportunity?.LastModifiedDate
    //         ? new Date(this.opportunity.LastModifiedDate).toLocaleString()
    //         : '—';
    // }

   get formattedDate() {
    return this.opportunity?.LastModifiedDate
        ? new Date(this.opportunity.LastModifiedDate).toLocaleString('en-US', {
            timeZone: 'America/Chicago',
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        })
        : '—';
}

    get lifetimeRevenue() {
        return this.opportunity?.Lifetime_Revenue__c ?? 0;
    }
    get prospectsReferred() {
    return this.opportunity?.Prospects_Referred__c ?? 0;
    }

    get clientsReferred() {
    return this.opportunity?.Clients_Referred__c ?? 0;
    }


    async handleSync() {
        this.loading = true;

        try {
            await runBatch();

            this.showToast(
                'Sync Started',
                'Opportunity metrics are being refreshed. Please wait...',
                'success'
            );

            setTimeout(async () => {
                await refreshApex(this.wiredResult);
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                this.dispatchEvent(new RefreshEvent());

                this.loading = false;
            }, 5000);

        } catch (error) {
            this.showToast(
                'Error',
                error?.body?.message || 'Unable to sync data',
                'error'
            );
            console.error(error);
            this.loading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}