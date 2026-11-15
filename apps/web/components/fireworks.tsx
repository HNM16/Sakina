"use client"

import { motion } from "framer-motion"
import { useEffect, useState } from "react"

interface Particle {
  id: number
  x: number
  y: number
  color: string
}

export function Fireworks() {
  const [particles, setParticles] = useState<Particle[]>([])

  useEffect(() => {
    const colors = ["#00d9ff", "#00ffaa", "#ff00ff", "#ffaa00"]
    const newParticles: Particle[] = []

    // Create multiple bursts
    for (let burst = 0; burst < 3; burst++) {
      const burstX = 20 + Math.random() * 60
      const burstY = 20 + Math.random() * 40

      for (let i = 0; i < 30; i++) {
        newParticles.push({
          id: burst * 30 + i,
          x: burstX,
          y: burstY,
          color: colors[Math.floor(Math.random() * colors.length)],
        })
      }
    }

    setParticles(newParticles)
  }, [])

  return (
    <div className="fixed inset-0 pointer-events-none z-50">
      {particles.map((particle, index) => {
        const angle = (index % 30) * (360 / 30)
        const distance = 100 + Math.random() * 200
        const duration = 1 + Math.random() * 0.5

        return (
          <motion.div
            key={particle.id}
            className="absolute w-2 h-2 rounded-full"
            style={{
              left: `${particle.x}%`,
              top: `${particle.y}%`,
              backgroundColor: particle.color,
              boxShadow: `0 0 10px ${particle.color}`,
            }}
            initial={{ scale: 0, opacity: 1 }}
            animate={{
              x: Math.cos((angle * Math.PI) / 180) * distance,
              y: Math.sin((angle * Math.PI) / 180) * distance,
              scale: [0, 1, 0],
              opacity: [1, 1, 0],
            }}
            transition={{
              duration,
              delay: Math.floor(index / 30) * 0.5,
              ease: "easeOut",
            }}
          />
        )
      })}
    </div>
  )
}
