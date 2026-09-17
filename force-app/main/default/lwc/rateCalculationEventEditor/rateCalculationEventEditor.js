import { LightningElement, api, wire } from 'lwc'; 
import { ShowToastEvent } from 'lightning/platformShowToastEvent'; 
import { getRecord } from 'lightning/uiRecordApi';
import getRateTypes from '@salesforce/apex/RateCalculationController.getRateTypePicklistValues'; 
import getUserLocations from '@salesforce/apex/RateCalculationController.getUserLocations'; 
import getRates from '@salesforce/apex/RateCalculationController.getRatesByLocation'; 
import getEventOwnerInfo from '@salesforce/apex/RateCalculationController.getEventOwnerInfo'; 
import saveEventRates from '@salesforce/apex/RateCalculationController.saveEventRates'; 
import getEventRateData from '@salesforce/apex/RateCalculationController.getEventRateData';
import validatePatientLocation from '@salesforce/apex/RateCalculationController.validatePatientLocation';
import updatePatientLocation from '@salesforce/apex/RateCalculationController.updatePatientLocation';
import getCareManagerRateTypePicklistValues from '@salesforce/apex/RateCalculationController.getCareManagerRateTypePicklistValues';
// --- Changed by Prasad - Start ---
import getMileageRate from '@salesforce/apex/RateCalculationController.getMileageRate';
// --- Changed by Prasad - End ---
import RateCalculationConfirmationModal from 'c/rateCalculationConfirmationModal';



export default class RateCalculation extends LightningElement { 
    @api recordId; 
    showInitialButton = true; 
    isLoading = false; 
    ownerId; 
    assignedUserName; 
    locationOptions = []; 
    selectedLocationId; 
    rateTypeOptions = []; 
    rateOptions = [];
    crRateOptions = []; 
    cmrRateOptions = [];
    activeSections = ['user', 'client', 'caregiver', 'mileage','expense']; 
    clientRateType ; 
    caregiverRateType ; 
    isClientRateDisabled = false; 
    isCaregiverRateDisabled = false; 
    clientRateValue; 
    caregiverRateValue; 
    clientRateText; 
    clientRateAmount; 
    caregiverRateText; 
    caregiverRateAmount; 
    caregiverRateTypeOptions = [];
    // --- Changed by Prasad - Start ---
    mileageEntries = [{ id: 0, description: '', amount: 0, miles: null, isLast: true, showRemove: false }];
    // --- Changed by Prasad - End ---
    expenseEntries = [{ id: 0, description: '', amount: 0, isLast: true, showRemove: false }];
    hasExistingData = false;
    entryIdCounter = 1; 
    isSaved = false; 
    noLocationMessage = ''; 
    dataLoaded = false;

    // Saved values
    savedLocationId;
    savedClientRateValue;
    savedCaregiverRateValue;
    savedClientRateType;
    savedCaregiverRateType;
    savedMileageEntries;
    savedExpenseEntries;
    savedIsClientRateDisabled;
    savedIsCaregiverRateDisabled;
    savedClientFlatRateAmount;
    savedCaregiverFlatRateAmount;

    // ✅ New Flat Rate properties
    clientFlatRateAmount = null;
    caregiverFlatRateAmount = null;

    isBillingSynced = false;
    //Ganesh code starts
    isBillableProduced = false;
      //Ganesh code ends
    // --- Changed by Prasad - Start ---
    mileageRate = 0;
    // --- Changed by Prasad - End ---

    connectedCallback() {
        this.loadEventOwner();
        this.loadRateTypes();
        // --- Changed by Prasad - Start ---
        this.loadMileageRate();
        // --- Changed by Prasad - End ---
        this.loadCareManagerRateTypes();
    } 

    get showEditButton() {
    return (
        this.hasExistingData &&
        this.isSaved &&
        !this.isBillingSynced
        );
    }

    get isFormDisabled() {
        return this.isSaved;
    }
    
    get isCaregiverRateComboDisabled() {
        return this.isFormDisabled || this.isCaregiverRateDisabled;
    }

    get isClientRateComboDisabled() {
        return this.isFormDisabled || this.isClientRateDisabled;
    }

