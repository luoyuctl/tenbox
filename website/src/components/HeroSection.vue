<template>
  <section class="hero">
    <div class="hero-bg">
      <div class="hero-glow hero-glow-1"></div>
      <div class="hero-glow hero-glow-2"></div>
    </div>
    <div class="container hero-content">
      <div class="hero-text">
        <h1 class="hero-title">{{ $t('hero.title') }}</h1>
        <p class="hero-subtitle">
          <span class="typewriter-text">{{ displayText }}</span>
          <span class="typewriter-cursor">|</span>
        </p>
        <p class="hero-desc">{{ $t('hero.description') }}</p>
        <div class="hero-actions">
          <a :href="downloadUrl" class="btn btn-large btn-hero hero-cta">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M0 3.5L9.75 2v9.4H0V3.5zm0 17l9.75 1.5v-9.4H0v7.9zm10.85 1.65L24 24V12.6H10.85v9.55zM10.85 2v9.4H24V0L10.85 2z"/>
            </svg>
            <span>{{ $t('hero.cta_win') }}</span>
          </a>
          <a v-if="downloadUrlMac" :href="downloadUrlMac" class="btn btn-large btn-hero-secondary hero-cta">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
            </svg>
            <span>{{ $t('hero.cta_mac') }}</span>
          </a>
          <a href="#install" class="btn btn-large btn-hero-secondary hero-cta">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M12.5 2c-.55 0-1.05.4-1.4.9-.35.5-.6 1.2-.6 1.95 0 .35.05.65.13.95-.4.25-.78.6-1.13 1-.55-.13-1.05-.13-1.45 0-.55.18-1 .55-1.3 1-.6.9-.65 2.05-.5 3.05.18 1.05.55 2.05 1 2.95-.5.85-.95 1.75-1.25 2.65-.3.95-.45 1.95-.2 2.85.13.45.35.85.7 1.15.4.35.95.55 1.55.55h7.5c.6 0 1.15-.2 1.55-.55.35-.3.55-.7.7-1.15.25-.9.1-1.9-.2-2.85-.3-.9-.75-1.8-1.25-2.65.45-.9.85-1.9 1-2.95.13-1 .1-2.15-.5-3.05-.3-.45-.75-.85-1.3-1-.4-.13-.9-.13-1.45 0-.35-.4-.73-.75-1.13-1 .08-.3.13-.6.13-.95 0-.75-.25-1.45-.6-1.95-.35-.5-.85-.9-1.4-.9zm0 1.5c.15 0 .35.13.55.45.2.3.35.75.35 1.2 0 .25-.05.5-.1.7-.27-.05-.55-.1-.8-.1s-.53.05-.8.1c-.05-.2-.1-.45-.1-.7 0-.45.15-.9.35-1.2.2-.32.4-.45.55-.45z"/>
            </svg>
            <span>{{ $t('hero.cta_linux') }}</span>
          </a>
        </div>
        <div class="hero-foot">
          <p class="hero-meta">v{{ latestVersion }} · {{ $t('hero.requirements') }}</p>
          <p class="hero-qq">{{ $t('hero.qq_group') }}：{{ $t('hero.qq_group_number') }}</p>
        </div>
      </div>
      <div class="hero-image">
        <div class="hero-image-frame">
          <img src="/images/screenshot.png" :alt="$t('hero.title')" />
        </div>
      </div>
    </div>
  </section>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'

/* global __APP_VERSION__, __APP_DOWNLOAD_URL__, __APP_DOWNLOAD_URL_MAC__ */
import { useI18n } from 'vue-i18n'

const { tm, locale } = useI18n()

const downloadUrl = __APP_DOWNLOAD_URL__
const downloadUrlMac = __APP_DOWNLOAD_URL_MAC__
const latestVersion = __APP_VERSION__

const displayText = ref('')
let timerId = null
let taglineIndex = 0
let charIndex = 0
let phase = 'typing'

const TYPING_SPEED = 80
const DELETING_SPEED = 40
const PAUSE_AFTER_TYPING = 2000
const PAUSE_AFTER_DELETING = 500

function getTaglines() {
  return tm('hero.taglines') || []
}

