import { LightningElement, api } from 'lwc';
import activateAccount from '@salesforce/apex/AccountActivationController.activateAccount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';

export default class ActivateAccountAction extends LightningElement {
    @api recordId;
    showModal = true;
    loading = false;

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleConfirm() {
        this.loading = true;

        activateAccount({ accountId: this.recordId })
            .then(result => {
                this.showModal = false;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: result.success ? 'Success' : 'Error',
                        message: result.success ? 'Account activated successfully.' : result.message,
                        variant: result.success ? 'success' : 'error'
                    })
                );

                //  Refresh only the record page data
                getRecordNotifyChange([{ recordId: this.recordId }]);

                // Close the modal
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(error => {
                this.showModal = false;


                let errorMessage = 'Unknown error';

                // Validation Rule / DML Errors
                if (error?.body?.output?.errors?.length) {
                    errorMessage = error.body.output.errors
                        .map(err => err.message)
                        .join(', ');
                }
                else if (error?.body?.message) {
                    errorMessage = error.body.message;
                }

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message:errorMessage,
                        variant: 'error'
                    })
                );

                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .finally(() => {
                this.loading = false;
            });
    }
}