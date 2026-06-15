import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { NgbActiveModal } from '@ng-bootstrap/ng-bootstrap';

import SharedModule from 'app/shared/shared.module';
import { ITEM_DELETED_EVENT } from 'app/config/navigation.constants';
import { IPayment } from '../payment.model';
import { PaymentService } from '../service/payment.service';

@Component({
  standalone: true,
  templateUrl: './payment-delete-dialog.component.html',
  imports: [SharedModule, FormsModule],
})
export class PaymentDeleteDialogComponent {
  payment?: IPayment;

  protected paymentService = inject(PaymentService);
  protected activeModal = inject(NgbActiveModal);

  cancel(): void {
    this.activeModal.dismiss();
  }

  confirmDelete(id: number): void {
    this.paymentService.delete(id).subscribe(() => {
      this.activeModal.close(ITEM_DELETED_EVENT);
    });
  }
}
