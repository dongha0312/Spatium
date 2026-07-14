import { useState } from "react";
import { Link } from "react-router-dom";
import Logo from "./Logo";
import "../styles/Header.css";

const DEFAULT_NAVIGATION = [
  {
    label: "기능",
    items: [
      // 추후 QR코드가 나오면 이 부분 수정하기
      // { label: "나의 방 스캔하기", to: "" },
      { label: "방 꾸미기", to: "/member/mypage" },
      { label: "이미지로 3D 가구 만들기", to: "/member/imgto3d" },
    ],
  },
  {
    label: "기능별 사용 설명서",
    items: [
      { label: "나의 방 스캔하기", to: "" },
      { label: "방 꾸미기", to: "" },
      { label: "서랍장을 나만의 피규어로 꾸미기", to: "" },
      { label: "이미지로 3D 가구 만들기", to: "" },
      { label: "자주 발생하는 문제", to: "" },
    ],
  },
  { label: "Contact Us", to: "/contact-us" },
];

// 페이지마다 반복되는 상단 네비게이션을 공통으로 제공합니다.
// 기본 메뉴는 모든 페이지에 표시되며, navigation 배열을 전달하면 페이지별로 바꿀 수 있습니다.
function Header({
  prefix,
  className,
  children,
  navigation = DEFAULT_NAVIGATION,
  navigationLabel = "주요 메뉴",
}) {
  const [openMenu, setOpenMenu] = useState(null);
  const headerClassName = [className || `${prefix}-nav`, "app-header"]
    .filter(Boolean)
    .join(" ");

  const renderNavigationAction = (item, className) => {
    const handleClick = () => {
      item.onClick?.();
      setOpenMenu(null);
    };

    if (item.to) {
      return (
        <Link to={item.to} className={className} onClick={handleClick}>
          {item.label}
        </Link>
      );
    }

    if (item.href) {
      return (
        <a href={item.href} className={className} onClick={handleClick}>
          {item.label}
        </a>
      );
    }

    return (
      <button type="button" className={className} onClick={handleClick}>
        {item.label}
      </button>
    );
  };

  return (
    <header className={headerClassName}>
      <Logo prefix={prefix} />
      {navigation.length > 0 && (
        <nav className="app-header-menu" aria-label={navigationLabel}>
          {navigation.map((item) => {
            const hasDropdown = item.items?.length > 0;
            const isOpen = openMenu === item.label;

            if (!hasDropdown) {
              return (
                <div className="app-header-item" key={item.label}>
                  {renderNavigationAction(item, "app-header-link")}
                </div>
              );
            }

            return (
              <div
                className="app-header-item"
                key={item.label}
                onMouseEnter={() => setOpenMenu(item.label)}
                onMouseLeave={() => setOpenMenu(null)}
              >
                <button
                  type="button"
                  className="app-header-link app-header-link-caret"
                  aria-expanded={isOpen}
                  aria-haspopup="menu"
                  onClick={() => setOpenMenu(isOpen ? null : item.label)}
                >
                  {item.label}
                </button>
                <div
                  className={`app-header-dropdown${
                    isOpen ? " app-header-dropdown-open" : ""
                  }${item.compact ? " app-header-dropdown-compact" : ""}`}
                  role="menu"
                >
                  {item.items.map((subItem) => (
                    <div key={subItem.label} role="none">
                      {renderNavigationAction(
                        subItem,
                        "app-header-dropdown-link",
                      )}
                    </div>
                  ))}
                </div>
              </div>
            );
          })}
        </nav>
      )}
      {children}
    </header>
  );
}

export default Header;
