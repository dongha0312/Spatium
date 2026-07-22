-- Oracle SQL Developer / SQL*Plus용 가구 카탈로그 등록 스크립트
-- 실행 방법: 스크립트 실행(F5)
-- 같은 FUR_CODE가 있으면 UPDATE, 없으면 INSERT한다.

SET DEFINE OFF;

DECLARE
    PROCEDURE UPSERT_FURNITURE (
        P_FUR_CODE        IN VARCHAR2,
        P_FUR_NAME        IN VARCHAR2,
        P_FUR_NAME_KR     IN VARCHAR2,
        P_FUR_CATEGORY    IN VARCHAR2,
        P_FUR_CATEGORY_KR IN VARCHAR2,
        P_FUR_WIDTH       IN VARCHAR2,
        P_FUR_HEIGHT      IN VARCHAR2,
        P_FUR_DEPTH       IN VARCHAR2,
        P_FUR_PATH        IN VARCHAR2
    ) IS
    BEGIN
        MERGE INTO FURNITURE F
        USING (
            SELECT
                P_FUR_CODE        AS FUR_CODE,
                P_FUR_NAME        AS FUR_NAME,
                P_FUR_NAME_KR     AS FUR_NAME_KR,
                P_FUR_CATEGORY    AS FUR_CATEGORY,
                P_FUR_CATEGORY_KR AS FUR_CATEGORY_KR,
                P_FUR_WIDTH       AS FUR_WIDTH,
                P_FUR_HEIGHT      AS FUR_HEIGHT,
                P_FUR_DEPTH       AS FUR_DEPTH,
                P_FUR_PATH        AS FUR_PATH
            FROM DUAL
        ) S
        ON (F.FUR_CODE = S.FUR_CODE)
        WHEN MATCHED THEN
            UPDATE SET
                F.FUR_MEM         = NULL,
                F.FUR_NAME        = S.FUR_NAME,
                F.FUR_NAME_KR     = S.FUR_NAME_KR,
                F.FUR_CATEGORY    = S.FUR_CATEGORY,
                F.FUR_CATEGORY_KR = S.FUR_CATEGORY_KR,
                F.FUR_WIDTH       = S.FUR_WIDTH,
                F.FUR_HEIGHT      = S.FUR_HEIGHT,
                F.FUR_DEPTH       = S.FUR_DEPTH,
                F.FUR_PATH        = S.FUR_PATH,
                F.FUR_IS_DEFAULT  = '1',
                F.FUR_IS_ACTIVE   = '1'
        WHEN NOT MATCHED THEN
            INSERT (
                FUR_CODE,
                FUR_MEM,
                FUR_NAME,
                FUR_NAME_KR,
                FUR_CATEGORY,
                FUR_CATEGORY_KR,
                FUR_WIDTH,
                FUR_HEIGHT,
                FUR_DEPTH,
                FUR_PATH,
                FUR_IS_DEFAULT,
                FUR_IS_ACTIVE
            )
            VALUES (
                S.FUR_CODE,
                NULL,
                S.FUR_NAME,
                S.FUR_NAME_KR,
                S.FUR_CATEGORY,
                S.FUR_CATEGORY_KR,
                S.FUR_WIDTH,
                S.FUR_HEIGHT,
                S.FUR_DEPTH,
                S.FUR_PATH,
                '1',
                '1'
            );
    END UPSERT_FURNITURE;
