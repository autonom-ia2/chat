<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CampoQuando from '../card/CampoQuando.vue';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import {
  formatarDia,
  somarDias,
  dataDaChave,
} from '../calendario/tempoNaConta';

// #1590 — "Quando?": o dia em botões grandes (hoje, amanhã, a próxima
// segunda, outro dia) e a hora em botões (manhã, almoço, tarde, fim do dia,
// outro horário). Tudo no fuso da conta, dito embaixo numa linha. Hoje só
// oferece as horas que ainda não passaram.
const props = defineProps({
  hoje: { type: String, required: true },
  agoraMinutos: { type: Number, required: true },
  fuso: { type: String, required: true },
  noPassado: { type: Boolean, default: false },
});
const quando = defineModel({ type: Object, required: true });

const { t, locale } = useI18n();
const M = 'CRM_MENSAGEM_MARCADA.QUANDO';
const idioma = computed(() => locale.value.replace('_', '-'));
const HORAS = ['09:00', '12:00', '15:00', '18:00'];
const SEGUNDA = 1;

const minutos = hora => {
  const [h, m] = hora.split(':').map(Number);
  return h * 60 + m;
};

const segunda = computed(() => {
  const semana = dataDaChave(props.hoje).getUTCDay();
  const faltam = (SEGUNDA - semana + 7) % 7 || 7;
  return somarDias(props.hoje, faltam);
});
const amanha = computed(() => somarDias(props.hoje, 1));
const horasDeHoje = computed(() =>
  HORAS.filter(hora => minutos(hora) > props.agoraMinutos)
);
const dias = computed(() =>
  [
    horasDeHoje.value.length && { chave: props.hoje, rotulo: t(`${M}.HOJE`) },
    { chave: amanha.value, rotulo: t(`${M}.AMANHA`) },
    segunda.value !== amanha.value && {
      chave: segunda.value,
      rotulo: formatarDia(segunda.value, idioma.value, { weekday: 'long' }),
    },
  ]
    .filter(Boolean)
    .map(dia => ({
      ...dia,
      data: formatarDia(dia.chave, idioma.value, {
        day: 'numeric',
        month: 'long',
      }),
    }))
);
const outroDia = ref(false);
const ehAtalho = computed(() =>
  dias.value.some(dia => dia.chave === quando.value.dia)
);
const escolherDia = chave => {
  outroDia.value = false;
  const hora =
    chave === props.hoje && !horasDeHoje.value.includes(quando.value.hora)
      ? ''
      : quando.value.hora;
  quando.value = { dia: chave, hora };
};
const diaDoCalendario = computed({
  get: () => quando.value.dia,
  set: chave => {
    quando.value = { ...quando.value, dia: chave };
  },
});

const horas = computed(() =>
  quando.value.dia === props.hoje ? horasDeHoje.value : HORAS
);
const outraHora = ref(false);
const todasAsHoras = computed(() =>
  Array.from({ length: 48 }, (_, indice) => {
    const texto = `${String(Math.floor(indice / 2)).padStart(2, '0')}:${indice % 2 ? '30' : '00'}`;
    return { value: texto, label: texto };
  })
);
const escolherHora = hora => {
  outraHora.value = false;
  quando.value = { ...quando.value, hora };
};
const NOME_DA_HORA = {
  '09:00': 'MANHA',
  '12:00': 'ALMOCO',
  '15:00': 'TARDE',
  '18:00': 'FIM',
};
const chip = ativo =>
  ativo
    ? 'bg-n-blue-2 text-n-blue-11 shadow-sm ring-2 ring-n-blue-8'
    : 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak hover:ring-n-slate-7';
</script>

