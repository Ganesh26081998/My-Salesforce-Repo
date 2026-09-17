import { LightningElement, track } from 'lwc';
import runBatch from '@salesforce/apex/WeeklyCapacityController.runBatch';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class RunWeeklyCapacity extends LightningElement {

    @track isLoading = false;

    handleRunBatch() {
        this.isLoading = true;

        runBatch()
            .then(() => {
                this.showToast('Success', 'Batch started successfully', 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}