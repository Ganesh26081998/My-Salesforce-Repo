import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLocationPicklistValues from '@salesforce/apex/ClientInvoiceController.getLocationPicklistValues';
import getAccountsForBulkInvoice from '@salesforce/apex/ClientInvoiceController.getAccountsForBulkInvoice';
import startBulkInvoiceEmail  from '@salesforce/apex/InvoiceService.startBulkInvoiceEmail';
import getZipJobStatus from '@salesforce/apex/InvoiceService.getZipJobStatus';
import startBulkInvoiceDownload from '@salesforce/apex/InvoiceService.startBulkInvoiceZip';
import getInvoicesForAccounts from '@salesforce/apex/InvoiceService.getInvoicesForAccounts';
import hasBillingsInRange from '@salesforce/apex/InvoiceService.hasBillingsInRange';
import checkSuperBillEligibility from '@salesforce/apex/InvoiceService.checkSuperBillEligibility';
import getRelatedPatients from '@salesforce/apex/InvoiceService.getRelatedPatients';
import generatePdfForPreview from '@salesforce/apex/InvoiceService.generatePdfForPreview';
import generateSuperBillForPreview from '@salesforce/apex/InvoiceService.generateSuperBillForPreview';
import getInvoiceEmailStatus from '@salesforce/apex/ClientInvoiceController.getInvoiceEmailStatus';
import getServicePeriods from '@salesforce/apex/ClientInvoiceController.getServicePeriods';

const POLL_INTERVAL_MS = 4000;
const PERIOD_CUSTOM    = 'custom';
const TWO_WEEK_DAYS    = 14;

export default class ClientInvoiceSearch extends LightningElement {

    // ── Date / period state ────────────────────────────────────────────────
    @track fromDate        = '';
    @track toDate          = '';
    @track selectedPeriod  = '';
    @track periodOptions   = [];

    // ── Filter state ───────────────────────────────────────────────────────
    @track selectedLocation      = 'All';
    @track locationOptions       = [];
    @track selectedPrimaryFilter = 'all';
    @track clientName            = '';
    @track isFilterChanged       = false;

    // ── Table / result state ───────────────────────────────────────────────
    @track clientData    = [];
    @track isLoading     = false;
    @track showResults   = false;
    @track showNoResults = false;
    @track totalRecords  = 0;
    @track sortedBy;
    @track sortedDirection = 'asc';

    // ── Bulk / ZIP state ───────────────────────────────────────────────────
    isDownloading     = false;
    progressValue     = 0;
    _progressInterval = null;
    showInvoiceLinks  = false;
    isBulkProcessing  = false;
    bulkJobId         = null;
    zipDownloadUrl;
    @track jobStatus  = null;
    @track jobError   = null;
    _pollTimer        = null;
    @track selectedRows = [];

    // ── Preview modal state ────────────────────────────────────────────────
    @track showPreviewModal      = false;
    @track previewClientName     = '';
    @track previewInvoiceGroups  = [];
    @track isLoadingInvoices     = false;
    _previewAccountIds           = [];

    primaryOptions = [
        { label: 'All',   value: 'all'   },
        { label: 'Yes',   value: 'true'  },
        { label: 'No',    value: 'false' }
    ];

    @track selectedSendInvoiceFilter = 'all';

    // ── Download modal state ───────────────────────────────────────────────
    @track showDownloadModal                  = false;
    @track downloadModalTitle                 = '';
    @track downloadModalInvoiceType           = '';
    @track downloadModalShowHouseholdChoice   = false;
    @track downloadPeriods                    = [];
    @track isLoadingDownloadModal             = false;
    _downloadSelectedRows                     = [];

    sendInvoiceOptions = [
        { label: 'All', value: 'all'   },
        { label: 'Yes', value: 'true'  },
        { label: 'No',  value: 'false' }
    ];

    columns = [
        { type: 'checkbox', fixedWidth: 40 },
        {
            label: 'Client Name',
            fieldName: 'accountUrl',
            type: 'url',
            sortable: true,
            typeAttributes: {
                label:   { fieldName: 'Name' },
                tooltip: { fieldName: 'Name' },
                target:  '_blank'
            }
        },
        { label: 'Location',               fieldName: 'Location_g__c',  type: 'text',    sortable: true },        
        { label: 'Couple Household Account?', fieldName: 'Is_Primary__c',             type: 'boolean', sortable: true },
        { label: 'Send Invoice To Client?',   fieldName: 'Send_Invoice_to_Client__c', type: 'boolean', sortable: true },
        {
            label: 'Invoice Emailed',
            fieldName: 'invoiceEmailed',
            type: 'boolean',
            sortable: true
        },
        {
            label: '',
            type: 'button-icon',
            fixedWidth: 52,
            typeAttributes: {
                iconName:        'utility:preview',
                variant:         'border-filled',
                alternativeText: 'Preview Invoice',
                title:           'Preview Invoice',
                name:            'preview_invoice'
            }
        }
    ];

