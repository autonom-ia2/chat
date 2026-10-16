<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CampoQuando from '../card/CampoQuando.vue';
import {
  FREQUENCIAS,
  diaCurto,
  diasDaSemana,
  frase,
  nomeDoDia,
  ocorrencias,
  totalDeVezes,
} from './recorrencia';

// #1460 — "Repetir?": uma vez só, todo dia, toda semana (com os dias), todo
// mês ou todo ano, e até quando. Embaixo, as próximas datas de verdade, para
// a pessoa conferir antes de salvar ("Próximas: seg., 20/10 · seg., 27/10").
const props = defineProps({
  // O dia e a hora do primeiro aviso ("2026-10-20T10:00").
  inicio: { type: String, default: '' },
  // O nome do fuso da conta, para a frase da hora.
  fuso: { type: String, default: '' },
  // Mudando "esta e as próximas", não existe "uma vez só" (para parar, Encerrar).
  semUmaVez: { type: Boolean, default: false },
});
const repetir = defineModel({ type: Object, required: true });

const { t, locale } = useI18n();
const R = 'CRM_LEMBRETE.REPETIR';
const id = useId();
const idioma = computed(() => locale.value.replace('_', '-'));
const juntar = nomes =>
  new Intl.ListFormat(idioma.value, {
    style: 'long',
    type: 'conjunction',
  }).format(nomes);

const ICONE = {
  nunca: 'i-lucide-circle-dot',
  dia: 'i-lucide-sun',
  semana: 'i-lucide-calendar-range',
  mes: 'i-lucide-calendar-days',
  ano: 'i-lucide-cake',
};
const frequencias = computed(() =>
  props.semUmaVez ? FREQUENCIAS.filter(item => item !== 'nunca') : FREQUENCIAS
);
const mudar = parte => {
  repetir.value = { ...repetir.value, ...parte };
};
const repete = computed(() => repetir.value.frequencia !== 'nunca');

// Segunda a domingo.
const SEMANA = [1, 2, 3, 4, 5, 6, 0];
const diasEscolhidos = computed(() =>
  diasDaSemana(repetir.value, props.inicio)
);
const alternarDia = numero => {
  const atuais = diasEscolhidos.value;
  const lista = atuais.includes(numero)
    ? atuais.filter(item => item !== numero)
    : [...atuais, numero];
  if (lista.length) mudar({ dias: lista });
};

const fins = computed(() => [
  { value: 'nunca', label: t(`${R}.FIM.NUNCA`) },
  { value: 'data', label: t(`${R}.FIM.DATA`) },
  { value: 'vezes', label: t(`${R}.FIM.VEZES`) },
]);
const vezes = computed(() =>
  [2, 3, 4, 5, 6, 8, 10, 12, 24, 52].map(numero => ({
    value: numero,
    label: t(`${R}.N_VEZES`, { n: numero }),
  }))
);

