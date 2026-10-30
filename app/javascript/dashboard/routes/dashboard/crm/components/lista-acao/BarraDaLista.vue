<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import MenuDeAcoes from './MenuDeAcoes.vue';
import { ABAS } from './grupos';

// #2283 — busca, "De todos | Só meus", Filtros, Mais e as abas "Mostrar".
// No celular: busca + Filtros numa linha, chave + Mais na outra, abas numa
// faixa rolável. Ganhos e Perdidos levam o nome do desfecho do funil (e do
// pacote do segmento: "Seguro ativo", "Não fechou").
const props = defineProps({
  quem: { type: String, required: true },
  aba: { type: String, required: true },
  totalAberto: { type: Number, default: 0 },
  // { ganho, perdido }: o nome do desfecho do funil (outcomeLabels).
  rotulosDasAbas: { type: Object, required: true },
  filtrosAtivos: { type: Number, default: 0 },
  podeBaixar: { type: Boolean, default: false },
  podeMarcar: { type: Boolean, default: false },
  // Abaixo de 1024 px o "Configurar" do topo vira item do "Mais" (Rodrigo, 28/10).
  podeConfigurar: { type: Boolean, default: false },
});
const emit = defineEmits(['quem', 'aba', 'filtros', 'mais']);
const busca = defineModel('busca', { type: String, default: '' });

const { t } = useI18n();
const L = 'CRM_LISTA_ACAO';
const QUEM = ['todos', 'meus'];
// A ordem do mockup aprovado (#2283, #2379): Baixar planilha · Organizar por ·
// Escolher o que aparece · Listas guardadas · Marcar vários · Configurar.
const itensMais = computed(() => [
  ...(props.podeBaixar
    ? [
        {
          chave: 'baixar',
          rotulo: t(`${L}.MAIS_MENU.BAIXAR`),
          icone: 'i-lucide-download',
        },
      ]
    : []),
  {
    chave: 'organizar',
    rotulo: t(`${L}.MAIS_MENU.ORGANIZAR`),
    icone: 'i-lucide-arrow-down-wide-narrow',
  },
  {
    chave: 'escolher',
    rotulo: t(`${L}.MAIS_MENU.ESCOLHER`),
    icone: 'i-lucide-columns-2',
  },
  {
    chave: 'listas',
    rotulo: t(`${L}.MAIS_MENU.LISTAS`),
    icone: 'i-lucide-bookmark',
  },
  ...(props.podeMarcar
    ? [
        {
          chave: 'marcar',
          rotulo: t(`${L}.MAIS_MENU.MARCAR_VARIOS`),
          icone: 'i-lucide-square-check',
          classe: 'md:hidden',
        },
      ]
    : []),
  ...(props.podeConfigurar
    ? [
        {
          chave: 'configurar',
          rotulo: t('CRM_KANBAN.ACTIONS.CONFIGURE'),
          icone: 'i-lucide-settings-2',
          classe: 'lg:hidden',
        },
      ]
    : []),
]);
const rotuloDaAba = aba =>
  props.rotulosDasAbas[aba] || t(`${L}.ABAS.${aba.toUpperCase()}`);
const classeDaAba = ativa =>
  ativa
    ? 'bg-n-slate-12 text-n-solid-1 font-semibold'
    : 'border border-solid border-n-weak bg-n-solid-1 text-n-slate-12 font-medium hover:bg-n-alpha-2';
const classeDoQuem = ativo =>
  ativo
    ? 'bg-n-solid-1 font-semibold shadow-sm text-n-slate-12 dark:bg-n-slate-12 dark:text-n-solid-1'
    : 'font-medium text-n-slate-11 hover:text-n-slate-12';
const mostraTotal = aba => aba === 'aberto' && props.aba === 'aberto';
</script>

