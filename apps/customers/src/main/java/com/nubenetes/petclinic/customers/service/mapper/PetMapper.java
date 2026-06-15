package com.nubenetes.petclinic.customers.service.mapper;

import com.nubenetes.petclinic.customers.domain.Owner;
import com.nubenetes.petclinic.customers.domain.Pet;
import com.nubenetes.petclinic.customers.service.dto.OwnerDTO;
import com.nubenetes.petclinic.customers.service.dto.PetDTO;
import org.mapstruct.*;

/**
 * Mapper for the entity {@link Pet} and its DTO {@link PetDTO}.
 */
@Mapper(componentModel = "spring")
public interface PetMapper extends EntityMapper<PetDTO, Pet> {
    @Mapping(target = "owner", source = "owner", qualifiedByName = "ownerId")
    PetDTO toDto(Pet s);

    @Named("ownerId")
    @BeanMapping(ignoreByDefault = true)
    @Mapping(target = "id", source = "id")
    OwnerDTO toDtoOwnerId(Owner owner);
}
