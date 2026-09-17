import { LightningElement, api, wire } from 'lwc';
import getClientUsers from '@salesforce/apex/ClientAccountTeamController.getClientUsers';
import { refreshApex } from '@salesforce/apex';
import ClientAccountTeamModal from 'c/clientAccountTeamModal';

export default class ClientAccountTeam extends LightningElement {
    @api recordId;
    users = [];
    internalUsers = [];
    externalUsers = [];
    wiredResult;
    isRefreshing = false;
    isDeactivated = false;

    @wire(getClientUsers, { accountId: '$recordId' })
    wiredUsers(result) {
        this.wiredResult = result;
        if (result.data) {
            this.users = result.data;
        
        this.internalUsers = this.sortUsersByRole(result.data[0] || []);
        this.externalUsers = this.sortUsersByRole(result.data[1] || []);
        }
    }

    sortUsersByRole(users) {

    const roleOrder = {
        'Primary Care Manager': 1,
        'Secondary Care Manager': 2
    };

        return [...users].sort((a, b) => {

            const aOrder = roleOrder[a.Role__c] || 999;
            const bOrder = roleOrder[b.Role__c] || 999;

            return aOrder - bOrder;
        });
    }

    

    async handleManage() {

        const result = await ClientAccountTeamModal.open({
            size: 'large',
            accountId: this.recordId
        });
        refreshApex(this.wiredResult);
    }

    get hasUsers() {
        return (
            !this.isRefreshing &&
            (this.internalUsers.length > 0 || this.externalUsers.length > 0)
        );
    }
}