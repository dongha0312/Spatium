import React, { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

// 6단계: 생성된 GLB 확인 · 보정 (회전 / 스케일 / 중심점 / 바닥 접지)
// TripoSR 결과 GLB가 들어올 자리 — 지금은 플레이스홀더 박스를 렌더링한다.
const BOX_SIZE = { w: 1, h: 0.8, d: 0.6 };

function ViewerStep({ objectLabel }) {
  const mountRef = useRef(null);
  const threeRef = useRef(null);
  const [rotY, setRotY] = useState(0);
  const [scale, setScale] = useState(1);
  const [floorSnap, setFloorSnap] = useState(true);

  // three.js 씬 초기화 (마운트 시 1회)
  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0xf2ede6);

    const camera = new THREE.PerspectiveCamera(
      45,
      mount.clientWidth / mount.clientHeight,
      0.1,
      100
    );
    camera.position.set(2.4, 1.8, 2.8);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(mount.clientWidth, mount.clientHeight);
    mount.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, BOX_SIZE.h / 2, 0);

    scene.add(new THREE.HemisphereLight(0xfff8ef, 0x8a7561, 1.1));
    const dirLight = new THREE.DirectionalLight(0xffffff, 1.4);
    dirLight.position.set(3, 5, 2);
    scene.add(dirLight);

    // 바닥 그리드 — 사이트 팔레트(탄 · 베이지) 톤
    const grid = new THREE.GridHelper(8, 16, 0xc4956a, 0xddd3c6);
    scene.add(grid);

    const box = new THREE.Mesh(
      new THREE.BoxGeometry(BOX_SIZE.w, BOX_SIZE.h, BOX_SIZE.d),
      new THREE.MeshStandardMaterial({ color: 0xc4956a, roughness: 0.55 })
    );
    box.position.y = BOX_SIZE.h / 2;
    scene.add(box);

    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(box.geometry),
      new THREE.LineBasicMaterial({ color: 0x5c3d2e })
    );
    box.add(edges);

    let raf;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    const onResize = () => {
      camera.aspect = mount.clientWidth / mount.clientHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(mount.clientWidth, mount.clientHeight);
    };
    window.addEventListener("resize", onResize);

    threeRef.current = { box, controls, camera };

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", onResize);
      controls.dispose();
      edges.geometry.dispose();
      edges.material.dispose();
      box.geometry.dispose();
      box.material.dispose();
      renderer.dispose();
      mount.removeChild(renderer.domElement);
      threeRef.current = null;
    };
  }, []);

  // 보정값(회전 / 스케일 / 바닥 접지)을 박스에 반영
  useEffect(() => {
    const t = threeRef.current;
    if (!t) return;
    t.box.rotation.y = THREE.MathUtils.degToRad(rotY);
    t.box.scale.setScalar(scale);
    t.box.position.y = floorSnap ? (BOX_SIZE.h * scale) / 2 : BOX_SIZE.h / 2;
  }, [rotY, scale, floorSnap]);

  // 중심점 초기화: 카메라 타겟과 보정값을 처음 상태로 되돌린다
  const resetCenter = () => {
    setRotY(0);
    setScale(1);
    setFloorSnap(true);
    const t = threeRef.current;
    if (!t) return;
    t.box.position.set(0, BOX_SIZE.h / 2, 0);
    t.controls.target.set(0, BOX_SIZE.h / 2, 0);
    t.camera.position.set(2.4, 1.8, 2.8);
  };

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">모델을 확인하고 보정해주세요</h2>
      <p className="it3-step-desc">
        마우스로 돌려보며 방향 · 크기 · 바닥 접지를 맞춰주세요.
        {objectLabel ? ` (${objectLabel})` : ""}
      </p>

      <div className="it3-viewer-layout">
        <div className="it3-viewer-canvas" ref={mountRef} />

        <div className="it3-viewer-panel">
          <div className="it3-ctrl">
            <label className="it3-ctrl-label">
              회전 (Y축) <span className="it3-ctrl-val">{rotY}°</span>
            </label>
            <input
              type="range"
              min="0"
              max="360"
              value={rotY}
              onChange={(e) => setRotY(Number(e.target.value))}
            />
          </div>

          <div className="it3-ctrl">
            <label className="it3-ctrl-label">
              스케일 <span className="it3-ctrl-val">×{scale.toFixed(2)}</span>
            </label>
            <input
              type="range"
              min="0.5"
              max="2"
              step="0.05"
              value={scale}
              onChange={(e) => setScale(Number(e.target.value))}
            />
          </div>

          <label className="it3-toggle">
            <input
              type="checkbox"
              checked={floorSnap}
              onChange={(e) => setFloorSnap(e.target.checked)}
            />
            바닥 접지 보정
          </label>

          <button type="button" className="it3-btn-ghost" onClick={resetCenter}>
            중심점 · 보정 초기화
          </button>

          <div className="it3-dim-card">
            <div className="it3-result-label">모델 크기</div>
            {(BOX_SIZE.w * scale).toFixed(2)}m × {(BOX_SIZE.h * scale).toFixed(2)}m ×{" "}
            {(BOX_SIZE.d * scale).toFixed(2)}m
          </div>
        </div>
      </div>
    </div>
  );
}

export default ViewerStep;