  /*  get isSaveDisabled() {
        if (this.isSaved) return true;
        if (!this.selectedLocationId) return true;

        const clientRateRequired =
            this.clientRateType === 'Hourly' && !this.clientRateValue;

        const caregiverRateRequired =
            this.caregiverRateType === 'Hourly' && !this.caregiverRateValue;

        // Block save if any mileage entry has a negative value
        const hasNegativeMileage = this.mileageEntries.some(e => e.miles !== null && e.miles < 0);

        return clientRateRequired || caregiverRateRequired || hasNegativeMileage;
    }
*/


// WITH this
get isSaveDisabled() {
    if (this.isSaved) return true;
    if (!this.selectedLocationId) return true;

    const clientRateRequired =
        this.clientRateType === 'Hourly' && !this.clientRateValue;
    const clientLiveInRequired =
        this.clientRateType === 'Flat Amount' && (this.clientFlatRateAmount == null || this.clientFlatRateAmount === '');

    const caregiverRateRequired =
        this.caregiverRateType === 'Hourly' && !this.caregiverRateValue;
    const caregiverLiveInRequired =
        this.caregiverRateType === 'Flat Amount' && (this.caregiverFlatRateAmount == null || this.caregiverFlatRateAmount === '');

    const hasNegativeMileage = this.mileageEntries.some(e => e.miles !== null && e.miles < 0);
    const hasNegativeExpense = this.expenseEntries.some(e => e.amount !== null && e.amount < 0);
    const hasNegativeClientRate = this.clientRateType === 'Flat Amount' && this.clientFlatRateAmount < 0;
    const hasNegativeCaregiverRate = this.caregiverRateType === 'Flat Amount' && this.caregiverFlatRateAmount < 0;

    return clientRateRequired || clientLiveInRequired ||
           caregiverRateRequired || caregiverLiveInRequired ||
           hasNegativeMileage || hasNegativeExpense ||
           hasNegativeClientRate || hasNegativeCaregiverRate;
}
    get isAddEntryDisabled() { 
        return this.mileageEntries.length >= 5 || this.isFormDisabled; 
    } 

    get isExpenseAddEntryDisabled() { 
        return this.expenseEntries.length >= 5 || this.isFormDisabled; 
    } 

    get canRemoveEntry() { 
        return this.mileageEntries.length > 1; 
    } 

    get canRemoveEntrys() { 
        return this.expenseEntries.length > 1; 
    } 

    // ✅ Live In computed properties
    get isClientFlatRate() {
        return this.clientRateType === 'Flat Amount';
    }

    get isCaregiverFlatRate() {
        return this.caregiverRateType === 'Flat Amount';
    }

    handleEdit() { 
        console.log('=== EDIT CLICKED ===');
        console.log('savedClientFlatRateAmount:', this.savedClientFlatRateAmount);
        console.log('savedCaregiverFlatRateAmount:', this.savedCaregiverFlatRateAmount);
        console.log('savedClientRateType:', this.savedClientRateType);
        console.log('savedCaregiverRateType:', this.savedCaregiverRateType);
        
        this.isSaved = false; 

        // Restore saved values
        this.selectedLocationId = this.savedLocationId;
        this.clientRateValue = this.savedClientRateValue;
        this.caregiverRateValue = this.savedCaregiverRateValue;
        this.clientRateType = this.savedClientRateType || 'Hourly';
        this.caregiverRateType = this.savedCaregiverRateType || 'Hourly';
        
        // Restore disabled states
        this.isClientRateDisabled = this.savedIsClientRateDisabled !== undefined 
            ? this.savedIsClientRateDisabled 
            : (this.clientRateType !== 'Hourly' && this.clientRateType !== 'Flat Amount');
        this.isCaregiverRateDisabled = this.savedIsCaregiverRateDisabled !== undefined 
            ? this.savedIsCaregiverRateDisabled 
            : (this.caregiverRateType !== 'Hourly' && this.caregiverRateType !== 'Flat Amount');
        
        this.mileageEntries = this.savedMileageEntries
            ? JSON.parse(JSON.stringify(this.savedMileageEntries))
            : this.mileageEntries;
        this.expenseEntries = this.savedExpenseEntries
            ? JSON.parse(JSON.stringify(this.savedExpenseEntries))
            : this.expenseEntries;

        // ✅ Restore Flat Rates
        this.clientFlatRateAmount = this.savedClientFlatRateAmount || null;
        this.caregiverFlatRateAmount = this.savedCaregiverFlatRateAmount || null;
        
        console.log('After restore - clientFlatRateAmount:', this.clientFlatRateAmount);
        console.log('After restore - caregiverFlatRateAmount:', this.caregiverFlatRateAmount);
    } 

    handleAddRateCalculation() { 
        this.showInitialButton = false; 
        this.addEntry(); 
        this.addEntrys();
    } 

    loadEventOwner() { 
        getEventOwnerInfo({ eventId: this.recordId }) 
            .then(result => { 
                this.ownerId = result.OwnerId; 
                this.assignedUserName = result.OwnerName;
                this.clientRateType = result.ClientRate || 'Hourly';
                this.caregiverRateType = result.CaregiverRate || 'Hourly';
                this.isBillingSynced = result.IsBillingSynced;
                  //Ganesh code starts
                this.isBillableProduced = !!result.IsBillableProduced;
                  //Ganesh code ends
            }) 
            .catch(err => this.showToast('Error', err.body?.message || err.message, 'error')); 

        getUserLocations({ eventId: this.recordId }) 
            .then(result => { 
                if (result.length === 0) { 
                    this.noLocationMessage = 'For this user, there is no location assigned.'; 
                } else { 
                    this.noLocationMessage = ''; 
                   this.locationOptions = result
    .filter(loc => loc.WellSpring_Location__r)
    .map(loc => ({
        label: loc.WellSpring_Location__r.City__c,
        value: loc.WellSpring_Location__r.Id,
        isPrimary: loc.Primary_Location__c === 'Yes'
    }));

// Auto-select Primary only if no saved location already exists
if (!this.selectedLocationId) {

    const primaryLocation = this.locationOptions.find(
        loc => loc.isPrimary
    );

    if (primaryLocation) {
        this.selectedLocationId = primaryLocation.value;
        this.selectedLocationName = primaryLocation.label;

        // Load rates for primary location automatically
        this.loadRatesForLocation(this.selectedLocationId);
    }

    // If no primary found:
    // do nothing, dropdown shows all locations and user selects manually
}
                    
                    if (!this.dataLoaded) {
                        this.loadSavedData(result);
                    }
                } 
            }) 
            .catch(err => this.showToast('Error', err.body?.message || err.message, 'error')); 
    } 

