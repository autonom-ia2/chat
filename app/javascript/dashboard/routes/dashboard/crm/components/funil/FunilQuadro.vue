<script setup>
import { computed, nextTick, onMounted, ref, useTemplateRef, watch } from 'vue';
import { useResizeObserver } from '@vueuse/core';

// #1384 — o Kanban em miniatura, só de leitura. Sai do mesmo estado do
// formulário: muda enquanto a pessoa preenche. A coluna em edição acende e a
// conversa nova aparece onde vai cair. Os cartões copiam o CrmKanbanCard
// (faixa da cor à esquerda, cantos de 1.25rem). Cada coluna tem largura
// mínima: o nome cabe em até duas linhas, sem hífen.
//
// Sempre colunas, como no Kanban de verdade, também no celular. Quando não
// cabem todas, o quadro rola para o lado só nesta área, e quatro sinais avisam:
// a coluna seguinte aparece cortada na borda, um degradê, as setas e o aviso
// escrito ("mais 3 etapas"). A coluna acesa ou onde a conversa chega rola
// sozinha até o meio, para nunca ficar escondida.
const props = defineProps({
  nome: { type: String, default: '' },
  // [{ chave, nome, cor, total (número ou null), falta (sem frase) }]
  etapas: { type: Array, required: true },
  acesa: { type: Number, default: -1 },
  chegando: { type: Number, default: -1 },
  exemplo: { type: String, default: '' },
});

const MAX_CARTOES = 3;
// Até cinco colunas dividem o quadro por igual. Com mais, a largura é de
// quatro colunas e meia: a quinta fica cortada ao meio na borda, o sinal mais
// claro de que o quadro continua. No celular, os 84 px mínimos já fazem
// sobrar colunas com cinco ou menos, e o quadro rola do mesmo jeito.
const MAX_LADO_A_LADO = 5;
const rola = computed(() => props.etapas.length > MAX_LADO_A_LADO);
// Um pixel de folga: o navegador arredonda a posição das colunas.
const FOLGA = 1;

const colunas = computed(() =>
  props.etapas.map((etapa, indice) => {
    const temTotal = Number.isFinite(etapa.total);
    const vagas = temTotal ? Math.min(etapa.total, MAX_CARTOES) : 2;
    const chega = indice === props.chegando;
    return {
      ...etapa,
      numero: indice + 1,
      acesa: indice === props.acesa,
      chega,
      temTotal,
      vazios: Math.max(vagas - (chega ? 1 : 0), 0),
    };
  })
);

const trilho = useTemplateRef('trilho');
// Quantas colunas estão escondidas (mesmo que só em parte) antes e depois.
const escondidas = ref({ antes: 0, depois: 0 });

const itens = () => [...(trilho.value?.children || [])];
const direitaParaEsquerda = () =>
  trilho.value && getComputedStyle(trilho.value).direction === 'rtl';

const medir = () => {
  const el = trilho.value;
  if (!el) return;
  const caixa = el.getBoundingClientRect();
  const rtl = direitaParaEsquerda();
  let antes = 0;
  let depois = 0;
  itens().forEach(item => {
    const r = item.getBoundingClientRect();
    const passaEsquerda = r.left < caixa.left - FOLGA;
    const passaDireita = r.right > caixa.right + FOLGA;
    if (rtl ? passaDireita : passaEsquerda) antes += 1;
    if (rtl ? passaEsquerda : passaDireita) depois += 1;
  });
  // Só troca quando muda: a rolagem suave chama isto a cada quadro.
  if (antes !== escondidas.value.antes || depois !== escondidas.value.depois)
    escondidas.value = { antes, depois };
};

// Desloca na horizontal pela distância física, que vale em LTR e RTL.
const deslocar = delta => {
  if (trilho.value && delta) trilho.value.scrollLeft += delta;
};

// A coluna em foco vai para o meio do quadro, com vizinhas dos dois lados.
const mostrarColuna = indice => {
  const el = trilho.value;
  const item = itens()[indice];
  if (!el || !item) return;
  const caixa = el.getBoundingClientRect();
  const r = item.getBoundingClientRect();
  if (r.left >= caixa.left - FOLGA && r.right <= caixa.right + FOLGA) {
    // Já inteira à vista: só recentra se estiver colada numa borda.
    const margem = Math.min(r.left - caixa.left, caixa.right - r.right);
    if (margem >= r.width / 2) return;
  }
  deslocar(r.left + r.width / 2 - (caixa.left + caixa.width / 2));
};

