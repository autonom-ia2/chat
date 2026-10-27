<script setup>
import { computed, ref } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { nomeDe, poucosCasos } from '../../../utils/desempenhoContrato';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import EscolhaDoCartao from '../comum/EscolhaDoCartao.vue';
import RankingDeBarras from '../comum/RankingDeBarras.vue';
import RessalvasDaConferencia from '../comum/RessalvasDaConferencia.vue';

// #2226 v2 (§2.4) — do que as pessoas falam (temas) e o que pediram (os cortes da ficha). Cada linha
// diz quantas fecharam e, nos temas, o que mais trava e se subiu ou desceu contra o período anterior.
// O clique leva à aba Detalhe já filtrada.
const props = defineProps({
  painel: { type: Object, required: true },
});

const emit = defineEmits(['detalhe']);

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.TEMAS';

const minusculo = texto =>
  String(texto || '').toLocaleLowerCase(fmt.idioma.value);
const fechou = computed(() => minusculo(props.painel.meta.nomes.fechou));
const compra = computed(() => minusculo(props.painel.meta.nomes.compra));

// "8,6% fecharam (7 de 81)" quando houve pedido de compra naquele item (compra > 0); com menos de 5,
// só a contagem e o aviso de poucos casos. Sem pedido de compra, "Sem …" (nos cortes) ou nada.
const fraseDoResultado = (linha, semCompra = false) => {
  if (!linha.compra) {
    return semCompra ? fmt.t(`${NS}.SEM_COMPRA`, { compra: compra.value }) : '';
  }
  const valores = {
    n: fmt.n(linha.fecharam),
    m: fmt.n(linha.compra),
    fechou: fechou.value,
    pct: fmt.pct(linha.taxa_pct),
  };
  return poucosCasos(linha.compra)
    ? fmt.t(`${NS}.FECHARAM_POUCOS`, valores)
    : fmt.t(`${NS}.FECHARAM`, valores);
};

// A trava de um tema só aparece quando é diferente da trava mais comum do período (senão repete em
// toda linha); o % de erro grave aponta o que ensinar.
const travaGeral = computed(() => props.painel.motivos?.ranking?.[0]?.id);
const partesDoTema = tema =>
  [
    fraseDoResultado(tema),
    tema.erro_grave_pct
      ? fmt.t(`${NS}.ERRO_GRAVE`, { pct: fmt.pct(tema.erro_grave_pct) })
      : '',
    tema.trava ? fmt.t(`${NS}.MAIS_TRAVA`, { motivo: tema.trava }) : '',
  ]
    .filter(Boolean)
    .join(' · ');

const temas = computed(() =>
  (props.painel.temas?.ranking || []).map(tema => ({
    ...tema,
    valor: tema.procuras,
    trava:
      tema.motivo_principal_id && tema.motivo_principal_id !== travaGeral.value
        ? nomeDe(props.painel.catalogo, 'motivos', tema.motivo_principal_id)
        : null,
    mudou:
      tema.anterior_procuras === null || tema.anterior_procuras === undefined
        ? null
        : tema.procuras - tema.anterior_procuras,
  }))
);

const cortes = computed(() => props.painel.cortes || []);
const corteId = ref(cortes.value[0]?.id || '');
const opcoesDeCorte = computed(() =>
  cortes.value.map(corte => ({ value: corte.id, label: corte.nome }))
);
const corte = computed(
  () => cortes.value.find(item => item.id === corteId.value) || cortes.value[0]
);
const itensDoCorte = computed(() =>
  (corte.value?.ranking || []).map(linha => ({
    ...linha,
    valor: linha.procuras,
  }))
);

const SETA = { subiu: 'i-lucide-arrow-up', desceu: 'i-lucide-arrow-down' };
</script>

<template>
  <section
    id="temas"
    aria-labelledby="temas-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="temas-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />
    <div class="grid items-start gap-4 xl:grid-cols-2">
      <CartaoDoPainel
        data-temas
        :titulo="fmt.t(`${NS}.FALAM`)"
        :descricao="fmt.t(`${NS}.FALAM_DESCRICAO`)"
        :unidade="fmt.t(`${NS}.UNIDADE_TEMAS`)"
      >
        <RessalvasDaConferencia :painel="painel" parte="temas" />
        <RankingDeBarras
          :itens="temas"
          cor="volume"
          :rotulo="fmt.t(`${NS}.FALAM`)"
          clicavel
          @escolher="item => emit('detalhe', { tema: item.id })"
        >
          <template #extra="{ item }">
            <span class="flex flex-wrap items-center gap-x-3">
              <span v-if="partesDoTema(item)">{{ partesDoTema(item) }}</span>
              <span
                v-if="item.mudou"
                data-mudou
                class="inline-flex items-center gap-0.5"
                :class="item.mudou > 0 ? 'text-n-blue-11' : 'text-n-slate-11'"
              >
                <span
                  class="size-3"
                  :class="item.mudou > 0 ? SETA.subiu : SETA.desceu"
                  aria-hidden="true"
                />
                {{
                  fmt.t(item.mudou > 0 ? `${NS}.SUBIU` : `${NS}.DESCEU`, {
                    n: fmt.n(Math.abs(item.mudou)),
                  })
                }}
              </span>
            </span>
          </template>
        </RankingDeBarras>
      </CartaoDoPainel>

      <CartaoDoPainel
        v-if="corte"
        data-cortes
        :titulo="fmt.t(`${NS}.PEDIRAM`)"
        :descricao="fmt.t(`${NS}.PEDIRAM_DESCRICAO`, { n: fmt.n(corte.base) })"
        :unidade="fmt.t(`${NS}.UNIDADE_CORTES`)"
      >
        <template v-if="opcoesDeCorte.length > 1" #acoes>
          <EscolhaDoCartao
            v-model="corteId"
            :opcoes="opcoesDeCorte"
            :rotulo="fmt.t(`${NS}.ESCOLHER_CORTE`)"
          />
        </template>
        <RessalvasDaConferencia :painel="painel" parte="cortes" />
        <RankingDeBarras
          :itens="itensDoCorte"
          cor="preparo"
          :rotulo="corte.nome"
          clicavel
          @escolher="
            item => emit('detalhe', { corte: `${corte.id}:${item.id}` })
          "
        >
          <template #extra="{ item }">
            {{ fraseDoResultado(item, true) }}
          </template>
        </RankingDeBarras>
      </CartaoDoPainel>
    </div>
  </section>
</template>
