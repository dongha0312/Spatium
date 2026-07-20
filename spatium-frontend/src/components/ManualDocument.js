import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

const UNIFIED_NAV_CSS = `
  .layout,
  .guide-shell {
    grid-template-columns: 210px minmax(0, 1fr);
    gap: 54px;
    align-items: start;
  }

  .rail.side-nav,
  .side-nav {
    position: sticky;
    top: 24px;
    z-index: 20;
    display: flex;
    flex-direction: column;
    align-self: start;
    padding: 17px;
    border: 1px solid var(--border, var(--line, #e5d9cc));
    border-radius: 18px;
    background: var(--card-bg, var(--paper, #fffdf9));
    box-shadow: 0 12px 40px rgba(58, 38, 27, 0.07);
  }

  .rail-title.side-nav-title,
  .side-nav-title {
    margin: 0 4px 12px;
    padding: 0;
    color: var(--ink-faint, var(--brown-500, #9a887a));
    font-family: Pretendard, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 10px;
    font-weight: 900;
    letter-spacing: 1.4px;
    line-height: 1.5;
  }

  .rail.side-nav .side-link,
  .side-nav .side-link {
    display: flex;
    align-items: center;
    gap: 9px;
    margin: 3px 0;
    padding: 8px 9px;
    border: 0;
    border-radius: 9px;
    color: var(--ink-soft, #665346);
    font-size: 12px;
    font-weight: 700;
    line-height: 1.5;
    text-decoration: none;
    white-space: nowrap;
    transition: background 0.18s ease, color 0.18s ease;
  }

  .rail.side-nav .side-link:hover,
  .rail.side-nav .side-link.active,
  .side-nav .side-link:hover,
  .side-nav .side-link.active {
    color: var(--brown-800, var(--brown-700, #533729));
    background: var(--bg-alt, var(--cream, #f5efe7));
    transform: none;
  }

  .side-nav .side-link:focus-visible {
    outline: 2px solid var(--brown-700, #6f4a35);
    outline-offset: 2px;
  }

  .side-nav .side-index {
    width: 22px;
    height: 22px;
    display: grid;
    place-items: center;
    flex: 0 0 auto;
    border: 1px solid var(--border, var(--line, #e5d9cc));
    border-radius: 50%;
    color: var(--ink-faint, #9a887a);
    background: transparent;
    font-size: 9px;
    font-weight: 800;
  }

  .side-nav .side-link.active .side-index {
    border-color: var(--brown-800, var(--brown-700, #533729));
    color: #fff;
    background: var(--brown-800, var(--brown-700, #533729));
  }

  @media (max-width: 980px) {
    .layout,
    .guide-shell {
      grid-template-columns: 1fr;
      gap: 36px;
    }

    .rail.side-nav,
    .side-nav {
      position: sticky;
      top: 0;
      flex-direction: row;
      width: 100%;
      padding: 8px;
      overflow-x: auto;
      border-radius: 14px;
      scrollbar-width: thin;
    }

    .rail-title.side-nav-title,
    .side-nav-title {
      display: none;
    }

    .rail.side-nav .side-link,
    .side-nav .side-link {
      flex: 0 0 auto;
      margin: 0;
      padding: 7px 10px;
    }
  }
`;

const scopeDocumentSelectors = (css) =>
  css.replace(
    /(^|[}\n]\s*|,\s*)(:root(?:\[[^\]]+\])?|html|body)(?=\s*[{,])/gm,
    (match, prefix, selector) => {
      if (selector === "html" || selector === "body") {
        return `${prefix}${selector === "html" ? ":host" : ".manual-document"}`;
      }

      return `${prefix}${selector.replace(":root", ":host")}`;
    },
  );

