import { LightningElement, api } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getProspectInfo from '@salesforce/apex/prospectWarningController.getProspectInfo';

export default class ProspectWarning extends LightningElement {
    @api recordId;
    Businessflag = false;
    Individualflag = false;
    self = '';
    subscriptions = [];
    accountChannel = '/data/AccountChangeEvent';
    acrChannel = '/data/HealthCloudGA__ContactContactRelation__ChangeEvent';
    refreshTimer;

    connectedCallback() {
        this.loadProspectInfo();
        this.subscribeToAccountChanges();
        this.subscribeToAcrChanges();
        this.registerErrorListener();
    }

    disconnectedCallback() {
        window.clearTimeout(this.refreshTimer);
        this.subscriptions.forEach(sub => {
            try {
                unsubscribe(sub, () => {});
            } catch (e) {                
            }
        });
        this.subscriptions = [];
    }

    loadProspectInfo() {
        if (!this.recordId) return;

        getProspectInfo({ accountId: this.recordId })
            .then(result => {
                console.log('resultwarning:',result);
                this.Businessflag = !!result?.Businessflag;
                this.Individualflag = !!result?.Individualflag;
                this.self = result?.self || '';
            })
            .catch(error => {
                console.error('Apex error', error);
            });
    }
    scheduleRefresh() {
        window.clearTimeout(this.refreshTimer);
        this.refreshTimer = window.setTimeout(() => {
            this.loadProspectInfo();
        }, 250);
    }
    subscribeToAccountChanges() {
        subscribe(this.accountChannel, -1, (response) => {
            const recordIds = response?.data?.payload?.ChangeEventHeader?.recordIds;
            if (recordIds?.includes(this.recordId)) {
                this.scheduleRefresh();
            }
        }).then(sub => this.subscriptions.push(sub));
    }

    subscribeToAcrChanges() {
        subscribe(this.acrChannel, -1, (response) => {
            const header = response?.data?.payload?.ChangeEventHeader;
            const changeType = header?.changeType;

            if (changeType === 'CREATE' || changeType === 'UPDATE' || changeType === 'DELETE' || changeType === 'UNDELETE') {
                this.scheduleRefresh();
            }
        }).then(sub => this.subscriptions.push(sub));
    }

    registerErrorListener() {
        onError(error => console.error('Streaming error', error));
    }

    get showWarning() {
        return ((this.self !== 'Self-Found' && !this.Businessflag) || !this.Individualflag);
    }

    get warningMessage() {
        if (this.self !== 'Self-Found' && !this.Businessflag && !this.Individualflag) {
            return 'Business and Family contact not attached.';
        }
        if (!this.Businessflag && this.self !== 'Self-Found') {
            return 'Business contact not attached.';
        }
        if (!this.Individualflag) {
            return 'Family contact not attached.';
        }
        return '';
    }
}