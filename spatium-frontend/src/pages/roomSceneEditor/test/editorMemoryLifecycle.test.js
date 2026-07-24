import { render, waitFor } from "@testing-library/react";
import roomSceneConfig from "../../../../public/config/room-scene-config.json";
import RoomSceneEditorPage from "../RoomSceneEditorPage";
import {
  clearGltfModelCache,
  loadModelTemplates,
  loadUsdRoomModel,
} from "../scene/sceneLoaders";

const mockRendererInstances = [];
const mockSharedTextures = [];

function mockCreateRoomModel() {
  const THREE = jest.requireActual("three");
  const texture = new THREE.Texture();
  texture.dispose = jest.fn();
  mockSharedTextures.push(texture);

  const floorGeometry = new THREE.BufferGeometry();
  floorGeometry.setAttribute(
    "position",
    new THREE.BufferAttribute(
      new Float32Array([
        -2, 0, -1.5,
        2, 0, -1.5,
        2, 0, 1.5,
        -2, 0, -1.5,
        2, 0, 1.5,
        -2, 0, 1.5,
      ]),
      3,
    ),
  );
  const floorMaterial = new THREE.MeshStandardMaterial({ map: texture });
  floorMaterial.userData.spatiumSharedTextures = true;
  const floor = new THREE.Mesh(floorGeometry, floorMaterial);
  floor.name = "Floor";

  const room = new THREE.Group();
  room.add(floor);
  return room;
}

jest.mock("three", () => {
  const actualThree = jest.requireActual("three");

  class MockWebGLRenderer {
    constructor() {
      this.domElement = globalThis.document.createElement("canvas");
      this.shadowMap = { enabled: false };
      this.setSize = jest.fn();
      this.setPixelRatio = jest.fn();
      this.render = jest.fn();
      this.dispose = jest.fn();
      this.forceContextLoss = jest.fn();
      mockRendererInstances.push(this);
    }
  }

  return {
    ...actualThree,
    WebGLRenderer: MockWebGLRenderer,
  };
});

jest.mock("three/examples/jsm/controls/OrbitControls.js", () => {
  const { Vector3 } = jest.requireActual("three");

  return {
    OrbitControls: class MockOrbitControls {
      constructor() {
        this.target = new Vector3();
        this.enabled = true;
        this.enableDamping = false;
        this.enablePan = true;
        this.enableRotate = true;
        this.enableZoom = true;
        this.maxDistance = Infinity;
        this.maxPolarAngle = Math.PI;
        this.update = jest.fn();
        this.dispose = jest.fn();
      }
    },
  };
});

jest.mock("three/examples/jsm/renderers/CSS2DRenderer.js", () => {
  const { Object3D } = jest.requireActual("three");

  class MockCSS2DObject extends Object3D {
    constructor(element) {
      super();
      this.element = element;
      this.isCSS2DObject = true;
    }
  }

  class MockCSS2DRenderer {
    constructor() {
      this.domElement = globalThis.document.createElement("div");
      this.setSize = jest.fn();
      this.render = jest.fn();
    }
  }

  return {
    CSS2DObject: MockCSS2DObject,
    CSS2DRenderer: MockCSS2DRenderer,
  };
});

jest.mock("../scene/sceneLoaders", () => {
  const actualLoaders = jest.requireActual("../scene/sceneLoaders");

  return {
    ...actualLoaders,
    clearGltfModelCache: jest.fn(),
    loadModelTemplates: jest.fn(),
    loadUsdRoomModel: jest.fn(),
  };
});

describe("RoomSceneEditorPage WebGL memory lifecycle", () => {
  const originalFetch = global.fetch;
  const originalRequestAnimationFrame = global.requestAnimationFrame;
  const originalCancelAnimationFrame = global.cancelAnimationFrame;

  beforeEach(() => {
    mockRendererInstances.length = 0;
    mockSharedTextures.length = 0;
    clearGltfModelCache.mockClear();
    loadModelTemplates.mockImplementation(() => Promise.resolve(new Map()));
    loadUsdRoomModel.mockImplementation(() =>
      Promise.resolve(mockCreateRoomModel()),
    );
    loadUsdRoomModel.mockClear();

    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        ...roomSceneConfig,
        room: {
          modelUrl: "/test/room.usdz",
          metadataUrl: "/test/room.json",
        },
      }),
    });

    let nextFrameId = 0;
    global.requestAnimationFrame = jest.fn(() => {
      nextFrameId += 1;
      return nextFrameId;
    });
    global.cancelAnimationFrame = jest.fn();
  });

  afterEach(() => {
    global.fetch = originalFetch;
    global.requestAnimationFrame = originalRequestAnimationFrame;
    global.cancelAnimationFrame = originalCancelAnimationFrame;
    document.body.replaceChildren();
  });

  test("releases textures and the WebGL context on every repeated entry and exit", async () => {
    const repeatCount = 5;
    const onFloorColorLoaded = jest.fn();
    const roomScene = {
      metadata: {
        objects: [],
        doors: [],
        windows: [],
        openings: [],
      },
    };

    for (let index = 0; index < repeatCount; index += 1) {
      const mounted = render(
        <RoomSceneEditorPage
          roomScene={roomScene}
          onFloorColorLoaded={onFloorColorLoaded}
        />,
      );

      await waitFor(() => {
        expect(mockRendererInstances).toHaveLength(index + 1);
        expect(loadUsdRoomModel).toHaveBeenCalledTimes(index + 1);
        expect(onFloorColorLoaded).toHaveBeenCalledTimes(index + 1);
      });

      const renderer = mockRendererInstances[index];
      const sharedTexture = mockSharedTextures[index];

      expect(document.querySelectorAll("canvas")).toHaveLength(1);
      mounted.unmount();

      expect(sharedTexture.dispose).toHaveBeenCalledTimes(1);
      expect(renderer.dispose).toHaveBeenCalledTimes(1);
      expect(renderer.forceContextLoss).toHaveBeenCalledTimes(1);
      expect(renderer.domElement.width).toBe(1);
      expect(renderer.domElement.height).toBe(1);
      expect(document.querySelectorAll("canvas")).toHaveLength(0);
    }

    expect(loadUsdRoomModel).toHaveBeenCalledTimes(repeatCount);
    expect(clearGltfModelCache).toHaveBeenCalledTimes(repeatCount);
    expect(global.cancelAnimationFrame).toHaveBeenCalledTimes(repeatCount);
  });
});
