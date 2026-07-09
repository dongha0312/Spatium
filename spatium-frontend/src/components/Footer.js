import { Link } from "react-router-dom";
import "../styles/footer.css";

// 쿠키 정책과 개인정보처리방침 링크를 포함한 공통 하단 Footer입니다.
const Footer = () => {
  return (
    <div className="site-footer">
      <span className="site-footer-brand">SPATIUM</span>
      <span className="site-footer-sep">·</span>
      <Link to="/cookie-policy">쿠키 정책</Link>
      <span className="site-footer-sep">·</span>
      <Link to="/privacy-consent">개인정보처리방침</Link>
      <span className="site-footer-copy"> &nbsp; © SPATIUM 2026 All rights reserved.</span>
    </div>
  );
};

export default Footer;