BEGIN
    -- public/data/default_3d_models: 17개
    UPSERT_FURNITURE('default_bathtub', 'Default Bathtub', '기본 욕조', 'bathtub', '욕조', '1.7', '0.6', '0.75', '/data/default_3d_models/bathtub.glb');
    UPSERT_FURNITURE('default_bed', 'Default Bed', '기본 침대', 'bed', '침대', '1.2', '0.55', '2.1', '/data/default_3d_models/bed.glb');
    UPSERT_FURNITURE('default_chair', 'Default Chair', '기본 의자', 'chair', '의자', '0.55', '0.85', '0.55', '/data/default_3d_models/chair.glb');
    UPSERT_FURNITURE('default_dishwasher', 'Default Dishwasher', '기본 식기세척기', 'dishwasher', '식기 세척기', '0.6', '0.85', '0.6', '/data/default_3d_models/dishwasher.glb');
    UPSERT_FURNITURE('default_door', 'Default Door', '기본 문', 'door', '문', '0.9', '2.1', '0.12', '/data/default_3d_models/door.glb');
    UPSERT_FURNITURE('default_oven', 'Default Oven', '기본 오븐', 'oven', '오븐', '0.6', '0.6', '0.6', '/data/default_3d_models/oven.glb');
    UPSERT_FURNITURE('default_refrigerator', 'Default Refrigerator', '기본 냉장고', 'refrigerator', '냉장고', '0.75', '1.8', '0.75', '/data/default_3d_models/refrigerator.glb');
    UPSERT_FURNITURE('default_sink', 'Default Sink', '기본 싱크대', 'sink', '싱크대', '1.0', '0.85', '0.6', '/data/default_3d_models/sink.glb');
    UPSERT_FURNITURE('default_sofa', 'Default Sofa', '기본 소파', 'sofa', '소파', '2.0', '0.85', '0.9', '/data/default_3d_models/sofa.glb');
    UPSERT_FURNITURE('default_stairs', 'Stairs', '계단', 'stairs', '계단', '1.2', '2.8', '4.59', '/data/default_3d_models/stairs.glb');
    UPSERT_FURNITURE('default_storage', 'Default Storage', '기본 수납', 'storage', '수납', '1.0', '1.2', '0.45', '/data/default_3d_models/storage.glb');
    UPSERT_FURNITURE('default_stove', 'Default Stove', '기본 가스레인지', 'stove', '가스레인지', '0.6', '0.85', '0.6', '/data/default_3d_models/stove.glb');
    UPSERT_FURNITURE('default_table', 'Default Desk', '기본 책상', 'table', '책상', '1.2', '0.75', '0.65', '/data/default_3d_models/table.glb');
    UPSERT_FURNITURE('default_television', 'Default Television', '기본 TV', 'television', 'TV', '1.2', '0.7', '0.08', '/data/default_3d_models/television.glb');
    UPSERT_FURNITURE('default_toilet', 'Default Toilet', '기본 변기', 'toilet', '변기', '0.4', '0.75', '0.7', '/data/default_3d_models/toilet.glb');
    UPSERT_FURNITURE('default_washer_dryer', 'Default Washer Dryer', '기본 세탁기', 'washerDryer', '세탁기·건조기', '0.65', '0.9', '0.65', '/data/default_3d_models/washerDryer.glb');
    UPSERT_FURNITURE('default_window', 'Default Window', '기본 창문', 'window', '창문', '0.9', '1.0', '0.1', '/data/default_3d_models/window.glb');

    -- public/data/3d_models: 18개
    UPSERT_FURNITURE('bunkbed', 'Bunk Bed', '이층 침대', 'bed', '침대', '1.0', '1.7', '2.1', '/data/3d_models/bed/bunkbed.glb');
    UPSERT_FURNITURE('simple_bed', 'Simple Bed', '심플 침대', 'bed', '침대', '1.2', '0.55', '2.1', '/data/3d_models/bed/simple_bed.glb');
    UPSERT_FURNITURE('wooden_bed', 'Wooden Bed', '원목 침대', 'bed', '침대', '1.2', '0.55', '2.1', '/data/3d_models/bed/wooden_bed.glb');
    UPSERT_FURNITURE('modern_chair', 'Modern Chair', '모던 의자', 'chair', '의자', '0.55', '0.85', '0.55', '/data/3d_models/chair/modern_chair.glb');
    UPSERT_FURNITURE('wooden_chair', 'Wooden Chair', '원목 의자', 'chair', '의자', '0.55', '0.85', '0.55', '/data/3d_models/chair/wooden_chair.glb');
    UPSERT_FURNITURE('white_door', 'White Door', '화이트 도어', 'door', '문', '0.9', '2.1', '0.12', '/data/3d_models/door/white_door.glb');
    UPSERT_FURNITURE('wooden_door', 'Wooden Door', '우드 도어', 'door', '문', '0.9', '2.1', '0.12', '/data/3d_models/door/wooden_door.glb');
    UPSERT_FURNITURE('def_editable_bookcase', 'Editable Bookcase', '꾸미기 책장', 'storage/editable', '수납/편집 가능', '0.8', '1.8', '0.3', '/data/3d_models/editable_furniture/editable_bookcase.glb');
    UPSERT_FURNITURE('editable_case', 'Editable Case', '꾸미기 장', 'storage/editable', '수납/편집 가능', '0.8', '1.8', '0.3', '/data/3d_models/editable_furniture/editable_case.glb');
    UPSERT_FURNITURE('bedside_drawer', 'Bedside Drawer', '협탁 서랍', 'storage', '수납', '0.5', '0.6', '0.45', '/data/3d_models/storage/bedside_drawer.glb');
    UPSERT_FURNITURE('closet', 'Closet', '옷장', 'storage', '수납', '1.2', '2.0', '0.55', '/data/3d_models/storage/closet.glb');
    UPSERT_FURNITURE('makeup_table', 'Makeup Table', '화장대', 'storage', '수납', '1.0', '0.8', '0.45', '/data/3d_models/storage/makeup_table.glb');
    UPSERT_FURNITURE('computer_desk', 'Computer Desk', '컴퓨터 책상', 'table', '책상', '1.25', '0.75', '0.7', '/data/3d_models/table/computer_desk.glb');
    UPSERT_FURNITURE('ikea_desk', 'IKEA Desk', '이케아 책상', 'table', '책상', '1.2', '0.75', '0.65', '/data/3d_models/table/ikea_desk.glb');
    UPSERT_FURNITURE('wooden_desk', 'Wooden Desk', '원목 책상', 'table', '책상', '1.2', '0.75', '0.65', '/data/3d_models/table/wooden_desk.glb');
    UPSERT_FURNITURE('double_window', 'Double Window', '더블 창문', 'window', '창문', '1.2', '1.0', '0.1', '/data/3d_models/window/double_window.glb');
    UPSERT_FURNITURE('tong_glass', 'Glass Window', '통유리', 'window', '창문', '0.9', '1.0', '0.1', '/data/3d_models/window/glass.glb');
    UPSERT_FURNITURE('single_window', 'Single Window', '싱글 창문', 'window', '창문', '0.75', '1.0', '0.1', '/data/3d_models/window/single_window.glb');

    COMMIT;
END;
/

-- 등록 확인: EXPECTED_COUNT가 35면 정상
SELECT COUNT(*) AS EXPECTED_COUNT
FROM FURNITURE
WHERE FUR_IS_DEFAULT = '1'
  AND (
      FUR_PATH LIKE '/data/default_3d_models/%.glb'
      OR FUR_PATH LIKE '/data/3d_models/%.glb'
  );

-- 등록 상세 확인
SELECT
    FUR_CODE,
    FUR_NAME_KR,
    FUR_CATEGORY,
    FUR_WIDTH,
    FUR_HEIGHT,
    FUR_DEPTH,
    FUR_PATH
FROM FURNITURE
WHERE FUR_IS_DEFAULT = '1'
  AND (
      FUR_PATH LIKE '/data/default_3d_models/%.glb'
      OR FUR_PATH LIKE '/data/3d_models/%.glb'
  )
ORDER BY FUR_CATEGORY, FUR_CODE;
