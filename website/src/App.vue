<script setup>
import { computed } from 'vue';
import SiteFooter from './components/SiteFooter.vue';
import SiteHeader from './components/SiteHeader.vue';
import HomePage from './pages/HomePage.vue';
import PrivacyPage from './pages/PrivacyPage.vue';
import SupportPage from './pages/SupportPage.vue';

const pathname = window.location.pathname;
const currentPage = computed(() => {
  if (pathname.includes('/privacy')) return 'privacy';
  if (pathname.includes('/support')) return 'support';
  return 'home';
});

const pageComponent = computed(() => ({
  home: HomePage,
  privacy: PrivacyPage,
  support: SupportPage,
})[currentPage.value]);
</script>

<template>
  <a class="skip-link" href="#main-content">跳到主要内容</a>
  <SiteHeader :current-page="currentPage" />
  <main id="main-content">
    <component :is="pageComponent" />
  </main>
  <SiteFooter />
</template>
