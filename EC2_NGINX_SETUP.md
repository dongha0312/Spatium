# EC2 서버에서 할 일

## 1. nginx 설정 확인

```bash
docker ps
docker exec <nginx컨테이너명> nginx -T | grep "X-Forwarded-For"
```

- `$proxy_add_x_forwarded_for` → 고칠 것 없음, 2번으로
- `$remote_addr` 이거나 아무것도 안 나옴 → 아래 수정

`/api` location 블록에 추가:

```nginx
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

```bash
docker exec <nginx컨테이너명> nginx -t
docker exec <nginx컨테이너명> nginx -s reload
```

## 2. 배포

```bash
cd <프로젝트 경로>
git pull origin deploy
docker compose up -d --build spring
```

## 3. 확인

서로 다른 네트워크(PC 와이파이 / 휴대폰 LTE)에서 동시에 3D 생성 요청
→ 서로 안 막히면 정상
