package com.nubenetes.petclinic.gateway.service.mapper;

import com.nubenetes.petclinic.gateway.domain.Invoice;
import com.nubenetes.petclinic.gateway.service.dto.InvoiceDTO;
import org.mapstruct.*;

/**
 * Mapper for the entity {@link Invoice} and its DTO {@link InvoiceDTO}.
 */
@Mapper(componentModel = "spring")
public interface InvoiceMapper extends EntityMapper<InvoiceDTO, Invoice> {}