    loadRateTypes() { 
        getRateTypes() 
            .then(data => { 
                //this.rateTypeOptions = data.map(v => ({ label: v, value: v })); 
            //     this.rateTypeOptions = (data || []).map(item => ({
            //     label: item.label, // shows label in UI
            //     value: item.value  // API value used in save
            // }));

            this.rateTypeOptions = (data || []).map(item =>
                (typeof item === 'string')
                    ? { label: item, value: item }
                    : { label: item.label, value: item.value }
            );
            }) 
            .catch(err => this.showToast('Error', err.body?.message || err.message, 'error')); 
    } 

    loadCareManagerRateTypes() {
    getCareManagerRateTypePicklistValues()
        .then(data => {
            this.caregiverRateTypeOptions = data.map(v => ({
                label: v,
                value: v
            }));
        })
        .catch(err => this.showToast('Error', err.body?.message || err.message, 'error'));
}

    // --- Changed by Prasad - Start ---
    loadMileageRate() {
        getMileageRate()
            .then(rate => {
                this.mileageRate = rate || 0;
                console.log('Mileage Rate loaded:', this.mileageRate);
            })
            .catch(err => {
                console.error('Error loading mileage rate:', err);
                this.mileageRate = 0;
            });
    }
    // --- Changed by Prasad - End ---

