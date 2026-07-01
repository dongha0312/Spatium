// 기본적으로 React 라이브러리 불러들여놓기
import React from "react";

// HomePage 정의 하기
function HomePage() {
  return (
    /** 실제 브라우저에 보여질 태그 정의 */
    <div>
      <h3>React Home 페이지 입니다</h3>
      <hr />

      {/* Home 바로가기 링크 추가 */}
      <p>
        <a href="/">[Home 바로가기]</a>
      </p>

      {/* 회원 전체 리스트 목록 조회 링크 추가
                - URL 패턴은 SpringBoot에서 회원전체조회 URL 패턴 그대로 사용 */}
      <p>
        <a href="/auth/login">[Login page 바로가기]</a>
      </p>

      <p>
        <a href="/auth/signup">[회원가입 페이지 바로가기]</a>
      </p>

      <p>
        <a href="/member/mypage">[마이 페이지 바로가기]</a>
      </p>

      <p>
        <a href="/member/account">[계정설정 페이지 바로가기]</a>
      </p>

      <p>
        <a href="/member/editor">[3D 에디터 페이지 바로가기]</a>
      </p>

      <p>
        <a href="/test">[test 페이지 바로가기]</a>
      </p>
    </div>
  );
}

export default HomePage;
