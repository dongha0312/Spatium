package com.pknu.spatium_backend.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.pknu.spatium_backend.model.Furniture;

@Repository
public interface FurnitureRepository extends JpaRepository<Furniture, String>{

}