    loadSavedData(locations = []) {
        if (this.dataLoaded) return;
        
        console.log('=== LOADING SAVED DATA ===');
        
        getEventRateData({ eventId: this.recordId })
            .then(data => {
                console.log('Received data:', JSON.stringify(data, null, 2));
                
                if (data.Location__c && locations.length > 0) {

    const matchedLoc = locations.find(
        loc =>
            loc.WellSpring_Location__r?.City__c &&
            loc.WellSpring_Location__r.City__c.toLowerCase() ===
            data.Location__c.toLowerCase()
    );

    if (matchedLoc) {
        this.selectedLocationId = matchedLoc.WellSpring_Location__r.Id;
        this.savedLocationId = matchedLoc.WellSpring_Location__r.Id;
        this.loadRatesForLocation(
            matchedLoc.WellSpring_Location__r.Id
        );
    } else {
        this.selectedLocationId = null;
        this.savedLocationId = null;
    }
}
                
                // ✅ Client Rate Type - Load FIRST
                if (data.Client_Rate__c) {
                    this.clientRateType = data.Client_Rate__c;
                    this.savedClientRateType = data.Client_Rate__c;
                    console.log('Client Rate Type loaded:', this.clientRateType);
                }
                
                // ✅ FIXED: Load Client Rate - For Live In, use Client_Rate_Amount__c (e.g., $300)
                if (this.clientRateType === 'Flat Amount' && data.Client_Rate_Amount__c) {
                    this.clientFlatRateAmount = parseFloat(data.Client_Rate_Amount__c);
                    this.savedClientFlatRateAmount = this.clientFlatRateAmount;
                    this.clientRateAmount = this.clientFlatRateAmount;
                    this.clientRateText = `$${this.clientFlatRateAmount}`;
                    this.isClientRateDisabled = false;
                    this.savedIsClientRateDisabled = false;
                    console.log('Client Flat Amount Rate loaded from Client_Rate_Amount__c:', this.clientFlatRateAmount);
                }
                // Client Hourly Rate
                else if (this.clientRateType === 'Hourly' && data.Client_Billing_Details__c) {
                    this.clientRateText = data.Client_Billing_Details__c;
                    const parts = data.Client_Billing_Details__c.split(' - ');
                    if (parts.length >= 2) {
                        const rateName = parts[0].trim();
                        const amount = parts[1].replace(/[$,]/g, '').trim();
                        this.isClientRateDisabled = false;
                        this.savedIsClientRateDisabled = false;
                        this.clientRateAmount = parseFloat(amount);
                        this.clientRateValue = `${rateName}|${amount}`;
                        this.savedClientRateValue = this.clientRateValue;
                    }
                }
                
                // ✅ Caregiver Rate Type - Load FIRST
                if (data.Caregiver_Rate__c) {
                    this.caregiverRateType = data.Caregiver_Rate__c;
                    this.savedCaregiverRateType = data.Caregiver_Rate__c;
                    console.log('Caregiver Rate Type loaded:', this.caregiverRateType);
                }
                
                // ✅ FIXED: Load Caregiver Rate - For Live In, use Caregiver_Rate_Amount__c (e.g., $400)
                if (this.caregiverRateType === 'Flat Amount' && data.Caregiver_Rate_Amount__c) {
                    this.caregiverFlatRateAmount = parseFloat(data.Caregiver_Rate_Amount__c);
                    this.savedCaregiverFlatRateAmount = this.caregiverFlatRateAmount;
                    this.caregiverRateAmount = this.caregiverFlatRateAmount;
                    this.caregiverRateText = `$${this.caregiverFlatRateAmount}`;
                    this.isCaregiverRateDisabled = false;
                    this.savedIsCaregiverRateDisabled = false;
                    console.log('Caregiver Flat Amount Rate loaded from Caregiver_Rate_Amount__c:', this.caregiverFlatRateAmount);
                }
                // Caregiver Hourly Rate
                else if (this.caregiverRateType === 'Hourly' && data.Caregiver_Billing_Details__c) {
                    this.caregiverRateText = data.Caregiver_Billing_Details__c;
                    const parts = data.Caregiver_Billing_Details__c.split(' - ');
                    if (parts.length >= 2) {
                        const rateName = parts[0].trim();
                        const amount = parts[1].replace(/[$,]/g, '').trim();
                        this.isCaregiverRateDisabled = false;
                        this.savedIsCaregiverRateDisabled = false;
                        this.caregiverRateAmount = parseFloat(amount);
                        this.caregiverRateValue = `${rateName}|${amount}`;
                        this.savedCaregiverRateValue = this.caregiverRateValue;
                    }
                }

                // Mileage
                if (data.mileageEntries && data.mileageEntries.length > 0) {
                    // --- Changed by Prasad - Start ---
                    this.mileageEntries = data.mileageEntries.map((entry, index) => ({
                        id: index,
                        description: entry.description || '',
                        amount: entry.amount || 0,
                        miles: (entry.miles !== null && entry.miles !== undefined) ? entry.miles : null,
                        isLast: index === data.mileageEntries.length - 1,
                        showRemove: data.mileageEntries.length > 1 && index === data.mileageEntries.length - 1
                    }));
                    // --- Changed by Prasad - End ---
                    this.savedMileageEntries = JSON.parse(JSON.stringify(this.mileageEntries));
                    this.entryIdCounter = data.mileageEntries.length;
                }
                
                // Expense
                if (data.expenseEntries && data.expenseEntries.length > 0) {
                    this.expenseEntries = data.expenseEntries.map((entry, index) => ({
                        id: index,
                        description: entry.description || '',
                        amount: entry.amount || 0,
                        isLast: index === data.expenseEntries.length - 1,
                        showRemove: data.expenseEntries.length > 1 && index === data.expenseEntries.length - 1
                    }));
                    this.savedExpenseEntries = JSON.parse(JSON.stringify(this.expenseEntries));
                }

                // Check if saved
                if (data.Location__c || data.Client_Billing_Details__c || data.Caregiver_Billing_Details__c || 
                    data.Client_Flat_Rate_Amount__c || data.Caregiver_Flat_Rate_Amount__c) {
                    this.isSaved = true;
                    this.hasExistingData = true;
                }
                
                this.dataLoaded = true;
                
                console.log('=== DATA LOADED ===');
                console.log('savedClientFlatRateAmount:', this.savedClientFlatRateAmount);
                console.log('savedCaregiverFlatRateAmount:', this.savedCaregiverFlatRateAmount);
            })
            .catch(err => {
                console.error('Error loading saved data:', err);
                this.dataLoaded = true;
            });
    }

    // loadRatesForLocation(locationId) {
    //     getRates({ locationId: locationId })
    //         .then(result => {
    //             this.rateOptions = result.map(r => ({
    //                 label: `${r.Type_of_Rate__c} - $${r.Rate_Amount__c}`,
    //                 value: `${r.Type_of_Rate__c}|${r.Rate_Amount__c}`
    //             }));

    //             if (this.rateOptions.length === 0) {
    //             this.noLocationMessage = 'No rates are defined for the selected location.';
    //         } else {
    //             this.noLocationMessage = '';
    //         }

    //         })
    //         .catch(err => console.error('Error loading rates:', err));
    // }

    loadRatesForLocation(locationId) {
    getRates({ locationId: locationId })
        .then(result => {

            // Reset all options
            this.rateOptions = [];
            this.crRateOptions = [];
            this.cmrRateOptions = [];

            result.forEach(r => {
                const option = {
                    label: `${r.Type_of_Rate__c}`,
                    value: `${r.Type_of_Rate__c}|${r.Rate_Amount__c}`
                };

                // Split based on Rate_Type__c
                if (r.Rate_Type__c === 'Client Rate') {
                    this.crRateOptions.push(option);
                } 
                else if (r.Rate_Type__c === 'Care Manager Rate') {
                    this.cmrRateOptions.push(option);
                }

                // Optional: keep combined list if still needed somewhere
                this.rateOptions.push(option);
            });

            // Empty state message
            if (result.length === 0) {
                this.noLocationMessage = 'No rates are defined for the selected location.';
            } else {
                this.noLocationMessage = '';
            }

            console.log('Caregiver Rates:', this.crRateOptions);
            console.log('Client Rates:', this.cmrRateOptions);

        })
        .catch(err => console.error('Error loading rates:', err));
}

