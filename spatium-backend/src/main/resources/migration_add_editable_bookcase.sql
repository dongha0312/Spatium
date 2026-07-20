-- 서랍장 꾸미기 전용 가구(editable_bookcase) 기본 카탈로그 등록
--  - ddl-auto=none이므로 이 스크립트를 Oracle(spatium 계정)에 직접 실행해야 함
--  - GLB 파일: spatium-frontend/public/data/3d_models/editable_furniture/editable_bookcase.glb
--  - 경로에 /editable_furniture/ 가 포함된 가구만 3D 에디터에서 "서랍장 꾸미기" 버튼이
--    활성화된다 (프론트 isDecoratableModelPath() 판정 기준)
--  - MERGE라서 여러 번 실행해도 안전하다(있으면 갱신, 없으면 삽입)

MERGE INTO Furniture f
USING (
    SELECT
        'def_editable_bookcase'                                        AS fur_code,
        NULL                                                           AS fur_mem,
        'editable bookcase'                                            AS fur_name,
        '꾸미기 책장'                                                  AS fur_name_kr,
        'storage'                                                      AS fur_category,
        '수납'                                                         AS fur_category_kr,
        '0.8'                                                          AS fur_width,
        '1.8'                                                          AS fur_height,
        '0.3'                                                          AS fur_depth,
        '/data/3d_models/editable_furniture/editable_bookcase.glb'     AS fur_path,
        '1'                                                            AS fur_is_default,
        '1'                                                            AS fur_is_active
    FROM dual
) src
ON (f.fur_code = src.fur_code)
WHEN MATCHED THEN UPDATE SET
    f.fur_mem         = src.fur_mem,
    f.fur_name        = src.fur_name,
    f.fur_name_kr     = src.fur_name_kr,
    f.fur_category    = src.fur_category,
    f.fur_category_kr = src.fur_category_kr,
    f.fur_width       = src.fur_width,
    f.fur_height      = src.fur_height,
    f.fur_depth       = src.fur_depth,
    f.fur_path        = src.fur_path,
    f.fur_is_default  = src.fur_is_default,
    f.fur_is_active   = src.fur_is_active
WHEN NOT MATCHED THEN INSERT (
    fur_code, fur_mem, fur_name, fur_name_kr,
    fur_category, fur_category_kr,
    fur_width, fur_height, fur_depth,
    fur_path, fur_is_default, fur_is_active
) VALUES (
    src.fur_code, src.fur_mem, src.fur_name, src.fur_name_kr,
    src.fur_category, src.fur_category_kr,
    src.fur_width, src.fur_height, src.fur_depth,
    src.fur_path, src.fur_is_default, src.fur_is_active
);

COMMIT;
