import { useEffect } from "react";
import { Link } from "react-router-dom";
import Footer from "../components/Footer";
import Header from "../components/Header";
import ManualDocument from "../components/ManualDocument";
import "../styles/manualpage.css";

const MANUALS = {
  "room-scan": {
    title: "나의 방 스캔하기 사용 설명서",
    src: "/manuals/room-scan.html",
    actionLabel: "내 프로젝트 보기",
    actionTo: "/member/mypage",
  },
  "room-decoration": {
    title: "방 꾸미기 사용 설명서",
    src: "/manuals/room-decoration.html",
    actionLabel: "3D 에디터 열기",
    actionTo: "/member/editor",
  },
  "drawer-decoration": {
    title: "서랍장을 나만의 피규어로 꾸미기 사용 설명서",
    src: "/manuals/drawer-decoration.html",
    actionLabel: "서랍장 꾸미기 시작",
    actionTo: "/member/imgto3d",
  },
  "furniture-creation": {
    title: "이미지로 3D 가구 만들기 사용 설명서",
    src: "/manuals/furniture-creation.html",
    actionLabel: "가구 만들기 시작",
    actionTo: "/member/imgto3d",
  },
};

function ManualPage({ manual }) {
  const config = MANUALS[manual] || MANUALS["room-decoration"];
  useEffect(() => {
    window.scrollTo({ top: 0, behavior: "auto" });
  }, [config.src]);

  const handlePrint = () => {
    window.print();
  };

  return (
    <div className="app-page manual-root">
      <Header prefix="manual">
        <div className="manual-nav-right">
          <button
            type="button"
            className="manual-btn manual-btn-out"
            onClick={handlePrint}
          >
            인쇄 · PDF
          </button>
          <Link className="manual-btn manual-btn-primary" to={config.actionTo}>
            {config.actionLabel}
          </Link>
        </div>
      </Header>
      <main className="manual-body">
        <ManualDocument src={config.src} title={config.title} />
      </main>
      <Footer />
    </div>
  );
}

export default ManualPage;
