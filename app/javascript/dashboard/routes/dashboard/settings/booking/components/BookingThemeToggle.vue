<script setup>
import { useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { PAGE_THEMES } from '../constants';

// "Claro / Escuro" da prévia (#1295): a página pública segue o tema do aparelho
// do cliente, então a prévia deixa ver os dois. Por baixo é um grupo de rádios
// de verdade (setas do teclado, leitor de tela), com alvo de 44 px; nunca a
// lista nativa do navegador. Só troca o que a prévia mostra: nada é salvo.
const model = defineModel({ type: String, default: 'light' });

const { t } = useI18n();
const name = useId();
const labelId = useId();
</script>

<template>
  <div
    data-theme-toggle
    class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2"
  >
    <p :id="labelId" class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.THEME.LABEL') }}
    </p>
    <div
      role="radiogroup"
      :aria-labelledby="labelId"
      class="inline-flex gap-1 p-1 rounded-2xl bg-n-alpha-2 ring-1 ring-inset ring-n-weak"
    >
      <label
        v-for="theme in PAGE_THEMES"
        :key="theme.key"
        :data-theme-option="theme.key"
        class="inline-flex items-center justify-center gap-2 min-h-11 px-4 m-0 rounded-xl text-base font-medium cursor-pointer text-n-slate-11 transition has-[:checked]:bg-n-solid-1 has-[:checked]:text-n-slate-12 has-[:checked]:shadow-sm has-[:checked]:ring-1 has-[:checked]:ring-inset has-[:checked]:ring-n-weak has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
      >
        <input
          v-model="model"
          type="radio"
          class="sr-only"
          :name="name"
          :value="theme.key"
        />
        <span class="size-4" :class="theme.icon" aria-hidden="true" />
        {{ t(`BOOKING.THEME.${theme.i18n}`) }}
      </label>
    </div>
  </div>
</template>
