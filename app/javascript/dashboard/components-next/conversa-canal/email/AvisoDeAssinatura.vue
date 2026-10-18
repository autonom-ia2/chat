<script setup>
// Na resposta de e-mail (#1786), a assinatura ligada sem texto vira uma linha discreta
// com o caminho para criar, no lugar da faixa tracejada do painel.
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Icon from 'next/icon/Icon.vue';

const { t } = useI18n();
const router = useRouter();
</script>

<template>
  <p
    class="flex flex-wrap items-center gap-x-2 gap-y-1 mb-2 px-1 text-xs text-n-slate-11"
    data-aviso-de-assinatura
  >
    <Icon icon="i-ph-signature" class="size-4" />
    {{ t('CONVERSA_CANAL.EMAIL.SEM_ASSINATURA') }}
    <button
      type="button"
      class="min-h-8 px-2 rounded-full font-medium text-n-blue-11 hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="router.push({ name: 'profile_settings_index' })"
    >
      {{ t('CONVERSA_CANAL.EMAIL.CRIAR_ASSINATURA') }}
    </button>
  </p>
</template>
