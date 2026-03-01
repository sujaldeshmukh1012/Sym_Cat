import { Canvas } from "@react-three/fiber";
import { OrbitControls, Environment, ContactShadows } from "@react-three/drei";
import Excavator from "./Excavator";

interface HangarSceneProps {
  onDoorClick: () => void;
}

const HangarScene = ({ onDoorClick }: HangarSceneProps) => {
  return (
    <div className="w-full h-screen">
      <Canvas
        camera={{ position: [5, 3, 6], fov: 45 }}
        gl={{ antialias: true, toneMapping: 3 }}
        dpr={[1, 2]}
      >
        {/* Lighting */}
        <ambientLight intensity={0.15} color="#4466aa" />
        <directionalLight position={[5, 8, 5]} intensity={1.2} color="#ffffff" castShadow />
        <pointLight position={[-3, 4, 2]} intensity={0.8} color="#FFCD00" distance={15} />
        <pointLight position={[3, 2, -3]} intensity={0.4} color="#FFCD00" distance={12} />
        <spotLight
          position={[0, 8, 0]}
          angle={0.5}
          penumbra={0.8}
          intensity={1.5}
          color="#ffffff"
          castShadow
        />

        {/* Grid floor */}
        <gridHelper args={[30, 30, "#333333", "#222222"]} position={[0, -1.5, 0]} />

        {/* Contact shadows for grounding */}
        <ContactShadows
          position={[0, -1.49, 0]}
          opacity={0.6}
          scale={15}
          blur={2}
          far={5}
          color="#000000"
        />

        {/* The excavator */}
        <Excavator onDoorClick={onDoorClick} />

        {/* Controls */}
        <OrbitControls
          enablePan={false}
          enableZoom={true}
          minDistance={4}
          maxDistance={12}
          minPolarAngle={Math.PI / 6}
          maxPolarAngle={Math.PI / 2.2}
          autoRotate
          autoRotateSpeed={0.3}
        />

        <Environment preset="warehouse" />
      </Canvas>
    </div>
  );
};

export default HangarScene;