    handleLocationChange(event) { 
        this.selectedLocationId = event.detail.value;
        const selected = this.locationOptions.find(
            opt => opt.value === this.selectedLocationId
        );
        this.selectedLocationName = selected?.label || null;
        // 🔹 Reset rate selections when location changes
        this.clientRateValue = null;
        this.clientRateText = null;
        this.clientRateAmount = null;
        this.clientFlatRateAmount = null;

        this.caregiverRateValue = null;
        this.caregiverRateText = null;
        this.caregiverRateAmount = null;
        this.caregiverFlatRateAmount = null;
        this.loadRatesForLocation(this.selectedLocationId);
    } 

    // ✅ Updated for Live In logic
    handleClientRateTypeChange(event) {
        this.clientRateType = event.detail.value;
        this.isClientRateDisabled = this.clientRateType !== 'Hourly' && this.clientRateType !== 'Flat Amount';
        if (this.clientRateType !== 'Hourly') {
            this.clientRateValue = null;
            this.clientRateText = null;
            this.clientRateAmount = null;
        }
        if (this.clientRateType !== 'Flat Amount') {
            this.clientFlatRateAmount = null;
        }
    }

    handleCaregiverRateTypeChange(event) {
        this.caregiverRateType = event.detail.value;
        this.isCaregiverRateDisabled = this.caregiverRateType !== 'Hourly' && this.caregiverRateType !== 'Flat Amount';
        if (this.caregiverRateType !== 'Hourly') {
            this.caregiverRateValue = null;
            this.caregiverRateText = null;
            this.caregiverRateAmount = null;
        }
        if (this.caregiverRateType !== 'Flat Amount') {
            this.caregiverFlatRateAmount = null;
        }
    }

    handleClientRateChange(event) { 
        this.clientRateValue = event.detail.value; 
        const [text, amount] = this.clientRateValue.split('|'); 
        this.clientRateText = `${text} - $${amount}`; 
        this.clientRateAmount = parseFloat(amount); 
    } 

    handleCaregiverRateChange(event) { 
        this.caregiverRateValue = event.detail.value; 
        const [text, amount] = this.caregiverRateValue.split('|'); 
        this.caregiverRateText = `${text} - $${amount}`; 
        this.caregiverRateAmount = parseFloat(amount); 
    } 
/*
    // ✅ New handlers for Flat Rate
    handleClientFlatRateChange(event) {
        this.clientFlatRateAmount = parseFloat(event.detail.value) || 0;
        this.clientRateAmount = this.clientFlatRateAmount;
        this.clientRateText = `$${this.clientFlatRateAmount}`;
    }

    handleCaregiverFlatRateChange(event) {
        this.caregiverFlatRateAmount = parseFloat(event.detail.value) || 0;
        this.caregiverRateAmount = this.caregiverFlatRateAmount;
        this.caregiverRateText = `$${this.caregiverFlatRateAmount}`;
    }
    */


// WITH this
handleClientFlatRateChange(event) {
    const raw = event.detail.value;
    this.clientFlatRateAmount = (raw === '' || raw == null) ? null : parseFloat(raw);
    this.clientRateAmount = this.clientFlatRateAmount;
    this.clientRateText = this.clientFlatRateAmount != null ? `$${this.clientFlatRateAmount}` : null;
}

handleCaregiverFlatRateChange(event) {
    const raw = event.detail.value;
    this.caregiverFlatRateAmount = (raw === '' || raw == null) ? null : parseFloat(raw);
    this.caregiverRateAmount = this.caregiverFlatRateAmount;
    this.caregiverRateText = this.caregiverFlatRateAmount != null ? `$${this.caregiverFlatRateAmount}` : null;
}

