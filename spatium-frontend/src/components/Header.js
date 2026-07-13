import Logo from "./Logo";

// 페이지마다 반복되던 상단 네비게이션(로고 + 우측 영역)을 공통 컴포넌트로 제공합니다.
// 우측 영역은 페이지마다 달라서 children으로 받습니다.
function Header({ prefix, className, children }) {
  return (
    <div className={className || `${prefix}-nav`}>
      <Logo prefix={prefix} />
      {children}
    </div>
  );
}

export default Header;