// A seta avança uma "página": a última coluna inteira daquele lado vai para a
// borda oposta, embaixo da outra seta, e serve de referência. Assim a coluna
// que estava cortada aparece inteira e livre, e nenhuma etapa é pulada. Tudo
// em posição física (esquerda/direita), que vale igual em LTR e RTL.
const rolar = sentido => {
  const el = trilho.value;
  if (!el) return;
  const caixa = el.getBoundingClientRect();
  const paraDireita = direitaParaEsquerda()
    ? sentido === 'antes'
    : sentido === 'depois';
  const lista = itens().map(item => item.getBoundingClientRect());
  const inteiras = lista.filter(
    r => r.left >= caixa.left - FOLGA && r.right <= caixa.right + FOLGA
  );
  if (paraDireita) {
    if (!lista.some(r => r.right > caixa.right + FOLGA)) return;
    const referencia = inteiras.reduce(
      (maisDireita, r) => (r.right > maisDireita.right ? r : maisDireita),
      inteiras[0]
    );
    if (referencia) deslocar(referencia.left - caixa.left);
  } else {
    if (!lista.some(r => r.left < caixa.left - FOLGA)) return;
    const referencia = inteiras.reduce(
      (maisEsquerda, r) => (r.left < maisEsquerda.left ? r : maisEsquerda),
      inteiras[0]
    );
    if (referencia) deslocar(referencia.right - caixa.right);
  }
};

const focoAlvo = computed(() =>
  props.acesa >= 0 ? props.acesa : props.chegando
);

// Ao montar e quando o quadro muda de largura (inclusive ao aparecer depois
// de montado), a coluna em foco volta para a vista.
const acompanhar = () => {
  if (focoAlvo.value >= 0) mostrarColuna(focoAlvo.value);
  medir();
};

watch(
  () => [focoAlvo.value, props.etapas.length],
  async () => {
    await nextTick();
    acompanhar();
  },
  { flush: 'post' }
);

// Se a seta em foco some (chegou ao fim), o foco passa para a do outro lado,
// em vez de cair no início da página.
const setaAntes = useTemplateRef('setaAntes');
const setaDepois = useTemplateRef('setaDepois');
watch(escondidas, async (agora, antes) => {
  const ativo = document.activeElement;
  const perdeuAntes = antes.antes && !agora.antes && ativo === setaAntes.value;
  const perdeuDepois =
    antes.depois && !agora.depois && ativo === setaDepois.value;
  if (!perdeuAntes && !perdeuDepois) return;
  await nextTick();
  (perdeuAntes ? setaDepois.value : setaAntes.value)?.focus();
});

useResizeObserver(trilho, acompanhar);
onMounted(acompanhar);
</script>

