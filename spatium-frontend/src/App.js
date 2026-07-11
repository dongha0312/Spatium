// React 라이브러리 가져오기
import React from "react";

// React Router 라이브러리 가져오기
import { BrowserRouter } from "react-router-dom";
import HomeRouters from "./routers/HomeRouters";
import MemberRouters from "./routers/MemberRouters";
import AuthRouters from "./routers/AuthRouters";

// 구글 인증처리 라이브러리(사전 설치 필요)
//  - LoginPage.js 등 어디서든 구글 로그인을 사용할 수 있도록 앱 최상단에서 감싸줌
import { GoogleOAuthProvider } from "@react-oauth/google";

// 구글 클라이언트 ID
const GOOGLE_CLIENT_ID =
  "75882144038-uo097qevmfnnb3in5q62n833ofptlnu1.apps.googleusercontent.com";

function App() {
  return (
    <GoogleOAuthProvider clientId={GOOGLE_CLIENT_ID}>
      <BrowserRouter>
        <HomeRouters></HomeRouters>
        <MemberRouters></MemberRouters>
        <AuthRouters></AuthRouters>
      </BrowserRouter>
    </GoogleOAuthProvider>
  );
}

export default App;
