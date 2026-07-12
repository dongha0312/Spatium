package com.pknu.spatium_backend.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import com.pknu.spatium_backend.model.Furniture;

@Repository
public interface FurnitureRepository extends JpaRepository<Furniture, String> {

    // 카탈로그에 노출할 기본 제공 가구(활성 상태)를 카테고리 순으로 조회한다.
    @Query("SELECT f FROM Furniture f " +
            "WHERE f.fur_is_active = '1' AND f.fur_is_default = '1' " +
            "ORDER BY f.fur_category")
    List<Furniture> findDefaultCatalog();
}
