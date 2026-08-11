<script setup>
const base = import.meta.env.BASE_URL;
const year = new Date().getFullYear();
</script>

<template>
  <footer class="site-footer">
    <div class="footer-inner container">
      <div>
        <a class="brand footer-brand" :href="base">
          <img :src="`${base}assets/app-icon.png`" alt="" width="32" height="32">
          <span>Familiar</span>
        </a>
        <p class="footer-copy">© {{ year }} Familiar. 安静、原生，始终在你手边。</p>
      </div>
      <nav class="footer-links" aria-label="页脚导航">
        <a :href="`${base}privacy/`">隐私政策</a>
        <a :href="`${base}support/`">支持中心</a>
        <a href="https://github.com/IsaacHuo/familiar/issues" target="_blank" rel="noreferrer">问题反馈</a>
        <a href="https://github.com/IsaacHuo/familiar" target="_blank" rel="noreferrer">GitHub</a>
      </nav>
    </div>
  </footer>
</template>
