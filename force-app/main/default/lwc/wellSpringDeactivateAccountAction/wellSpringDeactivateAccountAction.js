import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
// import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import ACCOUNT_NAME          from '@salesforce/schema/Account.Name';
import ACCOUNT_STATUS        from '@salesforce/schema/Account.Account_Status__c';
import getDeactivationReasonOptions from '@salesforce/apex/WellSpringAccountDeactivationController.getDeactivationReasonOptions';
// import ACCOUNT_DEACTIVATION_OBJECT from '@salesforce/schema/Account_Deactivation__c';
// import DEACTIVATION_REASON_FIELD   from '@salesforce/schema/Account_Deactivation__c.Deactivation_Reason__c';
import createDeactivationRecord from '@salesforce/apex/WellSpringAccountDeactivationController.createDeactivationRecord';
import isAccountDeactivated     from '@salesforce/apex/WellSpringAccountDeactivationController.isAccountDeactivated';

const ACCOUNT_FIELDS = [ACCOUNT_NAME, ACCOUNT_STATUS];

export default class WellSpringDeactivateAccountAction extends LightningElement {
    @api recordId;

    // @track recordTypeId      = null;
    accountLoaded            = false;
    deactivationChecked      = false;
    isDeactivated            = false;
    _closing                 = false;
    accountStatus            = '';
    accountName              = '';
    // _objectInfo              = null;
    saving                   = false;
    showConfirmModal         = false;
    reasonOptions            = [];

    formName        = '';
    formDate        = null;
    formReason      = '';
    formOtherReason = '';
    formComments    = '';