    async handleSave() {

        if (!this.validateInputs()) {
            return;
        }

        if (this.isLoading) {
            return;
        }

        this.isLoading = true;

        try {

  

            const shouldValidateLocation =
                !this.hasExistingData ||
                this.savedLocationId !== this.selectedLocationId;

            if (!shouldValidateLocation) {
                await this.saveData(true);
                return;
            }
            const result = await validatePatientLocation({
                eventId: this.recordId,
                selectedLocationName: this.selectedLocationName
            });

            if (result.isPatientLocationBlank) {
                const confirmed = await RateCalculationConfirmationModal.open({
                    size: 'small',
                    message: `Client location is empty.
    Do you want to update it?`
                });

                if (!confirmed) {
                    this.isLoading = false;
                    return;
                }

                await updatePatientLocation({
                    eventId: this.recordId,
                    selectedLocationName: this.selectedLocationName
                });

                await this.saveData(true);
                return;
            }

            if (result.isMismatch) {
                const confirmed = await RateCalculationConfirmationModal.open({
                    size: 'small',
                    message: `Client location "${result.patientLocation}"
    does not match the selected Care manager location.
    Do you still want to continue?`
                });

                if (!confirmed) {
                    this.isLoading = false;
                    return;
                }

                await this.saveData(true);
                return;
            }

            await this.saveData(true);
        } catch (error) {
            this.isLoading = false;
            this.showToast(
                'Error',
                error?.body?.message || error.message,
                'error'
            );
        }
    }
// handleSave() {
//     if (this.isLoading) {
//         return; // 🔒 prevent double execution
//     }
 
//     this.isLoading = true; // lock immediately
 
//     validatePatientLocation({
//         eventId: this.recordId,
//         selectedLocationName: this.selectedLocationName
//     })
//     .then(result => {
 
//         // 🚫 Patient location blank
//         if (result.isPatientLocationBlank) {
//             return RateCalculationConfirmationModal.open({
//                 size: 'small',
//                 message: `Patient location is empty.
// Do you want to update it?`
//              }).then(confirmed => {
//             //     if (confirmed) {
//             //         //return this.saveData(true);
                    
//             //     }
//             //     this.isLoading = false;
//              if (confirmed) {
//                 this.isLoading = false;
//             return updatePatientLocation({  // ← NEW METHOD CALLED HERE
//                 eventId: this.recordId,
//                 selectedLocationName: this.selectedLocationName
//             })
//             .then(() => {
//                 return this.saveData(true);
//             })
//         }
//             });
//         }

//         // 🚫 Location mismatch
//         if (result.isMismatch) {
//             return RateCalculationConfirmationModal.open({
//                 size: 'small',
//                 message: `Patient location "${result.patientLocation}"
// does not match the selected Care manager location.
// Do you still want to continue?`
//             }).then(confirmed => {
//                 if (confirmed) {
//                     return this.saveData(true);
//                 }
//                 this.isLoading = false;
//             });
//         }

//         // ✅ No modal → safe to save
//         return this.saveData(true);

//     })
//     .catch(error => {
//         this.isLoading = false;
//         this.showToast(
//             'Error',
//             error?.body?.message || error.message,
//             'error'
//         );
//     });
// }
 
    

    handleCancel() {
        location.reload();
    }

    resolveSelectedLocationName() {
        if (this.selectedLocationName) {
            return this.selectedLocationName;
        }

        const selected = this.locationOptions.find(
            opt => opt.value === this.selectedLocationId
        );

        this.selectedLocationName = selected ? selected.label : null;
        return this.selectedLocationName;
    }

    // Add these helper methods in the class (anywhere before saveData)
normalizeType(v) {
    return v ? String(v).trim() : null;
}

normalizeNumber(v) {
    if (v === '' || v === null || v === undefined) return null;
    const n = Number(v);
    return Number.isNaN(n) ? null : n;
}

parseRateValue(v) {
    if (!v) return { name: null, amount: null };
    const [name, amount] = String(v).split('|');
    return {
        name: name ? name.trim().toLowerCase() : null,
        amount: this.normalizeNumber(amount)
    };
}

hasClientRateChanged() {
    const currentType = this.normalizeType(this.clientRateType);
    const savedType = this.normalizeType(this.savedClientRateType);
    if (currentType !== savedType) return true;

    if (currentType === 'Hourly') {
        const c = this.parseRateValue(this.clientRateValue);
        const s = this.parseRateValue(this.savedClientRateValue);
        return c.name !== s.name || c.amount !== s.amount;
    }

    if (currentType === 'Flat Amount') {
        return this.normalizeNumber(this.clientFlatRateAmount) !==
               this.normalizeNumber(this.savedClientFlatRateAmount);
    }

    return false;
}

hasCaregiverRateChanged() {
    const currentType = this.normalizeType(this.caregiverRateType);
    const savedType = this.normalizeType(this.savedCaregiverRateType);
    if (currentType !== savedType) return true;

    if (currentType === 'Hourly') {
        const c = this.parseRateValue(this.caregiverRateValue);
        const s = this.parseRateValue(this.savedCaregiverRateValue);
        return c.name !== s.name || c.amount !== s.amount;
    }

    if (currentType === 'Flat Amount') {
        return this.normalizeNumber(this.caregiverFlatRateAmount) !==
               this.normalizeNumber(this.savedCaregiverFlatRateAmount);
    }

    return false;
}

haveRatesChanged() {
    return this.hasClientRateChanged() || this.hasCaregiverRateChanged();
}


