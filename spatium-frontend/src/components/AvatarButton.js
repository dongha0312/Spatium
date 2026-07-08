// 상단 사용자 아바타 버튼 UI를 페이지별 prefix 스타일로 재사용합니다.
function AvatarButton({
  prefix,
  imageUrl,
  initial,
  name,
  onClick,
  showCaret = true,
}) {
  return (
    <button
      type="button"
      className={`${prefix}-av-btn`}
      onClick={onClick}
      aria-label="내 정보 열기"
    >
      <div className={`${prefix}-av-circ`}>
        {imageUrl ? (
          <img className={`${prefix}-av-img`} src={imageUrl} alt="" />
        ) : (
          initial
        )}
      </div>
      <span className={`${prefix}-av-name`}>{name}</span>
      {showCaret && <span className={`${prefix}-av-caret`}>⌄</span>}
    </button>
  );
}

export default AvatarButton;
