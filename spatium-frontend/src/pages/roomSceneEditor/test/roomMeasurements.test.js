import * as THREE from "three";
import {
  calculateRoomMeasurements,
  framingBoundsFromMeasurements,
} from "../scene/roomMeasurements";

// Builds a flat rectangular floor (two triangles, XZ plane at y=0) named so
// isUsdFloorMesh() recognizes it, matching how scanned USD rooms are shaped.
function makeFloorMesh({ width, depth, name = "Floor" }) {
  const halfWidth = width / 2;
  const halfDepth = depth / 2;
  const v0 = [-halfWidth, 0, -halfDepth];
  const v1 = [halfWidth, 0, -halfDepth];
  const v2 = [halfWidth, 0, halfDepth];
  const v3 = [-halfWidth, 0, halfDepth];

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute(
    "position",
    new THREE.BufferAttribute(
      new Float32Array([...v0, ...v1, ...v2, ...v0, ...v2, ...v3]),
      3,
    ),
  );

  const mesh = new THREE.Mesh(geometry);
  mesh.name = name;
  return mesh;
}

function makeWallMesh({ height }) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(0.1, height, 0.1));
  mesh.name = "Wall";
  mesh.position.set(0, height / 2, 0);
  return mesh;
}

function makeRoomModel({ width, depth, wallHeight }) {
  const group = new THREE.Group();
  group.add(makeFloorMesh({ width, depth }));
  group.add(makeWallMesh({ height: wallHeight }));
  return group;
}

describe("calculateRoomMeasurements", () => {
  test("returns null when there is no room model", () => {
    expect(calculateRoomMeasurements(null)).toBeNull();
  });

  test("derives width/depth/area from the floor mesh, not the raw bounding box", () => {
    const roomModel = makeRoomModel({ width: 4, depth: 3, wallHeight: 2.4 });

    const measurements = calculateRoomMeasurements(roomModel);

    expect(measurements.areaSource).toBe("floor");
    expect(measurements.width).toBeCloseTo(4);
    expect(measurements.depth).toBeCloseTo(3);
    expect(measurements.area).toBeCloseTo(12); // 4 * 3
    expect(measurements.height).toBeCloseTo(2.4); // from the wall box, not the floor
  });

  test("outline segments trace only the floor's outer boundary, not the shared diagonal", () => {
    const roomModel = makeRoomModel({ width: 4, depth: 3, wallHeight: 2.4 });

    const { outlineSegments } = calculateRoomMeasurements(roomModel);

    // A quad split into two triangles has 5 edges total; the shared diagonal
    // is used by both triangles (count 2) and must be excluded, leaving the
    // 4 outer edges whose lengths sum to the rectangle's perimeter.
    expect(outlineSegments).toHaveLength(4);
    const perimeter = outlineSegments.reduce((sum, s) => sum + s.length, 0);
    expect(perimeter).toBeCloseTo(2 * (4 + 3));
  });

  test("falls back to the raw bounding box when no floor mesh is present", () => {
    const group = new THREE.Group();
    const wall = new THREE.Mesh(new THREE.BoxGeometry(4, 2.4, 3));
    wall.name = "SomethingElse";
    group.add(wall);

    const measurements = calculateRoomMeasurements(group);

    expect(measurements.areaSource).toBe("bounds");
    expect(measurements.width).toBeCloseTo(4);
    expect(measurements.depth).toBeCloseTo(3);
  });
});

describe("framingBoundsFromMeasurements", () => {
  const baseMeasurements = {
    areaSource: "floor",
    width: 4,
    depth: 3,
    height: 2.4,
    center: { x: 1, y: 0, z: -1 },
  };

  test("returns null when the source wasn't a floor mesh", () => {
    expect(
      framingBoundsFromMeasurements({ ...baseMeasurements, areaSource: "bounds" }),
    ).toBeNull();
  });

  test("returns null for a degenerate (zero-area) room", () => {
    expect(
      framingBoundsFromMeasurements({ ...baseMeasurements, width: 0 }),
    ).toBeNull();
  });

  test("builds a box centered on the room using width/depth, clamping height", () => {
    const box = framingBoundsFromMeasurements(baseMeasurements);

    expect(box.min.x).toBeCloseTo(1 - 4 / 2);
    expect(box.max.x).toBeCloseTo(1 + 4 / 2);
    expect(box.min.z).toBeCloseTo(-1 - 3 / 2);
    expect(box.max.z).toBeCloseTo(-1 + 3 / 2);
    expect(box.max.y - box.min.y).toBeCloseTo(2.4);
  });

  test("clamps unrealistic scan heights into the sane framing range", () => {
    const tooTall = framingBoundsFromMeasurements({
      ...baseMeasurements,
      height: 500, // e.g. an outlier vertex from a scan artifact
    });
    const tooShort = framingBoundsFromMeasurements({
      ...baseMeasurements,
      height: 0.1,
    });

    expect(tooTall.max.y - tooTall.min.y).toBeCloseTo(8); // FRAMING_MAX_HEIGHT
    expect(tooShort.max.y - tooShort.min.y).toBeCloseTo(2); // FRAMING_MIN_HEIGHT
  });
});
