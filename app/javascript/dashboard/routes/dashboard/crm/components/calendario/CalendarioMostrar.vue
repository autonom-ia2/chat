<script setup>
// Calendário Ouro — tudo o que filtra mora aqui, num painel só, em palavras
// do dia a dia. Só aparecem os tipos que a conta usa (sem WhatsApp conectado,
// não há "Mensagens marcadas").
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { TIPOS } from './itensDoCalendario';

const props = defineProps({
  quem: { type: String, required: true },
  tipos: { type: Object, required: true },
  tiposDisponiveis: { type: Array, required: true },
  feitos: { type: Boolean, default: false },
  funil: { type: [String, Number], default: null },
  funis: { type: Array, default: () => [] },
  podeAgendamento: { type: Boolean, default: false },
  podeCaixas: { type: Boolean, default: false },
});
const emit = defineEmits([
  'update:quem',
  'update:tipos',
  'update:feitos',
  'update:funil',
  'fechar',
  'abrirAgendamento',
  'abrirCaixas',
]);
const { t } = useI18n();
const N = 'CRM_CALENDARIO.MOSTRAR';

const alternar = tipo =>
  emit('update:tipos', { ...props.tipos, [tipo]: !props.tipos[tipo] });
</script>

<template>
  <section
    data-mostrar
    :aria-label="t(`${N}.TITULO`)"
    class="grid gap-6 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm md:grid-cols-[1fr_1.4fr_1fr] md:p-5"
  >
    <div class="flex flex-col gap-2">
      <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
        {{ t(`${N}.DE_QUEM`) }}
      </h3>
      <div
        class="grid grid-cols-2 gap-1 rounded-xl bg-n-alpha-2 p-1 md:grid-cols-1"
      >
        <button
          v-for="opcao in ['todos', 'meus']"
          :key="opcao"
          type="button"
          :data-quem="opcao"
          :aria-pressed="quem === opcao"
          class="min-h-11 rounded-lg px-3 text-sm font-medium transition"
          :class="
            quem === opcao
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="emit('update:quem', opcao)"
        >
          {{ t(`${N}.QUEM_${opcao.toUpperCase()}`) }}
        </button>
      </div>
      <h3 class="mb-0 mt-3 text-sm font-semibold text-n-slate-11">
        {{ t(`${N}.FUNIL`) }}
      </h3>
      <ChoiceSelect
        :model-value="funil"
        :options="funis"
        :aria-label="t(`${N}.FUNIL`)"
        @update:model-value="emit('update:funil', $event)"
      />
    </div>

    <div class="flex flex-col gap-2">
      <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
        {{ t(`${N}.O_QUE`) }}
      </h3>
      <button
        v-for="tipo in tiposDisponiveis"
        :key="tipo"
        type="button"
        role="checkbox"
        :data-mostrar-tipo="tipo"
        :aria-checked="tipos[tipo] !== false"
        class="flex min-h-12 items-center gap-3 rounded-xl px-2 text-start transition hover:bg-n-alpha-2"
        @click="alternar(tipo)"
      >
        <span
          class="grid size-5 shrink-0 place-items-center rounded-md border-2 transition"
          :class="
            tipos[tipo] !== false
              ? 'border-n-blue-9 bg-n-blue-9 text-white'
              : 'border-n-slate-7'
          "
          aria-hidden="true"
        >
          <span v-if="tipos[tipo] !== false" class="i-lucide-check size-3.5" />
        </span>
        <span
          class="grid size-8 shrink-0 place-items-center rounded-lg"
          :class="TIPOS[tipo].tom"
          aria-hidden="true"
        >
          <span class="size-4" :class="TIPOS[tipo].icone" />
        </span>
        <span class="min-w-0 flex-1">
          <span class="block text-sm font-medium text-n-slate-12">
            {{ t(`CRM_CALENDARIO.TIPO_LONGO.${tipo.toUpperCase()}`) }}
          </span>
          <span class="block text-xs text-n-slate-10">
            {{ t(`CRM_CALENDARIO.EXEMPLO.${tipo.toUpperCase()}`) }}
          </span>
        </span>
      </button>
    </div>

    <div class="flex flex-col gap-2">
      <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
        {{ t(`${N}.FEITOS_TITULO`) }}
      </h3>
      <button
        type="button"
        role="switch"
        data-mostrar-feitos
        :aria-checked="feitos"
        class="flex min-h-12 items-center gap-3 rounded-xl px-2 text-start hover:bg-n-alpha-2"
        @click="emit('update:feitos', !feitos)"
      >
        <span
          class="relative h-6 w-10 shrink-0 rounded-full transition"
          :class="feitos ? 'bg-n-blue-9' : 'bg-n-slate-6'"
          aria-hidden="true"
        >
          <span
            class="absolute top-0.5 size-5 rounded-full bg-white shadow transition-all"
            :class="feitos ? 'start-[1.125rem]' : 'start-0.5'"
          />
        </span>
        <span class="text-sm text-n-slate-12">{{ t(`${N}.FEITOS`) }}</span>
      </button>
      <template v-if="podeAgendamento || podeCaixas">
        <h3 class="mb-0 mt-3 text-sm font-semibold text-n-slate-11">
          {{ t(`${N}.CONFIG`) }}
        </h3>
        <button
          v-if="podeAgendamento"
          type="button"
          data-config="agendamento"
          class="flex min-h-11 items-center gap-2 rounded-xl px-2 text-start text-sm text-n-blue-11 hover:bg-n-alpha-2"
          @click="emit('abrirAgendamento')"
        >
          <span class="i-lucide-calendar-clock size-4" aria-hidden="true" />
          {{ t(`${N}.CONFIG_AGENDAMENTO`) }}
        </button>
        <button
          v-if="podeCaixas"
          type="button"
          data-config="caixas"
          class="flex min-h-11 items-center gap-2 rounded-xl px-2 text-start text-sm text-n-blue-11 hover:bg-n-alpha-2"
          @click="emit('abrirCaixas')"
        >
          <span class="i-lucide-inbox size-4" aria-hidden="true" />
          {{ t(`${N}.CONFIG_CAIXAS`) }}
        </button>
      </template>
      <button
        type="button"
        class="mt-auto min-h-11 self-end rounded-xl bg-n-alpha-2 px-5 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-3"
        @click="emit('fechar')"
      >
        {{ t(`${N}.PRONTO`) }}
      </button>
    </div>
  </section>
</template>
