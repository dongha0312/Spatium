#!/bin/bash

set -euo pipefail

if [ -z "${DB_PASSWORD:-}" ]; then
    echo "ERROR: DB_PASSWORD가 설정되지 않았습니다." >&2
    exit 1
fi

if [ "${#DB_PASSWORD}" -lt 24 ]; then
    echo "ERROR: DB_PASSWORD는 24자 이상이어야 합니다." >&2
    exit 1
fi

case "$DB_PASSWORD" in
    *[!A-Za-z0-9]*)
        echo "ERROR: DB_PASSWORD는 영문자와 숫자만 사용할 수 있습니다." >&2
        exit 1
        ;;
esac

sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE

ALTER SESSION SET CONTAINER = FREEPDB1;


/* 애플리케이션 전용 테이블스페이스 생성 */
DECLARE
    tablespace_count NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO tablespace_count
      FROM dba_tablespaces
     WHERE tablespace_name = 'SPATIUM_DATA';

    IF tablespace_count = 0 THEN
        EXECUTE IMMEDIATE
            'CREATE TABLESPACE SPATIUM_DATA
             DATAFILE ''/opt/oracle/oradata/FREE/FREEPDB1/spatium_data01.dbf''
             SIZE 256M
             AUTOEXTEND ON NEXT 64M
             MAXSIZE 5G';
    END IF;
END;
/


/* SPATIUM 사용자 생성 또는 비밀번호 갱신 */
DECLARE
    user_count NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO user_count
      FROM dba_users
     WHERE username = 'SPATIUM';

    IF user_count = 0 THEN
        EXECUTE IMMEDIATE
            'CREATE USER SPATIUM IDENTIFIED BY "${DB_PASSWORD}"';
    ELSE
        EXECUTE IMMEDIATE
            'ALTER USER SPATIUM IDENTIFIED BY "${DB_PASSWORD}" ACCOUNT UNLOCK';
    END IF;
END;
/


ALTER USER SPATIUM
    DEFAULT TABLESPACE SPATIUM_DATA
    TEMPORARY TABLESPACE TEMP
    QUOTA UNLIMITED ON SPATIUM_DATA;

GRANT CREATE SESSION, CREATE TABLE TO SPATIUM;

EXIT
SQL
