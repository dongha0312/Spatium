-- 소셜 로그인 지원을 위한 Member 테이블 변경 (ERD 최종본 기준)
-- ddl-auto=none 이라 자동 반영이 안 되므로, SQL Developer / sqlplus 등으로 직접 실행해야 함.
--
-- ERD 기준 Member 컬럼 : mem_id VARCHAR2(36), mem_nick VARCHAR2(15), mem_email VARCHAR2(50),
--                       mem_pass VARCHAR2(30), mem_bir VARCHAR2(10), mem_sex VARCHAR2(10),
--                       mem_img BLOB, provider VARCHAR2(10)
-- mem_id는 기존 그대로 문자열(UUID) PK 유지, 새로 필요한 건 provider 컬럼 하나뿐임.

-- 1) provider 컬럼 추가 (mem_ 접두사 없이 ERD 그대로)
ALTER TABLE "Member" ADD provider VARCHAR2(10);

-- 2) mem_pass 컬럼의 NOT NULL 제약 여부 확인 (소셜 가입 회원은 비밀번호가 없음)
SELECT column_name, nullable
FROM user_tab_columns
WHERE table_name = 'Member' AND column_name = 'MEM_PASS';

-- 위 결과에서 NULLABLE 값이 'N'(NOT NULL)으로 나오면 아래 실행해서 NULL 허용으로 변경
-- ALTER TABLE "Member" MODIFY mem_pass NULL;
