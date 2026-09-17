import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import CARE_PLAN_REFRESH_CHANNEL from '@salesforce/messageChannel/CarePlanRefreshChannel__c';
import getLatestCarePlanId from '@salesforce/apex/WorkingCarePlanController.getLatestCarePlanId';

export default class WorkingCarePlan extends LightningElement {

    @api recordId;           // Account record ID — auto-set on record pages
    @track isLoading = true;
    @track latestCarePlanId = null;
    subscription = null;

    // ── LMS ─────────────────────────────────────────────────────────────────
    @wire(MessageContext)
    messageContext;

    // ── Pick up recordId from the page reference (record pages) ─────────────
    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        // Record pages supply recordId via attributes
        const id = pageRef?.attributes?.recordId;
        if (id && id !== this.recordId) {
            this.recordId = id;
            this.loadLatestCarePlanId();
        }
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────
    connectedCallback() {
        this.subscribeToMessageChannel();
        // If recordId was already set via @api before wire fires, load now
        if (this.recordId) {
            this.loadLatestCarePlanId();
        }
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = null;
        }
    }

    // ── LMS: refresh when a care plan is saved / created ────────────────────
    subscribeToMessageChannel() {
        if (this.subscription) return;
        this.subscription = subscribe(
            this.messageContext,
            CARE_PLAN_REFRESH_CHANNEL,
            (message) => {
                if (message.refreshList) {
                    this.loadLatestCarePlanId();
                }
            },
            { scope: APPLICATION_SCOPE }
        );
    }

    // ── Fetch only the ID of the most-recent Care Plan for this account ──────
    loadLatestCarePlanId() {
        if (!this.recordId) return;

        this.isLoading = true;
        this.latestCarePlanId = null;   // reset so the child unmounts cleanly

        getLatestCarePlanId({ accountId: this.recordId })
            .then(id => {
                this.latestCarePlanId = id || null;
                this.isLoading = false;
            })
            .catch(error => {
                console.error('WorkingCarePlan – error loading latest care plan ID:', error);
                this.latestCarePlanId = null;
                this.isLoading = false;
            });
    }

    // ── Computed getters ─────────────────────────────────────────────────────
    get showEmptyState() {
        return !this.isLoading && !this.latestCarePlanId;
    }

    get showEditor() {
        return !this.isLoading && !!this.latestCarePlanId;
    }

    // ── carePlanEdit fires 'close' after a successful save ───────────────────
    // On this tab we stay on the same page, so just reload with the latest ID
    // (handles the clone case where a brand-new record is created)
    handleClose() {
        this.loadLatestCarePlanId();
    }
}