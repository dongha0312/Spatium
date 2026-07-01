import React from "react";
import { Link } from "react-router-dom";
import "../styles/cookiepolicy.css";

function CookiePolicy() {
    return (
        <div className="cp-root">

            {/* 상단 네비게이션 */}
            <div className="cp-nav">
                <Link to="/" className="cp-logo">
                    <div className="cp-logo-sq"><div className="cp-logo-sq-i"></div></div>
                    SPATIUM
                </Link>
                <span className="cp-nav-link">룸 인테리어</span>
                <div className="cp-nav-right">
                    <Link to="/" className="cp-btn-out">홈으로</Link>
                </div>
            </div>

            {/* 본문 */}
            <div className="cp-body">
                <div className="cp-content">
                    <div className="cp-eyebrow">고객 서비스</div>
                    <div className="cp-title">SPATIUM 쿠키 정책</div>
                    <div className="cp-updated">최종 수정일 : 2026. 07. 01</div>

                    <div className="cp-section">
                        <div className="cp-section-title">쿠키란?</div>
                        <p className="cp-text">
                            쿠키는 사용자가 SPATIUM 웹사이트나 3D 에디터를 이용할 때 해당 사용자의 컴퓨터나 모바일 기기의
                            브라우저에 저장되는 작은 텍스트 파일입니다. 사이트를 최대한 원활하게 이용할 수 있도록 로그인 상태와
                            편집 중인 룸 정보 등 기본 설정값을 기억하므로, 방문할 때마다 같은 정보를 다시 입력할 필요가 없습니다.
                            또한 당사는 쿠키를 활용해 서비스 작동 방식을 최적화하고, 사용자가 동의하는 경우 관련성 있는 안내나
                            제품(가구) 추천 정보를 전달할 수 있습니다.
                        </p>
                        <p className="cp-text">
                            이 정책에서는 쿠키에 대해 다루지만, 쿠키는 웹사이트에 사용되는 여러 추적 기술 중 하나일 뿐입니다.
                            픽셀, 로컬 스토리지(HTML5 local storage) 등 유사한 기술이 쿠키와 함께 비슷한 목적으로 사용될 수
                            있으며, 이 정책에서는 읽기 쉽도록 이를 통틀어 "쿠키"로 설명합니다.
                        </p>
                        <p className="cp-text">
                            쿠키에는 여러 유형이 있습니다. 일부는 SPATIUM 웹사이트에서 직접 설정하는 쿠키이며, 일부는
                            분석·기술 지원을 위해 협력하는 타사가 배치하는 쿠키입니다. 당사가 직접 배치한 쿠키로 수집되는
                            정보는 당사가 처리하며, 타사 쿠키는 해당 업체가 당사를 대신해 정보를 수집하거나(예: 분석 서비스)
                            자체 목적으로 수집합니다.
                        </p>
                        <p className="cp-text">
                            쿠키는 저장 기간에 따라 두 가지로 나뉩니다. 세션 쿠키는 브라우저를 종료하면 삭제되고, 영구 쿠키는
                            사용자가 직접 삭제하거나 만료일이 될 때까지 기기에 계속 저장됩니다.
                        </p>
                    </div>

                    <div className="cp-section">
                        <div className="cp-section-title">당사가 사용하는 쿠키의 유형과 사용 방식</div>

                        <div className="cp-subsection-title">1) 필수 쿠키</div>
                        <p className="cp-text">
                            서비스의 기본 기능을 이용하기 위해 꼭 필요한 쿠키입니다. 사용자가 사이트를 탐색하고 핵심 기능을
                            정상적으로 사용하는 데 필요한 활동을 수행합니다.
                        </p>
                        <ul className="cp-list">
                            <li>사용자의 SPATIUM 계정 로그인 및 로그인 상태 유지</li>
                            <li>회원가입·계정설정 등 각종 양식 작성 내용 임시 저장</li>
                            <li>3D 에디터에서 편집 중인 룸·가구 배치 정보 유지</li>
                            <li>당사의 개인정보 보호 기본 설정값 보관</li>
                            <li>사용자가 이용 중인 기기(PC, 모바일 등)에 알맞은 화면 표시</li>
                        </ul>
                        <p className="cp-text">
                            이러한 쿠키가 없으면 로그인, 프로젝트 저장 등 사이트의 핵심 기능이 정상적으로 작동하지 않습니다.
                            필수 쿠키는 쿠키 설정에서 비활성화할 수 없습니다.
                        </p>

                        <div className="cp-subsection-title">2) 성능 쿠키</div>
                        <p className="cp-text">
                            사용자가 서비스를 어떻게 이용하는지 파악해 서비스를 개선하는 데 도움이 되는 쿠키입니다. 예를 들어
                            방문자 수를 집계하고, 방문자가 3D 에디터·마이페이지 등 사이트 내에서 어떻게 이동하는지 확인합니다.
                            이를 통해 페이지 로딩 속도를 개선하고 자주 발생하는 오류를 파악하는 데 활용합니다.
                        </p>
                        <p className="cp-text">성능 쿠키는 쿠키 설정에서 비활성화할 수 있습니다.</p>
                        <div className="cp-example">
                            <div className="cp-example-name">Google Analytics</div>
                            <div className="cp-text" style={{ marginBottom: 0 }}>
                                웹사이트 방문 및 사이트 내 이동 경로를 추적하는 데 사용되는 성능 쿠키입니다. 수집된 데이터는
                                익명으로 처리되며, 서비스 성능을 모니터링하고 사용자 참여도를 파악하는 목적으로만 사용됩니다.
                            </div>
                            <div className="cp-cookie-names">사용되는 쿠키 이름 : _ga, _gid, _gclxxxx</div>
                        </div>

                        <div className="cp-subsection-title">3) 기능 쿠키</div>
                        <p className="cp-text">
                            사이트가 사용자의 기본 설정값을 기억해 맞춤화된 경험을 제공하도록 하는 쿠키입니다. 예를 들어
                            최근에 작업한 룸(프로젝트)을 기억해 다음 방문 시 이어서 편집할 수 있도록 하고, "로그인 상태 유지"
                            선택 여부를 기억합니다.
                        </p>
                        <p className="cp-text">
                            기능 쿠키는 쿠키 설정에서 끌 수 있으며, 끄는 경우 일부 편의 기능(예: 이어서 편집하기)이 정상적으로
                            동작하지 않을 수 있습니다.
                        </p>

                        <div className="cp-subsection-title">4) 타겟팅(광고) 쿠키</div>
                        <p className="cp-text">
                            SPATIUM은 현재 타사 광고 네트워크나 소셜 미디어와 연동된 타겟팅 쿠키를 사용하고 있지 않습니다.
                            추후 관련 기능을 도입할 경우, 사전에 이 정책을 통해 안내드리고 사용자의 동의를 받은 뒤 적용하겠습니다.
                        </p>
                    </div>

                    <div className="cp-section">
                        <div className="cp-section-title">쿠키 사용을 제어하는 방법</div>
                        <p className="cp-text">
                            당사는 사용자가 자신의 정보 공개 여부를 스스로 통제할 수 있기를 바랍니다. 각 페이지 하단의
                            "쿠키 설정" 메뉴에서 필수 쿠키를 제외한 성능·기능 쿠키의 허용 여부를 선택할 수 있습니다.
                        </p>
                        <p className="cp-text">
                            방문 중인 모든 웹사이트에 공통으로 적용되는 브라우저 자체 설정을 변경할 수도 있습니다. 대부분의
                            브라우저는 쿠키를 항상 허용, 거부하거나 특정 사이트의 쿠키만 삭제할 수 있는 기능을 제공합니다.
                            자세한 방법은 사용 중인 브라우저의 도움말 페이지를 참고해 주세요.
                        </p>
                        <div className="cp-note">
                            쿠키를 차단할 경우, 로그인 유지나 편집 중인 룸 이어서 보기 등 SPATIUM의 일부 기능이 평소대로
                            작동하지 않을 수 있습니다.
                        </div>
                    </div>

                    <div className="cp-footer">
                        SPATIUM · [사업자 등록번호 : 준비 중] · 대표 : [대표자명] · 고객지원 : [지원 이메일 / 연락처]
                        <br />
                        본 페이지는 서비스 준비 과정에서 작성된 초안이며, 실제 사업자 정보가 확정되는 대로 업데이트됩니다.
                    </div>
                </div>
            </div>
        </div>
    );
}

export default CookiePolicy;
