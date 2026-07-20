import { Link } from "react-router-dom";
import logoImg from "../assets/spatium-logo.png";

// 페이지마다 반복되던 SPATIUM 로고 마크를 공통 링크 컴포넌트로 제공합니다.
function Logo({ prefix, to = "/", label = "SPATIUM" }) {
  return (
    <Link to={to} className={`${prefix}-logo app-header-logo`}>
      <img
        src={logoImg}
        alt=""
        className="app-header-logo-image"
      />
      {label}
    </Link>
  );
}

export default Logo;
