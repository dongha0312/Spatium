import { Link } from "react-router-dom";

// 페이지마다 반복되던 SPATIUM 로고 마크를 공통 링크 컴포넌트로 제공합니다.
function Logo({ prefix, to = "/", label = "SPATIUM" }) {
  return (
    <Link to={to} className={`${prefix}-logo`}>
      <div className={`${prefix}-logo-sq`}>
        <div className={`${prefix}-logo-sq-i`} />
      </div>
      {label}
    </Link>
  );
}

export default Logo;
