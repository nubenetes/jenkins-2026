import { Component, input } from '@angular/core';
import { RouterModule } from '@angular/router';

import SharedModule from 'app/shared/shared.module';
import { DurationPipe, FormatMediumDatePipe, FormatMediumDatetimePipe } from 'app/shared/date';
import { IInvoice } from '../invoice.model';

@Component({
  standalone: true,
  selector: 'jhi-invoice-detail',
  templateUrl: './invoice-detail.component.html',
  imports: [SharedModule, RouterModule, DurationPipe, FormatMediumDatetimePipe, FormatMediumDatePipe],
})
export class InvoiceDetailComponent {
  invoice = input<IInvoice | null>(null);

  previousState(): void {
    window.history.back();
  }
}
