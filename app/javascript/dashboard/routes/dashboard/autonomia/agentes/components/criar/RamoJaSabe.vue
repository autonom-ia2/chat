<script setup>
import { useI18n } from 'vue-i18n';

// #2881 — ao lado da conversa de criação de um agente pronto por ramo, embaixo da conversa de exemplo: o que ele já
// vem sabendo, em três linhas. É o que explica por que a conversa só tem duas perguntas.
defineProps({
  ramo: { type: String, required: true },
});

const { t } = useI18n();
</script>

<template>
  <section
    data-ja-sabe
    aria-labelledby="ja-sabe-titulo"
    class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-2 ring-1 ring-inset ring-n-weak"
  >
    <h3 id="ja-sabe-titulo" class="m-0 text-base font-semibold text-n-slate-12">
      {{ t('AGENTS.JORNADA.RAMOS.CRIAR.JA_SABE.TITULO', { ramo }) }}
    </h3>
    <ul class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="linha in [
          t('AGENTS.JORNADA.RAMOS.CRIAR.JA_SABE.EXPLICA'),
          t('AGENTS.JORNADA.RAMOS.CRIAR.JA_SABE.PERGUNTA'),
          t('AGENTS.JORNADA.RAMOS.CRIAR.JA_SABE.PASSA'),
        ]"
        :key="linha"
        class="flex items-start gap-2 text-sm text-n-slate-12"
      >
        <span
          class="i-lucide-check size-4 mt-0.5 shrink-0 text-n-teal-11"
          aria-hidden="true"
        />
        {{ linha }}
      </li>
    </ul>
  </section>
</template>
