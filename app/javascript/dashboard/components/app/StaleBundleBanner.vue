<script setup>
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { isPanelOutdated } from 'dashboard/helper/staleBundle';

const { t } = useI18n();

const reloadPage = () => window.location.reload();
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Banner
    v-if="isPanelOutdated"
    color="amber"
    role="alert"
    :action-label="t('GENERAL_SETTINGS.PANEL_OUTDATED.RELOAD')"
    class="!rounded-none !justify-center"
    @action="reloadPage"
  >
    <span class="text-xs">{{
      t('GENERAL_SETTINGS.PANEL_OUTDATED.MESSAGE')
    }}</span>
  </Banner>
</template>
