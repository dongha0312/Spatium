import React, { useCallback, useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { TransformControls } from "three/examples/jsm/controls/TransformControls.js";
import { ViewHelper } from "three/examples/jsm/helpers/ViewHelper.js";
import { GLTFExporter } from "three/examples/jsm/exporters/GLTFExporter.js";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

// 6단계: 생성된 GLB 확인 · 보정
// 기본 조작은 roomSceneEditor와 동일 — 모델 드래그 = 바닥 이동, 링 핸들 드래그 = Y축 회전.
// "정밀 조정" 모드를 켜면 TransformControls 기즈모로 3축 이동/회전이 가능하다.
// 자동 정렬: AABB 부피 최소화 그리드 서치(기울기 제거) + 하위 퍼센타일 접지 +
//            바닥 발자국 무게중심 중앙 정렬.
const BOX_SIZE = { w: 1, h: 0.8, d: 0.6 };

// 업로드한 GLB의 최대 변을 이 크기(m)로 정규화해서 뷰어에 맞춘다
const TARGET_MAX_DIM = 1.2;

// 자동 정렬 파라미터
const ALIGN_SAMPLE_COUNT = 2000; // 정점 샘플 수
const ALIGN_SEARCH_RANGE = 25; // 기울기 탐색 범위 (±deg)
const FLOOR_PERCENTILE = 0.01; // 접지 기준: y좌표 하위 1퍼센타일 (노이즈 스파이크 무시)
const FOOTPRINT_BAND = 0.05; // 발자국: 바닥에서 높이의 5% 이내 정점들

// TripoSR 원본처럼 회전 · 위치가 어긋난 초기 상태 (사용자가 보정하는 시나리오)
const INITIAL = {
  rot: { x: 14, y: -32, z: 9 },
  pos: { x: 0.35, y: 0.55, z: -0.25 },
};

// 플레이스홀더 박스 (GLB가 없을 때)
function createPlaceholderBox() {
  const box = new THREE.Mesh(
    new THREE.BoxGeometry(BOX_SIZE.w, BOX_SIZE.h, BOX_SIZE.d),
    new THREE.MeshStandardMaterial({ color: 0xc4956a, roughness: 0.55 }),
  );
  const edges = new THREE.LineSegments(
    new THREE.EdgesGeometry(box.geometry),
    new THREE.LineBasicMaterial({ color: 0x5c3d2e }),
  );
  box.add(edges);
  box.userData.baseScale = 1;
  return box;
}

// 씬에서 내려간 모델의 geometry / material / texture 정리
function disposeObject(root) {
  root.traverse((child) => {
    if (child.geometry) child.geometry.dispose();
    if (child.material) {
      const mats = Array.isArray(child.material)
        ? child.material
        : [child.material];
      mats.forEach((m) => {
        Object.values(m).forEach((v) => {
          if (v && v.isTexture) v.dispose();
        });
        m.dispose();
      });
    }
  });
}

// 어긋난 초기 회전/위치를 모델에 적용
function applyInitialTransform(model) {
  model.rotation.set(
    THREE.MathUtils.degToRad(INITIAL.rot.x),
    THREE.MathUtils.degToRad(INITIAL.rot.y),
    THREE.MathUtils.degToRad(INITIAL.rot.z),
  );
  model.position.set(INITIAL.pos.x, INITIAL.pos.y, INITIAL.pos.z);
}

function rememberInitialTransform(model) {
  model.userData.initialTransform = {
    position: model.position.toArray(),
    quaternion: model.quaternion.toArray(),
  };
}

function restoreInitialTransform(model) {
  const initial = model.userData.initialTransform;
  if (!initial) return false;
  model.position.fromArray(initial.position);
  model.quaternion.fromArray(initial.quaternion);
  model.scale.setScalar(model.userData.baseScale || 1);
  return true;
}

// 모델의 정점을 모델 로컬 좌표로 균일 샘플링 (모델별로 1회 계산 후 캐시)
function collectLocalSamples(target) {
  if (target.userData._alignSamples) return target.userData._alignSamples;
  target.updateMatrixWorld(true);
  const invRoot = new THREE.Matrix4().copy(target.matrixWorld).invert();

  const meshes = [];
  let totalVertices = 0;
  target.traverse((child) => {
    if (child.isMesh && child.geometry?.attributes?.position) {
      meshes.push(child);
      totalVertices += child.geometry.attributes.position.count;
    }
  });

  const stride = Math.max(1, Math.ceil(totalVertices / ALIGN_SAMPLE_COUNT));
  const samples = [];
  const v = new THREE.Vector3();
  meshes.forEach((mesh) => {
    const attr = mesh.geometry.attributes.position;
    for (let i = 0; i < attr.count; i += stride) {
      v.fromBufferAttribute(attr, i)
        .applyMatrix4(mesh.matrixWorld)
        .applyMatrix4(invRoot);
      samples.push(v.clone());
    }
  });

  target.userData._alignSamples = samples;
  return samples;
}

function ViewerStep({ modelUrl, modelName, objectLabel, onComplete }) {
  const mountRef = useRef(null);
  const threeRef = useRef(null);
  const floorSnapRef = useRef(false);
  const gizmoModeRef = useRef(null);
  const modelLoadTokenRef = useRef(0);
  const [scale, setScale] = useState(1);
  const [floorSnap, setFloorSnap] = useState(true);
  const [gizmoMode, setGizmoMode] = useState(null); // null | "translate" | "rotate"
  const [fileName, setFileName] = useState(null); // null이면 플레이스홀더 박스
  const [baseSize, setBaseSize] = useState({ ...BOX_SIZE }); // 스케일 1 기준 모델 크기(m)
  const [loadingModel, setLoadingModel] = useState(false);
  const [modelError, setModelError] = useState("");
  const [exportingModel, setExportingModel] = useState(false);
  const [exportError, setExportError] = useState("");

  // three.js 씬 + 직접 조작(드래그 이동 / 핸들 회전 / 기즈모) 초기화 (마운트 시 1회)
  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0xf2ede6);

    const camera = new THREE.PerspectiveCamera(
      45,
      mount.clientWidth / mount.clientHeight,
      0.1,
      100,
    );
    camera.position.set(2.4, 1.8, 2.8);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.autoClear = false;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(mount.clientWidth, mount.clientHeight);
    mount.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.rotateSpeed = 0.3;
    controls.target.set(0, BOX_SIZE.h / 2, 0);

    const viewHelper = new ViewHelper(camera, renderer.domElement);
    viewHelper.location.top = 12;
    viewHelper.location.right = 12;
    viewHelper.setLabels("X", "Y", "Z");
    viewHelper.center.copy(controls.target);

    scene.add(new THREE.HemisphereLight(0xfff8ef, 0x8a7561, 1.1));
    const dirLight = new THREE.DirectionalLight(0xffffff, 1.4);
    dirLight.position.set(3, 5, 2);
    scene.add(dirLight);

    // 바닥 그리드 — 사이트 팔레트(탄 · 베이지) 톤
    const grid = new THREE.GridHelper(8, 16, 0xc4956a, 0xddd3c6);
    scene.add(grid);

    const model = createPlaceholderBox();
    applyInitialTransform(model);
    rememberInitialTransform(model);
    scene.add(model);

    // 선택 표시 — roomSceneEditor와 같은 시각 언어 (링 + 회전 핸들 + 연결선)
    const selectionRing = new THREE.Mesh(
      new THREE.RingGeometry(0.92, 1, 72),
      new THREE.MeshBasicMaterial({
        color: 0x5c3d2e,
        opacity: 0.82,
        transparent: true,
        depthTest: false,
        depthWrite: false,
        side: THREE.DoubleSide,
      }),
    );
    selectionRing.rotation.x = -Math.PI / 2;
    selectionRing.renderOrder = 30;

    const rotateHandle = new THREE.Mesh(
      new THREE.SphereGeometry(0.06, 20, 12),
      new THREE.MeshBasicMaterial({
        color: 0xc4956a,
        opacity: 0.95,
        transparent: true,
        depthTest: false,
        depthWrite: false,
      }),
    );
    rotateHandle.renderOrder = 31;

    const handleLine = new THREE.Line(
      new THREE.BufferGeometry(),
      new THREE.LineBasicMaterial({
        color: 0x5c3d2e,
        opacity: 0.75,
        transparent: true,
        depthTest: false,
      }),
    );
    handleLine.renderOrder = 30;
    scene.add(selectionRing, rotateHandle, handleLine);

    // 정밀 조정용 3축 기즈모 (기본은 숨김)
    const transformControls = new TransformControls(
      camera,
      renderer.domElement,
    );
    transformControls.attach(model);
    transformControls.enabled = false;
    const gizmoHelper = transformControls.getHelper();
    gizmoHelper.visible = false;
    scene.add(gizmoHelper);

    transformControls.addEventListener("dragging-changed", (event) => {
      controls.enabled = !event.value;
      // 기즈모 드래그를 놓는 순간 바닥 접지 재적용
      if (!event.value && floorSnapRef.current) snapToFloor();
      updateOverlay();
    });
    transformControls.addEventListener("objectChange", () => updateOverlay());

    // ─── 포인터 조작 상태 ───
    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();
    const floorPlane = new THREE.Plane();
    const upAxis = new THREE.Vector3(0, 1, 0);
    const floorHitPoint = new THREE.Vector3();
    let activeInteraction = null; // { type: "move" | "rotate", ... }
    let handleAngle = Math.PI / 4; // 회전 핸들이 링 위에서 놓이는 각도

    // 바닥 접지: y좌표 하위 퍼센타일을 바닥으로 잡는다 (Box3 min 대신 —
    // TripoSR 메시의 노이즈 스파이크 정점 하나 때문에 모델이 뜨는 걸 방지)
    function snapToFloor(target = threeRef.current?.model) {
      if (!target) return;
      const samples = collectLocalSamples(target);
      if (!samples.length) return;
      target.updateMatrixWorld(true);
      const v = new THREE.Vector3();
      const ys = samples
        .map((p) => v.copy(p).applyMatrix4(target.matrixWorld).y)
        .sort((a, b) => a - b);
      const floorY = ys[Math.floor(ys.length * FLOOR_PERCENTILE)];
      target.position.y -= floorY;
    }

    // 자동 정렬:
    // 1) 기울기 제거 — X/Z 미세 회전을 그리드 서치하며 AABB 부피가 최소가 되는
    //    회전을 찾는다 (기울어진 모델은 축 정렬 바운딩박스가 커지는 성질 이용).
    //    Y축 방향(yaw)은 사용자가 정한 값을 그대로 유지한다.
    // 2) 하위 퍼센타일 접지
    // 3) 바닥 발자국(footprint) 무게중심을 원점으로 — 비대칭 가구도 자연스럽게 중앙 정렬
    function autoAlign() {
      const t = threeRef.current;
      const target = t?.model;
      if (!target) return;
      const samples = collectLocalSamples(target);
      if (!samples.length) return;

      // 현재 회전 · 스케일이 적용된 방향 벡터 (위치 제외 — AABB 부피는 위치와 무관)
      const s = target.scale.x;
      const oriented = samples.map((p) =>
        p.clone().multiplyScalar(s).applyQuaternion(target.quaternion),
      );

      const v = new THREE.Vector3();
      const volumeFor = (q) => {
        let minX = Infinity,
          minY = Infinity,
          minZ = Infinity;
        let maxX = -Infinity,
          maxY = -Infinity,
          maxZ = -Infinity;
        for (let i = 0; i < oriented.length; i += 1) {
          v.copy(oriented[i]).applyQuaternion(q);
          if (v.x < minX) minX = v.x;
          if (v.x > maxX) maxX = v.x;
          if (v.y < minY) minY = v.y;
          if (v.y > maxY) maxY = v.y;
          if (v.z < minZ) minZ = v.z;
          if (v.z > maxZ) maxZ = v.z;
        }
        return (maxX - minX) * (maxY - minY) * (maxZ - minZ);
      };
      const quatFor = (rxDeg, rzDeg) =>
        new THREE.Quaternion().setFromEuler(
          new THREE.Euler(
            THREE.MathUtils.degToRad(rxDeg),
            0,
            THREE.MathUtils.degToRad(rzDeg),
          ),
        );

      // 코스(5°) → 파인(1°) 2단계 그리드 서치
      let best = { rx: 0, rz: 0, vol: volumeFor(quatFor(0, 0)) };
      const search = (centerX, centerZ, range, step) => {
        for (let rx = centerX - range; rx <= centerX + range; rx += step) {
          for (let rz = centerZ - range; rz <= centerZ + range; rz += step) {
            const vol = volumeFor(quatFor(rx, rz));
            if (vol < best.vol) best = { rx, rz, vol };
          }
        }
      };
      search(0, 0, ALIGN_SEARCH_RANGE, 5);
      search(best.rx, best.rz, 4, 1);

      target.quaternion.premultiply(quatFor(best.rx, best.rz));

      // 접지 (하위 퍼센타일)
      snapToFloor(target);

      // 발자국 무게중심 중앙 정렬 — 바닥 부근 정점들의 평균 x/z를 원점으로
      target.updateMatrixWorld(true);
      let minWorldY = Infinity;
      let maxWorldY = -Infinity;
      const world = samples.map((p) => {
        const w = p.clone().applyMatrix4(target.matrixWorld);
        if (w.y < minWorldY) minWorldY = w.y;
        if (w.y > maxWorldY) maxWorldY = w.y;
        return w;
      });
      const bandTop = minWorldY + (maxWorldY - minWorldY) * FOOTPRINT_BAND;
      let cx = 0,
        cz = 0,
        count = 0;
      world.forEach((w) => {
        if (w.y <= bandTop) {
          cx += w.x;
          cz += w.z;
          count += 1;
        }
      });
      if (count > 0) {
        target.position.x -= cx / count;
        target.position.z -= cz / count;
      }

      updateOverlay();
    }

    // 링/핸들/연결선을 현재 모델 위치 · 크기에 맞춰 갱신
    function updateOverlay() {
      const t = threeRef.current;
      const target = t?.model || model;
      const bounds = new THREE.Box3().setFromObject(target);
      if (bounds.isEmpty()) return;
      const size = bounds.getSize(new THREE.Vector3());
      const radius = Math.max(0.5, Math.max(size.x, size.z) * 0.58 + 0.18);
      const baseY = bounds.min.y + 0.02;

      selectionRing.position.set(target.position.x, baseY, target.position.z);
      selectionRing.scale.set(radius, radius, 1);

      rotateHandle.position.set(
        target.position.x + Math.sin(handleAngle) * radius,
        baseY,
        target.position.z + Math.cos(handleAngle) * radius,
      );
      handleLine.geometry.setFromPoints([
        new THREE.Vector3(target.position.x, baseY, target.position.z),
        rotateHandle.position.clone(),
      ]);
    }
    updateOverlay();

    // 모델 크기에 맞춰 카메라가 지나치게 멀어지지 않도록 제한
    function updateZoomLimit(target = threeRef.current?.model || model) {
      target.updateMatrixWorld(true);
      const bounds = new THREE.Box3().setFromObject(target);
      if (bounds.isEmpty()) return;
      const sphere = bounds.getBoundingSphere(new THREE.Sphere());
      controls.maxDistance = Math.max(4.2, sphere.radius * 6);

      const cameraOffset = camera.position.clone().sub(controls.target);
      if (cameraOffset.length() > controls.maxDistance) {
        camera.position
          .copy(controls.target)
          .add(cameraOffset.setLength(controls.maxDistance));
      }
      controls.update();
    }
    updateZoomLimit();

    // 기즈모 모드 전환 — 기즈모가 켜지면 링/핸들 직접 조작은 잠시 숨긴다
    function setGizmo(mode) {
      if (mode) {
        transformControls.setMode(mode);
        transformControls.enabled = true;
        gizmoHelper.visible = true;
        selectionRing.visible = false;
        rotateHandle.visible = false;
        handleLine.visible = false;
      } else {
        transformControls.enabled = false;
        gizmoHelper.visible = false;
        selectionRing.visible = true;
        rotateHandle.visible = true;
        handleLine.visible = true;
        updateOverlay();
      }
    }

    // 마우스/터치 좌표를 정규화 좌표로 바꾸고 raycaster를 세팅
    function setPointerRay(event) {
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse, camera);
    }

    // 포인터 ray가 "모델 높이의 수평면"과 만나는 지점 — 이동/회전 드래그 공통 기준
    function intersectModelFloor(event, object, target) {
      floorPlane.set(upAxis, -object.position.y);
      setPointerRay(event);
      return raycaster.ray.intersectPlane(floorPlane, target);
    }

    // 중심점 기준으로 바닥 위의 점이 이루는 각도 (드래그 회전 각도 계산용)
    function angleOnFloor(center, point) {
      return Math.atan2(point.x - center.x, point.z - center.z);
    }

    function capturePointer(pointerId) {
      try {
        renderer.domElement.setPointerCapture(pointerId);
      } catch (_error) {
        // 이미 해제된 포인터면 무시
      }
    }

    function releasePointer(pointerId) {
      try {
        renderer.domElement.releasePointerCapture(pointerId);
      } catch (_error) {
        // 이미 해제된 포인터면 무시
      }
    }

    // 드래그 이벤트가 OrbitControls로 전파되지 않게 막는다
    function stopSceneEvent(event) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation?.();
    }

    function beginMoveInteraction(event, object) {
      if (!intersectModelFloor(event, object, floorHitPoint)) return false;
      activeInteraction = {
        type: "move",
        pointerId: event.pointerId,
        object,
        offset: object.position.clone().sub(floorHitPoint),
        y: object.position.y,
      };
      controls.enabled = false;
      renderer.domElement.style.cursor = "grabbing";
      capturePointer(event.pointerId);
      return true;
    }

    function beginRotateInteraction(event, object) {
      if (!intersectModelFloor(event, object, floorHitPoint)) return false;
      activeInteraction = {
        type: "rotate",
        pointerId: event.pointerId,
        object,
        center: object.position.clone(),
        startAngle: angleOnFloor(object.position, floorHitPoint),
        startQuaternion: object.quaternion.clone(),
      };
      controls.enabled = false;
      renderer.domElement.style.cursor = "grabbing";
      capturePointer(event.pointerId);
      return true;
    }

    function updateActiveInteraction(event) {
      if (!activeInteraction || event.pointerId !== activeInteraction.pointerId)
        return;
      const { object } = activeInteraction;
      if (!object || !intersectModelFloor(event, object, floorHitPoint)) return;

      if (activeInteraction.type === "move") {
        floorHitPoint.add(activeInteraction.offset);
        object.position.set(
          floorHitPoint.x,
          activeInteraction.y,
          floorHitPoint.z,
        );
      } else {
        const angle = angleOnFloor(activeInteraction.center, floorHitPoint);
        const delta = angle - activeInteraction.startAngle;
        object.quaternion
          .copy(activeInteraction.startQuaternion)
          .premultiply(new THREE.Quaternion().setFromAxisAngle(upAxis, delta));
        handleAngle = angle; // 핸들이 포인터를 따라오게
        if (floorSnapRef.current) snapToFloor(object);
      }
      updateOverlay();
    }

    function endActiveInteraction(event) {
      if (!activeInteraction || event.pointerId !== activeInteraction.pointerId)
        return;
      activeInteraction = null;
      controls.enabled = true;
      renderer.domElement.style.cursor = "default";
      releasePointer(event.pointerId);
    }

    function handlePointerDown(event) {
      if (event.button !== 0) return;
      if (gizmoModeRef.current) return; // 기즈모 모드에선 TransformControls에 맡긴다
      const t = threeRef.current;
      if (!t?.model) return;
      setPointerRay(event);

      // 회전 핸들이 최우선
      if (raycaster.intersectObject(rotateHandle).length) {
        if (beginRotateInteraction(event, t.model)) stopSceneEvent(event);
        return;
      }
      // 모델 본체는 드래그 이동
      if (raycaster.intersectObject(t.model, true).length) {
        if (beginMoveInteraction(event, t.model)) stopSceneEvent(event);
      }
      // 빈 곳은 OrbitControls(화면 회전)에 넘긴다
    }

    function handlePointerMove(event) {
      if (gizmoModeRef.current) return;
      if (activeInteraction) {
        stopSceneEvent(event);
        updateActiveInteraction(event);
        return;
      }
      // 드래그 중이 아니면 호버 커서만 갱신
      const t = threeRef.current;
      if (!t?.model) return;
      setPointerRay(event);
      const hovering =
        raycaster.intersectObject(rotateHandle).length > 0 ||
        raycaster.intersectObject(t.model, true).length > 0;
      renderer.domElement.style.cursor = hovering ? "grab" : "default";
    }

    function handlePointerEnd(event) {
      if (!activeInteraction) return;
      stopSceneEvent(event);
      endActiveInteraction(event);
    }

    renderer.domElement.addEventListener(
      "pointerdown",
      handlePointerDown,
      true,
    );
    renderer.domElement.addEventListener(
      "pointermove",
      handlePointerMove,
      true,
    );
    renderer.domElement.addEventListener("pointerup", handlePointerEnd, true);
    renderer.domElement.addEventListener(
      "pointercancel",
      handlePointerEnd,
      true,
    );

    let raf;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      controls.update();
      renderer.clear();
      renderer.render(scene, camera);
      viewHelper.render(renderer);
    };
    animate();

    const onResize = () => {
      const { clientWidth: width, clientHeight: height } = mount;
      if (!width || !height) return;

      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height);
    };

    const resizeObserver = new ResizeObserver(onResize);
    resizeObserver.observe(mount);
    onResize();
    window.addEventListener("resize", onResize);

    threeRef.current = {
      scene,
      camera,
      controls,
      model,
      transformControls,
      snapToFloor,
      updateOverlay,
      updateZoomLimit,
      autoAlign,
      setGizmo,
    };

    return () => {
      modelLoadTokenRef.current += 1;
      cancelAnimationFrame(raf);
      resizeObserver.disconnect();
      window.removeEventListener("resize", onResize);
      renderer.domElement.removeEventListener(
        "pointerdown",
        handlePointerDown,
        true,
      );
      renderer.domElement.removeEventListener(
        "pointermove",
        handlePointerMove,
        true,
      );
      renderer.domElement.removeEventListener(
        "pointerup",
        handlePointerEnd,
        true,
      );
      renderer.domElement.removeEventListener(
        "pointercancel",
        handlePointerEnd,
        true,
      );
      viewHelper.dispose();
      transformControls.dispose();
      controls.dispose();
      const t = threeRef.current;
      if (t?.model) disposeObject(t.model);
      selectionRing.geometry.dispose();
      selectionRing.material.dispose();
      rotateHandle.geometry.dispose();
      rotateHandle.material.dispose();
      handleLine.geometry.dispose();
      handleLine.material.dispose();
      renderer.dispose();
      mount.removeChild(renderer.domElement);
      threeRef.current = null;
    };
  }, []);

  // 스케일 반영 (파일이 바뀌어도 재적용)
  useEffect(() => {
    const t = threeRef.current;
    if (!t?.model) return;
    t.model.scale.setScalar(scale * (t.model.userData.baseScale || 1));
    if (floorSnapRef.current) t.snapToFloor();
    t.updateOverlay();
    t.updateZoomLimit();
  }, [scale, fileName]);

  // 바닥 접지 토글 반영
  useEffect(() => {
    floorSnapRef.current = floorSnap;
    const t = threeRef.current;
    if (!t?.model) return;
    if (floorSnap) {
      t.snapToFloor();
      t.updateOverlay();
    }
  }, [floorSnap]);

  // 기즈모 모드 반영
  useEffect(() => {
    gizmoModeRef.current = gizmoMode;
    threeRef.current?.setGizmo(gizmoMode);
  }, [gizmoMode]);

  // 현재 모델을 새 모델로 교체 (이전 모델은 정리)
  const swapModel = useCallback((next) => {
    const t = threeRef.current;
    if (!t) return;
    if (t.model) {
      t.scene.remove(t.model);
      disposeObject(t.model);
    }
    t.model = next;
    t.scene.add(next);
    t.transformControls.attach(next);
    t.updateZoomLimit(next);
  }, []);

  const loadGlb = useCallback(
    (
      url,
      { displayName, applyDemoTransform = false, revokeUrl = false } = {},
    ) => {
      if (!url || !threeRef.current) return;

      const loadToken = modelLoadTokenRef.current + 1;
      modelLoadTokenRef.current = loadToken;
      setLoadingModel(true);
      setModelError("");

      const finishUrl = () => {
        if (revokeUrl) URL.revokeObjectURL(url);
      };

      new GLTFLoader().load(
        url,
        (gltf) => {
          finishUrl();
          if (modelLoadTokenRef.current !== loadToken || !threeRef.current) {
            disposeObject(gltf.scene);
            return;
          }

          const model = gltf.scene;
          const bounds = new THREE.Box3().setFromObject(model);
          const center = bounds.getCenter(new THREE.Vector3());
          const size = bounds.getSize(new THREE.Vector3());
          model.position.sub(center);

          const group = new THREE.Group();
          group.add(model);
          const maxDim = Math.max(size.x, size.y, size.z);
          const base = maxDim > 0 ? TARGET_MAX_DIM / maxDim : 1;
          group.userData.baseScale = base;
          group.scale.setScalar(base);

          if (applyDemoTransform) {
            applyInitialTransform(group);
          } else {
            // Python에서 이미 Three.js Y-up 축 보정을 마친 모델이므로 회전은 추가하지 않는다.
            group.position.set(0, (size.y * base) / 2, 0);
          }
          rememberInitialTransform(group);

          swapModel(group);
          setBaseSize({ w: size.x * base, h: size.y * base, d: size.z * base });
          setFileName(displayName || "generated-model.glb");
          setScale(1);
          setFloorSnap(true);
          threeRef.current?.updateOverlay();
          setLoadingModel(false);
        },
        undefined,
        () => {
          finishUrl();
          if (modelLoadTokenRef.current !== loadToken) return;
          setLoadingModel(false);
          setModelError("GLB 모델을 불러오지 못했습니다.");
        },
      );
    },
    [swapModel],
  );

  const loadGeneratedModel = useCallback(() => {
    if (!modelUrl) return;
    const name =
      modelName || modelUrl.split("/").pop() || "generated-model.glb";
    loadGlb(modelUrl, { displayName: name });
  }, [loadGlb, modelName, modelUrl]);

  useEffect(() => {
    loadGeneratedModel();
  }, [loadGeneratedModel]);

  // 축별 90° 회전 버튼
  const rotateBy = (axis, degrees) => {
    const t = threeRef.current;
    if (!t?.model) return;
    const axisVec = { x: [1, 0, 0], y: [0, 1, 0], z: [0, 0, 1] }[axis];
    t.model.quaternion.premultiply(
      new THREE.Quaternion().setFromAxisAngle(
        new THREE.Vector3(...axisVec),
        THREE.MathUtils.degToRad(degrees),
      ),
    );
    if (floorSnapRef.current) t.snapToFloor();
    t.updateOverlay();
  };

  // 자동 정렬 실행 후 바닥 접지 유지 모드로
  const handleAutoAlign = () => {
    threeRef.current?.autoAlign();
    setFloorSnap(true);
  };

  // 현재 모델이 처음 로드된 상태로 되돌리기 (카메라 포함)
  const resetAll = () => {
    const t = threeRef.current;
    if (!t?.model) return;
    if (!restoreInitialTransform(t.model)) return;
    setScale(1);
    setFloorSnap(true);
    t.model.scale.setScalar(t.model.userData.baseScale || 1);
    t.controls.target.set(0, BOX_SIZE.h / 2, 0);
    t.camera.position.set(2.4, 1.8, 2.8);
    t.updateOverlay();
  };

  // // 플레이스홀더 박스로 복귀
  // const restorePlaceholder = () => {
  //   modelLoadTokenRef.current += 1;
  //   const box = createPlaceholderBox();
  //   applyInitialTransform(box);
  //   rememberInitialTransform(box);
  //   swapModel(box);
  //   setBaseSize({ ...BOX_SIZE });
  //   setFileName(null);
  //   setScale(1);
  //   setFloorSnap(false);
  //   setLoadingModel(false);
  //   setModelError("");
  //   threeRef.current?.updateOverlay();
  // };

  const handleComplete = async () => {
    const target = threeRef.current?.model;
    if (!target || !fileName || exportingModel) return;

    setExportingModel(true);
    setExportError("");
    try {
      target.updateMatrixWorld(true);
      const bounds = new THREE.Box3().setFromObject(target);
      const size = bounds.getSize(new THREE.Vector3());
      const exportTarget = target.clone(true);
      exportTarget.traverse((child) => {
        child.userData = {};
      });

      const arrayBuffer = await new GLTFExporter().parseAsync(exportTarget, {
        binary: true,
        onlyVisible: true,
      });
      const file = new File([arrayBuffer], "spatium_furniture.glb", {
        type: "model/gltf-binary",
      });
      onComplete?.({
        file,
        dimensions: {
          x: Number(size.x.toFixed(4)),
          y: Number(size.y.toFixed(4)),
          z: Number(size.z.toFixed(4)),
        },
      });
    } catch (_error) {
      setExportError("보정된 GLB 파일을 만드는 데 실패했습니다.");
    } finally {
      setExportingModel(false);
    }
  };

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">모델을 확인하고 보정해주세요</h2>
      <p className="it3-step-desc">
        생성 직후엔 방향과 위치가 어긋나 있을 수 있어요. 직접 드래그하거나 자동
        정렬을 눌러주세요.
        {objectLabel ? ` (${objectLabel})` : ""}
      </p>

      <div className="it3-viewer-layout">
        <div className="it3-viewer-canvas">
          <div className="it3-viewer-mount" ref={mountRef} />
          <div className="it3-viewer-hint">
            {gizmoMode ? (
              "기즈모 축을 드래그해서 3축 이동 · 회전"
            ) : (
              <>
                가구 드래그 <b>이동</b> · 주황 핸들 드래그 <b>회전</b> · 빈 곳
                드래그 <b>화면 회전</b>
              </>
            )}
          </div>
        </div>

        <div className="it3-viewer-panel">
          <div className="it3-ctrl-group-label">보정</div>
          <button
            type="button"
            className="it3-btn-prim"
            onClick={handleAutoAlign}
          >
            자동 정렬
          </button>

          <div className="it3-ctrl-group-label">정밀 조정 (3축)</div>
          <div className="it3-rot-row">
            <button
              type="button"
              className={`it3-btn-sm${gizmoMode === null ? " is-on" : ""}`}
              onClick={() => setGizmoMode(null)}
            >
              끄기
            </button>
            <button
              type="button"
              className={`it3-btn-sm${gizmoMode === "translate" ? " is-on" : ""}`}
              onClick={() => setGizmoMode("translate")}
            >
              이동
            </button>
            <button
              type="button"
              className={`it3-btn-sm${gizmoMode === "rotate" ? " is-on" : ""}`}
              onClick={() => setGizmoMode("rotate")}
            >
              회전
            </button>
          </div>

          <div className="it3-ctrl-group-label">90° 회전</div>
          <div className="it3-rot-grid">
            {["x", "y", "z"].map((axis) => (
              <div key={axis} className="it3-rot-row">
                <span className="it3-rot-axis">{axis.toUpperCase()}축</span>
                <button
                  type="button"
                  className="it3-btn-sm"
                  onClick={() => rotateBy(axis, -90)}
                >
                  −90°
                </button>
                <button
                  type="button"
                  className="it3-btn-sm"
                  onClick={() => rotateBy(axis, 90)}
                >
                  +90°
                </button>
              </div>
            ))}
          </div>

          <div className="it3-ctrl-group-label">스케일</div>
          <div className="it3-ctrl">
            <label className="it3-ctrl-label">
              배율 <span className="it3-ctrl-val">×{scale.toFixed(2)}</span>
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

          <button type="button" className="it3-btn-ghost" onClick={resetAll}>
            처음 상태로 되돌리기
          </button>

          <div className="it3-dim-card">
            <div className="it3-result-label">모델 크기</div>
            {(baseSize.w * scale).toFixed(2)}m ×{" "}
            {(baseSize.h * scale).toFixed(2)}m ×{" "}
            {(baseSize.d * scale).toFixed(2)}m
          </div>

          {exportError && <div className="it3-hint">{exportError}</div>}
          <button
            type="button"
            className="it3-btn-prim"
            disabled={!fileName || loadingModel || exportingModel}
            onClick={handleComplete}
          >
            {exportingModel ? "GLB 내보내는 중…" : "보정 완료 · 저장하기"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default ViewerStep;
