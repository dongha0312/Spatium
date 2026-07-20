INDEX_HTML = """<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Image to 3D Prototype</title>
  <style>
    :root { color-scheme: light; font-family: Arial, Helvetica, sans-serif; color: #182321; background: #f5f6f2; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; }
    main { width: min(1140px, calc(100vw - 32px)); margin: 0 auto; padding: 28px 0 36px; }
    header { margin-bottom: 22px; }
    h1 { margin: 0 0 8px; font-size: 34px; letter-spacing: 0; }
    p { margin: 0; color: #52605d; }
    .layout { display: grid; grid-template-columns: minmax(0, 1fr) 340px; gap: 18px; align-items: start; }
    .surface { background: #fff; border: 1px solid #d8dfda; border-radius: 8px; }
    .preview { min-height: 570px; display: grid; place-items: center; overflow: hidden; position: relative; background-color: #fbfcfa; background-image: linear-gradient(45deg, #eef1ee 25%, transparent 25%), linear-gradient(-45deg, #eef1ee 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #eef1ee 75%), linear-gradient(-45deg, transparent 75%, #eef1ee 75%); background-size: 24px 24px; background-position: 0 0, 0 12px, 12px -12px, -12px 0; }
    .preview img { width: 100%; height: 100%; max-height: 650px; object-fit: contain; padding: 20px; display: none; }
    .empty { text-align: center; max-width: 300px; color: #6c7774; line-height: 1.6; }
    .panel { padding: 18px; }
    .field { display: grid; gap: 7px; margin-bottom: 15px; }
    label { font-size: 13px; font-weight: 700; color: #293330; }
    input, select { width: 100%; min-height: 40px; border: 1px solid #bfcac4; border-radius: 6px; padding: 8px 10px; background: #fff; color: #182321; font: inherit; }
    button { width: 100%; min-height: 43px; border: 0; border-radius: 6px; padding: 9px 12px; background: #176b5b; color: #fff; font: inherit; font-weight: 700; cursor: pointer; }
    button + button { margin-top: 9px; }
    button.secondary { background: #e5ece8; color: #1d443a; }
    button:disabled { background: #9ba7a1; cursor: wait; }
    .status { min-height: 20px; margin-top: 12px; font-size: 13px; color: #52605d; }
    .notice { display: none; margin-top: 14px; padding: 12px; border-radius: 6px; font-size: 13px; line-height: 1.45; word-break: break-word; }
    .result { background: #edf7f2; border: 1px solid #c9e3d5; color: #174c3e; }
    .error { background: #fff0ec; border: 1px solid #f0c9bc; color: #83321d; }
    .result a { color: #0c624f; font-weight: 700; }
    .pipeline { margin: 0 0 18px; padding: 11px; border-left: 3px solid #176b5b; background: #f2f7f4; color: #456057; font-size: 12px; line-height: 1.55; }
    .is-hidden { display: none; }
    .help { margin: -7px 0 14px; color: #6c7774; font-size: 12px; line-height: 1.45; }
    @media (max-width: 860px) { main { width: min(100% - 24px, 1140px); padding-top: 20px; } .layout { grid-template-columns: 1fr; } .preview { min-height: 400px; } }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Image to 3D</h1>
      <p>객체 분리 모델과 3D 생성 모델을 선택해 로컬 GPU에서 GLB를 생성합니다.</p>
    </header>

    <section class="layout">
      <div class="surface preview">
        <img id="previewImage" alt="업로드 또는 배경 제거 결과">
        <div id="emptyState" class="empty">사진을 고른 뒤 배경 제거 미리보기로 대상만 올바르게 선택됐는지 확인하세요.</div>
      </div>

      <form id="uploadForm" class="surface panel">
        <p class="pipeline">사진 + 객체명 → YOLO 또는 GroundingDINO+SAM2 → 투명 PNG 확인 → TripoSR 또는 Stable Fast 3D → GLB</p>
        <div class="field">
          <label for="image">사진</label>
          <input id="image" name="image" type="file" accept="image/png,image/jpeg,image/webp" required>
        </div>
        <div class="field">
          <label for="provider">3D 생성 모델</label>
          <select id="provider" name="provider">
            <option value="local_triposr" selected>TripoSR (기존 로컬 모델)</option>
            <option value="local_stable_fast_3d">Stable Fast 3D (무료 로컬 모델)</option>
          </select>
        </div>
        <p id="providerHelp" class="help">기존 TripoSR 환경을 사용합니다.</p>
        <div class="field">
          <label for="segmentation_provider">객체 분리 모델</label>
          <select id="segmentation_provider" name="segmentation_provider">
            <option value="yolo" selected>YOLO (빠른 기존 방식)</option>
            <option value="grounded_sam2">GroundingDINO + SAM2 (자연어·정밀 마스크)</option>
          </select>
        </div>
        <p id="segmentationHelp" class="help">정해진 가구 클래스를 빠르게 분리합니다.</p>
        <div id="yoloTarget" class="field">
          <label for="target_class">분리할 대상</label>
          <select id="target_class" name="target_class">
            <option value="auto" selected>자동 선택 (중앙의 큰 객체)</option>
            <option value="bathhub">bathhub</option>
            <option value="bed">bed</option>
            <option value="chair">의자</option>
            <option value="dishwasher">dishwasher</option>
            <option value="door">door</option>
            <option value="oven">oven</option>
            <option value="refrigerator">refrigerator</option>
            <option value="sink">sink</option>
            <option value="sofa">sofa</option>
            <option value="storage">storage</option>
            <option value="stove">stove</option>
            <option value="table">table</option>
            <option value="television">television</option>
            <option value="toilet">toilet</option>
            <option value="washerDryer">washerDryer</option>
            <option value="window">window</option>
          </select>
        </div>
        <div id="groundedTarget" class="field is-hidden">
          <label for="object_query">찾을 객체명 (한글 또는 영어)</label>
          <input id="object_query" name="object_query" type="text" placeholder="예: 회색 사무용 의자">
        </div>
        <div id="triposrOptions" class="field">
          <label for="mc_resolution">메시 해상도</label>
          <select id="mc_resolution" name="mc_resolution">
            <option value="192">192</option>
            <option value="256" selected>256</option>
            <option value="320">320</option>
          </select>
        </div>
        <div id="sf3dOptions" class="is-hidden">
          <div class="field">
            <label for="texture_resolution">텍스처 해상도</label>
            <select id="texture_resolution" name="texture_resolution">
              <option value="512">512</option>
              <option value="1024" selected>1024 (권장)</option>
              <option value="2048">2048</option>
            </select>
          </div>
          <div class="field">
            <label for="remesh">리메시</label>
            <select id="remesh" name="remesh">
              <option value="none" selected>없음 (권장)</option>
              <option value="triangle">Triangle</option>
              <option value="quad">Quad</option>
            </select>
          </div>
        </div>
        <button id="segmentButton" class="secondary" type="button">배경 제거 미리보기</button>
        <button id="submitButton" type="submit">확인된 이미지로 3D 모델 생성</button>
        <div id="status" class="status"></div>
        <div id="result" class="notice result"></div>
        <div id="error" class="notice error"></div>
      </form>
    </section>
  </main>

  <script>
    const form = document.getElementById("uploadForm");
    const imageInput = document.getElementById("image");
    const targetClass = document.getElementById("target_class");
    const segmentationProvider = document.getElementById("segmentation_provider");
    const segmentationHelp = document.getElementById("segmentationHelp");
    const yoloTarget = document.getElementById("yoloTarget");
    const groundedTarget = document.getElementById("groundedTarget");
    const objectQuery = document.getElementById("object_query");
    const providerSelect = document.getElementById("provider");
    const providerHelp = document.getElementById("providerHelp");
    const triposrOptions = document.getElementById("triposrOptions");
    const sf3dOptions = document.getElementById("sf3dOptions");
    const previewImage = document.getElementById("previewImage");
    const emptyState = document.getElementById("emptyState");
    const segmentButton = document.getElementById("segmentButton");
    const submitButton = document.getElementById("submitButton");
    const statusBox = document.getElementById("status");
    const resultBox = document.getElementById("result");
    const errorBox = document.getElementById("error");
    let preparedImage = null;

    providerSelect.addEventListener("change", syncProviderOptions);
    segmentationProvider.addEventListener("change", () => {
      preparedImage = null;
      syncSegmentationOptions();
    });
    syncProviderOptions();
    syncSegmentationOptions();

    imageInput.addEventListener("change", () => {
      preparedImage = null;
      hideNotices();
      const file = imageInput.files[0];
      if (!file) return showEmpty();
      previewImage.src = URL.createObjectURL(file);
      previewImage.style.display = "block";
      emptyState.style.display = "none";
    });

    segmentButton.addEventListener("click", async () => {
      const file = imageInput.files[0];
      if (!file) return showError("먼저 사진을 선택하세요.");
      if (!validateSegmentationInput()) return;
      hideNotices();
      const segmentationName = segmentationProvider.value === "grounded_sam2" ? "GroundingDINO+SAM2" : "YOLO";
      setBusy(true, `${segmentationName}가 대상을 분리하는 중...`);
      try {
        const data = new FormData();
        data.append("image", file);
        data.append("segmentation_provider", segmentationProvider.value);
        data.append("target_class", targetClass.value);
        data.append("object_query", objectQuery.value.trim());
        const response = await fetch("/v1/remove-background", { method: "POST", body: data });
        const payload = await readPayload(response);
        if (!response.ok) throw new Error(formatError(payload));
        const imageResponse = await fetch(payload.download_url);
        if (!imageResponse.ok) throw new Error("분리된 PNG를 가져오지 못했습니다.");
        const blob = await imageResponse.blob();
        preparedImage = new File([blob], "segmented.png", { type: "image/png" });
        previewImage.src = URL.createObjectURL(preparedImage);
        previewImage.style.display = "block";
        emptyState.style.display = "none";
        const translation = payload.translated_query ? ` / 영문: ${payload.translated_query}` : "";
        showResult(`배경 제거 완료: ${payload.segmented_object}${translation} (${payload.device})`);
      } catch (error) {
        showError(error.message);
      } finally {
        setBusy(false, "");
      }
    });

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const original = imageInput.files[0];
      if (!original) return showError("먼저 사진을 선택하세요.");
      if (!preparedImage && !validateSegmentationInput()) return;
      hideNotices();
      const modelName = providerSelect.value === "local_stable_fast_3d" ? "Stable Fast 3D" : "TripoSR";
      const segmentationName = segmentationProvider.value === "grounded_sam2" ? "GroundingDINO+SAM2" : "YOLO";
      setBusy(true, preparedImage ? `확인된 PNG로 ${modelName} 생성 중...` : `${segmentationName} 분리와 ${modelName} 생성을 진행 중...`);
      try {
        const data = new FormData(form);
        if (preparedImage) {
          data.set("image", preparedImage);
          data.set("remove_background", "false");
          data.set("background_removal", "none");
        } else {
          data.set("remove_background", "true");
          data.set("background_removal", segmentationProvider.value);
          data.set("segmentation_provider", segmentationProvider.value);
        }
        const response = await fetch("/v1/image-to-3d", { method: "POST", body: data });
        const payload = await readPayload(response);
        if (!response.ok) throw new Error(formatError(payload));
        const label = payload.segmented_object ? ` (${payload.segmented_object} 분리)` : "";
        showResult(`GLB 생성 완료${label}: <a href="${payload.download_url}" download>GLB 다운로드</a>`);
      } catch (error) {
        showError(error.message);
      } finally {
        setBusy(false, "");
      }
    });

    function setBusy(busy, text) {
      segmentButton.disabled = busy;
      submitButton.disabled = busy;
      statusBox.textContent = text;
    }
    function syncProviderOptions() {
      const stable = providerSelect.value === "local_stable_fast_3d";
      triposrOptions.classList.toggle("is-hidden", stable);
      sf3dOptions.classList.toggle("is-hidden", !stable);
      providerHelp.textContent = stable
        ? "Stability API 과금 없이 서버 GPU에서 로컬로 실행합니다. 최초 1회 설치가 필요합니다."
        : "기존 TripoSR 환경을 그대로 사용합니다.";
    }
    function syncSegmentationOptions() {
      const grounded = segmentationProvider.value === "grounded_sam2";
      yoloTarget.classList.toggle("is-hidden", grounded);
      groundedTarget.classList.toggle("is-hidden", !grounded);
      segmentationHelp.textContent = grounded
        ? "한글 객체명을 로컬 번역 모델로 영어로 바꾼 뒤, GroundingDINO 검출과 SAM2 마스크를 순서대로 실행합니다."
        : "정해진 가구 클래스를 빠르게 분리합니다.";
    }
    function validateSegmentationInput() {
      if (segmentationProvider.value === "grounded_sam2" && !objectQuery.value.trim()) {
        showError("GroundingDINO+SAM2를 사용할 때는 찾을 객체명을 입력하세요.");
        objectQuery.focus();
        return false;
      }
      return true;
    }
    function hideNotices() { resultBox.style.display = "none"; errorBox.style.display = "none"; }
    function showResult(html) { resultBox.innerHTML = html; resultBox.style.display = "block"; }
    function showError(message) { errorBox.textContent = message; errorBox.style.display = "block"; }
    function showEmpty() { previewImage.style.display = "none"; emptyState.style.display = "block"; }
    async function readPayload(response) {
      const type = response.headers.get("content-type") || "";
      return type.includes("application/json") ? response.json() : { detail: await response.text() };
    }
    function formatError(payload) { return typeof payload.detail === "string" ? payload.detail : JSON.stringify(payload.detail || payload); }
  </script>
</body>
</html>
"""