    @wire(getRecord, { recordId: '$recordId', fields: ACCOUNT_FIELDS })
    wiredAccount({ data, error }) {
        if (data) {
            this.accountName   = getFieldValue(data, ACCOUNT_NAME)   || '';
            this.accountStatus = getFieldValue(data, ACCOUNT_STATUS) || '';
            this.accountLoaded = true;
            this.formName      = this.accountName || '';
            this.formDate = this._todayAsIsoDate();
            this._checkDeactivationStatus();
            // this._resolveRecordType();
        } else if (error) {
            this._showToast('Error', 'Failed to load account details.', 'error');
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }

    // @wire(getObjectInfo, { objectApiName: ACCOUNT_DEACTIVATION_OBJECT })
    // wiredObjectInfo({ data, error }) {
    //     if (data) {
    //         this._objectInfo = data;
    //         this._resolveRecordType();
    //     } else if (error) {
    //         this._showToast('Error', 'Failed to load object metadata.', 'error');
    //         this.dispatchEvent(new CloseActionScreenEvent());
    //     }
    // }

    // @wire(getPicklistValues, {
    //     recordTypeId: '$recordTypeId',
    //     fieldApiName: DEACTIVATION_REASON_FIELD
    // })
    // wiredPicklistValues({ data }) {
    //     if (data) {
    //         this.reasonOptions = data.values.map(v => ({ label: v.label, value: v.value }));
    //         const validReasonValues = new Set(this.reasonOptions.map(option => option.value));
    //         if (this.formReason && !validReasonValues.has(this.formReason)) {
    //             this.formReason = '';
    //             this.formOtherReason = '';
    //         }
    //     }
    // }

    @wire(getDeactivationReasonOptions)
    wiredReasonOptions({ data, error }) {
        if (data) {
            this.reasonOptions = data.map(value => ({ label: value, value }));

            const validReasonValues = new Set(this.reasonOptions.map(option => option.value));
            if (this.formReason && !validReasonValues.has(this.formReason)) {
                this.formReason = '';
                this.formOtherReason = '';
            }
        } else if (error) {
            this._showToast('Error', 'Failed to load deactivation reasons.', 'error');
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }

    _checkDeactivationStatus() {
        if (this.deactivationChecked) return;

        isAccountDeactivated({ accountId: this.recordId })
            .then(result => {
                this.deactivationChecked = true;
                if (result) {
                    this._closing = true;
                    this._showToast(
                        'Account Already Deactivated',
                        'This account is deactivated. You cannot edit it. Take the backup first.',
                        'warning'
                    );
                    this.dispatchEvent(new CloseActionScreenEvent());
                    return;
                }
                this.isDeactivated = false;
            })
            .catch(() => {
                this.deactivationChecked = true;
            });
    }

    // _resolveRecordType() {
    //     if (!this._objectInfo || !this.accountStatus) return;
    //     const matched = Object.values(this._objectInfo.recordTypeInfos).find(
    //         rt => rt.name === this.accountStatus && !rt.master
    //     );
    //     if (matched) {
    //         this.recordTypeId = matched.recordTypeId;
    //     }
    // }

    _loadExistingDeactivationData() {
        // Intentionally not loading historical deactivation data.
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _todayAsIsoDate() {
        return new Date().toISOString().slice(0, 10);
    }

    get isLoading() {
        if (!this.accountLoaded || !this.deactivationChecked) return true;
        if (this.isDeactivated) return false;
        return false;
    }

    get isReady() {
        return !this.isLoading && !this._closing;
    }

    get modalTitle() {
        return this.isDeactivated
            ? 'Account Already Deactivated'
            : `Deactivate ${this.accountStatus} Account`;
    }

    get showDeactivatedBanner() {
        return !this.saving && this.isDeactivated;
    }

    get showConfirmView() {
        return !this.saving && !this.isDeactivated && this.showConfirmModal;
    }

    get showFormFields() {
        return !this.saving && !this.isDeactivated && !this.showConfirmModal;
    }

    get showOtherReasonField() {
        return this.formReason === 'Other';
    }

    get showDeactivatedFooter() {
        return this.isDeactivated;
    }

    get showConfirmFooter() {
        return !this.isDeactivated && this.showConfirmModal;
    }

    get showNormalFooter() {
        return !this.isDeactivated && !this.showConfirmModal;
    }

    handleKeyDown(e) {
        if (e.key === 'Enter') {
            e.preventDefault();
            e.stopPropagation();
        }
    }

    handleReasonChange(e) {
        this.formReason = e.detail.value;
        if (this.formReason !== 'Other') {
            this.formOtherReason = '';
        }
    }
    handleOtherReasonChange(e) { this.formOtherReason = e.detail.value; }
    handleCommentsChange(e)    { this.formComments = e.detail.value; }

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleSave() {
        if (this.isDeactivated) {
            this._showToast(
                'Account Already Deactivated',
                'This account is deactivated. You cannot edit it. Take the backup first.',
                'warning'
            );
            return;
        }
        if (!this.formName || !this.formName.trim()) {
            this._showToast('Validation Error', 'Account Name is required.', 'error');
            return;
        }
        if (!this.formReason) {
            this._showToast('Validation Error', 'Deactivation Reason is required.', 'error');
            return;
        }
        if (this.formReason === 'Other' && (!this.formOtherReason || !this.formOtherReason.trim())) {
            this._showToast('Validation Error', 'Other Reason is required when reason is Other.', 'error');
            return;
        }
        this.showConfirmModal = true;
    }

    handleCancelConfirm() {
        this.showConfirmModal = false;
    }

    handleConfirm() {
        this.showConfirmModal = false;
        this.saving = true;

        createDeactivationRecord({
            accountId:           this.recordId,
            name:                this.formName.trim(),
            deactivationDate:    this.formDate,
            deactivationReason:  this.formReason,
            otherReason:         this.formOtherReason ? this.formOtherReason.trim() : '',
            deactivationSummary: this.formComments
            // recordTypeId:        this.recordTypeId
        })
        .then(() => {
            this._showToast(
                'Account Deactivated',
                `${this.accountStatus} account has been deactivated successfully.`,
                'success'
            );
            this.dispatchEvent(new CloseActionScreenEvent());
            // eslint-disable-next-line no-restricted-globals
            window.location.reload();
        })
        .catch(error => {
            const msg = error?.body?.message ?? error?.message ?? 'An unexpected error occurred.';
            this._showToast('Deactivation Failed', msg, 'error');
        })
        .finally(() => {
            this.saving = false;
        });
    }
}