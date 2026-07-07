import { Link } from "react-router-dom"
import { exp } from "three/src/nodes/TSL.js"

const Footer = () => {
    return (
              <div className="lg-footer">
                <span className="lg-footer-brand">SPATIUM</span>
                <span className="lg-footer-sep">·</span>
                <Link to="/cookie-policy">쿠키 정책</Link>
                <span className="lg-footer-sep">·</span>
                <Link to="/privacy-consent">개인정보처리방침</Link>
                <div className="lg-footer-copy">© SPATIUM 2026</div>
              </div>
    )
}

export default Footer;