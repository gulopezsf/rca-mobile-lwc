import { LightningElement } from 'lwc';

import LBL_CANCEL from '@salesforce/label/c.MTLE_Cancel';

export default class MobileTleBottomSheet extends LightningElement {
    label = {
        cancel: LBL_CANCEL
    };

    handleBackdropClick() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}
