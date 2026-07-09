// 여러 페이지에서 반복되던 내 정보 패널 UI를 재사용하는 공통 컴포넌트입니다.
function AccountPanel({
  open,
  prefix,
  profile,
  statItems,
  onClose,
  onProfileClick,
  onLogout,
  onAccountClick,
  showScrim = true,
  panelExtraClass = "",
}) {
  if (!open) return null;

  const displayName = profile?.name || "회원";
  const displayInitial =
    profile?.initial || displayName.charAt(0).toUpperCase();
  const panelClassName = [`${prefix}-panel`, panelExtraClass]
    .filter(Boolean)
    .join(" ");

  return (
    <>
      {showScrim && <div className={`${prefix}-scrim`} onClick={onClose} />}
      <div className={panelClassName}>
        <div className={`${prefix}-panel-head`}>
          <div className={`${prefix}-panel-title`}>내 정보</div>
          <button
            className={`${prefix}-panel-close`}
            onClick={onClose}
            aria-label="닫기"
          >
            ×
          </button>
        </div>
        <div className={`${prefix}-panel-body`}>
          <span className={`${prefix}-panel-label`}>기본정보</span>
          <button
            className={`${prefix}-panel-profile`}
            onClick={onProfileClick}
          >
            <div className={`${prefix}-panel-avatar`}>
              {profile?.imageUrl ? (
                <img
                  className={`${prefix}-panel-avatar-img`}
                  src={profile.imageUrl}
                  alt=""
                />
              ) : (
                displayInitial.toUpperCase()
              )}
            </div>
            <div>
              <div className={`${prefix}-panel-pname`}>{displayName}</div>
              <div className={`${prefix}-panel-pnick`}>
                {profile?.subtext || ""}
              </div>
            </div>
            <span className={`${prefix}-panel-arrow`}>›</span>
          </button>

          <span className={`${prefix}-panel-label`}>이용현황</span>
          <div className={`${prefix}-panel-stats`}>
            {statItems.map((item) => (
              <div className={`${prefix}-panel-stat`} key={item.label}>
                <span className={`${prefix}-panel-stat-num`}>{item.value}</span>
                <span className={`${prefix}-panel-stat-label`}>
                  {item.label}
                </span>
              </div>
            ))}
          </div>
        </div>
        <div className={`${prefix}-panel-foot`}>
          <button
            className={`${prefix}-panel-foot-btn ${prefix}-panel-sub`}
            onClick={onLogout}
          >
            로그아웃
          </button>
        </div>
      </div>
    </>
  );
}

export default AccountPanel;
