import React from "react";
import { Link } from "react-router-dom";
import Header from "../components/Header";
import Footer from "../components/Footer";
import {
  LEGAL_EFFECTIVE_DATE,
  LegalDocumentContent,
  PRIVACY_SECTIONS,
} from "../components/legal/LegalDocumentContent";
import "../styles/cookiepolicy.css";

function PrivacyConsent() {
  return (
    <div className="app-page cp-root">
      <Header prefix="cp">
        <div className="cp-nav-right">
          <Link to="/" className="cp-btn-out">홈으로</Link>
        </div>
      </Header>
      <main className="cp-body">
        <div className="ui-card cp-content">
          <div className="cp-eyebrow">개인정보 보호</div>
          <h1 className="cp-title">SPATIUM 개인정보처리방침</h1>
          <div className="cp-updated">시행일: {LEGAL_EFFECTIVE_DATE}</div>
          <p className="cp-text">
            SPATIUM 운영팀은 개인정보 보호법 등 관계 법령을 준수하며, 웹사이트와
            iOS 앱에서 처리하는 개인정보를 아래와 같이 안내합니다.
          </p>
          <div className="cp-note">
            공간 스캔이나 가구 사진에 사람의 얼굴, 문서, 주소 또는 타인의 사생활이
            포함되지 않도록 촬영 전에 주변을 확인해 주세요.
          </div>
          <LegalDocumentContent sections={PRIVACY_SECTIONS} />
        </div>
      </main>
      <Footer />
    </div>
  );
}

export default PrivacyConsent;
