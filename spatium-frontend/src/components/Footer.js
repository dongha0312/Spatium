import { Link } from "react-router-dom";
import "../styles/footer.css";

// 주요 법적 문서 링크와 저작권 표시를 포함한 공통 하단 Footer입니다.
const Footer = () => {
  return (
    <div className="site-footer">
      <span className="site-footer-brand">SPATIUM</span>
      <span className="site-footer-sep">·</span>
      <Link to="/cookie-policy">쿠키 정책</Link>
      <span className="site-footer-sep">·</span>
      <Link to="/privacy">개인정보처리방침</Link>
      <span className="site-footer-sep">·</span>
      <Link to="/terms">이용약관</Link>
      <span className="site-footer-copy"> &nbsp; Copyright © 2026 SPATIUM. All rights reserved.</span>
    </div>
  );
};

export default Footer;