    saveData(showSpinner) { 
        if (showSpinner) this.isLoading = true; 
        //Ganesh Code starts
        const shouldShowRateWarning = this.isBillableProduced && this.haveRatesChanged();
        //Ganesh code ends
        console.log('=== SAVING DATA ===');
        console.log('clientFlatRateAmount:', this.clientFlatRateAmount);
        console.log('caregiverFlatRateAmount:', this.caregiverFlatRateAmount);
        // --- Changed by Prasad - Start ---
        console.log('mileageEntries (miles only, amount calculated in Apex):', JSON.stringify(this.mileageEntries));
        // --- Changed by Prasad - End ---

        const fields = { 
            Id: this.recordId, 
            Location__c: this.selectedLocationId, 
            Client_Billing_Details__c: this.clientRateText, 
            Client_Rate__c: this.clientRateType || null,
        /*    Client_Rate_Amount__c: this.clientRateAmount || null, */
            Caregiver_Billing_Details__c: this.caregiverRateText, 
          /*  Caregiver_Rate_Amount__c: this.caregiverRateAmount || null,  */
            Caregiver_Rate__c: this.caregiverRateType || null,
            
            // ✅ Flat Rate fields - FIXED FIELD NAMES
        /*    Client_Flat_Rate_Amount__c: this.clientFlatRateAmount || null,  */
        /*    Caregiver_Flat_Rate_Amount__c: this.caregiverFlatRateAmount || null  */


        // WITH this
Client_Rate_Amount__c: this.clientRateAmount != null ? this.clientRateAmount : null,
Caregiver_Rate_Amount__c: this.caregiverRateAmount != null ? this.caregiverRateAmount : null,
Client_Flat_Rate_Amount__c: this.clientFlatRateAmount != null ? this.clientFlatRateAmount : null,
Caregiver_Flat_Rate_Amount__c: this.caregiverFlatRateAmount != null ? this.caregiverFlatRateAmount : null,
        }; 

        // --- Changed by Prasad - Start ---
        // Initialize all possible mileage fields to null (to clear removed entries)
        // Mileage_Amount fields are NOT sent from JS; they are calculated in Apex
        for (let i = 0; i < 5; i++) {
            const suffix = i === 0 ? '' : `_${i + 1}`;
            fields[`Mileage_Description${suffix}__c`] = null;
            fields[`Enter_Miles_${i + 1}__c`] = null;
        }
        this.mileageEntries.forEach((entry, index) => {
            const suffix = index === 0 ? '' : `_${index + 1}`;
            fields[`Mileage_Description${suffix}__c`] = entry.description || null;
            // Use explicit null check so that 0 miles saves as 0, not null
            fields[`Enter_Miles_${index + 1}__c`] = (entry.miles !== null && entry.miles !== undefined) ? entry.miles : null;
        });
        // --- Changed by Prasad - End ---

        for (let i = 0; i < 5; i++) {
            const suffix = i === 0 ? '' : `_${i + 1}`;
            fields[`Expense_Amount${suffix}__c`] = null;
            fields[`Expense_Description${suffix}__c`] = null;
        }
        this.expenseEntries.forEach((entry, index) => {
            const suffix = index === 0 ? '' : `_${index + 1}`;
        /*    fields[`Expense_Amount${suffix}__c`] = entry.amount || null;   */
        // WITH
fields[`Expense_Amount${suffix}__c`] = entry.amount != null ? entry.amount : null;
            fields[`Expense_Description${suffix}__c`] = entry.description || null;
        });

        saveEventRates({ fields, selectedLocationName: this.resolveSelectedLocationName()}) 
            .then(() => { 
                this.showToast('Success', 'Your data is stored in Event Billing Details', 'success');
                window.location.reload();
                //Ganesh Code start
                if (shouldShowRateWarning){
                this.showToast(
                'Warning',
                'After the billable record is created, the rate values are no longer editable.',
                'warning',
                'sticky'
    ); 
     }
     //Ganesh code ends
                this.isLoading = false; 
                this.isSaved = true; 

                // ✅ Save state including flat rate amounts
                this.savedLocationId = this.selectedLocationId;
                this.savedClientRateValue = this.clientRateValue;
                this.savedCaregiverRateValue = this.caregiverRateValue;
                this.savedClientRateType = this.clientRateType;
                this.savedCaregiverRateType = this.caregiverRateType;
                this.savedIsClientRateDisabled = this.isClientRateDisabled;
                this.savedIsCaregiverRateDisabled = this.isCaregiverRateDisabled;
                this.savedClientFlatRateAmount = this.clientFlatRateAmount;
                this.savedCaregiverFlatRateAmount = this.caregiverFlatRateAmount;
                this.savedMileageEntries = JSON.parse(JSON.stringify(this.mileageEntries));
                this.savedExpenseEntries = JSON.parse(JSON.stringify(this.expenseEntries));
                
                console.log('Saved - savedClientFlatRateAmount:', this.savedClientFlatRateAmount);
                console.log('Saved - savedCaregiverFlatRateAmount:', this.savedCaregiverFlatRateAmount);
            }) 
            .catch(err => { 
                console.error('Save Error:', err);
                this.showToast('Error', err.body?.message || err.message, 'error'); 
                this.isLoading = false; 
            }); 
    } 

    showToast(title, message, variant, mode = 'dismissable') { 
        this.dispatchEvent(new ShowToastEvent({ title, message, variant,mode })); 
    } 

    // ✅ ADD MISSING METHODS
    addEntry() {
        if (this.mileageEntries.length < 5) {
            this.mileageEntries = this.mileageEntries.map(e => ({
                ...e,
                isLast: false,
                showRemove: false
            }));

            this.mileageEntries.push({
                id: this.entryIdCounter++,
                description: '',
                amount: 0,
                // --- Changed by Prasad - Start ---
                miles: null,
                // --- Changed by Prasad - End ---
                isLast: true,
                showRemove: this.mileageEntries.length >= 1
            });
        }
    }

