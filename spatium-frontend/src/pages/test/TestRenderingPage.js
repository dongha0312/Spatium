import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { USDLoader } from "three/examples/jsm/loaders/USDLoader.js";

const DEFAULT_ROOM_MODEL_URL =
  "/testdata/4550c4e3-a2e9-49cb-867b-5e5d5ca38732_room-scan.usdz";

function disposeMaterial(material) {
  Object.values(material).forEach((value) => {
    if (
      value &&
      typeof value === "object" &&
      typeof value.dispose === "function"
    ) {
      value.dispose();
    }
  });
  material.dispose();
}

function disposeScene(scene) {
  scene.traverse((object) => {
    if (object.geometry) object.geometry.dispose();
    if (object.material) {
      if (Array.isArray(object.material)) {
        object.material.forEach(disposeMaterial);
      } else {
        disposeMaterial(object.material);
      }
    }
  });
}

function frameObject(camera, controls, object) {
  const bounds = new THREE.Box3().setFromObject(object);
  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const maxDimension = Math.max(size.x, size.y, size.z, 1);
  const distance =
    (maxDimension / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2))) *
    1.45;
  const viewDirection = new THREE.Vector3(0.8, 0.55, 1).normalize();

  camera.position.copy(center).addScaledVector(viewDirection, distance);
  camera.near = Math.max(distance / 1000, 0.01);
  camera.far = distance * 100;
  camera.updateProjectionMatrix();

  controls.target.copy(center);
  controls.update();
}

export default function TestRenderingPage({
  modelUrl = DEFAULT_ROOM_MODEL_URL,
  height = "100vh",
}) {
  const containerRef = useRef(null);
  const [error, setError] = useState("");
  const [loadingText, setLoadingText] = useState("Loading USDZ model...");

  useEffect(() => {
    if (!containerRef.current) return undefined;

    let isMounted = true;
    let frameId = 0;
    const root = containerRef.current;
    const width = root.clientWidth || window.innerWidth;
    const heightPx = root.clientHeight || window.innerHeight;

    root.replaceChildren();
    setError("");
    setLoadingText("Loading USDZ model...");

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0xf4f1ea);

    const camera = new THREE.PerspectiveCamera(
      50,
      width / heightPx,
      0.01,
      1000,
    );
    camera.position.set(3.5, 3, 5);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, heightPx);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1;
    root.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 0, 0);

    scene.add(new THREE.HemisphereLight(0xffffff, 0xd8cfc0, 2.4));
    const sun = new THREE.DirectionalLight(0xffffff, 1.7);
    sun.position.set(5, 8, 6);
    scene.add(sun);

    const grid = new THREE.GridHelper(10, 20, 0xc7bda9, 0xdfd7ca);
    grid.visible = false;
    scene.add(grid);

    const loader = new USDLoader();
    loader.load(
      modelUrl,
      (model) => {
        if (!isMounted) {
          disposeScene(model);
          return;
        }

        model.traverse((object) => {
          if (object.isMesh) {
            object.castShadow = true;
            object.receiveShadow = true;
          }
        });

        scene.add(model);

        const bounds = new THREE.Box3().setFromObject(model);
        if (!bounds.isEmpty()) {
          grid.position.y = bounds.min.y - 0.01;
          grid.visible = true;
        }

        frameObject(camera, controls, model);
        setLoadingText("");
      },
      (event) => {
        if (!isMounted || !event.total) return;
        const percent = Math.round((event.loaded / event.total) * 100);
        setLoadingText(`Loading USDZ model... ${percent}%`);
      },
      (caughtError) => {
        if (!isMounted) return;
        setLoadingText("");
        setError(
          caughtError instanceof Error
            ? caughtError.message
            : String(caughtError),
        );
      },
    );

    function animate() {
      frameId = requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    }
    animate();

    function resize() {
      const nextWidth = root.clientWidth || window.innerWidth;
      const nextHeight = root.clientHeight || window.innerHeight;
      camera.aspect = nextWidth / nextHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(nextWidth, nextHeight);
    }

    window.addEventListener("resize", resize);

    return () => {
      isMounted = false;
      cancelAnimationFrame(frameId);
      window.removeEventListener("resize", resize);
      controls.dispose();
      disposeScene(scene);
      renderer.dispose();
      root.replaceChildren();
    };
  }, [modelUrl]);

  return (
    <div style={{ position: "relative", width: "100%", height }}>
      <div ref={containerRef} style={{ position: "absolute", inset: 0 }} />
      <div
        style={{
          position: "absolute",
          left: 18,
          right: 18,
          top: 16,
          maxWidth: 420,
          padding: "12px 14px",
          background: "rgba(255,255,255,.86)",
          border: "1px solid rgba(0,0,0,.12)",
          borderRadius: 8,
          boxShadow: "0 8px 24px rgba(0,0,0,.12)",
          backdropFilter: "blur(8px)",
          color: "#242424",
          fontFamily: "Arial, Helvetica, sans-serif",
          overflowWrap: "anywhere",
        }}
      >
        <h1 style={{ margin: "0 0 6px", fontSize: 18 }}>
          CapturedRoom USDZ Viewer
        </h1>
        <p style={{ margin: 0, fontSize: 13, lineHeight: 1.35 }}>{modelUrl}</p>
      </div>
      {loadingText && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "grid",
            placeItems: "center",
            color: "#242424",
            fontFamily: "Arial, Helvetica, sans-serif",
            pointerEvents: "none",
          }}
        >
          {loadingText}
        </div>
      )}
      {error && (
        <pre
          style={{
            position: "absolute",
            left: 18,
            right: 18,
            bottom: 18,
            margin: 0,
            padding: "12px 14px",
            background: "#fff0f0",
            color: "#7a1111",
            border: "1px solid #d7aaaa",
            borderRadius: 8,
            whiteSpace: "pre-wrap",
          }}
        >
          {error}
        </pre>
      )}
    </div>
  );
}
