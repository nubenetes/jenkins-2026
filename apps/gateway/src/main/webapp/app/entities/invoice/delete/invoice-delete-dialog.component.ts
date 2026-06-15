import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { NgbActiveModal } from '@ng-bootstrap/ng-bootstrap';

import SharedModule from 'app/shared/shared.module';
import { ITEM_DELETED_EVENT } from 'app/config/navigation.constants';
import { IInvoice } from '../invoice.model';
import { InvoiceService } from '../service/invoice.service';

@Component({
  standalone: true,
  templateUrl: './invoice-delete-dialog.component.html',
  imports: [SharedModule, FormsModule],
})
export class InvoiceDeleteDialogComponent {
  invoice?: IInvoice;

  protected invoiceService = inject(InvoiceService);
  protected activeModal = inject(NgbActiveModal);

  cancel(): void {
    this.activeModal.dismiss();
  }

  confirmDelete(id: number): void {
    this.invoiceService.delete(id).subscribe(() => {
      this.activeModal.close(ITEM_DELETED_EVENT);
    });
  }
}