    addEntrys() {
        if (this.expenseEntries.length < 5) {
            this.expenseEntries = this.expenseEntries.map(e => ({
                ...e,
                isLast: false,
                showRemove: false
            }));
            
            this.expenseEntries.push({
                id: this.entryIdCounter++,
                description: '',
                amount: 0,
                isLast: true,
                showRemove: this.expenseEntries.length >= 1
            });
        }
    }

    // --- Changed by Prasad - Start ---
    handleEntryChange(event) {
        const entryId = parseInt(event.target.dataset.id);
        const field = event.target.dataset.field;

/*        if (field === 'miles') {
            const rawValue = event.target.value;
            const numValue = parseFloat(rawValue);

            // Reject negative values
            if (!isNaN(numValue) && numValue < 0) {
                event.target.setCustomValidity('Negative values can\'t be accepted');
                event.target.reportValidity();
                return;
            }

            // Clear any previous validation error
            event.target.setCustomValidity('');
            event.target.reportValidity();

            // Handle 0 properly — don't use || which converts 0 to falsy
            const value = (rawValue === '' || rawValue === null || rawValue === undefined)
                ? null
                : numValue;

            this.mileageEntries = this.mileageEntries.map(entry =>
                entry.id === entryId ? { ...entry, miles: value } : entry
            );
        } 
        */


        // WITH this — store the value first, THEN validate so isSaveDisabled can react
if (field === 'miles') {
    const rawValue = event.target.value;
    const numValue = parseFloat(rawValue);

    const value = (rawValue === '' || rawValue === null || rawValue === undefined)
        ? null
        : numValue;

    // Store value first (even if negative) so isSaveDisabled getter can block save
    this.mileageEntries = this.mileageEntries.map(entry =>
        entry.id === entryId ? { ...entry, miles: value } : entry
    );

    // Show/clear inline error message
    if (!isNaN(numValue) && numValue < 0) {
        event.target.setCustomValidity('Negative values can\'t be accepted');
    } else {
        event.target.setCustomValidity('');
    }
    event.target.reportValidity();
}
        
        else {
            const value = event.target.value;
            this.mileageEntries = this.mileageEntries.map(entry =>
                entry.id === entryId ? { ...entry, [field]: value } : entry
            );
        }
    }
    // --- Changed by Prasad - End ---

 /*   handleexpenseEntryChange(event) {
        const entryId = parseInt(event.target.dataset.id);
        const field = event.target.dataset.field;
        const value = field === 'amount' ? parseFloat(event.target.value) || 0 : event.target.value;

        this.expenseEntries = this.expenseEntries.map(entry =>
            entry.id === entryId ? { ...entry, [field]: value } : entry
        );
    }
*/


// WITH this
handleexpenseEntryChange(event) {
    const entryId = parseInt(event.target.dataset.id);
    const field = event.target.dataset.field;

    if (field === 'amount') {
        const raw = event.target.value;
        const numValue = (raw === '' || raw == null) ? null : parseFloat(raw);

        this.expenseEntries = this.expenseEntries.map(entry =>
            entry.id === entryId ? { ...entry, amount: numValue } : entry
        );

        if (numValue !== null && numValue < 0) {
            event.target.setCustomValidity('Negative values can\'t be accepted');
        } else {
            event.target.setCustomValidity('');
        }
        event.target.reportValidity();
    } else {
        this.expenseEntries = this.expenseEntries.map(entry =>
            entry.id === entryId ? { ...entry, [field]: event.target.value } : entry
        );
    }
}
    removeEntry(event) {
        const entryId = parseInt(event.target.dataset.id);
        this.mileageEntries = this.mileageEntries.filter(entry => entry.id !== entryId);
        
        if (this.mileageEntries.length > 0) {
            this.mileageEntries = this.mileageEntries.map((entry, index) => ({
                ...entry,
                isLast: index === this.mileageEntries.length - 1,
                showRemove: this.mileageEntries.length > 1 && index === this.mileageEntries.length - 1
            }));
        }
    }

    removeEntrys(event) {
        const entryId = parseInt(event.target.dataset.id);
        this.expenseEntries = this.expenseEntries.filter(entry => entry.id !== entryId);
        
        if (this.expenseEntries.length > 0) {
            this.expenseEntries = this.expenseEntries.map((entry, index) => ({
                ...entry,
                isLast: index === this.expenseEntries.length - 1,
                showRemove: this.expenseEntries.length > 1 && index === this.expenseEntries.length - 1
            }));
        }
    }

    // validation before save for decimal numbers in milege and expenses

    validateInputs() {
        const allInputs = [
            ...this.template.querySelectorAll('lightning-input'),
            ...this.template.querySelectorAll('lightning-combobox')
        ];

        let isValid = true;

        allInputs.forEach(input => {
            input.reportValidity();

            if (!input.checkValidity()) {
                isValid = false;
            }
        });

        return isValid;
    }

}