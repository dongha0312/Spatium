import roomSceneConfig from "../../../../public/config/room-scene-config.json";
import { loadSceneConfig } from "../scene/sceneConfig";
import {
  canTransformObject,
  editableObjectLabel,
  shouldCheckFurnitureCollision,
  shouldConstrainToWalls,
  wallBoundaryPenetrationDidNotIncrease,
} from "../scene/collision";

// wallBoundaryPenetrationDidNotIncrease() reads its tolerance from scene
// config (wallConstraints.boundaryEpsilon), which is only populated after
// loadSceneConfig() resolves — mirror that startup step here with the real
// config file so the test exercises the actual tolerance value in production.
beforeAll(async () => {
  global.fetch = jest.fn().mockResolvedValue({
    ok: true,
    json: async () => roomSceneConfig,
  });
  await loadSceneConfig();
});

function makeFurniture({
  category = "chair",
  editable = true,
  ignoreWallConstraint = false,
  isDecorFigure = false,
  sourceIndex = 0,
} = {}) {
  return {
    userData: {
      editable,
      ignoreWallConstraint,
      isDecorFigure,
      sourceIndex,
      roomItem: { category },
    },
  };
}

describe("canTransformObject", () => {
  test("is transformable only when explicitly marked editable", () => {
    expect(canTransformObject(makeFurniture({ editable: true }))).toBe(true);
    expect(canTransformObject(makeFurniture({ editable: false }))).toBe(false);
  });

  test("treats a missing object as not transformable", () => {
    expect(canTransformObject(null)).toBe(false);
    expect(canTransformObject(undefined)).toBe(false);
  });
});

describe("shouldConstrainToWalls", () => {
  test("ordinary editable furniture is constrained to walls", () => {
    expect(shouldConstrainToWalls(makeFurniture({ category: "sofa" }))).toBe(true);
  });

  test("doors and windows are never wall-constrained", () => {
    expect(shouldConstrainToWalls(makeFurniture({ category: "door" }))).toBe(false);
    expect(shouldConstrainToWalls(makeFurniture({ category: "window" }))).toBe(false);
  });

  test("an object mid-drag with ignoreWallConstraint set is exempt", () => {
    expect(
      shouldConstrainToWalls(makeFurniture({ ignoreWallConstraint: true })),
    ).toBe(false);
  });

  test("decor figures placed on furniture surfaces are exempt", () => {
    expect(
      shouldConstrainToWalls(makeFurniture({ isDecorFigure: true })),
    ).toBe(false);
  });

  test("non-editable objects (e.g. the room shell) are exempt", () => {
    expect(shouldConstrainToWalls(makeFurniture({ editable: false }))).toBe(false);
  });
});

describe("shouldCheckFurnitureCollision", () => {
  test("unlike shouldConstrainToWalls, ignoreWallConstraint does not suppress collision highlighting", () => {
    const draggedObject = makeFurniture({ ignoreWallConstraint: true });

    expect(shouldConstrainToWalls(draggedObject)).toBe(false);
    expect(shouldCheckFurnitureCollision(draggedObject)).toBe(true);
  });

  test("doors, windows, and decor figures are still excluded", () => {
    expect(shouldCheckFurnitureCollision(makeFurniture({ category: "door" }))).toBe(false);
    expect(shouldCheckFurnitureCollision(makeFurniture({ category: "window" }))).toBe(false);
    expect(shouldCheckFurnitureCollision(makeFurniture({ isDecorFigure: true }))).toBe(false);
  });
});

describe("editableObjectLabel", () => {
  test("combines the category with a 1-based index for debug logs", () => {
    expect(editableObjectLabel(makeFurniture({ category: "chair", sourceIndex: 2 }))).toBe(
      "chair 3",
    );
  });

  test("falls back to a generic label when no category is set", () => {
    const object = makeFurniture({ sourceIndex: 0 });
    object.userData.roomItem.category = undefined;
    expect(editableObjectLabel(object)).toBe("object 1");
  });
});

describe("wallBoundaryPenetrationDidNotIncrease", () => {
  test("true when no wall is penetrated more deeply than before", () => {
    expect(wallBoundaryPenetrationDidNotIncrease([0, 0.02], [0, 0.01])).toBe(true);
  });

  test("false when any wall's penetration depth grows beyond tolerance", () => {
    expect(wallBoundaryPenetrationDidNotIncrease([0, 0], [0, 0.05])).toBe(false);
  });

  test("treats a wall with no prior recorded penetration as starting at 0", () => {
    expect(wallBoundaryPenetrationDidNotIncrease([], [0])).toBe(true);
    expect(wallBoundaryPenetrationDidNotIncrease([], [0.05])).toBe(false);
  });
});
