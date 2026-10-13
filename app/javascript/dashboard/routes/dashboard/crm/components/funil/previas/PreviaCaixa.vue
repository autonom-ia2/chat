<script setup>
import { I18nT } from 'vue-i18n';

// #1384 — a frase que acompanha o quadro em "Caixas de entrada": quem chama
// por qual caixa e em que coluna aparece.
defineProps({
  foco: { type: Object, default: null },
});
</script>

<template>
  <section
    v-if="foco"
    class="flex items-start gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <span
      class="grid size-9 shrink-0 place-items-center rounded-xl bg-n-teal-3 text-n-teal-11"
      aria-hidden="true"
    >
      <span class="i-lucide-message-circle size-5" />
    </span>
    <I18nT
      :keypath="
        foco.sozinho
          ? 'CRM_FUNIL.PREVIA.CAIXA_SOZINHO'
          : 'CRM_FUNIL.PREVIA.CAIXA_EQUIPE'
      "
      tag="p"
      scope="global"
      class="mb-0 text-[0.9375rem] leading-relaxed text-n-slate-12"
    >
      <template #caixa>
        <strong class="font-semibold">{{ foco.nome }}</strong>
      </template>
      <template #coluna>
        <strong class="font-semibold">{{ foco.etapa?.name }}</strong>
      </template>
    </I18nT>
  </section>
  <p
    v-else
    class="mb-0 rounded-2xl border border-dashed border-n-slate-6 p-4 text-[0.9375rem] text-n-slate-11"
  >
    {{ $t('CRM_FUNIL.PREVIA.CAIXA_NENHUMA') }}
  </p>
</template>
