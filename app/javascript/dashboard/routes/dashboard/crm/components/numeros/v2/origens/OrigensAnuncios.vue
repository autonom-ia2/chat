<script setup>
import { computed } from 'vue';
import { useNumerosFormato } from '../useNumerosFormato';

// Números › Origens (#2001, F6) — pergunta 2: "Qual anúncio me trouxe venda?". Cada anúncio com a miniatura e o título que
// a Meta manda junto da primeira mensagem (funciona sem o acesso ao gasto), por R$. Anúncio sem venda fica no
// fim, com "ainda sem venda". Com gasto conectado, cada linha ganha "gastou" e "por venda"; sem, nada disso.
// Ação única: "Ver os clientes deste anúncio". Sem foto guardada, um ícone no lugar.
const props = defineProps({
  anuncios: { type: Array, required: true },
  // "Todos os funis": sem lista única, a linha pede para escolher um funil.
  emTodos: { type: Boolean, default: false },
  moeda: { type: String, default: 'BRL' },
  destinoDe: { type: Function, required: true },
});

const O = 'CRM_NUMEROS_ORIGENS';
const { t, dinheiro } = useNumerosFormato(props.moeda);

// Nenhum anúncio com venda (funil sem venda no mês): a frase do resumo já diz; as linhas não repetem.
const semVenda = computed(() => props.anuncios.every(ad => !ad.vendas));
// Sem a permissão de ver valores de venda (#2075) o valor chega null: só a contagem.
const comValor = (texto, valor) =>
  valor === null ? texto : `${texto} · ${dinheiro(valor)}`;
const numerosDe = ad =>
  [
    t(`${O}.DE_ONDE.CLIENTES`, { n: ad.clientes }, ad.clientes),
    ad.vendas
      ? comValor(
          t(`${O}.DE_ONDE.VENDAS`, { n: ad.vendas }, ad.vendas),
          ad.valor
        )
      : !semVenda.value && t(`${O}.ANUNCIOS.SEM_VENDA`),
  ]
    .filter(Boolean)
    .join(' · ');

// Sem gasto conectado (ou gasto zero) o anúncio não traz `gasto`: nada de custo na linha.
const custoDe = ad =>
  ad.gasto === undefined
    ? ''
    : [
        t(`${O}.ANUNCIOS.GASTOU`, { valor: dinheiro(ad.gasto) }),
        ad.porVenda === null
          ? ''
          : t(`${O}.ANUNCIOS.POR_VENDA`, { valor: dinheiro(ad.porVenda) }),
      ]
        .filter(Boolean)
        .join(' · ');

const linhas = computed(() =>
  props.anuncios.map(ad => {
    const numeros = numerosDe(ad);
    const custo = custoDe(ad);
    const titulo = ad.titulo || t(`${O}.ANUNCIOS.SEM_NOME`);
    return {
      ...ad,
      titulo,
      numeros,
      custo,
      destino: props.destinoDe(ad.id),
      // Nome do link: a ação e o anúncio primeiro, depois os números.
      rotulo: t(`${O}.ANUNCIOS.VER_ARIA`, {
        anuncio: titulo,
        numeros: [numeros, custo].filter(Boolean).join(' · '),
      }),
    };
  })
);
</script>

<template>
  <section
    data-origens-bloco="anuncios"
    aria-labelledby="origens-anuncios"
    class="flex flex-col gap-3"
  >
    <h2
      id="origens-anuncios"
      class="mb-0 text-base font-semibold text-n-slate-12"
    >
      {{ t(`${O}.ANUNCIOS.TITULO`) }}
    </h2>
    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li v-for="ad in linhas" :key="ad.id">
        <component
          :is="ad.destino ? 'RouterLink' : 'div'"
          :to="ad.destino"
          :data-anuncio="ad.id"
          :data-clientes="ad.clientes"
          :data-lista="ad.lista"
          :aria-label="ad.destino ? ad.rotulo : undefined"
          class="flex min-h-11 items-start gap-3 rounded-xl bg-n-solid-1 p-3 ring-1 ring-inset ring-n-weak"
          :class="
            ad.destino
              ? 'group transition hover:bg-n-alpha-1 hover:ring-n-slate-6 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand motion-reduce:transition-none'
              : ''
          "
        >
          <img
            v-if="ad.miniatura"
            :src="ad.miniatura"
            alt=""
            width="64"
            height="64"
            class="size-16 shrink-0 rounded-lg object-cover"
          />
          <span
            v-else
            data-anuncio-sem-foto
            class="flex size-16 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-10"
            aria-hidden="true"
          >
            <span class="i-lucide-megaphone size-6" />
          </span>
          <span class="flex min-w-0 flex-1 flex-col gap-1">
            <span class="text-sm font-semibold text-n-slate-12">
              {{ ad.titulo }}
            </span>
            <span class="text-sm tabular-nums text-n-slate-11">
              {{ ad.numeros }}
            </span>
            <span
              v-if="ad.custo"
              data-anuncio-custo
              class="text-sm tabular-nums text-n-slate-11"
            >
              {{ ad.custo }}
            </span>
            <span
              v-if="ad.destino"
              aria-hidden="true"
              class="inline-flex items-center gap-1 text-sm font-medium text-n-blue-11 group-hover:underline"
            >
              {{ t(`${O}.ANUNCIOS.VER`) }}
              <span
                class="i-lucide-chevron-right size-4 rtl:rotate-180"
                aria-hidden="true"
              />
            </span>
            <span
              v-else-if="emTodos"
              data-origens-escolha-funil
              class="text-sm text-n-slate-11"
            >
              {{ t(`${O}.FUNIL.SEM_LISTA`) }}
            </span>
          </span>
        </component>
      </li>
    </ul>
  </section>
</template>
