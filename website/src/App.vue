<template>
  <NavBar />
  <main>
    <HeroSection />
    <FeaturesSection />
    <InstallSection />
    <HowItWorks />
  </main>
  <FooterSection />
</template>

<script setup>
import NavBar from './components/NavBar.vue'
import HeroSection from './components/HeroSection.vue'
import FeaturesSection from './components/FeaturesSection.vue'
import InstallSection from './components/InstallSection.vue'
import HowItWorks from './components/HowItWorks.vue'
import FooterSection from './components/FooterSection.vue'
</script>
