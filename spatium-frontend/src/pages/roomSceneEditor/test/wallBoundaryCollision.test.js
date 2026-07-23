import * as THREE from "three";
import { OBB } from "three/examples/jsm/math/OBB.js";
import roomSceneConfig from "../../../../public/config/room-scene-config.json";
import { loadSceneConfig } from "../scene/sceneConfig";
import {
  constrainedMovementBeforeWallCollision,
  objectOverlapsWallSpan,
  objectWallBoundaryPenetration,
  objectObbViolatesWallBoundary,
  projectionRadiusForObb,
  wallBlocksObjectObb,
} from "../scene/collision";

// These functions read boundaryEpsilon/boundarySpanPadding/sweepStep from
// scene config, same as collision.test.js — load the real config file so
// the geometry math below matches production tolerances exactly.
beforeAll(async () => {
  global.fetch = jest.fn().mockResolvedValue({
    ok: true,
    json: async () => roomSceneConfig,
  });
  await loadSceneConfig();
});

describe("projectionRadiusForObb", () => {
  test("an axis-aligned box's projection onto a principal axis is that axis's half-size", () => {
    const obb = new OBB(new THREE.Vector3(), new THREE.Vector3(1, 0.5, 2));

    expect(projectionRadiusForObb(obb, new THREE.Vector3(1, 0, 0))).toBeCloseTo(1);
    expect(projectionRadiusForObb(obb, new THREE.Vector3(0, 0, 1))).toBeCloseTo(2);
  });

  test("projecting onto a diagonal axis blends both half-sizes (SAT radius)", () => {
    const obb = new OBB(new THREE.Vector3(), new THREE.Vector3(1, 0.5, 2));
    const diagonal = new THREE.Vector3(1, 1, 0).normalize();

    // radius = |axis.x|*hx + |axis.y|*hy = (1/sqrt2)*1 + (1/sqrt2)*0.5
    expect(projectionRadiusForObb(obb, diagonal)).toBeCloseTo(1.5 / Math.SQRT2);
  });
});

// A wall whose inner (room-facing) surface sits at z = 0.25, thickness 0.1m,
// modelled the way wallColliders.js builds real walls: an OBB slab plus a
// roomFacingNormal/roomFacingProjection pair describing the boundary plane.
function makeBoundaryWall({ spanAxes = null } = {}) {
  return {
    object: { name: "TestWall" },
    obb: new OBB(new THREE.Vector3(0, 0, 0.3), new THREE.Vector3(2, 2, 0.05)),
    roomFacingNormal: new THREE.Vector3(0, 0, -1),
    roomFacingProjection: -0.25,
    spanAxes,
    spanPolygon: null,
  };
}

describe("objectObbViolatesWallBoundary / objectWallBoundaryPenetration", () => {
  const wall = makeBoundaryWall();

  test("furniture sitting clear of the wall does not violate the boundary", () => {
    const clearObb = new OBB(new THREE.Vector3(0, 0, 0), new THREE.Vector3(0.3, 0.3, 0.1));

    expect(objectObbViolatesWallBoundary(clearObb, wall)).toBe(false);
    expect(objectWallBoundaryPenetration(clearObb, wall)).toBe(0);
  });

  test("furniture pushed past the wall's inner face violates the boundary by the overlap depth", () => {
    const penetratingObb = new OBB(
      new THREE.Vector3(0, 0, 0.2),
      new THREE.Vector3(0.3, 0.3, 0.1),
    );

    expect(objectObbViolatesWallBoundary(penetratingObb, wall)).toBe(true);
    // boundary at 0.25, object's inner-most face reaches 0.2 + 0.1 = 0.3 -> 0.05 overlap
    expect(objectWallBoundaryPenetration(penetratingObb, wall)).toBeCloseTo(0.05);
  });
});

describe("objectOverlapsWallSpan", () => {
  const wall = {
    obb: new OBB(new THREE.Vector3(0, 0, 0), new THREE.Vector3(2, 1, 0.05)),
    spanAxes: [{ axis: new THREE.Vector3(1, 0, 0), halfSize: 2 }],
  };

  test("an object within the wall's horizontal span overlaps it", () => {
    const obb = new OBB(new THREE.Vector3(1, 0, 0), new THREE.Vector3(0.2, 0.2, 0.2));
    expect(objectOverlapsWallSpan(obb, wall)).toBe(true);
  });

  test("an object beyond the wall's span (e.g. past its end) does not overlap", () => {
    const obb = new OBB(new THREE.Vector3(5, 0, 0), new THREE.Vector3(0.2, 0.2, 0.2));
    expect(objectOverlapsWallSpan(obb, wall)).toBe(false);
  });

  test("a collider with no spanAxes (e.g. a door) has no horizontal limit", () => {
    const doorlike = { obb: wall.obb, spanAxes: null };
    const farObb = new OBB(new THREE.Vector3(500, 0, 0), new THREE.Vector3(0.2, 0.2, 0.2));
    expect(objectOverlapsWallSpan(farObb, doorlike)).toBe(true);
  });
});

describe("wallBlocksObjectObb for solid colliders (doors/windows without roomFacingNormal)", () => {
  const doorSlab = {
    obb: new OBB(new THREE.Vector3(0, 0, 1), new THREE.Vector3(0.5, 1, 0.05)),
    roomFacingNormal: null,
    roomFacingProjection: null,
    spanAxes: null,
  };

  test("blocks furniture that physically overlaps the slab", () => {
    const overlapping = new OBB(new THREE.Vector3(0, 0, 1), new THREE.Vector3(0.2, 0.2, 0.2));
    expect(wallBlocksObjectObb(overlapping, doorSlab)).toBe(true);
  });

  test("does not block furniture far from the slab", () => {
    const faraway = new OBB(new THREE.Vector3(0, 0, 5), new THREE.Vector3(0.2, 0.2, 0.2));
    expect(wallBlocksObjectObb(faraway, doorSlab)).toBe(false);
  });
});

describe("constrainedMovementBeforeWallCollision", () => {
  function makeFurnitureObject() {
    const object = new THREE.Object3D();
    object.userData.localObb = new OBB(
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(0.3, 0.3, 0.1),
    );
    return object;
  }

  test("clips a drag that would push furniture through a wall to stop at its boundary", () => {
    const object = makeFurnitureObject();
    const wall = makeBoundaryWall();
    const requestedMovement = new THREE.Vector3(0, 0, 0.3);

    const constrained = constrainedMovementBeforeWallCollision(
      object,
      requestedMovement,
      [wall],
    );

    // Violation threshold worked out from the wall geometry above is z > 0.15,
    // so the drag should be clipped well short of the full 0.3m requested.
    expect(constrained.z).toBeCloseTo(0.15, 2);
    expect(constrained.length()).toBeLessThan(requestedMovement.length());
    expect(object.userData.blockedWallColliders).toContain(wall);
  });

  test("does not clip movement that pulls furniture away from the wall", () => {
    const object = makeFurnitureObject();
    const wall = makeBoundaryWall();
    const requestedMovement = new THREE.Vector3(0, 0, -0.3);

    const constrained = constrainedMovementBeforeWallCollision(
      object,
      requestedMovement,
      [wall],
    );

    expect(constrained.z).toBeCloseTo(-0.3);
    expect(object.userData.blockedWallColliders).toHaveLength(0);
  });

  test("returns the full movement untouched when there are no wall colliders", () => {
    const object = makeFurnitureObject();
    const requestedMovement = new THREE.Vector3(1, 0, 1);

    const constrained = constrainedMovementBeforeWallCollision(object, requestedMovement, []);

    expect(constrained).toEqual(requestedMovement);
  });
});
