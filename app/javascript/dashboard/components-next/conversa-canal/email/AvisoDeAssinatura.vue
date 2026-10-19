<script setup>
// Na resposta de e-mail (#1786), a assinatura ligada sem texto vira uma linha discreta
// com o caminho para criar, no lugar da faixa tracejada do painel.
// #1809: "Criar assinatura" abre o perfil numa aba nova. Na mesma aba a gaveta
// "Escrever" fechava e o texto escrito (que só vive na gaveta) se perdia. Ao voltar
// para esta aba, o perfil é relido: a assinatura criada lá já vale aqui, e o aviso some.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useEventListener } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import Icon from 'next/icon/Icon.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

const enderecoDoPerfil = computed(
  () => router.resolve({ name: 'profile_settings_index' }).href
);

const foiCriar = ref(false);
useEventListener(window, 'focus', () => {
  if (!foiCriar.value) return;
  // Uma releitura por ida ao perfil: cada foco seguinte não chama a API de novo.
  foiCriar.value = false;
  store.dispatch('validityCheck');
});
</script>

<template>
  <p
    class="flex flex-wrap items-center gap-x-2 gap-y-1 mb-2 px-1 text-xs text-n-slate-11"
    data-aviso-de-assinatura
  >
    <Icon icon="i-ph-signature" class="size-4" />
    {{ t('CONVERSA_CANAL.EMAIL.SEM_ASSINATURA') }}
    <a
      :href="enderecoDoPerfil"
      target="_blank"
      rel="noopener noreferrer"
      class="inline-flex items-center min-h-11 px-2 rounded-full font-medium text-n-blue-11 hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      data-criar-assinatura
      @click="foiCriar = true"
    >
      {{ t('CONVERSA_CANAL.EMAIL.CRIAR_ASSINATURA') }}
      <span class="sr-only">
        {{ t('CONVERSA_CANAL.EMAIL.CRIAR_ASSINATURA_NOVA_ABA') }}
      </span>
    </a>
  </p>
</template>
