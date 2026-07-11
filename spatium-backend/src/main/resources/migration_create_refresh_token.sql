-- refreshToken 서버측 저장 테이블 (로그아웃/재발급 시 무효화용)
--  - ddl-auto=none이므로 이 스크립트를 Oracle(spatium 계정)에 직접 실행해야 함
--  - token_hash : 토큰 원문이 아닌 SHA-256 해시(hex 64자)만 저장

CREATE TABLE refresh_token (
    token_id     VARCHAR2(36)  PRIMARY KEY,
    mem_id       VARCHAR2(36)  NOT NULL,
    token_hash   VARCHAR2(64)  NOT NULL,
    expires_at   TIMESTAMP     NOT NULL,
    revoked      NUMBER(1)     DEFAULT 0 NOT NULL,
    created_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash)
);

CREATE INDEX idx_refresh_token_mem ON refresh_token (mem_id);
