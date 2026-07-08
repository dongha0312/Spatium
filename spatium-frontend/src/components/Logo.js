import { Link } from "react-router-dom";

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
