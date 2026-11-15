"use client"

import { motion, useScroll } from "framer-motion"
import { useEffect, useRef, useState } from "react"
import { Fireworks } from "@/components/fireworks"
import { PulsatingHeart } from "@/components/pulsating-heart"
import { ParallaxBackground } from "@/components/parallax-background"

export default function Home() {
  const containerRef = useRef<HTMLDivElement>(null)
  const { scrollYProgress } = useScroll({
    target: containerRef,
    offset: ["start start", "end end"],
  })

  const [showFireworks, setShowFireworks] = useState(true)

  useEffect(() => {
    const timer = setTimeout(() => {
      setShowFireworks(false)
    }, 4000)
    return () => clearTimeout(timer)
  }, [])

  const paragraphs = [
    "Привет. Меня зовут Некруз.\nЯ фронтенд-разработчик — работаю в частной компании, владельцем которой является друг моего отца. Сейчас учусь на первом курсе в Славянском университете на программиста, хотя, если честно, я уже давно им являюсь.",
    "Мой рост 173 см, но с 5 лет я тренируюсь — сначала шесть лет занимался самбо, потом перешёл в бокс. Сейчас я кандидат в мастера спорта по боксу. Так что если нужно — защитить смогу 🙂",
    "Я читаю намаз 5 раз в день, стараюсь жить правильно и с верой.\nТы — первая девушка, которой я написал сам. До этого у меня была только одна короткая история ещё в школе, и с тех пор я сосредоточился на себе, работе и развитии.",
    "Я не из тех, кто играет чувствами.\nНе обижу, не подведу и не дам никому обидеть.\nЯ не мешаю учебе или личным целям — наоборот, хочу, чтобы рядом со мной человек рос и чувствовал поддержку.",
    "Мне действительно понравился твой характер, даже если мы пока мало знакомы.\nЕсли ты дашь шанс — я сделаю всё, чтобы доказать, что достоин доверия.\nИ, ин ша Аллах, когда придёт время, я хотел бы, чтобы именно ты была в моём будущем.",
  ]

  return (
    <div ref={containerRef} className="relative min-h-screen overflow-hidden">
      {/* Animated gradient background */}
      <div className="fixed inset-0 bg-gradient-to-br from-[#0a0a0f] via-[#10101a] to-[#0a0a0f] noise-bg" />

      {/* Parallax background effect */}
      <ParallaxBackground />

      {/* Fireworks effect */}
      {showFireworks && <Fireworks />}

      {/* Glowing lines decoration */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <motion.div
          className="absolute top-0 left-1/4 w-px h-full bg-gradient-to-b from-transparent via-accent/30 to-transparent"
          animate={{
            opacity: [0.3, 0.6, 0.3],
            scaleY: [0.8, 1, 0.8],
          }}
          transition={{
            duration: 3,
            repeat: Number.POSITIVE_INFINITY,
            ease: "easeInOut",
          }}
        />
        <motion.div
          className="absolute top-0 right-1/3 w-px h-full bg-gradient-to-b from-transparent via-accent/20 to-transparent"
          animate={{
            opacity: [0.2, 0.5, 0.2],
            scaleY: [1, 0.8, 1],
          }}
          transition={{
            duration: 4,
            repeat: Number.POSITIVE_INFINITY,
            ease: "easeInOut",
            delay: 1,
          }}
        />
      </div>

      {/* Main content */}
      <div className="relative z-10 container mx-auto px-4 py-20 md:py-32">
        <div className="max-w-4xl mx-auto">
          {/* Hero section with name */}
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 1, delay: 0.5 }}
            className="mb-20 text-center"
          >
            <motion.div
              className="inline-block"
              whileHover={{ scale: 1.05 }}
              transition={{ type: "spring", stiffness: 300 }}
            >
              <h1 className="text-6xl md:text-8xl font-bold mb-6 neon-glow text-accent">
                <TypewriterText text="Sakina" delay={1000} />
              </h1>
            </motion.div>
            <motion.div
              initial={{ scaleX: 0 }}
              animate={{ scaleX: 1 }}
              transition={{ duration: 1, delay: 2 }}
              className="h-px w-64 mx-auto bg-gradient-to-r from-transparent via-accent to-transparent"
            />
          </motion.div>

          {/* Content paragraphs with scroll reveal */}
          <div className="space-y-12">
            {paragraphs.map((paragraph, index) => (
              <ScrollRevealParagraph key={index} text={paragraph} delay={index * 0.1} />
            ))}
          </div>

          {/* Signature */}
          <motion.div
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={{ duration: 1, delay: 0.5 }}
            className="mt-20 text-right"
          >
            <motion.p
              className="text-2xl md:text-3xl font-bold text-accent neon-glow inline-block"
              whileHover={{
                scale: 1.05,
                textShadow: [
                  "0 0 10px rgba(0, 217, 255, 0.8)",
                  "0 0 30px rgba(0, 217, 255, 1)",
                  "0 0 10px rgba(0, 217, 255, 0.8)",
                ],
              }}
              transition={{ duration: 0.3 }}
            >
              {"— Некруз ⚡️"}
            </motion.p>
          </motion.div>
        </div>
      </div>

      {/* Pulsating heart at bottom */}
      <PulsatingHeart />
    </div>
  )
}

// Typewriter effect component
function TypewriterText({ text, delay = 0 }: { text: string; delay?: number }) {
  const [displayText, setDisplayText] = useState("")
  const [currentIndex, setCurrentIndex] = useState(0)

  useEffect(() => {
    const startTimeout = setTimeout(() => {
      if (currentIndex < text.length) {
        const timeout = setTimeout(() => {
          setDisplayText((prev) => prev + text[currentIndex])
          setCurrentIndex((prev) => prev + 1)
        }, 100)
        return () => clearTimeout(timeout)
      }
    }, delay)
    return () => clearTimeout(startTimeout)
  }, [currentIndex, text, delay])

  return <span>{displayText}</span>
}

// Scroll reveal paragraph component
function ScrollRevealParagraph({ text, delay = 0 }: { text: string; delay?: number }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 50 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-100px" }}
      transition={{ duration: 0.8, delay }}
      className="relative"
    >
      <motion.div
        className="absolute -left-4 top-0 w-1 h-full bg-gradient-to-b from-accent/50 to-transparent rounded-full"
        initial={{ scaleY: 0 }}
        whileInView={{ scaleY: 1 }}
        viewport={{ once: true }}
        transition={{ duration: 0.8, delay: delay + 0.2 }}
      />
      <p className="text-lg md:text-xl leading-relaxed text-foreground/90 whitespace-pre-line pl-6">{text}</p>
    </motion.div>
  )
}
