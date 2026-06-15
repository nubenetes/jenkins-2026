import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { NgbActiveModal } from '@ng-bootstrap/ng-bootstrap';

import SharedModule from 'app/shared/shared.module';
import { ITEM_DELETED_EVENT } from 'app/config/navigation.constants';
import { IPet } from '../pet.model';
import { PetService } from '../service/pet.service';

@Component({
  standalone: true,
  templateUrl: './pet-delete-dialog.component.html',
  imports: [SharedModule, FormsModule],
})
export class PetDeleteDialogComponent {
  pet?: IPet;

  protected petService = inject(PetService);
  protected activeModal = inject(NgbActiveModal);

  cancel(): void {
    this.activeModal.dismiss();
  }

  confirmDelete(id: number): void {
    this.petService.delete(id).subscribe(() => {
      this.activeModal.close(ITEM_DELETED_EVENT);
    });
  }
}
