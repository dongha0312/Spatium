package com.pknu.spatium_backend.model;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.ToString;

@Entity
@Table(name = "Furniture")
@Getter
@Setter

@NoArgsConstructor
@AllArgsConstructor

@Builder

@ToString
public class Furniture {

    @Id
    private String fur_code;

    // 사용자가 생성한 가구일 때만 소유자(회원) 식별용. 기본 제공 가구는 NULL.
    private String fur_mem;

    // 영어명 (LLM 정규화 결과가 들어갈 자리)
    private String fur_name;

    // 표시용 한글명
    private String fur_name_kr;

    // 에디터 로직용 카테고리 코드 ("bed", "chair" 등)
    private String fur_category;

    // 프론트 group으로 내려가는 한글 카테고리 ("침대", "의자" 등)
    private String fur_category_kr;

    // 치수 m 단위 (컬럼이 VARCHAR2라 문자열로 매핑)
    private String fur_width;

    private String fur_height;

    private String fur_depth;

    // GLB 경로 (없으면 프론트에서 fallback 박스)
    private String fur_path;

    // 기본 제공 가구 여부 ('1' 기본 / '0' 사용자 생성)
    private String fur_is_default;

    // 활성 여부 ('1' 노출 / '0' 숨김 = soft delete)
    private String fur_is_active;

}