<template>
  <section data-passo="quando" class="flex flex-col gap-6">
    <fieldset class="m-0 flex flex-col gap-3 border-0 p-0">
      <legend class="mb-2 p-0 text-base font-semibold text-n-slate-12">
        {{ t(`${M}.DIA`) }}
      </legend>
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <button
          v-for="(dia, indice) in dias"
          :key="dia.chave"
          type="button"
          :data-dia="dia.chave"
          :data-foco="indice === 0 ? '' : null"
          :aria-pressed="quando.dia === dia.chave && !outroDia"
          class="flex min-h-16 flex-col items-start justify-center gap-0.5 rounded-2xl px-4 py-2 text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="chip(quando.dia === dia.chave && !outroDia)"
          @click="escolherDia(dia.chave)"
        >
          <span class="text-base font-semibold first-letter:uppercase">
            {{ dia.rotulo }}
          </span>
          <span class="text-sm text-n-slate-11">{{ dia.data }}</span>
        </button>
        <button
          type="button"
          data-dia-outro
          :aria-pressed="outroDia || (Boolean(quando.dia) && !ehAtalho)"
          class="flex min-h-16 items-center gap-2 rounded-2xl px-4 py-2 text-start text-base font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="chip(outroDia || (Boolean(quando.dia) && !ehAtalho))"
          @click="outroDia = true"
        >
          <span class="i-lucide-calendar-days size-5" aria-hidden="true" />
          {{ t(`${M}.OUTRO_DIA`) }}
        </button>
      </div>
      <CampoQuando
        v-if="outroDia || (quando.dia && !ehAtalho)"
        v-model="diaDoCalendario"
        :rotulo="t(`${M}.ESCOLHA_DIA`)"
        :com-hora="false"
      />
    </fieldset>

    <fieldset
      v-if="quando.dia"
      data-quando-hora
      class="m-0 flex flex-col gap-3 border-0 p-0"
    >
      <legend class="mb-2 p-0 text-base font-semibold text-n-slate-12">
        {{ t(`${M}.HORA`) }}
      </legend>
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
        <button
          v-for="hora in horas"
          :key="hora"
          type="button"
          :data-hora="hora"
          :aria-pressed="quando.hora === hora && !outraHora"
          class="flex min-h-16 flex-col items-start justify-center gap-0.5 rounded-2xl px-4 py-2 text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="chip(quando.hora === hora && !outraHora)"
          @click="escolherHora(hora)"
        >
          <span class="text-base font-semibold">{{ hora }}</span>
          <span class="text-sm text-n-slate-11">
            {{ t(`${M}.NOME_HORA.${NOME_DA_HORA[hora]}`) }}
          </span>
        </button>
        <button
          type="button"
          data-hora-outra
          :aria-pressed="
            outraHora || (Boolean(quando.hora) && !horas.includes(quando.hora))
          "
          class="flex min-h-16 items-center gap-2 rounded-2xl px-4 py-2 text-start text-base font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            chip(
              outraHora ||
                (Boolean(quando.hora) && !horas.includes(quando.hora))
            )
          "
          @click="outraHora = true"
        >
          <span class="i-lucide-clock size-5" aria-hidden="true" />
          {{ t(`${M}.OUTRA_HORA`) }}
        </button>
      </div>
      <label
        v-if="outraHora || (quando.hora && !horas.includes(quando.hora))"
        class="flex max-w-xs flex-col gap-1.5"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${M}.ESCOLHA_HORA`) }}
        </span>
        <ChoiceSelect
          :model-value="quando.hora"
          :options="todasAsHoras"
          :aria-label="t(`${M}.ESCOLHA_HORA`)"
          :placeholder="t(`${M}.ESCOLHA_HORA`)"
          class="w-full"
          @update:model-value="hora => (quando = { ...quando, hora })"
        />
      </label>
      <p
        v-if="noPassado"
        role="status"
        class="mb-0 rounded-xl border border-n-amber-7 bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
      >
        {{ t(`${M}.PASSADO`) }}
      </p>
    </fieldset>

    <p
      data-quando-fuso
      class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
    >
      <span class="i-lucide-globe size-4 shrink-0" aria-hidden="true" />
      {{ t(`${M}.FUSO`, { fuso: rotuloDoFuso(fuso) }) }}
    </p>
  </section>
</template>
