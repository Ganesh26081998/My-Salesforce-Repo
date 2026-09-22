import { LightningElement } from 'lwc';

export default class TestLwc extends LightningElement {
    connectedCallback() {
        console.log('testLwc component loaded');
        console.log('testLwc component loaded');
        console.log('testLwc new component loaded');
        console.log('testLwc new branch component loaded');
        console.log('testLwc after merge loaded');
    }
}