import { Link } from "react-router-dom"

const Footer = () => {
    return (
              <div className="lg-footer">
                <span className="lg-footer-brand">SPATIUM</span>
                <span className="lg-footer-sep">·</span>
                <Link to="/cookie-policy">쿠키 정책</Link>
                <span className="lg-footer-sep">·</span>
                <Link to="/privacy-consent">개인정보처리방침</Link>
                <span className="lg-footer-copy"> &nbsp; © SPATIUM 2026</span>
              </div>
    )
}

export default Footer;