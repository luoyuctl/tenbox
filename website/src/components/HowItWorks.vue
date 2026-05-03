<template>
  <section class="howitworks" id="howitworks">
    <div class="container">
      <h2 class="section-title">{{ $t('howitworks.title') }}</h2>
      <div class="steps">
        <div v-for="(step, idx) in steps" :key="step.key" class="step">
          <div class="step-number">{{ idx + 1 }}</div>
          <div class="step-content">
            <h3 class="step-title">{{ $t(`howitworks.${step.key}.title`) }}</h3>
            <p class="step-desc">{{ $t(`howitworks.${step.key}.desc`) }}</p>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<script setup>
const steps = [
  { key: 'step1' },
  { key: 'step2' },
  { key: 'step3' },
]
</script>

<style scoped>
.howitworks {
  padding: var(--section-padding);
  background: var(--color-bg);
}

.steps {
  display: flex;
  gap: 40px;
  margin-top: 48px;
  justify-content: center;
}

.step {
  flex: 1;
  max-width: 320px;
  text-align: center;
  position: relative;
}

.step-number {
  width: 64px;
  height: 64px;
  border-radius: 50%;
  background: var(--color-primary);
  color: #fff;
  font-size: 1.5rem;
  font-weight: 800;
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0 auto 24px;
  box-shadow: 0 4px 16px rgba(37, 99, 235, 0.25);
}

.step-title {
  font-size: 1.15rem;
  font-weight: 700;
  margin-bottom: 10px;
  color: var(--color-text);
}

.step-desc {
  font-size: 0.95rem;
  line-height: 1.65;
  color: var(--color-text-light);
}

/* Connector lines between steps */
.step:not(:last-child)::after {
  content: '';
  position: absolute;
  top: 32px;
  right: -20px;
  width: 40px;
  height: 2px;
  background: var(--color-border);
}

@media (max-width: 768px) {
  .steps {
    flex-direction: column;
    align-items: center;
    gap: 32px;
  }

  .step {
    max-width: 400px;
  }

  .step:not(:last-child)::after {
    display: none;
  }
}
</style>