function ManualDocument({ src, title }) {
  const hostRef = useRef(null);
  const [shadowRoot, setShadowRoot] = useState(null);
  const [documentContent, setDocumentContent] = useState({
    html: "",
    css: "",
    status: "loading",
  });

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return undefined;

    const root = host.shadowRoot || host.attachShadow({ mode: "open" });
    setShadowRoot(root);
    return undefined;
  }, []);

  useEffect(() => {
    const controller = new AbortController();

    const loadDocument = async () => {
      setDocumentContent({ html: "", css: "", status: "loading" });

      try {
        const response = await fetch(src, { signal: controller.signal });
        if (!response.ok)
          throw new Error(`Manual request failed: ${response.status}`);

        const source = await response.text();
        const parsed = new DOMParser().parseFromString(source, "text/html");
        const inlineCss = [...parsed.head.querySelectorAll("style")]
          .map((style) => style.textContent || "")
          .join("\n");
        const stylesheetUrls = [
          ...parsed.head.querySelectorAll('link[rel="stylesheet"]'),
        ]
          .map((link) => link.getAttribute("href"))
          .filter(Boolean);

        const externalCss = await Promise.all(
          stylesheetUrls.map(async (href) => {
            const cssUrl = new URL(href, window.location.origin).toString();
            const cssResponse = await fetch(cssUrl, {
              signal: controller.signal,
            });
            if (!cssResponse.ok) {
              throw new Error(
                `Manual stylesheet request failed: ${cssResponse.status}`,
              );
            }
            return cssResponse.text();
          }),
        );

        parsed.body
          .querySelectorAll("script")
          .forEach((script) => script.remove());

        setDocumentContent({
          html: parsed.body.innerHTML,
          css: scopeDocumentSelectors([inlineCss, ...externalCss].join("\n")),
          status: "ready",
        });
      } catch (error) {
        if (error.name !== "AbortError") {
          setDocumentContent({ html: "", css: "", status: "error" });
        }
      }
    };

    loadDocument();
    return () => controller.abort();
  }, [src]);

  useEffect(() => {
    if (!shadowRoot || documentContent.status !== "ready") return undefined;

    const manual = shadowRoot.querySelector(".manual-document");
    if (!manual) return undefined;

    const handleAnchorClick = (event) => {
      const link = event.target.closest?.('a[href^="#"]');
      if (!link) return;

      const id = decodeURIComponent(link.getAttribute("href").slice(1));
      const target = [...manual.querySelectorAll("[id]")].find(
        (node) => node.id === id,
      );
      if (!target) return;

      event.preventDefault();
      target.scrollIntoView({ behavior: "smooth", block: "start" });
      window.history.replaceState(
        null,
        "",
        `${window.location.pathname}${window.location.search}#${id}`,
      );
    };

    manual.addEventListener("click", handleAnchorClick);

    const links = [...manual.querySelectorAll(".side-link, .rail a")];
    const sections = [
      ...new Set(manual.querySelectorAll(".step[id], section[id]")),
    ];
    const observer =
      "IntersectionObserver" in window
        ? new IntersectionObserver(
            (entries) => {
              const visible = entries
                .filter((entry) => entry.isIntersecting)
                .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
              if (!visible) return;

              links.forEach((link) => {
                link.classList.toggle(
                  "active",
                  link.getAttribute("href") === `#${visible.target.id}`,
                );
              });
            },
            { rootMargin: "-18% 0px -58%", threshold: [0.08, 0.25, 0.5] },
          )
        : null;

    sections.forEach((section) => observer?.observe(section));

    const initialId = decodeURIComponent(window.location.hash.slice(1));
    if (initialId) {
      const initialTarget = [...manual.querySelectorAll("[id]")].find(
        (node) => node.id === initialId,
      );
      window.requestAnimationFrame(() =>
        initialTarget?.scrollIntoView({ block: "start" }),
      );
    }

    return () => {
      manual.removeEventListener("click", handleAnchorClick);
      observer?.disconnect();
    };
  }, [documentContent.status, shadowRoot]);

  return (
    <div className="manual-document-host" ref={hostRef} aria-label={title}>
      {shadowRoot &&
        createPortal(
          <>
            <style>{`
              :host { display: block; min-height: 70vh; }
              .manual-document-status {
                display: grid;
                min-height: 70vh;
                place-items: center;
                padding: 40px 24px;
                color: #5a4535;
                background: #faf7f3;
                font-family: Pretendard, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                font-size: 15px;
              }
              ${documentContent.css}
              ${UNIFIED_NAV_CSS}
            `}</style>
            {documentContent.status === "error" && (
              <div className="manual-document-status" role="alert">
                매뉴얼을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.
              </div>
            )}
            {documentContent.status === "ready" && (
              <div
                className="manual-document"
                dangerouslySetInnerHTML={{ __html: documentContent.html }}
              />
            )}
          </>,
          shadowRoot,
        )}
    </div>
  );
}

export default ManualDocument;
