<script setup>
// Calendário Ouro — o mês como visão de conjunto: até três itens por dia,
// "+N" para o resto. Clicar no dia abre o "Meu dia" daquele dia.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CalendarioPilula from './CalendarioPilula.vue';
import { TIPOS, porHorario } from './itensDoCalendario';
import { diasDaSemana, formatarDia, semanasDoMes } from './tempoNaConta';

const props = defineProps({
  itens: { type: Array, default: () => [] },
  mes: { type: String, required: true },
  hoje: { type: String, required: true },
  fuso: { type: String, required: true },
  idioma: { type: String, required: true },
});
const emit = defineEmits(['escolherDia', 'abrir']);
const { t } = useI18n();
// Dois por dia: cada um com alvo de toque de 44 px; o resto em "+N mais".
const NO_DIA = 2;

const porDia = computed(() => {
  const mapa = {};
  [...props.itens].sort(porHorario).forEach(item => {
    (mapa[item.chave] ||= []).push(item);
  });
  return mapa;
});
const semanas = computed(() => semanasDoMes(props.mes));
const cabecalho = computed(() =>
  diasDaSemana(props.hoje).map(chave =>
    formatarDia(chave, props.idioma, { weekday: 'short' }).replace('.', '')
  )
);
const foraDoMes = chave => chave.slice(0, 7) !== props.mes.slice(0, 7);
const longo = chave =>
  formatarDia(chave, props.idioma, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
</script>

<template>
  <div
    data-mes
    class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
  >
    <div class="grid grid-cols-7 border-b border-n-weak bg-n-alpha-1">
      <span
        v-for="nome in cabecalho"
        :key="nome"
        class="py-2 text-center text-xs font-medium uppercase text-n-slate-10"
      >
        {{ nome }}
      </span>
    </div>
    <div
      v-for="semana in semanas"
      :key="semana[0]"
      class="grid grid-cols-7 border-b border-n-weak last:border-b-0"
    >
      <div
        v-for="chave in semana"
        :key="chave"
        :data-mes-dia="chave"
        class="flex min-h-16 min-w-0 flex-col gap-1 border-e border-n-weak p-1 last:border-e-0 md:min-h-32 md:p-1.5"
        :class="foraDoMes(chave) ? 'bg-n-alpha-1' : ''"
      >
        <button
          type="button"
          class="flex min-h-11 items-center justify-center rounded-lg hover:bg-n-alpha-2 md:justify-start md:px-1"
          :aria-label="
            t('CRM_CALENDARIO.SEMANA.VER_DIA', { dia: longo(chave) })
          "
          @click="emit('escolherDia', chave)"
        >
          <span
            class="grid size-7 place-items-center rounded-full text-sm tabular-nums"
            :class="
              chave === hoje
                ? 'bg-n-blue-9 font-semibold text-white'
                : foraDoMes(chave)
                  ? 'text-n-slate-8'
                  : 'font-medium text-n-slate-12'
            "
          >
            {{ Number(chave.slice(8)) }}
          </span>
        </button>
        <!-- celular: só os pontinhos -->
        <div class="flex justify-center gap-0.5 md:hidden" aria-hidden="true">
          <span
            v-for="item in (porDia[chave] || []).slice(0, NO_DIA)"
            :key="item.id"
            class="size-1.5 rounded-full"
            :class="
              item.atrasado && item.chave < hoje
                ? 'bg-n-ruby-9'
                : TIPOS[item.tipo].ponto
            "
          />
        </div>
        <div class="hidden flex-col gap-1 md:flex">
          <CalendarioPilula
            v-for="item in (porDia[chave] || []).slice(0, NO_DIA)"
            :key="item.id"
            :item="item"
            :hoje="hoje"
            :fuso="fuso"
            :idioma="idioma"
            compacto
            @abrir="emit('abrir', $event)"
          />
          <button
            v-if="(porDia[chave] || []).length > NO_DIA"
            type="button"
            class="min-h-11 rounded-lg px-1.5 text-start text-xs font-medium text-n-blue-11 hover:bg-n-alpha-2"
            @click="emit('escolherDia', chave)"
          >
            {{
              t('CRM_CALENDARIO.MES.MAIS', { n: porDia[chave].length - NO_DIA })
            }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
