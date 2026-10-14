<script setup>
// Calendário Ouro — o mês pequeno ao lado do "Meu dia": escolher outro dia.
// Pontinho = tem coisa marcada; vermelho = tem coisa atrasada.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  diasDaSemana,
  formatarDia,
  semanasDoMes,
  somarMeses,
} from './tempoNaConta';

const props = defineProps({
  mes: { type: String, required: true },
  dia: { type: String, required: true },
  hoje: { type: String, required: true },
  idioma: { type: String, required: true },
  marcas: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['escolher', 'update:mes']);
const { t } = useI18n();

const semanas = computed(() => semanasDoMes(props.mes));
const titulo = computed(() =>
  formatarDia(props.mes, props.idioma, { month: 'long', year: 'numeric' })
);
const letras = computed(() =>
  diasDaSemana(props.hoje).map(chave =>
    formatarDia(chave, props.idioma, { weekday: 'narrow' })
  )
);
const rotulo = chave =>
  formatarDia(chave, props.idioma, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
</script>

<template>
  <div
    data-mini-mes
    class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 shadow-sm"
  >
    <div class="mb-1 flex items-center justify-between">
      <button
        type="button"
        class="grid size-11 place-items-center rounded-xl text-n-slate-11 hover:bg-n-alpha-2"
        :aria-label="t('CRM_CALENDARIO.NAV.MES_ANTERIOR')"
        @click="emit('update:mes', somarMeses(mes, -1))"
      >
        <span
          class="i-lucide-chevron-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
      <span
        class="text-sm font-semibold text-n-slate-12 first-letter:uppercase"
      >
        {{ titulo }}
      </span>
      <button
        type="button"
        class="grid size-11 place-items-center rounded-xl text-n-slate-11 hover:bg-n-alpha-2"
        :aria-label="t('CRM_CALENDARIO.NAV.MES_SEGUINTE')"
        @click="emit('update:mes', somarMeses(mes, 1))"
      >
        <span
          class="i-lucide-chevron-right size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
    </div>
    <div class="grid grid-cols-7 text-center">
      <span
        v-for="(letra, i) in letras"
        :key="i"
        class="pb-1 text-xs font-medium uppercase text-n-slate-10"
        aria-hidden="true"
      >
        {{ letra }}
      </span>
      <template v-for="semana in semanas" :key="semana[0]">
        <button
          v-for="chave in semana"
          :key="chave"
          type="button"
          :data-mini-dia="chave"
          :aria-label="rotulo(chave)"
          :aria-pressed="chave === dia"
          class="relative mx-auto grid size-11 place-items-center rounded-full text-sm tabular-nums transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="[
            chave === dia
              ? 'bg-n-slate-12 font-semibold text-n-solid-1'
              : chave === hoje
                ? 'font-bold text-n-blue-11 ring-1 ring-inset ring-n-blue-8'
                : 'hover:bg-n-alpha-2',
            chave.slice(0, 7) !== mes.slice(0, 7) && chave !== dia
              ? 'text-n-slate-8'
              : chave !== dia && chave !== hoje
                ? 'text-n-slate-12'
                : '',
          ]"
          @click="emit('escolher', chave)"
        >
          {{ Number(chave.slice(8)) }}
          <span
            v-if="marcas[chave]"
            class="absolute bottom-1 size-1 rounded-full"
            :class="
              marcas[chave] === 'atrasado'
                ? 'bg-n-ruby-9'
                : chave === dia
                  ? 'bg-n-solid-1'
                  : 'bg-n-blue-9'
            "
            aria-hidden="true"
          />
        </button>
      </template>
    </div>
  </div>
</template>
