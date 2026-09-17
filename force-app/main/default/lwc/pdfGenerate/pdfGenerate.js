import { LightningElement, api } from 'lwc';
import generatePdf from '@salesforce/apex/InvoiceService.generatePdf';
import getRelatedPatients from '@salesforce/apex/InvoiceService.getRelatedPatients';
import generateSuperBill from '@salesforce/apex/InvoiceService.generateSuperBill';
import checkSuperBillEligibility from '@salesforce/apex/InvoiceService.checkSuperBillEligibility';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PdfGenerate extends LightningElement {

    primaryAccountId;
    fromDate;
    toDate;

    showModal = false;
    relatedPatients = [];

    selectAll = false;

    /* ===============================
       INVOICE DOWNLOAD
    =============================== */
    @api
    downloadInvoice(accountId, fromDate, toDate) {
        console.log('fromDate: ',fromDate);
        console.log('toDate: ',toDate);

        generatePdf({
            accountId: accountId,
            fromDateStr: fromDate,
            toDateStr: toDate
        })
        .then(url => {
            window.open(url, '_blank');
        })
        .catch(error => {
            this.showError('Invoice Error', error);
        });
    }


    /* ===============================
       SUPER BILL ENTRY POINT
    =============================== */
    @api
    async handleSuperBillRequest(accountId, fromDate, toDate) {

        this.primaryAccountId = accountId;
        this.fromDate = fromDate;
        this.toDate = toDate;

        try {
            const related = await getRelatedPatients({
                primaryAccountId: accountId
            });

            // 0 Related → Generate Primary Only
            if (!related || related.length === 0) {
                // this.callGenerate([]);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'No Related Clients',
                        message: 'There are no related clients available for Household Invoice generation.',
                        variant: 'warning'
                    })
                );
                return;
            }

            // 1 Related → Auto include
            if (related.length === 1) {
                this.callGenerate([related[0].accountId]);
                return;
            }

            // More than 1 → Show Modal
            this.relatedPatients = related.map(r => ({
                contactId: r.contactId,
                accountId: r.accountId,
                name: r.name,
                roleName: r.roleName,
                selected: false
            }));

            this.showModal = true;
            this.selectAll = false;

        } catch (error) {
            this.showError('Super Bill Error', error);
        }
    }


    /* ===============================
       CALL GENERATE APEX
    =============================== */
    async callGenerate(selectedAccountIds) {

        try {

            console.log('In try');

            console.log('selectedAccountIds : ',JSON.stringify(selectedAccountIds));

            console.log('primaryAccountId:', this.primaryAccountId);
                console.log('selectedRelatedAccountIds:', selectedAccountIds);
                console.log('fromDateStr:', this.fromDate);
                console.log('toDateStr:', this.toDate);

            const eligibility = await checkSuperBillEligibility({
                primaryAccountId: this.primaryAccountId,
                selectedRelatedAccountIds: selectedAccountIds,
                fromDateStr: this.fromDate,
                toDateStr: this.toDate
            });

            console.log('In try eligibility',eligibility);

            // if (!eligibility.hasPrimaryBillables) {
            //     this.showToast(
            //         'No Primary Billables',
            //         'Primary client has no billables in selected date range.',
            //         'warning'
            //     );
            //     return;
            // }

            // if (!eligibility.validRelatedAccountIds ||
            //     eligibility.validRelatedAccountIds.length === 0) {

            //     this.showToast(
            //         'No Related Billables',
            //         'Selected related clients have no billables in selected date range.',
            //         'warning'
            //     );
            //     return;
            // }

            const hasPrimary = eligibility.hasPrimaryBillables;
            const validRelated = eligibility.validRelatedAccountIds || [];

            // Only stop if neither Primary nor Related has billables
            if (!hasPrimary && validRelated.length === 0) {
                this.showToast(
                    'No Billables',
                    'No billables found in the selected date range.',
                    'warning'
                );
                return;
            }

            // Only pass valid related
            // const url = await generateSuperBill({
            //     primaryAccountId: this.primaryAccountId,
            //     selectedRelatedAccountIds: eligibility.validRelatedAccountIds,
            //     fromDateStr: this.fromDate,
            //     toDateStr: this.toDate
            // });
            const url = await generateSuperBill({
    primaryAccountId: this.primaryAccountId,
    selectedRelatedAccountIds: validRelated,
    fromDateStr: this.fromDate,
    toDateStr: this.toDate
});

window.open(url, '_blank');

            

        } catch (error) {
            console.log('error',JSON.stringify(error));
            this.showError('Super Bill Error', error);
        }
    }

    /* ===============================
       MODAL ACTIONS
    =============================== */

    handleCheckboxChange(event) {
        const accId = event.target.dataset.id;
        const checked = event.target.checked;

        this.relatedPatients = this.relatedPatients.map(p => {
            if (p.accountId === accId) {
                return { ...p, selected: checked };
            }
            return p;
        });

        this.selectAll = this.relatedPatients.every(p => p.selected);
    }

    handleSelectAll(event) {
        const checked = event.target.checked;

        this.selectAll = checked;

        this.relatedPatients = this.relatedPatients.map(p => ({
            ...p,
            selected: checked
        }));

        // this.selectAll = this.relatedPatients.every(p => p.selected);
    }

    handleGenerateClick() {

        const selectedIds = this.relatedPatients
            .filter(p => p.selected)
            .map(p => p.accountId);

        if (selectedIds.length === 0) {
            return;
        }

        this.showModal = false;
        this.callGenerate(selectedIds);
    }

    handleCancel() {
        this.showModal = false;
        this.selectAll = false;
    }

    get isGenerateDisabled() {
        return !this.relatedPatients?.some(p => p.selected);
    }


    /* ===============================
       TOAST HELPER
    =============================== */
    showError(title, error) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: error?.body?.message || 'Something went wrong',
                variant: 'error'
            })
        );
    }

    showToast(title, message, variant) {
    this.dispatchEvent(
        new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        })
    );
}

}