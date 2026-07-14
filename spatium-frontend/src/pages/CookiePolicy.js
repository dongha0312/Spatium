import React from "react";
import { Link } from "react-router-dom";
import Header from "../components/Header";
import Footer from "../components/Footer";
import {
  COOKIE_SECTIONS,
  LEGAL_EFFECTIVE_DATE,
  LegalDocumentContent,
} from "../components/legal/LegalDocumentContent";
import "../styles/cookiepolicy.css";

function CookiePolicy() {
  return (
    <div className="cp-root">
      <Header prefix="cp">
        <div className="cp-nav-right">
          <Link to="/" className="cp-btn-out">홈으로</Link>
        </div>
      </Header>
      <main className="cp-body">
        <div className="cp-content">
          <div className="cp-eyebrow">웹 저장 기술 안내</div>
          <h1 className="cp-title">SPATIUM 쿠키 정책</h1>
          <div className="cp-updated">시행일: {LEGAL_EFFECTIVE_DATE}</div>
          <p className="cp-text">
            SPATIUM은 웹 로그인과 보안 기능을 제공하기 위해 아래와 같은 필수 쿠키와
            브라우저 저장 기술을 사용합니다.
          </p>
          <LegalDocumentContent sections={COOKIE_SECTIONS} />
        </div>
      </main>
      <Footer />
    </div>
  );
}

export default CookiePolicy;
