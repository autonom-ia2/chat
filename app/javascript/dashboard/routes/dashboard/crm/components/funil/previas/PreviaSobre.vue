<script setup>
import { I18nT } from 'vue-i18n';

// #1384 — como a frase de "Sobre este funil" é usada quando chega conversa.
defineProps({
  nome: { type: String, default: '' },
  texto: { type: String, default: '' },
});
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <p class="mb-0 flex items-center gap-2 text-sm text-n-slate-11">
      <span class="i-lucide-message-circle size-4" aria-hidden="true" />
      {{ $t('CRM_FUNIL.PREVIA.SOBRE_CHEGA') }}
    </p>
    <span
      class="i-lucide-arrow-down size-4 text-n-slate-10"
      aria-hidden="true"
    />
    <blockquote
      v-if="texto.trim()"
      class="m-0 rounded-xl bg-n-blue-2 p-3 text-[0.9375rem] leading-relaxed text-n-slate-12"
    >
      {{ $t('CRM_FUNIL.SOBRE.FRASE', { nome: nome.trim() || '…' }) }}
      <strong class="font-semibold">{{ texto.trim() }}</strong>
    </blockquote>
    <p
      v-else
      class="mb-0 rounded-xl border border-dashed border-n-amber-8 bg-n-amber-2 p-3 text-sm text-n-slate-12"
    >
      {{ $t('CRM_FUNIL.PREVIA.SOBRE_FALTA') }}
    </p>
    <template v-if="texto.trim()">
      <span
        class="i-lucide-arrow-down size-4 text-n-slate-10"
        aria-hidden="true"
      />
      <I18nT
        keypath="CRM_FUNIL.PREVIA.SOBRE_VAI"
        tag="p"
        scope="global"
        class="mb-0 text-[0.9375rem] text-n-slate-12"
      >
        <template #nome>
          <strong class="font-semibold">{{ nome.trim() }}</strong>
        </template>
      </I18nT>
    </template>
  </section>
</template>