    // ── Lifecycle ──────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadLocationPicklist();
        // this.buildPeriodOptions();
        this.loadServicePeriods();
    }

    disconnectedCallback() { this._stopPolling(); }

    // ── Getters ────────────────────────────────────────────────────────────

    get today() {
        return this._getToday();
    }

    get maxServicePeriodEndDate() {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const dayOfWeek     = today.getDay();
        const daysToLastSat = dayOfWeek === 6 ? 0 : dayOfWeek + 1;
        const lastSat       = new Date(today);
        lastSat.setDate(today.getDate() - daysToLastSat);
        return this.formatDate(lastSat);
    }

    get isResetDisabled()  { return !this.isFilterChanged; }
    get isCustomPeriod()   { return this.selectedPeriod === PERIOD_CUSTOM; }
    get isCompleted()      { return this.jobStatus === 'Completed';  }
    get isFailed()         { return this.jobStatus === 'Failed';     }
    get isProcessing()     { return this.jobStatus === 'Processing'; }

    get isDownloadDisabled() {
        if (!this.selectedRows || this.selectedRows.length === 0) return true;
        const hasNonPrimary = this.clientData.some(
            row => this.selectedRows.includes(row.Id) && row.Is_Primary__c !== true
        );
        return !hasNonPrimary || this.isBulkProcessing;
    }

    get showHouseholdDownload() {
        if (!this.selectedRows || this.selectedRows.length === 0) return false;
        return this.clientData.some(
            row => this.selectedRows.includes(row.Id) && row.Is_Primary__c === true
        );
    }

    get isHouseholdDisabled()      { return !this.showHouseholdDownload || this.isBulkProcessing; }

    get isEmailDisabled() {
        if (!this.selectedRows || this.selectedRows.length === 0) return true;
        const hasNonPrimary = this.clientData.some(
            row => this.selectedRows.includes(row.Id) && row.Is_Primary__c !== true
        );
        return !hasNonPrimary || this.isBulkProcessing;
    }

    get isEmailHouseholdDisabled() { return !this.showHouseholdDownload || this.isBulkProcessing; }

    get noPreviewInvoices() {
        return !this.isLoadingInvoices &&
               (!this.previewInvoiceGroups || this.previewInvoiceGroups.length === 0);
    }

    get noDownloadPeriods() {
        return !this.isLoadingDownloadModal &&
               (!this.downloadPeriods || this.downloadPeriods.length === 0);
    }

    get allPeriodsSelected() {
        return this.downloadPeriods.length > 0 && this.downloadPeriods.every(p => p.selected);
    }

    get noPeriodsSelected() {
        return !this.downloadPeriods.some(p => p.selected);
    }

    get isSearchDisabled() {
        if (!this.fromDate || !this.toDate) return true;
        return this.toDate > this.maxServicePeriodEndDate;
    }   
   
    _resolveEffectiveDates(fromDateStr, toDateStr) {
        if (this.selectedPeriod !== PERIOD_CUSTOM) {
            return { effectiveFrom: fromDateStr, effectiveTo: toDateStr };
        }
        return {
            effectiveFrom: this._snapToPeriodStart(fromDateStr),
            effectiveTo:   this._snapToPeriodEnd(toDateStr)
        };
    }

    _resolvePreviewDates(fromDateStr, toDateStr) {        
        return { effectiveFrom: fromDateStr, effectiveTo: toDateStr };
    }

    _snapToPeriodStart(dateStr) {
        const input     = new Date(dateStr + 'T00:00:00');
        let   periodEnd = new Date(this._getLastCompletedSaturday());
        while (periodEnd >= input) {
            const periodStart = new Date(periodEnd);
            periodStart.setDate(periodEnd.getDate() - 13);
            if (input >= periodStart && input <= periodEnd) return this.formatDate(periodStart);
            periodEnd = new Date(periodStart);
            periodEnd.setDate(periodStart.getDate() - 1);
        }
        return dateStr;
    }

    _snapToPeriodEnd(dateStr) {
        const input     = new Date(dateStr + 'T00:00:00');
        let   periodEnd = new Date(this._getLastCompletedSaturday());
        while (periodEnd >= input) {
            const periodStart = new Date(periodEnd);
            periodStart.setDate(periodEnd.getDate() - 13);
            if (input >= periodStart && input <= periodEnd) return this.formatDate(periodEnd);
            periodEnd = new Date(periodStart);
            periodEnd.setDate(periodStart.getDate() - 1);
        }
        return dateStr;
    }

    _getLastCompletedSaturday() {
        const today         = new Date(this._getToday() + 'T00:00:00');
        const dayOfWeek     = today.getDay();
        // For maxServicePeriodEndDate we still want last completed Saturday
        const daysToLastSat = dayOfWeek === 6 ? 0 : dayOfWeek + 1;
        const lastSat       = new Date(today);
        lastSat.setDate(today.getDate() - daysToLastSat);
        return lastSat;
    }
    

    handleRowAction(event) {
        const row = event.detail.row;

        if (this.selectedPeriod === PERIOD_CUSTOM) {
            const { effectiveFrom, effectiveTo } = this._resolvePreviewDates(
                this.fromDate, this.toDate
            );
            const periods = this._splitIntoPeriods(effectiveFrom, effectiveTo);

            if (periods.length === 1) {
                try {
                    if (row.Is_Primary__c === true) {
                        this.template.querySelector('c-pdf-generate')
                            .handleSuperBillRequest(row.Id, periods[0].fromDate, periods[0].toDate);
                    } else {
                        this.template.querySelector('c-pdf-generate')
                            .downloadInvoice(row.Id, periods[0].fromDate, periods[0].toDate);
                    }
                } catch (error) {
                    this.showToast('No Billables',
                        error?.body?.message || 'No billable services found for selected period.',
                        'warning');
                }
                return;
            }
            
            if (row.Is_Primary__c === true) {
                this._openPreviewModal([row.Id], row.Name, 'Household Invoice', effectiveFrom, effectiveTo);
            } else {
                this._openPreviewModal([row.Id], row.Name, 'Standard Invoice', effectiveFrom, effectiveTo);
            }
            return;
        }

        // Non-custom: period boundaries are already exact; no snapping needed.
        try {
            if (row.Is_Primary__c === true) {
                this.template.querySelector('c-pdf-generate')
                    .handleSuperBillRequest(row.Id, this.fromDate, this.toDate);
            } else {
                this.template.querySelector('c-pdf-generate')
                    .downloadInvoice(row.Id, this.fromDate, this.toDate);
            }
        } catch (error) {
            this.showToast('No Billables',
                error?.body?.message || 'No billable services found for selected period.',
                'warning');
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Invoice type filter helper (download/email restriction)
    // ═════════════════════════════════════════════════════════════════════════

    _filterRowsByInvoiceType(accountIds, invoiceType) {
        return this.clientData
            .filter(row => {
                if (!accountIds.includes(row.Id)) return false;
                if (invoiceType === 'Household Invoice') return row.Is_Primary__c === true;
                return row.Is_Primary__c !== true;
            })
            .map(row => row.Id);
    }

    _getToday() {
        // Use Intl to get today's date in the browser's local timezone
        // formatted as YYYY-MM-DD — avoids UTC offset shifting the date
        const now    = new Date();
        const year   = now.getFullYear();
        const month  = String(now.getMonth() + 1).padStart(2, '0');
        const day    = String(now.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Period helpers
    // ═════════════════════════════════════════════════════════════════════════

loadServicePeriods() {

    getServicePeriods()
        .then(result => {

            this.periodOptions = result;

            if (result.length > 1) {

                this.selectedPeriod = result[1].value;
                this._applyPeriodValue(result[1].value);

            }

        })
        .catch(error => {
            console.error(error);
        });
}

//     buildPeriodOptions() {
//     const options = [{ label: 'Custom', value: PERIOD_CUSTOM }];

//     // Use US Central Time
//     const today = new Date(
//         new Date().toLocaleString('en-US', {
//             timeZone: 'America/Chicago'
//         })
//     );
//     today.setHours(0, 0, 0, 0);

//     const MS_PER_DAY = 24 * 60 * 60 * 1000;
//     const CYCLE_DAYS = 14;

//     // Anchor Billing Sunday (first billing run)
//     const billingAnchor = new Date(2026, 5, 14); // June 14, 2026

//     // Service period for first billing run
//     const serviceAnchorStart = new Date(2026, 4, 31); // May 31, 2026
//     const serviceAnchorEnd = new Date(2026, 5, 13);   // June 13, 2026

//     const diffDays = Math.floor(
//         (today.getTime() - billingAnchor.getTime()) / MS_PER_DAY
//     );

//     let cycleIndex;

//     if (diffDays < 0) {
//         cycleIndex = 0;
//     } else {
//         cycleIndex = Math.floor(diffDays / CYCLE_DAYS);
//     }

//     let periodStart = new Date(serviceAnchorStart);
//     periodStart.setDate(serviceAnchorStart.getDate() + (cycleIndex * CYCLE_DAYS));

//     let periodEnd = new Date(serviceAnchorEnd);
//     periodEnd.setDate(serviceAnchorEnd.getDate() + (cycleIndex * CYCLE_DAYS));

//     for (let i = 0; i < 13; i++) {

//         options.push({
//             label:
//                 this.formatDateLabel(periodStart) +
//                 ' – ' +
//                 this.formatDateLabel(periodEnd),
//             value:
//                 this.formatDate(periodStart) +
//                 '|' +
//                 this.formatDate(periodEnd)
//         });

//         periodEnd = new Date(periodStart);
//         periodEnd.setDate(periodStart.getDate() - 1);

//         periodStart = new Date(periodEnd);
//         periodStart.setDate(periodEnd.getDate() - 13);
//     }

//     this.periodOptions = options;

//     if (options.length > 1) {
//         this.selectedPeriod = options[1].value;
//         this._applyPeriodValue(options[1].value);
//     }
// }

//     buildPeriodOptions() {
//     const options = [{ label: 'Custom', value: PERIOD_CUSTOM }];

//     // Business timezone (US Central)
//     const today = new Date(
//         new Date().toLocaleString('en-US', {
//             timeZone: 'America/Chicago'
//         })
//     );

//     today.setHours(0, 0, 0, 0);

//     const dayOfWeek = today.getDay(); // 0=Sun ... 6=Sat

//     let periodEnd;

//     if (dayOfWeek === 0) {
//         // Sunday billing run -> yesterday (Saturday)
//         periodEnd = new Date(today);
//         periodEnd.setDate(today.getDate() - 1);
//     } else {
//         // Any other day -> previous Saturday
//         const daysToLastSat = dayOfWeek + 1;
//         periodEnd = new Date(today);
//         periodEnd.setDate(today.getDate() - daysToLastSat);
//     }

//     for (let i = 0; i < 13; i++) {
//         const periodStart = new Date(periodEnd);
//         periodStart.setDate(periodEnd.getDate() - 13);

//         const label =
//             this.formatDateLabel(periodStart) +
//             ' – ' +
//             this.formatDateLabel(periodEnd);

//         const value =
//             this.formatDate(periodStart) +
//             '|' +
//             this.formatDate(periodEnd);

//         options.push({ label, value });

//         periodEnd = new Date(periodStart);
//         periodEnd.setDate(periodStart.getDate() - 1);
//     }

//     this.periodOptions = options;

//     if (options.length > 1) {
//         this.selectedPeriod = options[1].value;
//         this._applyPeriodValue(options[1].value);
//     }
// }

    _applyPeriodValue(value) {
        if (value === PERIOD_CUSTOM) return;
        const [start, end] = value.split('|');
        this.fromDate = start;
        this.toDate   = end;
    }

    formatDateLabel(date) {
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day   = String(date.getDate()).padStart(2, '0');
        return `${month}/${day}/${date.getFullYear()}`;
    }

    formatDate(date) {
        const year  = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day   = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    _splitIntoPeriods(fromDateStr, toDateStr) {
        const periods    = [];
        const overallEnd = new Date(toDateStr   + 'T00:00:00');
        let   chunkStart = new Date(fromDateStr + 'T00:00:00');

        while (chunkStart <= overallEnd) {
            const chunkEnd = new Date(chunkStart);
            chunkEnd.setDate(chunkEnd.getDate() + TWO_WEEK_DAYS - 1);
            const clamped = chunkEnd > overallEnd ? overallEnd : chunkEnd;
            periods.push({
                fromDate: this.formatDate(chunkStart),
                toDate:   this.formatDate(clamped)
            });
            chunkStart = new Date(clamped);
            chunkStart.setDate(chunkStart.getDate() + 1);
        }
        return periods;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Event handlers
    // ═════════════════════════════════════════════════════════════════════════

    handlePeriodChange(event) {
        this.selectedPeriod = event.detail.value;
        this._applyPeriodValue(this.selectedPeriod);
        this.isFilterChanged = true;
        this.clearSelections();
    }

    handleFromDateChange(event) {
        this.fromDate = event.target.value;
        this.isFilterChanged = true;
        this.clearSelections();
    }

    handleToDateChange(event) {
        const selectedDate = event.target.value;
        if (selectedDate > this.maxServicePeriodEndDate) {
            this.showToast('Invalid Service Period End',
                `Service Period End cannot be after ${this._fmtDate(this.maxServicePeriodEndDate)}.`,
                'warning');
            this.toDate = this.maxServicePeriodEndDate;
            return;
        }
        this.toDate = selectedDate;
        this.isFilterChanged = true;
        this.clearSelections();
    }

    handleLocationChange(event) {
        this.selectedLocation = event.detail.value;
        this.isFilterChanged  = true;
        this.clearSelections();
    }

    handlePrimaryFilterChange(event) {
        this.selectedPrimaryFilter = event.detail.value;
        this.isFilterChanged       = true;
        this.clearSelections();
    }

    handleClientNameChange(event) {
        this.clientName      = event.target.value;
        this.isFilterChanged = true;
        this.clearSelections();
    }

    handleSendInvoiceFilterChange(event) {
        this.selectedSendInvoiceFilter = event.detail.value;
        this.isFilterChanged           = true;
        this.clearSelections();
    }

    handleSearch() {
        if (!this.fromDate || !this.toDate) {
            this.showToast('Warning', 'Please select a Service Period or enter both start and end dates.', 'warning');
            return;
        }
        if (new Date(this.fromDate) > new Date(this.toDate)) {
            this.showToast('Warning', 'Service Period Start cannot be after Service Period End.', 'warning');
            return;
        }
        this.loadData();
    }

    handleReset() {
        // this.buildPeriodOptions();
        this.loadServicePeriods();
        this.selectedLocation          = 'All';
        this.selectedPrimaryFilter     = 'all';
        this.clientName                = '';
        this.clientData                = [];
        this.totalRecords              = 0;
        this.showResults               = false;
        this.showNoResults             = false;
        this.isFilterChanged           = false;
        this.showInvoiceLinks          = false;
        this.jobStatus                 = null;
        this.jobError                  = null;
        this.bulkJobId                 = null;
        this.isBulkProcessing          = false;
        this.selectedRows              = [];
        this.showPreviewModal          = false;
        this.selectedSendInvoiceFilter = 'all';
        this.showDownloadModal         = false;
        this._stopPolling();

        setTimeout(() => {
            const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox');
            inputs.forEach(input => {
                input.setCustomValidity('');
                input.reportValidity();
            });
        }, 0);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Data loading
    // ═════════════════════════════════════════════════════════════════════════

    loadData() {
        this.isLoading = true;
        getAccountsForBulkInvoice({
            fromDate:          this.fromDate,
            toDate:            this.toDate,
            location:          this.selectedLocation,
            clientName:        this.clientName,
            primaryFilter:     this.selectedPrimaryFilter,
            sendInvoiceFilter: this.selectedSendInvoiceFilter
        })
        .then(result => {            
            console.log('getAccountsForBulkInvoice result',JSON.stringify(result));
            this.clientData = result.map(client => ({
                ...client,
                Name:
                    client.LastName && client.FirstName
                        ? `${client.LastName}, ${client.FirstName}`
                        : client.Name,            
                accountUrl: '/' + client.Id
            }));
            getInvoiceEmailStatus({
                accountIds: this.clientData.map(c => c.Id),
                fromDate: this.fromDate,
                toDate: this.toDate
            })
            .then(statusMap => {

                this.clientData = this.clientData.map(client => ({
                    ...client,
                    invoiceEmailed: statusMap[client.Id] || false
                }));

            })
            .catch(error => {
                console.error(error);
            });
            this.totalRecords     = this.clientData.length;
            this.showResults      = this.clientData.length > 0;
            this.showNoResults    = this.clientData.length === 0;
            this.showInvoiceLinks = this.clientData.length > 0;
            this.isLoading        = false;
        })
        .catch(error => {
            this.isLoading        = false;
            this.showInvoiceLinks = false;
            this.showToast('Error', error.body?.message || error.message, 'error');
        });
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Preview Modal
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * Opens the invoice preview modal.
     *
     * overrideFrom / overrideTo (optional): when supplied, these dates are used
     * directly instead of deriving them from this.fromDate/toDate.
     * The row action handler passes the already-resolved preview dates here
     * so the modal always matches what the row action computed.
     */
    async _openPreviewModal(accountIds, clientLabel, invoiceType, overrideFrom, overrideTo) {
        console.log('_openPreviewModal');
        this.previewClientName    = clientLabel || '';
        this._previewAccountIds   = accountIds;
        this.showPreviewModal     = true;
        this.previewInvoiceGroups = [];
        this.isLoadingInvoices    = true;
        try {
console.log('_openPreviewModal try');
        // KEY FIX: use override dates when provided (from row action, which
        // uses _resolvePreviewDates — no snapping).
        // Fall back to _resolvePreviewDates for any other caller.
        const effectiveFrom = overrideFrom || this._resolvePreviewDates(this.fromDate, this.toDate).effectiveFrom;
        const effectiveTo   = overrideTo   || this._resolvePreviewDates(this.fromDate, this.toDate).effectiveTo;

        const periods = this._splitIntoPeriods(effectiveFrom, effectiveTo);


console.log('_openPreviewModal try periods');
        for (let i = 0; i < periods.length; i++) {

    const p = periods[i];

    // check existing invoices first
    // eslint-disable-next-line no-await-in-loop
    const existing = await getInvoicesForAccounts({
        accountIds:  accountIds,
        fromDateStr: p.fromDate,
        toDateStr:   p.toDate,
        invoiceType: invoiceType
    });

    
    // if no invoice exists for THIS specific account → generate it
    const existingForThisAccount = existing
        ? existing.filter(inv => inv.Client__c === accountIds[0])
        : [];

    if (!existingForThisAccount || existingForThisAccount.length === 0) {

        for (let j = 0; j < accountIds.length; j++) {

            const accId = accountIds[j];

             // For Household Invoice, check billings on the primary account
// AND on related accounts (Events are stored against patient accounts,
// not the household head's account).
let hasBills = await hasBillingsInRange({
    accountId: accId,
    fromDateStr: p.fromDate,
    toDateStr: p.toDate
});

console.log('hasBills (primary)>> ', hasBills);

if (!hasBills && invoiceType === 'Household Invoice') {
    // Primary account has no direct Events — check related members
    // eslint-disable-next-line no-await-in-loop
    const relatedCheck = await getRelatedPatients({ primaryAccountId: accId });
    const relatedIds   = relatedCheck?.map(r => r.accountId) || [];

    for (let k = 0; k < relatedIds.length; k++) {
        // eslint-disable-next-line no-await-in-loop
        const relHasBills = await hasBillingsInRange({
            accountId:   relatedIds[k],
            fromDateStr: p.fromDate,
            toDateStr:   p.toDate
        });
        console.log('hasBills (related ' + relatedIds[k] + ')>> ', relHasBills);
        if (relHasBills) {
            hasBills = true;
            break;
        }
    }
}

// skip periods where neither primary nor any related account has billables
if (!hasBills) {
    console.log('No billables found for period, skipping: ', p.fromDate, p.toDate);
    continue;
}

            try {

                if (invoiceType === 'Household Invoice') {

                    // eslint-disable-next-line no-await-in-loop
                    const relatedPatients =
                        await getRelatedPatients({
                            primaryAccountId: accId
                        });

                    const relatedIds =
                        relatedPatients?.map(r => r.accountId) || [];

                    // eslint-disable-next-line no-await-in-loop
                    await generateSuperBillForPreview({
                        primaryAccountId: accId,
                        selectedRelatedAccountIds: relatedIds,
                        fromDateStr: p.fromDate,
                        toDateStr: p.toDate
                    });
                    console.log('Generated Household Invoice for period:', p.fromDate, p.toDate);

                } else {

                    // eslint-disable-next-line no-await-in-loop
                    await generatePdfForPreview({
                        accountId: accId,
                        fromDateStr: p.fromDate,
                        toDateStr: p.toDate
                    });
                    console.log('Generated Standard Invoice for period:', p.fromDate, p.toDate);
                }

            } catch (e) {
                // Log but do NOT rethrow — failure on one period/account must
                // not stop the outer loop from processing remaining periods.
                console.error('Invoice generation failed for period',
                    p.fromDate, p.toDate, e?.body?.message || e);
            }
        }
    }
}

const results = [];

for (let i = 0; i < periods.length; i++) {

    const p = periods[i];

    // eslint-disable-next-line no-await-in-loop
    const res = await getInvoicesForAccounts({
        accountIds: accountIds,
        fromDateStr: p.fromDate,
        toDateStr: p.toDate,
        invoiceType: invoiceType
    });

    console.log(
        'Fetched invoices for period:',
        p.fromDate,
        p.toDate,
        JSON.stringify(res)
    );

    results.push(res);
}

console.log(
    'Fetched invoice results:',
    JSON.stringify(results)
);
                console.log(
    'Fetched invoice results:',
    JSON.stringify(results)
);
                const allInvoices = [];
                results.forEach(r => { if (r && r.length) allInvoices.push(...r); });
console.log(
    'allInvoices:',
    JSON.stringify(allInvoices)
);
                const seen   = new Set();
                const unique = allInvoices.filter(inv => {
                    if (seen.has(inv.Id)) return false;
                    seen.add(inv.Id);
                    return true;
                });
                console.log(
    'unique invoices:',
    JSON.stringify(unique)
);

                const groupMap = {};
                console.log(
    'invoiceType expected:',
    invoiceType
);

unique.forEach(inv => {
    console.log(
        'DB InvoiceType:',
        inv.InvoiceType__c,
        'Invoice:',
        inv.Name
    );
});
                unique
    .filter(inv => {
        if (inv.InvoiceType__c !== invoiceType) return false;
        // KEY FIX: for Household Invoice, only show the invoice whose
        // Client__c is the selected primary account — not related members.
        if (invoiceType === 'Household Invoice') {
            return inv.Client__c === accountIds[0];
        }
        return accountIds.includes(inv.Client__c);
    })
    .forEach(inv => {
        const cid = inv.Client__c;
        if (!groupMap[cid]) {
            groupMap[cid] = {
                clientId:   cid,
                clientName: clientLabel || (inv.Client__r ? inv.Client__r.Name : cid),
                invoices:   []
            };
        }
        groupMap[cid].invoices.push({
            id:          inv.Id,
            name:        inv.Name,
            accountId:   inv.Client__c,
            type:        inv.InvoiceType__c,
            fromDate:    this._fmtDate(inv.From_Date__c),
            toDate:      this._fmtDate(inv.To_Date__c),
            rawFromDate: inv.From_Date__c,
            rawToDate:   inv.To_Date__c
        });
    });

                this.previewInvoiceGroups = Object.values(groupMap);
                this.isLoadingInvoices    = false; 
        } catch (err) {

    this.isLoadingInvoices = false;

    this.showToast(
        'Error',
        err.body?.message || 'Failed to load invoices.',
        'error'
    );
}

    }

    closePreviewModal() {
        this.showPreviewModal     = false;
        this.previewInvoiceGroups = [];
        this._previewAccountIds   = [];
    }

    async handlePreviewInvoice(event) {

        const accountId = event.currentTarget.dataset.accountId;
        const fromDate  = event.currentTarget.dataset.fromDate;
        const toDate    = event.currentTarget.dataset.toDate;
        const invName   = event.currentTarget.dataset.invName;
        const invType   = event.currentTarget.dataset.invType;

        let url;

        if (invType === 'Household Invoice') {

            let relatedAccountIds = '';

            try {

                const relatedPatients = await getRelatedPatients({
                    primaryAccountId: accountId
                });
                
                console.log('relatedPatients : ',relatedPatients);

                relatedAccountIds =
                    relatedPatients?.map(acc => acc.accountId).join(',') || '';
                
                console.log('relatedAccountIds : ',relatedAccountIds);

            } catch (e) {
                console.error('Error fetching related patients', e);
            }

            url =
                `/apex/HouseholdInvoice?primaryAccountId=${accountId}`
                + `&relatedAccountIds=${relatedAccountIds}`
                + `&fromDate=${fromDate}`
                + `&toDate=${toDate}`
                + `&invoiceId=${encodeURIComponent(invName)}`;

        } else {

            url =
                `/apex/InvoicePDF?accountId=${accountId}`
                + `&fromDate=${fromDate}`
                + `&toDate=${toDate}`
                + `&invoiceNo=${encodeURIComponent(invName)}`;
        }

        window.open(url, '_blank');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Download Modal
    // ═════════════════════════════════════════════════════════════════════════

    handleDownloadStandard()  { this._openDownloadModal('Standard Invoice');  }
    handleDownloadSuperBill() { this._openDownloadModal('Household Invoice'); }

    async _openDownloadModal(invoiceType) {
        if (!this.selectedRows || this.selectedRows.length === 0) {
            this.showToast('Warning', 'Select at least one client.', 'warning');
            return;
        }

        const filteredIds = this._filterRowsByInvoiceType(this.selectedRows, invoiceType);
        if (filteredIds.length === 0) {
            const msg = invoiceType === 'Household Invoice'
                ? 'No couple household clients selected. Please select at least one couple household client.'
                : 'No standard clients selected. Please select at least one non-couple-household client.';
            this.showToast('No Eligible Clients', msg, 'warning');
            return;
        }

        this._downloadSelectedRows            = filteredIds;
        this.downloadModalInvoiceType         = invoiceType;
        this.downloadModalTitle               = `Download ${invoiceType}`;
        this.downloadModalShowHouseholdChoice = false;
        
        this.downloadPeriods          = [];
        this.isLoadingDownloadModal   = true;
        this.showDownloadModal        = true;

        await this._buildDownloadPeriods();
        this.isLoadingDownloadModal   = false;
    }

    async _buildDownloadPeriods() {
        // Bulk/download flows DO snap to period boundaries.
        const { effectiveFrom, effectiveTo } = this._resolveEffectiveDates(this.fromDate, this.toDate);
        const periods = this._splitIntoPeriods(effectiveFrom, effectiveTo);

        const validPeriods = [];
        for (let i = 0; i < periods.length; i++) {
            const p = periods[i];
            let hasValidBillables = false;

            for (let j = 0; j < this._downloadSelectedRows.length; j++) {
                // eslint-disable-next-line no-await-in-loop
                const hasBills = await hasBillingsInRange({
                    accountId:   this._downloadSelectedRows[j],
                    fromDateStr: p.fromDate,
                    toDateStr:   p.toDate
                });
                if (hasBills) { hasValidBillables = true; break; }
            }

            if (hasValidBillables) {
                validPeriods.push({
                    key:      `dp-${i}`,
                    label:    `Period ${validPeriods.length + 1}`,
                    fromDate: this._fmtDate(p.fromDate),
                    toDate:   this._fmtDate(p.toDate),
                    rawFrom:  p.fromDate,
                    rawTo:    p.toDate,
                    selected: false
                });
            }
        }
        this.downloadPeriods = validPeriods;
    }

    handleSelectAllPeriods(event) {
        const checked = event.target.checked;
        this.downloadPeriods = this.downloadPeriods.map(p => ({ ...p, selected: checked }));
    }

    handlePeriodCheckboxChange(event) {
        const key     = event.target.dataset.key;
        const checked = event.target.checked;
        this.downloadPeriods = this.downloadPeriods.map(p =>
            p.key === key ? { ...p, selected: checked } : p
        );
    }

    async handleDownloadSelectedPeriods() {
    const selected = this.downloadPeriods.filter(p => p.selected);
    if (!selected.length) {
        this.showToast('Warning', 'Select at least one period.', 'warning');
        return;
    }
    if (this.isBulkProcessing) {
        this.showToast('Info', 'A job is already running. Please wait.', 'info');
        return;
    }

    if (this.downloadModalInvoiceType === 'Household Invoice') {
        const eligibilityResult = await this._validateHouseholdEligibility(
            this._downloadSelectedRows, this.fromDate, this.toDate
        );
        if (!eligibilityResult.isValid) {
            this.showToast('No Billables',
                'No billables found for the selected period.', 'warning');
            return;
        }
    }

    this.showToast('Download Started',
        `Generating ZIP for ${selected.length} period(s). This may take a moment...`, 'info');

    try {
        this.isBulkProcessing = true;
        this.jobStatus        = 'Processing';

        // Build periods JSON to pass all selected periods in one ZIP job
        const periodsJson = JSON.stringify(
            selected.map(p => ({ fromDate: p.rawFrom, toDate: p.rawTo }))
        );

        // Single job covers ALL selected periods — produces one ZIP
        this.bulkJobId = await startBulkInvoiceDownload({
            accountIds:  this._downloadSelectedRows,
            fromDateStr: selected[0].rawFrom,
            toDateStr:   selected[selected.length - 1].rawTo,
            type:        this.downloadModalInvoiceType,
            periodsJson: periodsJson
        });

        await this._pollUntilDone(this.bulkJobId);
        this.isBulkProcessing = false;

    } catch (e) {
        this.isBulkProcessing = false;
        this.showToast('Error', e.body?.message || e.message, 'error');
    }
}

    closeDownloadModal() {
        this.showDownloadModal              = false;
        this.downloadPeriods                = [];
        this.downloadModalShowHouseholdChoice = false;
        this._downloadSelectedRows          = [];
    }

    handleDownloadModalStandard() {
        this.downloadModalInvoiceType         = 'Standard Invoice';
        this.downloadModalShowHouseholdChoice = false;
        this._buildDownloadPeriods();
    }

    handleDownloadModalHousehold() {
        this.downloadModalInvoiceType         = 'Household Invoice';
        this.downloadModalShowHouseholdChoice = false;
        this._buildDownloadPeriods();
    }

    async handleDownloadPeriodClick(event) {
        const fromDateStr = event.currentTarget.dataset.fromDate;
        const toDateStr   = event.currentTarget.dataset.toDate;
        const invType     = event.currentTarget.dataset.invType;

        if (invType === 'Household Invoice') {
            const eligibilityResult = await this._validateHouseholdEligibility(
                this._downloadSelectedRows, fromDateStr, toDateStr
            );
            if (!eligibilityResult.isValid) {
                this.showToast('No Billables',
                    'No billables found for the selected period.', 'warning');
                return;
            }
        }

        if (this.isBulkProcessing) {
            this.showToast('Info', 'A job is already running. Please wait.', 'info');
            return;
        }

        this.showToast('Download Started',
            `Generating ${invType}(s) for ${this._downloadSelectedRows.length} client(s).`, 'info');

        try {
            this.isBulkProcessing = true;
            this.jobStatus        = 'Processing';
            this.bulkJobId = await startBulkInvoiceDownload({
                accountIds:  this._downloadSelectedRows,
                fromDateStr: fromDateStr,
                toDateStr:   toDateStr,
                type:        invType,
                periodsJson: JSON.stringify([{ fromDate: fromDateStr, toDate: toDateStr }])
            });
            await this._pollUntilDone(this.bulkJobId);
            this.isBulkProcessing = false;
        } catch (e) {
            this.isBulkProcessing = false;
            this.showToast('Error', e.body?.message || e.message, 'error');
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Household eligibility validation
    // ═════════════════════════════════════════════════════════════════════════

    // async _validateHouseholdEligibility(primaryAccountIds, fromDateStr, toDateStr) {
    //     let totalValidRelated = 0;
    //     for (let i = 0; i < primaryAccountIds.length; i++) {
    //         // eslint-disable-next-line no-await-in-loop
    //         const result = await checkSuperBillEligibility({
    //             primaryAccountId:          primaryAccountIds[i],
    //             selectedRelatedAccountIds: [],
    //             fromDateStr:               fromDateStr,
    //             toDateStr:                 toDateStr
    //         });
    //         if (result.validRelatedAccountIds) {
    //             totalValidRelated += result.validRelatedAccountIds.length;
    //         }
    //     }
    //     return { isValid: totalValidRelated > 0 };
    // }
    async _validateHouseholdEligibility(primaryAccountIds, fromDateStr, toDateStr) {

    let hasAnyBillables = false;

    for (let i = 0; i < primaryAccountIds.length; i++) {

        // eslint-disable-next-line no-await-in-loop
        const result = await checkSuperBillEligibility({
            primaryAccountId: primaryAccountIds[i],
            selectedRelatedAccountIds: [],
            fromDateStr,
            toDateStr
        });

        const hasPrimary = result.hasPrimaryBillables;
        const hasRelated =
            result.validRelatedAccountIds &&
            result.validRelatedAccountIds.length > 0;

        if (hasPrimary || hasRelated) {
            hasAnyBillables = true;
            break;
        }
    }

    return { isValid: hasAnyBillables };
}

    // ═════════════════════════════════════════════════════════════════════════
    // Bulk Email
    // ═════════════════════════════════════════════════════════════════════════

    handleBulkStandard()  { this.handleBulkEmail('Standard Invoice');  }
    handleBulkSuperBill() { this.handleBulkEmail('Household Invoice'); }

    async handleBulkEmail(type) {
        if (this.isBulkProcessing) return;
        if (!this.selectedRows || !this.selectedRows.length) {
            this.showToast('Warning', 'Select at least one client.', 'warning');
            return;
        }

        try {
            const accountIds = this._filterRowsByInvoiceType(this.selectedRows, type);
            if (accountIds.length === 0) {
                const msg = type === 'Household Invoice'
                    ? 'No couple household clients selected. Household Invoice requires couple household clients.'
                    : 'No standard clients selected. Standard Invoice requires non-couple-household clients.';
                this.showToast('No Eligible Clients', msg, 'warning');
                return;
            }

            if (type === 'Household Invoice') {
                const eligibilityResult = await this._validateHouseholdEligibility(
                    accountIds, this.fromDate, this.toDate
                );
                if (!eligibilityResult.isValid) {
                    this.showToast('No Billables',
                        'No billables found for the selected period.', 'warning');
                    return;
                }
            }

            // Bulk email uses snapped period boundaries.
            const { effectiveFrom, effectiveTo } = this._resolveEffectiveDates(this.fromDate, this.toDate);
            const periods = this._splitIntoPeriods(effectiveFrom, effectiveTo);

            this.isBulkProcessing = true;
            this.jobStatus        = 'Processing';
            this.jobError         = null;
            this.bulkJobId        = null;

            for (let i = 0; i < periods.length; i++) {
                const p = periods[i];
                // eslint-disable-next-line no-await-in-loop
                this.bulkJobId = await startBulkInvoiceEmail({
                    accountIds:  accountIds,
                    fromDateStr: p.fromDate,
                    toDateStr:   p.toDate,
                    type:        type
                });
            }

            this.showToast('Email Success',
                `${type}(s) sent for ${accountIds.length} client(s) across ${periods.length} period(s).`,
                'success');
            this._startPolling();

        } catch (error) {
            this.isBulkProcessing = false;
            this.showToast('Error', error.body?.message || 'Failed to send Invoice email.', 'error');
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Polling
    // ═════════════════════════════════════════════════════════════════════════

    _startPolling() {
        this._pollTimer = setInterval(() => this._checkJobStatus(), POLL_INTERVAL_MS);
    }

    _checkJobStatus() {
        getZipJobStatus({ jobId: this.bulkJobId })
            .then(job => {
                this.jobStatus = job.Status__c;
                if (job.Status__c === 'Completed') {
                    this._stopPolling();
                    this.isBulkProcessing = false;
                    if (job.Error_Message__c) this.triggerDownload(job.Error_Message__c);
                } else if (job.Status__c === 'Failed') {
                    this._stopPolling();
                    this.isBulkProcessing = false;
                    this.jobError = job.Error_Message__c || 'Job failed.';
                    this.showToast('Error', this.jobError, 'error');
                }
            })
            .catch(() => {});
    }

    _stopPolling() {
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
    }

    _pollUntilDone(jobId) {
        return new Promise((resolve, reject) => {
            const timer = setInterval(() => {
                getZipJobStatus({ jobId })
                    .then(job => {
                        this.jobStatus = job.Status__c;
                        if (job.Status__c === 'Completed') {
                            clearInterval(timer);
                            if (job.Error_Message__c) this.triggerDownload(job.Error_Message__c);
                            resolve();
                        } else if (job.Status__c === 'Failed') {
                            clearInterval(timer);
                            this.jobError = job.Error_Message__c || 'Job failed.';
                            this.showToast('Error', this.jobError, 'error');
                            reject(new Error(this.jobError));
                        }
                    })
                    .catch(() => {});
            }, POLL_INTERVAL_MS);
        });
    }

    triggerDownload(url) {
        try {
            const link  = document.createElement('a');
            link.href   = url;
            link.target = '_self';
            link.click();
        } catch (e) {
            window.open(url, '_self');
        }
    }

    // ── Row selection / sort ───────────────────────────────────────────────

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows.map(row => row.Id);
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;

        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;

        const data = [...this.clientData];

        // Map URL columns to their actual display label field
        const fieldMap = {
            'accountUrl': 'Name'
        };

        // Use the mapped field name for sorting if one exists
        const sortField = fieldMap[fieldName] ?? fieldName;

        data.sort((a, b) => {
            let valueA = a[sortField] ?? '';
            let valueB = b[sortField] ?? '';

            if (typeof valueA === 'string') valueA = valueA.toLowerCase();
            if (typeof valueB === 'string') valueB = valueB.toLowerCase();

            if (valueA === valueB) return 0;

            return sortDirection === 'asc'
                ? (valueA > valueB ? 1 : -1)
                : (valueA < valueB ? 1 : -1);
        });

        this.clientData = data;
    }

    // ── Location picklist ──────────────────────────────────────────────────

    loadLocationPicklist() {
        getLocationPicklistValues()
            .then(result => {
                this.locationOptions = [
                    { label: 'All', value: 'All' },
                    ...result.map(item => ({ label: item, value: item }))
                ];
            })
            .catch(error => {
                this.showToast('Error', 'Error loading location values: ' + error.body.message, 'error');
            });
    }

    // ── Utilities ──────────────────────────────────────────────────────────

    clearSelections() {
        this.selectedRows = [];

        const datatable = this.template.querySelector('lightning-datatable');

        if (datatable) {
            datatable.selectedRows = [];
        }
    }

    _fmtDate(dateStr) {
        if (!dateStr) return '';
        const [y, m, d] = dateStr.split('-');
        return `${m}/${d}/${y}`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(title, error) {
        this.showToast(title, error?.body?.message || 'Something went wrong', 'error');
    }
}