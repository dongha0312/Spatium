import { Link } from "react-router-dom";
import "../styles/footer.css";

const Footer = () => {
  return (
    <div className="site-footer">
      <span className="site-footer-brand">SPATIUM</span>
      <span className="site-footer-sep">·</span>
      <Link to="/cookie-policy">쿠키 정책</Link>
      <span className="site-footer-sep">·</span>
      <Link to="/privacy-consent">개인정보처리방침</Link>
      <span className="site-footer-copy"> &nbsp; © SPATIUM 2026</span>
    </div>
  );
};

export default Footer;