const numeroDoDia = computed(() => Number(props.inicio.slice(8, 10)) || 0);
const fraseDaSerie = computed(() =>
  frase({
    t,
    idioma: idioma.value,
    juntar,
    inicio: props.inicio,
    repetir: repetir.value,
  })
);
const proximas = computed(() =>
  ocorrencias(props.inicio, repetir.value, 5).map(dia =>
    diaCurto(dia, idioma.value)
  )
);
const total = computed(() => totalDeVezes(props.inicio, repetir.value));
const ultima = computed(() => {
  if (!Number.isFinite(total.value)) return '';
  const lista = ocorrencias(props.inicio, repetir.value, total.value);
  return lista.length ? diaCurto(lista.at(-1), idioma.value) : '';
});
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-3 border-0 p-0" data-repetir>
    <legend class="mb-1 p-0 text-base font-semibold text-n-slate-12">
      {{ t(`${R}.PERGUNTA`) }}
    </legend>
    <div class="flex flex-wrap gap-2">
      <button
        v-for="frequencia in frequencias"
        :key="frequencia"
        type="button"
        :data-frequencia="frequencia"
        :aria-pressed="repetir.frequencia === frequencia"
        class="inline-flex min-h-11 items-center gap-2 rounded-xl px-3 text-sm font-medium ring-1 ring-inset transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :class="
          repetir.frequencia === frequencia
            ? 'bg-n-blue-2 text-n-blue-11 ring-2 ring-n-blue-8'
            : 'bg-n-solid-1 text-n-slate-12 ring-n-weak hover:ring-n-slate-7'
        "
        @click="mudar({ frequencia })"
      >
        <span class="size-4" :class="ICONE[frequencia]" aria-hidden="true" />
        {{ t(`${R}.OPCAO.${frequencia.toUpperCase()}`) }}
      </button>
    </div>

    <div
      v-if="repete"
      class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
      data-repetir-detalhe
    >
      <button
        v-if="repetir.frequencia === 'dia'"
        type="button"
        role="switch"
        :aria-checked="repetir.soDiasUteis"
        class="flex min-h-11 w-fit items-center gap-3 rounded-xl px-1 text-start text-sm text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        @click="mudar({ soDiasUteis: !repetir.soDiasUteis })"
      >
        <span
          class="relative h-6 w-10 shrink-0 rounded-full transition"
          :class="repetir.soDiasUteis ? 'bg-n-blue-9' : 'bg-n-slate-6'"
          aria-hidden="true"
        >
          <span
            class="absolute top-0.5 size-5 rounded-full bg-white shadow transition-all"
            :class="repetir.soDiasUteis ? 'start-[1.125rem]' : 'start-0.5'"
          />
        </span>
        {{ t(`${R}.SO_DIAS_UTEIS`) }}
      </button>

      <div
        v-if="repetir.frequencia === 'semana'"
        class="flex flex-col gap-2"
        data-repetir-dias
      >
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t(`${R}.QUAIS_DIAS`) }}
        </p>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="numero in SEMANA"
            :key="numero"
            type="button"
            :aria-pressed="diasEscolhidos.includes(numero)"
            :aria-label="nomeDoDia(numero, idioma)"
            class="grid size-11 place-items-center rounded-xl text-sm font-semibold ring-1 ring-inset transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            :class="
              diasEscolhidos.includes(numero)
                ? 'bg-n-blue-9 text-white ring-n-blue-9'
                : 'bg-n-solid-1 text-n-slate-12 ring-n-weak hover:ring-n-slate-7'
            "
            @click="alternarDia(numero)"
          >
            {{ nomeDoDia(numero, idioma, 'short').replace('.', '') }}
          </button>
        </div>
      </div>

      <p
        v-if="repetir.frequencia === 'mes' && numeroDoDia > 28"
        class="mb-0 flex items-start gap-2 text-sm text-n-slate-11"
      >
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ t(`${R}.MES_CURTO`, { dia: numeroDoDia }) }}
      </p>

      <div class="grid gap-3 sm:grid-cols-2">
        <div class="flex flex-col gap-1">
          <label :for="`${id}-fim`" class="text-sm font-medium text-n-slate-12">
            {{ t(`${R}.ATE_QUANDO`) }}
          </label>
          <ChoiceSelect
            :model-value="repetir.fim"
            :trigger-id="`${id}-fim`"
            :options="fins"
            :aria-label="t(`${R}.ATE_QUANDO`)"
            class="w-full"
            @update:model-value="fim => mudar({ fim })"
          />
        </div>
        <div v-if="repetir.fim === 'vezes'" class="flex flex-col gap-1">
          <label
            :for="`${id}-vezes`"
            class="text-sm font-medium text-n-slate-12"
          >
            {{ t(`${R}.QUANTAS`) }}
          </label>
          <ChoiceSelect
            :model-value="repetir.vezes"
            :trigger-id="`${id}-vezes`"
            :options="vezes"
            :aria-label="t(`${R}.QUANTAS`)"
            class="w-full"
            @update:model-value="numero => mudar({ vezes: numero })"
          />
        </div>
      </div>
      <CampoQuando
        v-if="repetir.fim === 'data'"
        :model-value="repetir.ate"
        :rotulo="t(`${R}.ULTIMO_DIA`)"
        :com-hora="false"
        @update:model-value="ate => mudar({ ate })"
      />

      <section
        class="flex flex-col gap-2 rounded-xl bg-n-solid-1 p-3 ring-1 ring-inset ring-n-weak"
        data-repetir-proximas
        aria-live="polite"
      >
        <p
          class="mb-0 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-repeat size-4 text-n-blue-11"
            aria-hidden="true"
          />
          {{ fraseDaSerie }}
        </p>
        <template v-if="inicio">
          <p class="mb-0 text-xs font-medium text-n-slate-11">
            {{ t(`${R}.PROXIMAS`) }}
          </p>
          <ul class="m-0 flex list-none flex-wrap gap-1.5 p-0">
            <li
              v-for="(dia, indice) in proximas"
              :key="dia"
              class="rounded-lg px-2 py-1 text-sm tabular-nums"
              :class="
                indice
                  ? 'bg-n-alpha-2 text-n-slate-12'
                  : 'bg-n-blue-3 font-semibold text-n-blue-11'
              "
            >
              {{ dia }}
            </li>
          </ul>
          <p class="mb-0 text-xs text-n-slate-11">
            {{
              Number.isFinite(total)
                ? t(`${R}.TOTAL`, { n: total, ultima })
                : t(`${R}.SEM_FIM`)
            }}
          </p>
        </template>
        <p v-else class="mb-0 text-sm text-n-slate-11">
          {{ t(`${R}.ESCOLHA_DIA`) }}
        </p>
        <p v-if="fuso" class="mb-0 text-xs text-n-slate-11">
          {{ t(`${R}.FUSO`, { fuso }) }}
        </p>
      </section>
    </div>
  </fieldset>
</template>
