<script setup>
import { onBeforeUnmount, onMounted, ref, useTemplateRef } from 'vue';

defineProps({
  currentPage: {
    type: String,
    required: true,
  },
});

const base = import.meta.env.BASE_URL;
const isOpen = ref(false);
const menuButton = useTemplateRef('menuButton');
const nav = useTemplateRef('nav');

function closeMenu({ restoreFocus = false } = {}) {
  isOpen.value = false;
  if (restoreFocus) menuButton.value?.focus();
}

function onKeydown(event) {
  if (event.key === 'Escape' && isOpen.value) closeMenu({ restoreFocus: true });
}

function onPointerdown(event) {
  if (isOpen.value && !nav.value?.contains(event.target)) closeMenu();
}

onMounted(() => {
  document.addEventListener('keydown', onKeydown);
  document.addEventListener('pointerdown', onPointerdown);
});

onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKeydown);
  document.removeEventListener('pointerdown', onPointerdown);
});
</script>

<template>
  <header class="site-header">
    <nav ref="nav" class="nav container" aria-label="主导航">
      <a class="brand" :href="base" aria-label="Familiar 首页">
        <img :src="`${base}assets/app-icon.png`" alt="" width="32" height="32">
        <span>Familiar</span>
      </a>

      <button
        ref="menuButton"
        class="nav-toggle"
        type="button"
        aria-label="打开导航菜单"
        :aria-expanded="isOpen"
        aria-controls="site-navigation"
        @click="isOpen = !isOpen"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
          <path d="M4 7h16M4 12h16M4 17h16" stroke-linecap="round" />
        </svg>
      </button>

      <div id="site-navigation" class="nav-links" :data-open="isOpen" @click="closeMenu()">
        <a class="nav-link" :href="base" :aria-current="currentPage === 'home' ? 'page' : undefined">首页</a>
        <a class="nav-link" :href="`${base}privacy/`" :aria-current="currentPage === 'privacy' ? 'page' : undefined">隐私</a>
        <a class="nav-link" :href="`${base}support/`" :aria-current="currentPage === 'support' ? 'page' : undefined">支持</a>
        <a class="nav-link" href="https://github.com/IsaacHuo/familiar" target="_blank" rel="noreferrer">GitHub</a>
        <a class="button button-primary" href="https://github.com/IsaacHuo/familiar" target="_blank" rel="noreferrer">查看项目</a>
      </div>
    </nav>
  </header>
</template>
