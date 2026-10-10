<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { safeAbsoluteUrl } from '../helpers/url';
import ActionButton from './ActionButton.vue';

// Saída para falar com a empresa (RA-17). Só aparece com link http/https vindo da página.
const props = defineProps({
  url: { type: String, default: '' },
  variant: { type: String, default: 'secondary' },
  label: { type: String, default: '' },
});

const { t } = useI18n();
const href = computed(() => safeAbsoluteUrl(props.url));
</script>

<template>
  <div class="contents">
    <ActionButton v-if="href" :href="href" :variant="variant" external>
      {{ label || t('BOOKING_V2.HELP.WHATSAPP') }}
    </ActionButton>
  </div>
</template>
