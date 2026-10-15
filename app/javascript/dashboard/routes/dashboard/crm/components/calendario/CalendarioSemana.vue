<script setup>
// Calendário Ouro — a semana em sete colunas, sem a grade de horas vazias.
// Clicar no dia abre o "Meu dia" daquele dia; dia livre oferece marcar.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CalendarioPilula from './CalendarioPilula.vue';
import { porHorario } from './itensDoCalendario';
import { diasDaSemana, formatarDia } from './tempoNaConta';

const props = defineProps({
  itens: { type: Array, default: () => [] },
  dia: { type: String, required: true },
  hoje: { type: String, required: true },
  fuso: { type: String, required: true },
  idioma: { type: String, required: true },
});
const emit = defineEmits(['escolherDia', 'abrir', 'novo']);
const { t } = useI18n();

const colunas = computed(() =>
  diasDaSemana(props.dia).map(chave => ({
    chave,
    itens: props.itens.filter(i => i.chave === chave).sort(porHorario),
  }))
);
const nome = chave => formatarDia(chave, props.idioma, { weekday: 'short' });
const longo = chave =>
  formatarDia(chave, props.idioma, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
</script>

<template>
  <div data-semana class="grid grid-cols-1 gap-2 lg:grid-cols-7">
    <section
      v-for="coluna in colunas"
      :key="coluna.chave"
      :data-semana-dia="coluna.chave"
      class="group flex min-w-0 flex-col gap-2 rounded-2xl border bg-n-solid-1 p-2 lg:min-h-[30rem]"
      :class="
        coluna.chave === hoje ? 'border-n-blue-7 shadow-sm' : 'border-n-weak'
      "
    >
      <button
        type="button"
        class="flex min-h-11 items-center gap-2 rounded-xl px-1 text-start hover:bg-n-alpha-2 lg:flex-col lg:items-start lg:gap-0"
        :aria-label="
          t('CRM_CALENDARIO.SEMANA.VER_DIA', { dia: longo(coluna.chave) })
        "
        @click="emit('escolherDia', coluna.chave)"
      >
        <span class="text-xs font-medium uppercase text-n-slate-10">
          {{ nome(coluna.chave).replace('.', '') }}
        </span>
        <span
          class="grid size-8 place-items-center rounded-full text-lg font-semibold tabular-nums"
          :class="
            coluna.chave === hoje ? 'bg-n-blue-9 text-white' : 'text-n-slate-12'
          "
        >
          {{ Number(coluna.chave.slice(8)) }}
        </span>
      </button>
      <CalendarioPilula
        v-for="item in coluna.itens"
        :key="item.id"
        :item="item"
        :hoje="hoje"
        :fuso="fuso"
        :idioma="idioma"
        @abrir="emit('abrir', $event)"
      />
      <button
        v-if="!coluna.itens.length"
        type="button"
        data-semana-livre
        class="flex min-h-11 flex-1 items-center justify-center gap-1 rounded-xl text-sm text-n-slate-9 transition hover:bg-n-alpha-2 hover:text-n-blue-11 lg:flex-col"
        :aria-label="
          t('CRM_CALENDARIO.SEMANA.MARCAR_EM', { dia: longo(coluna.chave) })
        "
        @click="emit('novo', coluna.chave)"
      >
        <span
          class="i-lucide-plus size-4 opacity-0 transition group-hover:opacity-100"
          aria-hidden="true"
        />
        {{ t('CRM_CALENDARIO.SEMANA.LIVRE') }}
      </button>
    </section>
  </div>
</template>
