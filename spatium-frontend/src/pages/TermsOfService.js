import React from "react";
import { Link } from "react-router-dom";
import Header from "../components/Header";
import Footer from "../components/Footer";
import {
  LEGAL_EFFECTIVE_DATE,
  LegalDocumentContent,
  TERMS_SECTIONS,
} from "../components/legal/LegalDocumentContent";
import "../styles/cookiepolicy.css";

function TermsOfService() {
  return (
    <div className="cp-root">
      <Header prefix="cp">
        <div className="cp-nav-right">
          <Link to="/" className="cp-btn-out">홈으로</Link>
        </div>
      </Header>
      <main className="cp-body">
        <div className="cp-content">
          <div className="cp-eyebrow">약관 및 정책</div>
          <h1 className="cp-title">SPATIUM 이용약관</h1>
          <div className="cp-updated">시행일: {LEGAL_EFFECTIVE_DATE}</div>
          <p className="cp-text">
            회원가입 전에 아래 내용을 확인해 주세요. 이 약관은 SPATIUM 웹사이트와
            iOS 앱에 공통으로 적용됩니다.
          </p>
          <LegalDocumentContent sections={TERMS_SECTIONS} />
        </div>
      </main>
      <Footer />
    </div>
  );
}

export default TermsOfService;
