import React from "react";
import { Link } from "react-router-dom";
import "../styles/cookiepolicy.css";

function PrivacyConsent() {
    return (
        <div className="cp-root">

            {/* 상단 네비게이션 */}
            <div className="cp-nav">
                <Link to="/" className="cp-logo">
                    <div className="cp-logo-sq"><div className="cp-logo-sq-i"></div></div>
                    SPATIUM
                </Link>
                <div className="cp-nav-right">
                    <Link to="/" className="cp-btn-out">홈으로</Link>
                </div>
            </div>

            {/* 본문 */}
            <div className="cp-body">
                <div className="cp-content">
                    <div className="cp-eyebrow">약관 및 정책</div>
                    <div className="cp-title">개인정보 수집·이용 동의</div>
                    <div className="cp-updated">최종 수정일 : 2026. 07. 01</div>

                    <p className="cp-text">
                        SPATIUM(이하 "당사"라고 합니다)는 「개인정보 보호법」 제30조에 따라 정보주체의 개인정보를
                        수집·이용합니다. 본 개인정보의 수집·이용에 동의하지 않으실 경우 SPATIUM 웹사이트를 통한 회원가입이
                        불가능하고, 회원가입을 전제로 당사가 제공하는 서비스 및 기타 혜택을 받을 수 없습니다.
                    </p>

                    <div className="cp-section">
                        <div className="cp-section-title">1. 개인정보 이용 목적</div>

                        <div className="cp-subsection-title">1) 회원 가입 및 관리</div>
                        <p className="cp-text">
                            회원가입 의사 확인, 본인 식별·인증, 회원자격 유지·관리, 서비스 부정이용 방지, 만 14세 미만
                            아동의 가입 제한, 각종 고지·통지, 이용약관 위반 회원에 대한 이용제한 조치, 서비스의 원활한
                            운영에 지장을 미치는 행위 및 부정이용행위 제재, 가입 및 가입횟수 제한, 탈퇴의사 확인
                        </p>

                        <div className="cp-subsection-title">2) 서비스 제공</div>
                        <p className="cp-text">
                            3D 룸 인테리어 시뮬레이터, 룸(프로젝트) 저장·편집·불러오기 등 SPATIUM이 제공하는 서비스 제공,
                            유료 요금제를 이용하는 경우 결제 처리, 서비스 이용과 관련된 회원 확인 등 문제 해결
                        </p>

                        <div className="cp-subsection-title">3) 서비스 개선</div>
                        <p className="cp-text">
                            회원의 컴퓨터·모바일 기기 등 정보통신기기에 최적화된 방식으로 서비스를 제공할 수 있도록 개선,
                            서비스 개발, 개선 등 당사의 업무와 관련된 통계자료 작성
                        </p>

                        <div className="cp-subsection-title">4) 민원 처리</div>
                        <p className="cp-text">
                            민원인의 신원 확인, 민원사항 확인, 사실조사를 위한 연락·통지, 처리결과 통보, 서비스 이용과
                            관련하여 발생하는 문제 해결, 서비스 이용에 대한 만족도 조사 등
                        </p>

                        <div className="cp-subsection-title">5) 마케팅 목적 (선택)</div>
                        <p className="cp-text">
                            마케팅 목적에 선택 동의한 회원에 한하여, 당사가 제공하는 서비스 및 기타 혜택에 관련된 정보,
                            뉴스레터, 각종 이벤트 안내, 기타 당사가 회원을 대상으로 실시하는 마케팅 정보 제공
                        </p>
                    </div>

                    <div className="cp-section">
                        <div className="cp-section-title">2. 개인정보 수집 항목 및 수집 방법</div>
                        <p className="cp-text">당사는 다음 각 호의 개인정보를 수집·처리합니다.</p>

                        <div className="cp-subsection-title">1) 회원가입 정보</div>
                        <ul className="cp-list">
                            <li>필수 : 이메일 주소, 닉네임, 비밀번호, 생년월일, 성별</li>
                            <li>선택 : 프로필 사진</li>
                        </ul>

                        <div className="cp-subsection-title">2) 소셜 로그인 이용 시 (Apple, Google)</div>
                        <ul className="cp-list">
                            <li>필수 : 소셜 계정 이메일 주소, 소셜 계정 식별자(고유 ID)</li>
                        </ul>

                        <div className="cp-subsection-title">3) 서비스 이용 및 문의·민원 처리 시</div>
                        <ul className="cp-list">
                            <li>필수 : 닉네임, 이메일, 문의·민원의 내용</li>
                            <li>선택 : 전화번호</li>
                        </ul>

                        <div className="cp-subsection-title">4) 유료 요금제 결제 시 (해당하는 경우)</div>
                        <ul className="cp-list">
                            <li>필수 : 카드사, 카드번호 등 결제대행사를 통해 수집되는 결제 정보</li>
                        </ul>

                        <div className="cp-subsection-title">5) 가입 및 서비스 이용 과정에서 자동으로 생성되는 정보</div>
                        <ul className="cp-list">
                            <li>IP 주소, 접속 로그, 쿠키, 기기 및 브라우저 정보</li>
                        </ul>

                        <div className="cp-subsection-title">6) 마케팅 정보 수신 동의 시 (선택)</div>
                        <ul className="cp-list">
                            <li>선택 : 이메일, 휴대전화번호</li>
                        </ul>

                        <p className="cp-text" style={{ marginTop: 16 }}>
                            당사는 다음과 같은 방법으로 개인정보를 수집합니다.
                        </p>
                        <ul className="cp-list">
                            <li>회원가입, 소셜 로그인(Apple, Google) 연동, 서비스 이용, 이벤트 응모, 회원정보 수정, 고객센터 문의</li>
                            <li>생성정보 수집 도구(쿠키 등)를 통한 자동 수집</li>
                        </ul>
                    </div>

                    <div className="cp-section">
                        <div className="cp-section-title">3. 개인정보의 보유·이용 기간</div>
                        <p className="cp-text">
                            당사는 고객의 개인정보를 고지 및 동의받은 기간 동안 보유·이용합니다. 당사는 원칙적으로 회원이
                            탈퇴한 경우 또는 개인정보의 수집·이용 목적이 달성된 경우에는 해당 회원의 개인정보를 지체 없이
                            파기합니다.
                        </p>
                        <p className="cp-text">
                            다만 관련 법령(「전자상거래 등에서의 소비자 보호에 관한 법률」, 「전자금융거래법」, 「특정
                            금융거래정보의 보고 및 이용 등에 관한 법률」 등)에 따라 보존할 필요가 있는 경우에는 그 기간
                            동안 보존합니다. 이 경우 당사는 보관하는 정보를 그 보관 목적으로만 이용하며, 보존기간은 아래와
                            같습니다.
                        </p>
                        <ul className="cp-list">
                            <li>계약 또는 청약철회에 관한 기록, 대금결제 및 서비스 제공에 관한 기록 : 5년</li>
                            <li>소비자 불만 또는 분쟁처리에 관한 기록 : 3년</li>
                            <li>로그기록자료, 접속지의 추적자료 등 통신사실확인자료 : 3개월</li>
                            <li>전기통신일시, 전기통신개시·종료시간, 사용도수 등 통신사실확인자료 : 12개월</li>
                        </ul>
                    </div>

                    <div className="cp-footer">
                        SPATIUM · [사업자 등록번호 : 준비 중] · 대표 : [대표자명] · 고객지원 : [지원 이메일 / 연락처]
                        <br />
                        본 페이지는 서비스 준비 과정에서 작성된 초안이며, 실제 사업자 정보 및 유료 요금제 도입 여부가
                        확정되는 대로 업데이트됩니다.
                    </div>
                </div>
            </div>
        </div>
    );
}

export default PrivacyConsent;
