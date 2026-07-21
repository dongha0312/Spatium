import React from "react";

// Apple 로그인 반환 URL(https://spatium.kro.kr/auth/apple/callback)이 실제로 렌더링하는 페이지.
//  - usePopup:true로 로그인하면 Apple JS SDK가 팝업 안에서 이 페이지로 리다이렉트된 뒤
//    자체적으로 opener(로그인 페이지)에 결과를 postMessage로 전달하고 팝업을 닫는다.
//  - 따라서 이 페이지는 별도 로직 없이, 아주 짧게 보이는 대기 화면 역할만 하면 된다.
function AppleCallbackPage() {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        height: "100vh",
        fontSize: "14px",
        color: "#666",
      }}
    >
      Apple 로그인 처리 중입니다...
    </div>
  );
}

export default AppleCallbackPage;
