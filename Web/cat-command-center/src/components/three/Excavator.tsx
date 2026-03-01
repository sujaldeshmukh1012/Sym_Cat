import { useRef, useState } from "react";
import { useFrame } from "@react-three/fiber";
import { Html } from "@react-three/drei";
import * as THREE from "three";

const catYellow = "#FFCD00";
const machineBlack = "#191919";
const darkGray = "#2a2a2a";

interface ExcavatorProps {
  onDoorClick: () => void;
}

const Excavator = ({ onDoorClick }: ExcavatorProps) => {
  const boomRef = useRef<THREE.Group>(null);
  const pistonRef = useRef<THREE.Mesh>(null);
  const [doorHovered, setDoorHovered] = useState(false);
  const markerRef = useRef<THREE.Group>(null);

  useFrame(({ clock }) => {
    const t = clock.getElapsedTime();
    // Breathing animation on boom
    if (boomRef.current) {
      boomRef.current.rotation.z = Math.sin(t * 0.8) * 0.02 - 0.3;
    }
    // Piston movement
    if (pistonRef.current) {
      pistonRef.current.position.y = 1.2 + Math.sin(t * 0.8) * 0.05;
    }
    // Marker float
    if (markerRef.current) {
      markerRef.current.position.y = 2.8 + Math.sin(t * 2) * 0.1;
    }
  });

  return (
    <group position={[0, -1.5, 0]}>
      {/* Tracks / Undercarriage */}
      <group position={[0, 0, 0]}>
        {/* Left track */}
        <mesh position={[-1.2, 0.2, 0]}>
          <boxGeometry args={[0.5, 0.4, 3.5]} />
          <meshStandardMaterial color={machineBlack} roughness={0.8} />
        </mesh>
        {/* Right track */}
        <mesh position={[1.2, 0.2, 0]}>
          <boxGeometry args={[0.5, 0.4, 3.5]} />
          <meshStandardMaterial color={machineBlack} roughness={0.8} />
        </mesh>
        {/* Track frame */}
        <mesh position={[0, 0.3, 0]}>
          <boxGeometry args={[2.4, 0.3, 3]} />
          <meshStandardMaterial color={darkGray} roughness={0.7} />
        </mesh>
        {/* Track wheels */}
        {[-1.2, 1.2].map((x) =>
          [-1.2, -0.4, 0.4, 1.2].map((z, i) => (
            <mesh key={`wheel-${x}-${i}`} position={[x, 0.2, z]} rotation={[0, 0, Math.PI / 2]}>
              <cylinderGeometry args={[0.2, 0.2, 0.55, 8]} />
              <meshStandardMaterial color={darkGray} roughness={0.6} metalness={0.3} />
            </mesh>
          ))
        )}
      </group>

      {/* Main body / Upper structure */}
      <group position={[0, 0.9, -0.2]}>
        <mesh>
          <boxGeometry args={[2.2, 1, 2.5]} />
          <meshStandardMaterial color={catYellow} roughness={0.3} metalness={0.6} />
        </mesh>
        {/* Engine compartment rear */}
        <mesh position={[0, 0.1, -0.8]}>
          <boxGeometry args={[2, 0.8, 1]} />
          <meshStandardMaterial color={catYellow} roughness={0.35} metalness={0.5} />
        </mesh>
        {/* Exhaust stack */}
        <mesh position={[0.6, 0.8, -0.8]} rotation={[0, 0, 0]}>
          <cylinderGeometry args={[0.08, 0.1, 0.6, 8]} />
          <meshStandardMaterial color={machineBlack} roughness={0.5} metalness={0.4} />
        </mesh>
      </group>

      {/* Cabin */}
      <group position={[-0.2, 1.9, 0.4]}>
        {/* Cabin frame */}
        <mesh>
          <boxGeometry args={[1.4, 1, 1.2]} />
          <meshStandardMaterial color={catYellow} roughness={0.3} metalness={0.6} />
        </mesh>
        {/* Cabin windows (dark glass) */}
        <mesh position={[0, 0.1, 0.61]}>
          <boxGeometry args={[1.1, 0.7, 0.02]} />
          <meshStandardMaterial color="#1a3040" roughness={0.1} metalness={0.8} transparent opacity={0.7} />
        </mesh>
        {/* Side window */}
        <mesh position={[0.71, 0.1, 0]}>
          <boxGeometry args={[0.02, 0.7, 0.9]} />
          <meshStandardMaterial color="#1a3040" roughness={0.1} metalness={0.8} transparent opacity={0.7} />
        </mesh>

        {/* CABIN DOOR - Interactive */}
        <mesh
          position={[0.72, -0.05, 0]}
          onPointerOver={(e) => {
            e.stopPropagation();
            setDoorHovered(true);
            document.body.style.cursor = "crosshair";
          }}
          onPointerOut={() => {
            setDoorHovered(false);
            document.body.style.cursor = "default";
          }}
          onClick={(e) => {
            e.stopPropagation();
            document.body.style.cursor = "default";
            onDoorClick();
          }}
        >
          <boxGeometry args={[0.05, 0.95, 1.15]} />
          <meshStandardMaterial
            color={doorHovered ? "#FFE066" : catYellow}
            roughness={0.2}
            metalness={0.7}
            emissive={doorHovered ? catYellow : "#000000"}
            emissiveIntensity={doorHovered ? 0.4 : 0}
          />
        </mesh>

        {/* Door handle */}
        <mesh position={[0.78, -0.05, -0.3]}>
          <boxGeometry args={[0.04, 0.06, 0.15]} />
          <meshStandardMaterial color={machineBlack} roughness={0.4} metalness={0.6} />
        </mesh>
      </group>

      {/* INSPECT marker */}
      <group ref={markerRef} position={[1.2, 2.8, 0.4]}>
        <Html center distanceFactor={8}>
          <div className="animate-pulse-glow px-3 py-1.5 rounded font-hud text-xs tracking-widest bg-primary/20 border border-primary/50 text-primary whitespace-nowrap select-none pointer-events-none">
            ▸ INSPECT
          </div>
        </Html>
      </group>

      {/* Boom arm */}
      <group ref={boomRef} position={[0, 1.6, 1.2]} rotation={[0, 0, -0.3]}>
        {/* Main boom */}
        <mesh position={[0, 1.2, 0]}>
          <boxGeometry args={[0.35, 2.5, 0.3]} />
          <meshStandardMaterial color={catYellow} roughness={0.3} metalness={0.6} />
        </mesh>
        {/* Hydraulic piston */}
        <mesh ref={pistonRef} position={[0.25, 1.2, 0]}>
          <cylinderGeometry args={[0.06, 0.06, 1.8, 8]} />
          <meshStandardMaterial color="#888888" roughness={0.2} metalness={0.8} />
        </mesh>
        {/* Arm (stick) */}
        <group position={[0, 2.4, 0]} rotation={[0, 0, 0.6]}>
          <mesh position={[0, 0.8, 0]}>
            <boxGeometry args={[0.28, 1.8, 0.25]} />
            <meshStandardMaterial color={catYellow} roughness={0.3} metalness={0.6} />
          </mesh>
          {/* Bucket */}
          <group position={[0, 1.7, 0]} rotation={[0, 0, 0.4]}>
            <mesh>
              <boxGeometry args={[0.6, 0.4, 0.5]} />
              <meshStandardMaterial color={machineBlack} roughness={0.6} metalness={0.3} />
            </mesh>
            {/* Bucket teeth */}
            {[-0.2, 0, 0.2].map((z, i) => (
              <mesh key={`tooth-${i}`} position={[0.3, -0.1, z]}>
                <boxGeometry args={[0.12, 0.08, 0.08]} />
                <meshStandardMaterial color="#666666" roughness={0.4} metalness={0.5} />
              </mesh>
            ))}
          </group>
        </group>
        {/* Pivot joint */}
        <mesh position={[0, 0, 0]} rotation={[Math.PI / 2, 0, 0]}>
          <cylinderGeometry args={[0.12, 0.12, 0.45, 12]} />
          <meshStandardMaterial color={darkGray} roughness={0.4} metalness={0.6} />
        </mesh>
      </group>

      {/* Counterweight */}
      <mesh position={[0, 0.9, -1.5]}>
        <boxGeometry args={[1.8, 0.6, 0.5]} />
        <meshStandardMaterial color={machineBlack} roughness={0.7} metalness={0.3} />
      </mesh>
    </group>
  );
};

export default Excavator;
