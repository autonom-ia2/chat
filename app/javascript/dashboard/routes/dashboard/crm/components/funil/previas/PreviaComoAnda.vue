<script setup>
import { I18nT } from 'vue-i18n';

// #1384 — embaixo do quadro: o que acontece com o cliente, em três frases.
defineProps({
  primeira: { type: String, default: '' },
  ia: { type: Boolean, default: false },
});

// O número de cada frase é só visual: a lista já é ordenada para o leitor de tela.
const NUMEROS = [1, 2, 3];
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
      {{ $t('CRM_FUNIL.PREVIA.ANDA') }}
    </h4>
    <ol class="m-0 flex list-none flex-col gap-3 p-0">
      <li class="flex items-start gap-3 text-sm text-n-slate-12">
        <span
          class="grid size-6 shrink-0 place-items-center rounded-full bg-n-blue-3 text-xs font-bold text-n-blue-11"
          aria-hidden="true"
        >
          {{ NUMEROS[0] }}
        </span>
        <I18nT keypath="CRM_FUNIL.PREVIA.ANDA_1" tag="span" scope="global">
          <template #coluna>
            <strong class="font-semibold">{{ primeira }}</strong>
          </template>
        </I18nT>
      </li>
      <li class="flex items-start gap-3 text-sm text-n-slate-12">
        <span
          class="grid size-6 shrink-0 place-items-center rounded-full bg-n-blue-3 text-xs font-bold text-n-blue-11"
          aria-hidden="true"
        >
          {{ NUMEROS[1] }}
        </span>
        {{ $t(ia ? 'CRM_FUNIL.PREVIA.ANDA_2_IA' : 'CRM_FUNIL.PREVIA.ANDA_2') }}
      </li>
      <li class="flex items-start gap-3 text-sm text-n-slate-12">
        <span
          class="grid size-6 shrink-0 place-items-center rounded-full bg-n-blue-3 text-xs font-bold text-n-blue-11"
          aria-hidden="true"
        >
          {{ NUMEROS[2] }}
        </span>
        {{ $t('CRM_FUNIL.PREVIA.ANDA_3') }}
      </li>
    </ol>
  </section>
</template>
