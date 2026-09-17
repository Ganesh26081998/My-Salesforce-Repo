import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPatients from '@salesforce/apex/BusinessAccountPatientsController.getPatients';

function normalizeStage(status) {
    if (!status) return status;
    return status.trim().toLowerCase() === 'client' ? 'Client' : 'Prospect';
}

function getStatusTagClass(status) {
    if (!status) return 'bap-tag bap-tag--status-default';
    const s = status.toLowerCase();
    if (s.includes('active') || s.includes('enrolled') || s.includes('current') || s === 'client') {
        return 'bap-tag bap-tag--status-active';
    }
    if (s.includes('inactive') || s.includes('discharg') || s.includes('closed') || s.includes('terminat')) {
        return 'bap-tag bap-tag--status-inactive';
    }
    if (s.includes('pending') || s.includes('prospect') || s.includes('new') || s.includes('referral')) {
        return 'bap-tag bap-tag--status-pending';
    }
    if (s.includes('hold') || s.includes('pause') || s.includes('suspend') || s.includes('wait')) {
        return 'bap-tag bap-tag--status-hold';
    }
    return 'bap-tag bap-tag--status-default';
}

export default class BusinessAccountPatients extends LightningElement {
    @api recordId;

    @track patients;
    @track searchTerm    = '';
    @track selectedStage = 'All';
    @track pageSize      = 10;

    skeletonRows = [1, 2, 3];

    @wire(getPatients, { recordId: '$recordId' })
    wiredPatients({ data, error }) {
        if (data) {
            this.patients = data.map(p => ({
                ...p,
                accountStatus:    normalizeStage(p.accountStatus),
                patientUrl:     '/' + p.patientId,
                statusTagClass: getStatusTagClass(normalizeStage(p.accountStatus)),
                contactList:    p.businessContactNames
                    ? p.businessContactNames.split(', ').map((name, i) => ({ key: i, name }))
                    : []
            }));
        } else if (error) {
            this.patients = [];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || 'Failed to load patients',
                    variant: 'error'
                })
            );
            console.error(error);
        }
    }

    // ── Computed ──────────────────────────────────────────

    get filteredPatients() {
        if (!this.patients) return [];
        const term  = this.searchTerm.toLowerCase().trim();
        const stage = this.selectedStage;
        return this.patients.filter(p => {
            const nameMatch    = !term || (p.patientName || '').toLowerCase().includes(term);
            const contactMatch = !term || (p.businessContactNames || '').toLowerCase().includes(term);
            const stageMatch   = stage === 'All' || p.accountStatus === stage;
            return (nameMatch || contactMatch) && stageMatch;
        });
    }

    get pagedPatients() {
        const all = this.filteredPatients;
        if (this.pageSize === 0) return all;
        return all.slice(0, this.pageSize);
    }

    get hasFiltered() {
        return this.filteredPatients.length > 0;
    }

    get filteredCount() {
        return this.filteredPatients.length;
    }

    get filteredCountSuffix() {
        return this.filteredCount === 1 ? '' : 's';
    }

    get showingLabel() {
        const total   = this.filteredPatients.length;
        const showing = this.pagedPatients.length;
        if (showing >= total) return `Showing all ${total} record${total === 1 ? '' : 's'}`;
        return `Showing ${showing} of ${total} records`;
    }

    get stageOptions() {
        const opts = [{ label: 'All', value: 'All', selected: this.selectedStage === 'All' }];
        if (this.patients) {
            const seen = new Set();
            this.patients.forEach(p => {
                if (p.accountStatus && !seen.has(p.accountStatus)) {
                    seen.add(p.accountStatus);
                    opts.push({
                        label:    p.accountStatus,
                        value:    p.accountStatus,
                        selected: this.selectedStage === p.accountStatus
                    });
                }
            });
        }
        return opts;
    }

    get pageSizeOptions() {
        const sizes = [
            { label: '10',  value: 10  },
            { label: '25',  value: 25  },
            { label: '100', value: 100 },
            { label: 'All', value: 0   }
        ];
        return sizes.map(s => ({
            ...s,
            btnClass: this.pageSize === s.value
                ? 'bap-per-page-btn bap-per-page-btn--active'
                : 'bap-per-page-btn'
        }));
    }

    // ── Handlers ──────────────────────────────────────────

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.pageSize   = 10;
    }

    handleStageChange(event) {
        this.selectedStage = event.target.value;
        this.pageSize      = 10;
    }

    handlePerPage(event) {
        this.pageSize = parseInt(event.currentTarget.dataset.value, 10);
    }

    handleClear() {
        this.searchTerm    = '';
        this.selectedStage = 'All';
        this.pageSize      = 10;
        const input  = this.template.querySelector('.bap-search-input');
        if (input)  input.value  = '';
        const select = this.template.querySelector('.bap-select');
        if (select) select.value = 'All';
    }
}