<template>
  <section class="flex flex-col gap-3" :aria-label="t(`${L}.FILTROS`)">
    <div
      class="grid grid-cols-[minmax(0,1fr)_auto] gap-2 md:flex md:items-center"
    >
      <label class="relative md:order-1 md:flex-1">
        <span class="sr-only">{{ t(`${L}.BUSCA.ROTULO`) }}</span>
        <span
          class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-n-slate-11 md:left-4"
          aria-hidden="true"
        />
        <input
          v-model="busca"
          type="search"
          data-lista-acao-busca
          :placeholder="t(`${L}.BUSCA.PLACEHOLDER`)"
          class="reset-base !mb-0 min-h-12 w-full rounded-xl border border-solid border-n-weak bg-n-solid-1 !pl-10 pr-2 text-base text-n-slate-12 placeholder:text-n-slate-11 focus:outline-none focus:ring-2 focus:ring-n-brand md:!pl-12 md:pr-4"
        />
      </label>
      <button
        type="button"
        data-lista-acao-filtros
        class="inline-flex min-h-12 items-center justify-center gap-2 rounded-xl border border-solid border-n-weak bg-n-solid-1 px-3 text-base font-medium text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand md:order-3 md:px-4"
        @click="emit('filtros')"
      >
        <span class="i-lucide-list-filter size-5" aria-hidden="true" />
        {{ t(`${L}.FILTROS`) }}
        <span
          v-if="filtrosAtivos"
          class="grid h-6 min-w-6 place-items-center rounded-full bg-n-blue-3 px-1.5 text-sm font-semibold tabular-nums text-n-blue-11"
        >
          {{ filtrosAtivos }}
        </span>
      </button>
      <div
        class="flex min-w-0 rounded-xl bg-n-alpha-2 p-1 md:order-2"
        role="group"
        :aria-label="t(`${L}.QUEM.ROTULO`)"
      >
        <button
          v-for="opcao in QUEM"
          :key="opcao"
          type="button"
          :data-lista-acao-quem="opcao"
          :aria-pressed="quem === opcao"
          class="min-h-11 flex-1 whitespace-nowrap rounded-lg px-3 text-base focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand md:flex-none md:px-5"
          :class="classeDoQuem(quem === opcao)"
          @click="emit('quem', opcao)"
        >
          {{ t(`${L}.QUEM.${opcao === 'todos' ? 'TODOS' : 'MEUS'}`) }}
        </button>
      </div>
      <div class="grid md:order-4" data-lista-acao-mais>
        <MenuDeAcoes
          :rotulo-do-botao="t(`${L}.MAIS`)"
          :aria-label="t(`${L}.MAIS`)"
          :itens="itensMais"
          icone-do-botao="i-lucide-ellipsis"
          classe-do-botao="min-h-12 px-4"
          @escolher="emit('mais', $event)"
        />
      </div>
    </div>
    <div class="relative -mx-4 md:mx-0">
      <div
        class="flex gap-2 overflow-x-auto px-4 [scrollbar-width:none] md:flex-wrap md:px-0"
        role="group"
        :aria-label="t(`${L}.ABAS.ROTULO`)"
      >
        <button
          v-for="opcao in ABAS"
          :key="opcao"
          type="button"
          :data-lista-acao-aba="opcao"
          :aria-pressed="aba === opcao"
          class="inline-flex min-h-11 shrink-0 items-center gap-2 whitespace-nowrap rounded-full px-4 text-base focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="classeDaAba(aba === opcao)"
          @click="emit('aba', opcao)"
        >
          {{ rotuloDaAba(opcao) }}
          <span
            v-if="mostraTotal(opcao)"
            class="text-sm tabular-nums opacity-80"
          >
            {{ totalAberto }}
          </span>
        </button>
      </div>
      <span
        class="pointer-events-none absolute inset-y-0 right-0 w-10 bg-gradient-to-l from-n-background md:hidden"
        aria-hidden="true"
      />
    </div>
  </section>
</template>
