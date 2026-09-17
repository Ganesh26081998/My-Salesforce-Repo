import { LightningElement, api, wire, track } from 'lwc';
import getContactMetrics from '@salesforce/apex/ContactReferralMetricsController.getContactMetrics';
import runBatch from '@salesforce/apex/ContactReferralMetricsController.runBatch';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import LOCALE from '@salesforce/i18n/locale';

export default class ContactReferralMetrics extends LightningElement {
    @api recordId;

    @track contact;
    loading = false;
    wiredResult;

    /* Fetch contact metrics safely */
    @wire(getContactMetrics, { contactId: '$recordId' })
    wiredContact(result) {
        this.wiredResult = result;

        if (result.data) {
            this.contact = result.data;
        } else if (result.error) {
            this.contact = null;
            this.showToast(
                'Error',
                'Failed to load referral metrics',
                'error'
            );
            console.error(result.error);
        }
    }

    /* Safe formatted date */
    get formattedDate() {
        return this.contact?.Records_Updated_On__c
            ? new Date(this.contact.Records_Updated_On__c).toLocaleString(LOCALE, {
              timeZone: TIME_ZONE
          })
        : '—';
            
    }
    
    get lifetimeRevenue() {
        return this.contact?.Lifetime_Revenue__c ?? 0;
    }
    get prospectsReferred() {
        return this.contact?.Prospects_Referred__c ?? 0;
    }

    get clientsReferred() {
        return this.contact?.Clients_Referred__c ?? 0;
    }

    /* Sync button handler */
    async handleSync() {
    this.loading = true;

    try {
        await runBatch();

        this.showToast(
            'Sync Started',
            'Referral metrics refresh has started. Please refresh after a moment.',
            'success'
        );

        // Wait before refreshing (batch needs time)
        setTimeout(async () => {
            await refreshApex(this.wiredResult);
            this.loading = false;
        }, 5000); // 5 seconds (adjust if needed)

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

    /* Toast helper */
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