function tick() {
  const taglines = getTaglines()
  if (!taglines.length) return

  const current = taglines[taglineIndex % taglines.length]

  if (phase === 'typing') {
    charIndex++
    displayText.value = current.slice(0, charIndex)
    if (charIndex >= current.length) {
      phase = 'pausing'
      timerId = setTimeout(tick, PAUSE_AFTER_TYPING)
      return
    }
    timerId = setTimeout(tick, TYPING_SPEED)
  } else if (phase === 'pausing') {
    phase = 'deleting'
    timerId = setTimeout(tick, DELETING_SPEED)
  } else if (phase === 'deleting') {
    charIndex--
    displayText.value = current.slice(0, charIndex)
    if (charIndex <= 0) {
      phase = 'waiting'
      timerId = setTimeout(tick, PAUSE_AFTER_DELETING)
      return
    }
    timerId = setTimeout(tick, DELETING_SPEED)
  } else if (phase === 'waiting') {
    taglineIndex = (taglineIndex + 1) % taglines.length
    charIndex = 0
    phase = 'typing'
    timerId = setTimeout(tick, TYPING_SPEED)
  }
}

function reset() {
  if (timerId) clearTimeout(timerId)
  taglineIndex = 0
  charIndex = 0
  phase = 'typing'
  displayText.value = ''
  timerId = setTimeout(tick, TYPING_SPEED)
}

onMounted(() => {
  reset()
})

onUnmounted(() => {
  if (timerId) clearTimeout(timerId)
})

watch(locale, () => {
  reset()
})
</script>

<style scoped>
.hero {
  position: relative;
  min-height: 100vh;
  display: flex;
  align-items: center;
  overflow: hidden;
  background: linear-gradient(180deg, #f8fafc 0%, #ffffff 60%, #ffffff 100%);
}

.hero-bg {
  position: absolute;
  inset: 0;
  overflow: hidden;
  pointer-events: none;
}

.hero-glow {
  position: absolute;
  border-radius: 50%;
  filter: blur(110px);
  opacity: 0.18;
}

.hero-glow-1 {
  width: 600px;
  height: 600px;
  background: var(--color-primary);
  top: -220px;
  right: -120px;
}

.hero-glow-2 {
  width: 420px;
  height: 420px;
  background: var(--color-accent);
  bottom: -120px;
  left: -120px;
}

.hero-content {
  position: relative;
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 64px;
  align-items: center;
  padding-top: calc(var(--nav-height) + 48px);
  padding-bottom: 80px;
}

.hero-text {
  color: var(--color-text);
  max-width: 560px;
}

.hero-title {
  font-size: 4rem;
  font-weight: 800;
  line-height: 1.05;
  margin-bottom: 12px;
  letter-spacing: -0.02em;
  color: var(--color-text);
}

.hero-subtitle {
  font-size: 1.4rem;
  font-weight: 500;
  color: var(--color-primary);
  margin-bottom: 28px;
  font-family: var(--font-mono);
  min-height: 1.8em;
  line-height: 1.4;
}

.typewriter-cursor {
  display: inline-block;
  margin-left: 2px;
  animation: blink 0.7s step-end infinite;
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}

.hero-desc {
  font-size: 1.125rem;
  line-height: 1.7;
  color: var(--color-text-light);
  margin-bottom: 36px;
}

.hero-actions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.hero-cta {
  min-width: 168px;
  justify-content: center;
}

.hero-foot {
  margin-top: 28px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.hero-meta {
  font-size: 0.85rem;
  color: #94a3b8;
}

.hero-qq {
  font-size: 0.85rem;
  color: #0e7490;
}

.hero-image {
  display: flex;
  justify-content: center;
  align-items: center;
}

.hero-image-frame {
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 24px 80px rgba(15, 23, 42, 0.12),
    0 0 0 1px rgba(15, 23, 42, 0.06);
  transition: transform 0.3s ease;
  background: #fff;
}

.hero-image-frame:hover {
  transform: translateY(-4px);
}

.hero-image-frame img {
  width: 100%;
  display: block;
}

@media (max-width: 1024px) {
  .hero-content {
    grid-template-columns: 1fr;
    text-align: center;
    gap: 48px;
  }

  .hero-text {
    max-width: 640px;
    margin: 0 auto;
  }

  .hero-title {
    font-size: 3rem;
  }

  .hero-actions {
    justify-content: center;
  }

  .hero-foot {
    align-items: center;
  }
}

@media (max-width: 768px) {
  .hero {
    min-height: auto;
    padding-top: 0;
  }

  .hero-content {
    padding-top: calc(var(--nav-height) + 32px);
    padding-bottom: 56px;
    gap: 36px;
  }

  .hero-title {
    font-size: 2.5rem;
  }

  .hero-subtitle {
    font-size: 1.1rem;
  }

  .hero-desc {
    font-size: 1rem;
  }

  .hero-cta {
    min-width: 0;
    flex: 1 1 calc(50% - 6px);
  }
}
</style>
