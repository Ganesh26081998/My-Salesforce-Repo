import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getPicklistValues }           from 'lightning/uiObjectInfoApi';
import { getObjectInfo }               from 'lightning/uiObjectInfoApi';
import { refreshApex }                 from '@salesforce/apex'; 
import getStageHistory                 from '@salesforce/apex/AccountStageHistoryController.getStageHistory';

import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import ACCOUNT_STATUS from '@salesforce/schema/Account.Account_Status__c';

export default class AccountStageChecklist extends LightningElement {
    @api recordId;
    
    stages        = [];
    currentStage;
    _recordTypeId;
    _picklistValues;
    _historyMap   = {};
    _wiredHistoryRef;    

    @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
    wiredObjectInfo({ data }) {
        if (data) {
            const rtis = data.recordTypeInfos;            

            this._recordTypeId = Object.keys(rtis).find(
                rtId => rtis[rtId].name === 'Prospect'
            );

            console.log('this._recordTypeId',this._recordTypeId);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$_recordTypeId',
        fieldApiName: ACCOUNT_STATUS
    })
    wiredPicklist({ data }) {
        if (data) {
            this._picklistValues = data.values;
            this._buildStages();
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: [ACCOUNT_STATUS] })
    wiredRecord({ data }) {
        if (data) {
            const newStage = getFieldValue(data, ACCOUNT_STATUS);
            if (newStage !== this.currentStage) {
                this.currentStage = newStage;
                if (this._wiredHistoryRef) {
                    refreshApex(this._wiredHistoryRef);
                }
            }
            this._buildStages();
        }
    }

    @wire(getStageHistory, { accountId: '$recordId' })
    wiredHistory(result) {
        this._wiredHistoryRef = result;
        const { data } = result;        
        if (data) {
            this._historyMap = data.history || {};            

            this._buildStages();
        }
    }

    _buildStages() {
        if (!this._picklistValues || !this.currentStage) return;

        const currentIndex = this._picklistValues.findIndex(
            p => p.value === this.currentStage
        );
        

        this.stages = this._picklistValues.map((entry, index) => {
            let date = this._historyMap[entry.value] ?? null;
            

            return {
                id:        `stage-cb-${index}`,
                label:     entry.label,
                completed: index <= currentIndex,
                date,
                textClass: index <= currentIndex ? 'stage-label completed' : 'stage-label'
            };
        });
        
    }
    
}