WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SQLBLANKLINES ON

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = SPATIUM;


/* =========================================
   기본 가구 22개
   ========================================= */

INSERT ALL

    INTO FURNITURE (
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
    ) VALUES (
        'default_bed',
        NULL,
        'Default Bed',
        '기본 침대',
        'bed',
        '침대',
        '1.2',
        '0.55',
        '2.1',
        '/data/default_3d_models/bed.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'wooden_bed',
        NULL,
        'Wooden Bed',
        '원목 침대',
        'bed',
        '침대',
        '1.2',
        '0.55',
        '2.1',
        '/data/3d_models/bed/wooden_bed.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'simple_bed',
        NULL,
        'Simple Bed',
        '심플 침대',
        'bed',
        '침대',
        '1.2',
        '0.55',
        '2.1',
        '/data/3d_models/bed/simple_bed.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'default_chair',
        NULL,
        'Default Chair',
        '기본 의자',
        'chair',
        '의자',
        '0.55',
        '0.85',
        '0.55',
        '/data/default_3d_models/chair.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'modern_chair',
        NULL,
        'Modern Chair',
        '모던 의자',
        'chair',
        '의자',
        '0.55',
        '0.85',
        '0.55',
        '/data/3d_models/chair/modern_chair.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'wooden_chair',
        NULL,
        'Wooden Chair',
        '원목 의자',
        'chair',
        '의자',
        '0.55',
        '0.85',
        '0.55',
        '/data/3d_models/chair/wooden_chair.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'default_storage',
        NULL,
        'Default Storage',
        '기본 수납',
        'storage',
        '수납',
        '1',
        '1.2',
        '0.45',
        '/data/default_3d_models/storage.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'closet',
        NULL,
        'Closet',
        '옷장',
        'storage',
        '수납',
        '1.2',
        '2',
        '0.55',
        '/data/3d_models/storage/closet.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'bedside_drawer',
        NULL,
        'Bedside Drawer',
        '협탁 서랍',
        'storage',
        '수납',
        '0.5',
        '0.6',
        '0.45',
        '/data/3d_models/storage/bedside_drawer.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'makeup_table',
        NULL,
        'Makeup Table',
        '화장대',
        'storage',
        '수납',
        '1',
        '0.8',
        '0.45',
        '/data/3d_models/storage/makeup_table.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'default_table',
        NULL,
        'Default Desk',
        '기본 책상',
        'table',
        '책상',
        '1.2',
        '0.75',
        '0.65',
        '/data/default_3d_models/table.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'wooden_desk',
        NULL,
        'Wooden Desk',
        '원목 책상',
        'table',
        '책상',
        '1.2',
        '0.75',
        '0.65',
        '/data/3d_models/table/wooden_desk.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'ikea_desk',
        NULL,
        'IKEA Desk',
        '이케아 책상',
        'table',
        '책상',
        '1.2',
        '0.75',
        '0.65',
        '/data/3d_models/table/ikea_desk.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'computer_desk',
        NULL,
        'Computer Desk',
        '컴퓨터 책상',
        'table',
        '책상',
        '1.25',
        '0.75',
        '0.7',
        '/data/3d_models/table/computer_desk.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'default_door',
        NULL,
        'Default Door',
        '기본 문',
        'door',
        '문',
        '0.9',
        '2.1',
        '0.12',
        '/data/default_3d_models/door.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'white_door',
        NULL,
        'White Door',
        '화이트 도어',
        'door',
        '문',
        '0.9',
        '2.1',
        '0.12',
        '/data/3d_models/door/white_door.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'wooden_door',
        NULL,
        'Wooden Door',
        '우드 도어',
        'door',
        '문',
        '0.9',
        '2.1',
        '0.12',
        '/data/3d_models/door/wooden_door.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'default_window',
        NULL,
        'Default Window',
        '기본 창문',
        'window',
        '창문',
        '0.9',
        '1',
        '0.1',
        '/data/default_3d_models/window.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'tong_glass',
        NULL,
        'Glass Window',
        '통유리',
        'window',
        '창문',
        '0.9',
        '1',
        '0.1',
        '/data/3d_models/window/glass.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'single_window',
        NULL,
        'Single Window',
        '싱글 창문',
        'window',
        '창문',
        '0.75',
        '1',
        '0.1',
        '/data/3d_models/window/single_window.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'double_window',
        NULL,
        'Double Window',
        '더블 창문',
        'window',
        '창문',
        '1.2',
        '1',
        '0.1',
        '/data/3d_models/window/double_window.glb',
        '1',
        '1'
    )

    INTO FURNITURE VALUES (
        'default_stairs',
        NULL,
        'Stairs',
        '계단',
        'stairs',
        '계단',
        '1.2',
        '2.8',
        '4.59',
        '/data/default_3d_models/stairs.glb',
        '1',
        '1'
    )

SELECT 1 FROM DUAL;


/* =========================================
   편집 가능 가구 2개
   ========================================= */

INSERT ALL

    INTO FURNITURE (
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
    ) VALUES (
        'def_editable_bookcase',
        NULL,
        'editable bookcase',
        '꾸미기 책장',
        'storage/editable',
        '수납/편집 가능',
        '0.8',
        '1.8',
        '0.3',
        '/data/3d_models/editable_furniture/editable_bookcase.glb',
        '1',
        '1'
    )

    INTO FURNITURE (
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
    ) VALUES (
        'editable_case',
        NULL,
        'editable case',
        '꾸미기 장',
        'storage/editable',
        '수납/편집 가능',
        '0.8',
        '1.8',
        '0.3',
        '/data/3d_models/editable_furniture/editable_case.glb',
        '1',
        '1'
    )

SELECT 1 FROM DUAL;

COMMIT;

EXIT
