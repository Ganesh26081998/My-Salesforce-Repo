import { api } from 'lwc';
import LightningModal from 'lightning/modal';
export default class RateCalculationConfirmationModal extends LightningModal {
    @api message;

    handleConfirm() {
    this.close(true);
    }
    handleCancel() {
    this.close(false);
    }

}