<script setup>
import { computed, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import PreviaSelo from './PreviaSelo.vue';
import { MAX_COLUNAS_LADO_A_LADO, useTrilhoRolagem } from './useTrilhoRolagem';
import { ETAPA_PROPRIA, etapaLigada, textoDoJeito } from '../passagem';

// #1385 — o quadro do funil em miniatura, com o que vale em cada coluna: chama a equipe, não chama, ou o jeito da
// etapa feita do seu jeito. Sempre colunas, como o Kanban e o quadro do funil (#1384): até cinco dividem a largura;
// com mais (ou quando a tela é estreita demais para a largura mínima, como no celular), o quadro rola para o lado só
// nesta área (useTrilhoRolagem). A coluna acesa é a aberta e rola até o meio.
// Com `selo`, ganha "Agora": é o pedaço real da prévia.
const props = defineProps({
  nome: { type: String, default: '' },
  etapas: { type: Array, required: true },
  regra: { type: Object, required: true },
  pessoas: { type: Array, default: () => [] },
  acesa: { type: [Number, String], default: null },
  selo: { type: String, default: '' },
});

const { t, locale } = useI18n();
const P = 'CRM_KANBAN.PASSAGEM.PREVIA';

const rola = computed(() => props.etapas.length > MAX_COLUNAS_LADO_A_LADO);
// Hifenização desligada: o nome quebra em até duas linhas inteiras. O idioma vai em BCP 47 para o leitor de tela.
const idioma = computed(() => String(locale.value).replaceAll('_', '-'));

const estado = etapa => {
  if (etapa.modo === ETAPA_PROPRIA) return 'PROPRIA';
  return etapaLigada(etapa, props.regra) ? 'PASSA' : 'NAO';
};
const COR = {
  PASSA: {
    barra: 'bg-n-teal-9',
    texto: 'text-n-teal-11',
    icone: 'i-lucide-users',
  },
  PROPRIA: {
    barra: 'bg-n-blue-9',
    texto: 'text-n-blue-11',
    icone: 'i-lucide-sparkles',
  },
  NAO: {
    barra: 'bg-n-slate-6',
    texto: 'text-n-slate-11',
    icone: 'i-lucide-bot',
  },
};
// Na etapa do seu jeito, a coluna diz o jeito em poucas palavras ("Convite para Bruno").
const texto = etapa =>
  estado(etapa) === 'PROPRIA'
    ? textoDoJeito(t, etapa.regra, props.pessoas)
    : t(`${P}.QUADRO.${estado(etapa)}`);

const trilho = useTemplateRef('trilho');
const indiceAceso = () =>
  props.etapas.findIndex(etapa => etapa.id === props.acesa);
const { escondidas, medir, rolar, setaAntes, setaDepois } = useTrilhoRolagem({
  trilho,
  foco: indiceAceso,
  total: () => props.etapas.length,
});
</script>

<template>
  <section
    data-previa-colunas
    class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
    :aria-label="t(`${P}.QUADRO_ROTULO`, { nome })"
  >
    <header class="flex flex-wrap items-center gap-2">
      <PreviaSelo v-if="selo" :tipo="selo" />
      <span class="i-lucide-kanban size-4 text-n-slate-11" aria-hidden="true" />
      <h3
        class="mb-0 min-w-0 flex-1 truncate text-sm font-semibold text-n-slate-12"
      >
        {{ nome }}
      </h3>
      <span class="shrink-0 text-xs text-n-slate-11">
        {{ t(`${P}.COLUNAS`, { n: etapas.length }, etapas.length) }}
      </span>
    </header>
    <div class="relative">
      <ol
        ref="trilho"
        data-previa-trilho
        :lang="idioma"
        class="relative m-0 flex snap-x snap-proximity list-none gap-1 overflow-x-auto overscroll-x-contain p-0 pb-1 motion-safe:scroll-smooth"
        @scroll.passive="medir"
      >
        <li
          v-for="(etapa, posicao) in etapas"
          :key="etapa.id"
          :data-coluna="etapa.nome"
          :aria-current="etapa.id === acesa ? 'true' : undefined"
          class="flex min-h-28 min-w-[5.25rem] shrink-0 grow snap-start flex-col gap-1.5 rounded-xl px-1.5 py-2"
          :class="[
            rola
              ? 'basis-[calc((100%_-_1rem)/4.55)]'
              : 'basis-[calc((100%_-_1rem)/5)]',
            etapa.id === acesa
              ? 'bg-n-blue-2 ring-2 ring-inset ring-n-blue-8'
              : 'bg-n-alpha-1',
          ]"
        >
          <span class="flex items-center gap-1.5">
            <span class="text-xs font-semibold text-n-slate-11">{{
              posicao + 1
            }}</span>
            <span
              class="h-1 flex-1 rounded-full"
              :class="COR[estado(etapa)].barra"
              aria-hidden="true"
            />
          </span>
          <span
            :title="etapa.nome"
            class="line-clamp-2 hyphens-none break-words text-xs font-semibold leading-4 text-n-slate-12"
          >
            {{ etapa.nome }}
          </span>
          <span
            class="mt-auto flex items-start gap-1 text-xs leading-4"
            :class="COR[estado(etapa)].texto"
          >
            <span
              class="size-3.5 shrink-0"
              :class="COR[estado(etapa)].icone"
              aria-hidden="true"
            />
            <span class="line-clamp-2 min-w-0">{{ texto(etapa) }}</span>
          </span>
        </li>
      </ol>
      <!-- Degradê e seta só do lado em que há mais colunas. -->
      <div
        v-if="escondidas.antes"
        class="pointer-events-none absolute inset-y-0 start-0 w-10 from-n-solid-1 to-transparent ltr:bg-gradient-to-r rtl:bg-gradient-to-l"
        aria-hidden="true"
      />
      <div
        v-if="escondidas.depois"
        class="pointer-events-none absolute inset-y-0 end-0 w-10 from-n-solid-1 to-transparent ltr:bg-gradient-to-l rtl:bg-gradient-to-r"
        aria-hidden="true"
      />
      <button
        v-if="escondidas.antes"
        ref="setaAntes"
        type="button"
        data-previa-antes
        class="absolute start-0 top-1/2 grid size-11 -translate-y-1/2 place-items-center rounded-full border border-n-weak bg-n-solid-1 text-n-slate-12 shadow-md hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :aria-label="
          t(`${P}.VER_ANTES`, { n: escondidas.antes }, escondidas.antes)
        "
        @click="rolar('antes')"
      >
        <span
          class="i-lucide-chevron-left size-5 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
      <button
        v-if="escondidas.depois"
        ref="setaDepois"
        type="button"
        data-previa-depois
        class="absolute end-0 top-1/2 grid size-11 -translate-y-1/2 place-items-center rounded-full border border-n-weak bg-n-solid-1 text-n-slate-12 shadow-md hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :aria-label="
          t(`${P}.VER_DEPOIS`, { n: escondidas.depois }, escondidas.depois)
        "
        @click="rolar('depois')"
      >
        <span
          class="i-lucide-chevron-right size-5 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
    </div>
    <!-- O aviso por escrito, para quem não percebe a coluna cortada. Parece link, então também rola; pelo teclado,
         quem rola são as setas. -->
    <div
      v-if="escondidas.antes || escondidas.depois"
      data-previa-aviso
      class="-mb-2 -mt-4 flex items-center"
    >
      <button
        v-if="escondidas.antes"
        type="button"
        tabindex="-1"
        class="inline-flex min-h-11 items-center gap-1 text-xs font-semibold text-n-blue-11 hover:underline"
        @click="rolar('antes')"
      >
        <span
          class="i-lucide-arrow-left size-3.5 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t(`${P}.MAIS_ANTES`, { n: escondidas.antes }, escondidas.antes) }}
      </button>
      <button
        v-if="escondidas.depois"
        type="button"
        tabindex="-1"
        class="ms-auto inline-flex min-h-11 items-center gap-1 text-xs font-semibold text-n-blue-11 hover:underline"
        @click="rolar('depois')"
      >
        {{ t(`${P}.MAIS_DEPOIS`, { n: escondidas.depois }, escondidas.depois) }}
        <span
          class="i-lucide-arrow-right size-3.5 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
    </div>
  </section>
</template>