<template>
  <section
    data-funil-quadro
    class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-2.5 shadow-sm"
    :aria-label="$t('CRM_FUNIL.PREVIA.QUADRO', { nome })"
  >
    <header class="flex items-center gap-2 px-1">
      <span class="i-lucide-kanban size-4 text-n-slate-11" aria-hidden="true" />
      <span
        class="min-w-0 flex-1 truncate text-sm font-semibold text-n-slate-12"
      >
        {{ nome || $t('CRM_FUNIL.PREVIA.SEM_NOME') }}
      </span>
      <span class="shrink-0 text-xs text-n-slate-11">
        {{
          $t('CRM_FUNIL.PREVIA.COLUNAS', { n: etapas.length }, etapas.length)
        }}
      </span>
    </header>
    <div class="relative">
      <!-- 84 px no mínimo por coluna; o nome quebra em duas linhas, sem hífen. -->
      <ol
        ref="trilho"
        data-funil-quadro-trilho
        class="relative m-0 flex list-none gap-1 overflow-x-auto overscroll-x-contain p-0 pb-1 motion-safe:scroll-smooth"
        @scroll.passive="medir"
      >
        <li
          v-for="coluna in colunas"
          :key="coluna.chave"
          :data-coluna="coluna.nome"
          :aria-current="coluna.acesa ? 'true' : undefined"
          class="flex min-w-[5.25rem] shrink-0 grow flex-col gap-1.5 rounded-xl p-1 transition"
          :class="[
            rola
              ? 'basis-[calc((100%_-_1rem)/4.55)]'
              : 'basis-[calc((100%_-_1rem)/5)]',
            coluna.acesa
              ? 'bg-n-blue-2 ring-2 ring-inset ring-n-blue-8'
              : 'bg-n-alpha-2',
          ]"
        >
          <span class="flex items-center gap-1">
            <span
              class="grid size-5 shrink-0 place-items-center rounded-full text-xs font-bold"
              :class="
                coluna.acesa
                  ? 'bg-n-blue-9 text-white'
                  : 'bg-n-solid-1 text-n-slate-11'
              "
            >
              {{ coluna.numero }}
            </span>
            <span
              class="h-1 min-w-0 flex-1 rounded-full"
              :style="{ backgroundColor: coluna.cor }"
              aria-hidden="true"
            />
          </span>
          <span
            :title="coluna.nome"
            class="line-clamp-2 min-h-8 hyphens-none break-words px-0.5 text-xs font-semibold leading-4 text-n-slate-12"
          >
            {{ coluna.nome }}
          </span>
          <span v-if="coluna.temTotal" class="-mt-1 text-xs text-n-slate-11">
            {{
              $t('CRM_FUNIL.PREVIA.CLIENTES', { n: coluna.total }, coluna.total)
            }}
          </span>
          <span
            v-if="coluna.chega"
            data-chegando
            class="relative overflow-hidden rounded-[1.25rem] border border-n-teal-8 bg-n-solid-1 py-2 pe-1.5 ps-2.5 shadow-md"
          >
            <span
              class="absolute inset-y-0 start-0 w-[0.188rem]"
              :style="{ backgroundColor: coluna.cor }"
              aria-hidden="true"
            />
            <span class="flex items-center gap-1">
              <span
                class="size-3.5 shrink-0 rounded-full bg-n-blue-5"
                aria-hidden="true"
              />
              <span class="truncate text-xs font-semibold text-n-slate-12">
                {{ exemplo }}
              </span>
            </span>
            <span
              class="mt-1.5 block h-1 w-3/4 rounded-full bg-n-slate-4"
              aria-hidden="true"
            />
          </span>
          <span
            v-for="vazio in coluna.vazios"
            :key="vazio"
            aria-hidden="true"
            class="relative block h-9 overflow-hidden rounded-[1.25rem] border border-n-weak bg-n-solid-1"
          >
            <span
              class="absolute inset-y-0 start-0 w-[0.188rem] opacity-60"
              :style="{ backgroundColor: coluna.cor }"
            />
            <span
              class="ms-2.5 mt-2.5 block h-1 w-1/2 rounded-full bg-n-slate-4"
            />
            <span
              class="ms-2.5 mt-1.5 block h-1 w-1/3 rounded-full bg-n-slate-3"
            />
          </span>
          <span
            v-if="coluna.falta"
            class="rounded-lg border border-dashed border-n-amber-8 bg-n-amber-2 px-1 py-1 text-xs leading-4 text-n-amber-11"
          >
            {{ $t('CRM_FUNIL.PREVIA.FALTA') }}
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
        data-funil-quadro-antes
        class="absolute start-0 top-1/2 grid size-11 -translate-y-1/2 place-items-center rounded-full border border-n-weak bg-n-solid-1 text-n-slate-12 shadow-md hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :aria-label="
          $t(
            'CRM_FUNIL.PREVIA.VER_ANTES',
            { n: escondidas.antes },
            escondidas.antes
          )
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
        data-funil-quadro-depois
        class="absolute end-0 top-1/2 grid size-11 -translate-y-1/2 place-items-center rounded-full border border-n-weak bg-n-solid-1 text-n-slate-12 shadow-md hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :aria-label="
          $t(
            'CRM_FUNIL.PREVIA.VER_DEPOIS',
            { n: escondidas.depois },
            escondidas.depois
          )
        "
        @click="rolar('depois')"
      >
        <span
          class="i-lucide-chevron-right size-5 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
    </div>
    <!-- O aviso por escrito, para quem não percebe a coluna cortada. Parece
         link, então também rola; pelo teclado, quem rola são as setas. -->
    <div
      v-if="escondidas.antes || escondidas.depois"
      data-funil-quadro-aviso
      class="-mb-2 -mt-4 flex items-center px-1"
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
        {{
          $t(
            'CRM_FUNIL.PREVIA.MAIS_ANTES',
            { n: escondidas.antes },
            escondidas.antes
          )
        }}
      </button>
      <button
        v-if="escondidas.depois"
        type="button"
        tabindex="-1"
        class="ms-auto inline-flex min-h-11 items-center gap-1 text-xs font-semibold text-n-blue-11 hover:underline"
        @click="rolar('depois')"
      >
        {{
          $t(
            'CRM_FUNIL.PREVIA.MAIS_DEPOIS',
            { n: escondidas.depois },
            escondidas.depois
          )
        }}
        <span
          class="i-lucide-arrow-right size-3.5 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
    </div>
  </section>
</template>
