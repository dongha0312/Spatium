import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import Footer from "../components/Footer";
import Header from "../components/Header";
import "../styles/manualpage.css";

const MANUALS = {
  "room-decoration": {
    title: "방 꾸미기 사용 설명서",
    src: "/manuals/room-decoration.html",
    actionLabel: "3D 에디터 열기",
    actionTo: "/member/editor",
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
  const iframeRef = useRef(null);
  const observerRef = useRef(null);
  const [frameHeight, setFrameHeight] = useState(900);

  const resizeFrame = useCallback(() => {
    const frame = iframeRef.current;
    const documentElement = frame?.contentDocument?.documentElement;
    const body = frame?.contentDocument?.body;

    if (!documentElement || !body) return;

    const nextHeight = Math.max(
      documentElement.scrollHeight,
      documentElement.offsetHeight,
      body.scrollHeight,
      body.offsetHeight,
    );

    if (nextHeight > 0) setFrameHeight(Math.ceil(nextHeight));
  }, []);

  const handleFrameLoad = useCallback(() => {
    observerRef.current?.disconnect();
    resizeFrame();

    const frame = iframeRef.current;
    const frameWindow = frame?.contentWindow;
    const frameDocument = frame?.contentDocument;
    const ResizeObserverClass = frameWindow?.ResizeObserver;

    if (frameDocument?.fonts?.ready) {
      frameDocument.fonts.ready.then(resizeFrame).catch(() => undefined);
    }

    if (ResizeObserverClass && frameDocument?.documentElement) {
      const observer = new ResizeObserverClass(resizeFrame);
      observer.observe(frameDocument.documentElement);
      if (frameDocument.body) observer.observe(frameDocument.body);
      observerRef.current = observer;
    }

    frameDocument?.querySelectorAll("img").forEach((image) => {
      if (!image.complete) image.addEventListener("load", resizeFrame, { once: true });
    });
  }, [resizeFrame]);

  useEffect(() => {
    window.scrollTo({ top: 0, behavior: "auto" });
    window.addEventListener("resize", resizeFrame);

    return () => {
      window.removeEventListener("resize", resizeFrame);
      observerRef.current?.disconnect();
    };
  }, [config.src, resizeFrame]);

  const handlePrint = () => {
    iframeRef.current?.contentWindow?.print();
  };

  return (
    <div className="manual-root">
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
        <iframe
          ref={iframeRef}
          className="manual-frame"
          src={config.src}
          title={config.title}
          style={{ height: `${frameHeight}px` }}
          onLoad={handleFrameLoad}
        />
      </main>
      <Footer />
    </div>
  );
}

export default ManualPage;
