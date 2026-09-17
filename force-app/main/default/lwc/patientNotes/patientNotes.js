import { LightningElement, track, api, wire } from 'lwc';
import getNotes from '@salesforce/apex/PatientNotesController.getNotes';
import saveNote from '@salesforce/apex/PatientNotesController.saveNote';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import TIME_ZONE from '@salesforce/i18n/timeZone'; 
import LOCALE from '@salesforce/i18n/locale';

export default class PatientNotes extends LightningElement {

    @api recordId;
    @track notes = [];

    showCreateForm = false;
    pageRecordId = null;
    isLoading = false;

    name = '';
    description = '';
    searchKey = '';

    pageSize = 10;
    currentPage = 1;

    sortDirection = 'DESC';

    connectedCallback() {
        this.loadNotes();
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (pageRef?.attributes?.recordId) {
            this.pageRecordId = pageRef.attributes.recordId;
        }
    }

    get effectiveAccountId() {
        return this.recordId || this.pageRecordId || null;
    }

    get pagedNotes() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.notes.slice(start, start + this.pageSize);
    }

    get hasPagedNotes() {
        return this.pagedNotes.length > 0;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.notes.length / this.pageSize));
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get footerText() {
        const total = this.notes.length;
        if (total === 0) return 'Showing 0 entries';
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, total);
        return `Showing ${start} to ${end} of ${total} entries`;
    }

    get isAsc() {
        return this.sortDirection === 'ASC';
    }

    async loadNotes() {
        this.isLoading = true;

        try {
            const result = await getNotes({
                searchKey: this.searchKey || '',
                accountId: this.effectiveAccountId,
                sortDirection: this.sortDirection || 'DESC'
            });

            const localizeDateTime = (utcString) => {
                if (!utcString) return '';
                return new Intl.DateTimeFormat(LOCALE, {
                    year: 'numeric',
                    month: 'short',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit',
                    //second: '2-digit',
                    hour12: true,
                    timeZone: TIME_ZONE // This forces the conversion to the user's CDT profile setting
                }).format(new Date(utcString));
            };

            const formatDate = (dateString) => {
                if (!dateString) return '';

                const [year, month, day] = dateString.split('-');
                return `${month}/${day}/${year}`;
            };

            this.notes = (result || []).map(row => ({
                Id: row.Id,
                Name: row.Name,
                noteUrl: `/lightning/r/Patient_Notes__c/${row.Id}/view`,
                Descriptions__c: row.Descriptions__c || '',
                Date__c: row.Date__c,
                DateFormatted: formatDate(row.Date__c),   // <-- Add this
                //CreatedDate: row.CreatedDate,
                CreatedDateFormatted: localizeDateTime(row.CreatedDate),
                CreatedByName: row.CreatedBy?.Name || '',
                hasDescription: !!row.Descriptions__c,
                expanded: false,
                descClass: 'desc-collapse',
                toggleText: 'Show more',
                showToggle: (row.Descriptions__c || '').length > 200
            }));

            this.currentPage = 1;

        } catch (error) {
            console.error('FULL ERROR', JSON.stringify(error));
            this.showToast('Error', error?.body?.message || 'Error loading notes', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSort() {
        this.sortDirection = this.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        this.loadNotes();
    }

    handleSearchKeyUp(event) {
        this.searchKey = event.target.value;
        if (event.key === 'Enter') {
            this.loadNotes();
        }
    }

    handleGoSearch() {
        this.loadNotes();
    }

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.target.value, 10);
        this.currentPage = 1;
    }

    handlePrevPage() {
        if (this.currentPage > 1) this.currentPage--;
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) this.currentPage++;
    }

    handleNewClick() {
        this.showCreateForm = true;
        this.name = '';
        this.description = '';
    }

    handleCancel() {
        this.showCreateForm = false;
    }

    handleNameChange(e) {
        this.name = e.target.value;
    }

    handleDescriptionChange(e) {
        this.description = e.target.value;
    }

    toggleDescription(event) {
        const id = event.currentTarget.dataset.id;
        this.notes = this.notes.map(n => {
            if (n.Id === id) {
                n.expanded = !n.expanded;
                n.descClass = n.expanded ? 'desc-expand' : 'desc-collapse';
                n.toggleText = n.expanded ? 'Show less' : 'Show more';
            }
            return n;
        });
    }

    async handleSave() {
        if (!this.name?.trim()) {
            this.showToast('Error', 'Title is required', 'error');
            return;
        }

        if (!this.description) {
            this.showToast('Error', 'Description is required', 'error');
            return;
        }

        this.isLoading = true;

        try {
            await saveNote({
                name: this.name.trim(),
                description: this.description,
                accountId: this.effectiveAccountId
            });

            this.showToast('Success', 'Note Created Successfully', 'success');

            this.showCreateForm = false;
            this.name = '';
            this.description = '';

            await this.loadNotes();

        } catch (error) {
            console.error('SAVE ERROR', error);
            this.showToast('Error', error?.body?.message || 'Error creating note', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}