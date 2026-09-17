import { LightningElement, api, wire, track } from 'lwc';
import getContactMetricsSummary from '@salesforce/apex/BusinessAccountContactMetricsController.getContactMetricsSummary';
import runAccountBatch from '@salesforce/apex/BusinessAccountContactMetricsController.runAccountBatch';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// import saveMetricsToAccount from '@salesforce/apex/BusinessAccountContactMetricsController.saveMetricsToAccount';

export default class BusinessAccountContactMetrics extends LightningElement {
    @api recordId;

    @track metrics;
    loading = false;
    wiredResult;

    /* Fetch aggregated contact metrics for this Business Account */
    @wire(getContactMetricsSummary, { accountId: '$recordId' })
    wiredMetrics(result) {
        this.wiredResult = result;

        if (result.data) {
            this.metrics = result.data;
            
        
        } else if (result.error) {
            this.metrics = null;
            this.showToast(
                'Error',
                'Failed to load contact referral metrics',
                'error'
            );
            console.error(result.error);
        }
    }

    /* Format lifetime revenue as USD currency */
    get formattedRevenue() {
        const revenue = this.metrics?.lifetimeRevenue || 0;
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2
        }).format(revenue);
    }

    /* Refresh handler — re-fetches live data from Salesforce */
    // async handleRefresh() {
    //     this.loading = true;

    //     try {
    //         await refreshApex(this.wiredResult);
    //         this.showToast('Refreshed', 'Contact metrics updated successfully', 'success');
    //     } catch (error) {
    //         this.showToast(
    //             'Error',
    //             error?.body?.message || 'Unable to refresh data',
    //             'error'
    //         );
    //         console.error(error);
    //     } finally {
    //         this.loading = false;
    //     }
    // }
//     async handleRefresh() {
//     this.loading = true;

//     try {
//         await refreshApex(this.wiredResult);

//         if (this.metrics) {
//             await saveMetricsToAccount({
//                 accountId: this.recordId,
//                 clientsReferred: this.metrics.clientsReferred,
//                 prospectsReferred: this.metrics.prospectsReferred,
//                 lifetimeRevenue: this.metrics.lifetimeRevenue
//             });
//         }

//         this.showToast('Refreshed', 'Contact metrics updated successfully', 'success');
//     } catch (error) {
//         this.showToast(
//             'Error',
//             error?.body?.message || 'Unable to refresh data',
//             'error'
//         );
//         console.error(error);
//     } finally {
//         this.loading = false;
//     }
// }


async handleRefresh() {
        this.loading = true;
        try {
            // Kickoff asynchronous system-wide batch sync
            await runAccountBatch();

            this.showToast(
                'Sync Running', 
                'Account calculations are updating in the background. Refreshing layout shortly...', 
                'info'
            );

            // Wait 5 seconds for the database transactions to update records
            setTimeout(async () => {
                await refreshApex(this.wiredResult);
                this.loading = false;
                this.showToast('Updated', 'Account metrics refreshed successfully', 'success');
            }, 5000);

        } catch (error) {
            this.showToast(
                'Sync Error',
                error?.body?.message || 'Unable to start background sync execution.',
                'error'
            );
            console.error(error);
            this.loading = false;
        }
    }

    /* Toast helper */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}