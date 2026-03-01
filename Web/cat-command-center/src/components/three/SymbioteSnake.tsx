import { useRef, useMemo } from "react";
import { useFrame } from "@react-three/fiber";
import * as THREE from "three";

const catYellow = "#FFCD00";
const machineBlack = "#191919";

interface SymbioteSnakeProps {
  /** 0 → idle crawl, 1 → lunge toward camera */
  lungeProgress?: number;
}

/**
 * 3D spline-based "Symbiote Snake" that crawls along a CatmullRomCurve3
 * path around the excavator. Gold & black stripe segments.
 */
const SymbioteSnake = ({ lungeProgress = 0 }: SymbioteSnakeProps) => {
  const groupRef = useRef<THREE.Group>(null);
  const segmentsRef = useRef<THREE.Mesh[]>([]);

  // CatmullRomCurve3 path that wraps around the crane
  const { curve, lungeCurve } = useMemo(() => {
    const points = [
      new THREE.Vector3(-1.5, -0.5, 2.0),   // behind left track
      new THREE.Vector3(-1.2, 0.0, 1.0),     // up the left side
      new THREE.Vector3(-0.5, 0.6, 0.5),     // onto the body
      new THREE.Vector3(0.0, 0.9, 0.0),      // across the top
      new THREE.Vector3(0.5, 1.2, 0.8),      // toward cabin
      new THREE.Vector3(0.0, 1.6, 1.2),      // base of boom
      new THREE.Vector3(0.0, 2.2, 1.4),      // up the boom arm
      new THREE.Vector3(0.0, 3.0, 1.6),      // mid-boom
      new THREE.Vector3(0.1, 3.8, 1.2),      // elbow of stick
      new THREE.Vector3(0.2, 4.2, 0.6),      // upper stick
      new THREE.Vector3(0.0, 3.5, -0.2),     // curling back
      new THREE.Vector3(-0.3, 2.5, -0.8),    // down the back
      new THREE.Vector3(-0.5, 1.2, -1.0),    // down to engine
      new THREE.Vector3(-1.0, 0.2, -0.5),    // low rear
      new THREE.Vector3(-1.5, -0.5, 2.0),    // loop back to start
    ];
    const c = new THREE.CatmullRomCurve3(points, true, "catmullrom", 0.5);

    // Lunge curve — snake flies toward the camera
    const lungePoints = [
      new THREE.Vector3(0.0, 1.6, 1.2),
      new THREE.Vector3(0.0, 1.4, 2.5),
      new THREE.Vector3(0.0, 0.8, 4.0),
      new THREE.Vector3(0.0, 0.2, 6.0),
      new THREE.Vector3(0.0, 0.0, 9.0),
    ];
    const lc = new THREE.CatmullRomCurve3(lungePoints, false, "catmullrom", 0.5);

    return { curve: c, lungeCurve: lc };
  }, []);

  const SEGMENT_COUNT = 48;
  const SEGMENT_SPACING = 0.012; // fraction of curve per segment

  // Create segment refs lazily
  const setSegmentRef = (index: number) => (el: THREE.Mesh | null) => {
    if (el) segmentsRef.current[index] = el;
  };

  useFrame(({ clock }) => {
    const t = clock.getElapsedTime();
    const speed = 0.04; // crawl speed (fraction of path per second)

    for (let i = 0; i < SEGMENT_COUNT; i++) {
      const mesh = segmentsRef.current[i];
      if (!mesh) continue;

      if (lungeProgress > 0) {
        // Lunge animation — segments stream toward camera
        const frac = ((i / SEGMENT_COUNT) + lungeProgress * 1.5) % 1;
        const pos = lungeCurve.getPoint(Math.min(frac, 1));
        mesh.position.copy(pos);

        // scale down as they lunge
        const s = Math.max(0.2, 1 - frac * 0.6);
        mesh.scale.setScalar(s);

        // look along lunge direction
        const tangent = lungeCurve.getTangent(Math.min(frac, 0.99));
        const lookTarget = pos.clone().add(tangent);
        mesh.lookAt(lookTarget);
      } else {
        // Normal crawl
        const frac = ((t * speed) + (i * SEGMENT_SPACING)) % 1;
        const pos = curve.getPoint(frac);
        mesh.position.copy(pos);
        mesh.scale.setScalar(1);

        // Orient along curve
        const tangent = curve.getTangent(frac);
        const lookTarget = pos.clone().add(tangent);
        mesh.lookAt(lookTarget);

        // Subtle sine wave body undulation
        const wave = Math.sin(t * 3 + i * 0.4) * 0.03;
        mesh.position.y += wave;
      }
    }
  });

  // Head geometry (slightly larger, more golden)
  const headSize = 0.12;
  // Body taper
  const bodySize = (i: number) => {
    const mid = SEGMENT_COUNT / 2;
    const distFromHead = i;
    const taper = 1 - Math.abs(distFromHead - mid * 0.3) / (SEGMENT_COUNT * 0.8);
    return Math.max(0.03, headSize * 0.7 * Math.max(0.3, taper));
  };

  return (
    <group ref={groupRef}>
      {Array.from({ length: SEGMENT_COUNT }).map((_, i) => {
        const isHead = i < 3;
        const isGold = i % 4 < 2; // alternating gold/black stripe pattern
        const size = i === 0 ? headSize : bodySize(i);

        return (
          <mesh key={i} ref={setSegmentRef(i)}>
            <sphereGeometry args={[size, 8, 6]} />
            <meshStandardMaterial
              color={isHead ? catYellow : isGold ? catYellow : machineBlack}
              roughness={isHead ? 0.2 : 0.4}
              metalness={isHead ? 0.8 : 0.5}
              emissive={isHead ? catYellow : isGold ? "#996600" : "#000000"}
              emissiveIntensity={isHead ? 0.3 : 0.05}
            />
          </mesh>
        );
      })}

      {/* Snake eye glow */}
      <pointLight
        color={catYellow}
        intensity={0.5}
        distance={2}
        ref={(light) => {
          if (light && segmentsRef.current[0]) {
            // Will be positioned in useFrame via parent
          }
        }}
      />
    </group>
  );
};

export default SymbioteSnake;
