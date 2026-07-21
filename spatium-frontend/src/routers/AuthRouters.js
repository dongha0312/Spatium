// React 라이브러리 가지고 오기
import React from "react";

// URL 패턴에 따른 매핑 작업을 위한 라이브러리 가져오기
//  - Routes : 라우트 전체 관리
//  - Route :
import { Route, Routes } from "react-router-dom";
import LoginPage from "../pages/member/LoginPage";
import SignupPage from "../pages/member/SignupPage";
import AppleCallbackPage from "../pages/member/AppleCallbackPage";

function AuthRouters() {
  return (
    <Routes>
      <Route path="auth/login" element={<LoginPage></LoginPage>}></Route>
      <Route path="auth/signup" element={<SignupPage></SignupPage>}></Route>
      {/* Apple Developer 콘솔에 등록한 반환 URL과 동일한 경로 */}
      <Route
        path="auth/apple/callback"
        element={<AppleCallbackPage></AppleCallbackPage>}
      ></Route>
    </Routes>
  );
}

export default AuthRouters;
