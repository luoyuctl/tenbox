<template>
  <footer class="footer">
    <div class="container footer-inner">
      <p class="footer-copy">{{ $t('footer.copyright') }}</p>
    </div>
  </footer>
</template>

<style scoped>
.footer {
  background: var(--color-bg-alt);
  color: var(--color-text-light);
  padding: 40px 0;
  border-top: 1px solid var(--color-border);
}

.footer-inner {
  display: flex;
  align-items: center;
  justify-content: center;
}

.footer-copy {
  font-size: 0.875rem;
}
</style>
