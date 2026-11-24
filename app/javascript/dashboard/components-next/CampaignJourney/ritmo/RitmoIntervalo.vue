<script setup>
// #3101 — na tela "Limite de mensagens": pelo menos X horas entre duas mensagens à mesma pessoa. Soma-se ao limite por
// período: "3 a cada 7 dias" sozinho deixa as 3 saírem no mesmo dia; com o intervalo, elas se espalham.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { INTERVALOS, SEM_INTERVALO } from './ritmoDeEnvio';

const horas = defineModel({ type: Number, default: SEM_INTERVALO });

const NS = 'CAMPAIGN_JOURNEY.RITMO.INTERVALO';
const { t } = useI18n();

const opcoes = computed(() => [
  { value: SEM_INTERVALO, label: t(`${NS}.SEM_INTERVALO`) },
  ...INTERVALOS.map(value => ({
    value,
    label: t(`${NS}.HORAS`, { n: value }, value),
  })),
]);
</script>

<template>
  <section
    class="rounded-3xl border border-n-weak bg-n-solid-1 px-5 py-5 shadow-sm sm:px-6"
    data-ritmo-intervalo
  >
    <h2 class="mb-1 text-base font-semibold text-n-slate-12">
      {{ t(`${NS}.TITLE`) }}
    </h2>
    <p class="mb-4 text-sm text-n-slate-11">{{ t(`${NS}.HELP`) }}</p>
    <div class="w-full sm:w-72">
      <ChoiceSelect
        v-model="horas"
        :options="opcoes"
        :aria-label="t(`${NS}.LABEL`)"
      />
    </div>
    <p
      v-if="horas !== SEM_INTERVALO"
      class="mb-0 mt-3 text-xs text-n-slate-11"
      data-ritmo-intervalo-exemplo
    >
      {{ t(`${NS}.EXEMPLO`, { n: horas }, horas) }}
    </p>
  </section>
</template>
