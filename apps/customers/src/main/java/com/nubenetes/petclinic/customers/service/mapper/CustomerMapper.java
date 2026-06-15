package com.nubenetes.petclinic.customers.service.mapper;

import com.nubenetes.petclinic.customers.domain.Customer;
import com.nubenetes.petclinic.customers.service.dto.CustomerDTO;
import org.mapstruct.*;

/**
 * Mapper for the entity {@link Customer} and its DTO {@link CustomerDTO}.
 */
@Mapper(componentModel = "spring")
public interface CustomerMapper extends EntityMapper<CustomerDTO, Customer> {}
