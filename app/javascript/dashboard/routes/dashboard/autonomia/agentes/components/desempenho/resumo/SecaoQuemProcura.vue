<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import LinkDaConversa from '../comum/LinkDaConversa.vue';
import MiniEstatistica from '../comum/MiniEstatistica.vue';
import RankingDeBarras from '../comum/RankingDeBarras.vue';
import { poucosCasos } from '../../../utils/desempenhoContrato';

// #2226 v2 (§2.9) — quem procura (tipos de pessoa dos dados) e quanto o uso se concentra em poucas
// conversas. Embaixo, as conversas que mais pedem e quantas fecharam: quem pede muito e não fecha
// pode estar fechando por outro caminho. O link leva à tabela completa, na aba Detalhe.
const props = defineProps({
  painel: { type: Object, required: true },
});

const emit = defineEmits(['detalhe']);

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.QUEM';
const LIMITE_DE_ATIVAS = 5;

const minusculo = texto =>
  String(texto || '').toLocaleLowerCase(fmt.idioma.value);
const quem = computed(() => props.painel.quem || {});
const ranking = computed(() =>
  (quem.value.ranking || []).map(linha => ({ ...linha, valor: linha.procuras }))
);
// "16,7% fecharam (1 de 6)"; com menos de 5 pedidos de compra, só a contagem e o aviso.
const fraseDaLinha = linha => {
  if (!linha.compra) return '';
  const valores = {
    pct: fmt.pct(linha.taxa_pct),
    n: fmt.n(linha.fecharam),
    m: fmt.n(linha.compra),
    fechou: minusculo(props.painel.meta.nomes.fechou),
  };
  return poucosCasos(linha.compra)
    ? fmt.t(`${NS}.FECHAM_POUCOS`, valores)
    : fmt.t(`${NS}.FECHAM`, valores);
};

const maisPedem = computed(() =>
  (props.painel.conversas_ativas || [])
    .filter(linha => linha.compra > 0)
    .slice(0, LIMITE_DE_ATIVAS)
);

const concentracao = computed(() => {
  const dados = quem.value.concentracao;
  if (!dados) return [];
  return [
    {
      id: 'compra',
      valor: fmt.n(dados.conversas_com_compra),
      legenda: fmt.t(`${NS}.CONVERSAS_COM_COMPRA`, {
        compra: minusculo(props.painel.meta.nomes.compra),
      }),
    },
    {
      id: 'fechamento',
      valor: fmt.n(dados.conversas_com_fechamento),
      legenda: fmt.t(`${NS}.CONVERSAS_FECHARAM`),
      cor: 'resultado',
    },
    {
      id: 'uma',
      valor: fmt.n(dados.conversas_uma_procura),
      legenda: fmt.t(`${NS}.UMA_VEZ`),
    },
    {
      id: 'top10',
      valor: fmt.pct(dados.top10_pct_da_compra),
      legenda: fmt.t(`${NS}.TOP10`, {
        compra: minusculo(props.painel.meta.nomes.compra),
      }),
      cor: 'volume',
    },
  ];
});
</script>

<template>
  <section
    id="quem"
    aria-labelledby="quem-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="quem-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />
    <div class="grid items-start gap-4 xl:grid-cols-2">
      <CartaoDoPainel
        :titulo="fmt.t(`${NS}.QUEM_E`)"
        :unidade="fmt.t(`${NS}.UNIDADE`)"
      >
        <RankingDeBarras
          :itens="ranking"
          cor="volume"
          :rotulo="fmt.t(`${NS}.QUEM_E`)"
        >
          <template #extra="{ item }">{{ fraseDaLinha(item) }}</template>
        </RankingDeBarras>
      </CartaoDoPainel>
      <CartaoDoPainel
        :titulo="fmt.t(`${NS}.CONCENTRACAO`)"
        :descricao="fmt.t(`${NS}.CONCENTRACAO_DESCRICAO`)"
      >
        <div class="grid grid-cols-2 gap-2">
          <MiniEstatistica
            v-for="item in concentracao"
            :key="item.id"
            :data-estatistica="item.id"
            :valor="item.valor"
            :legenda="item.legenda"
            :cor="item.cor || ''"
          />
        </div>
        <button
          type="button"
          data-ver-ativas
          class="self-start text-sm font-semibold rounded-md min-h-11 text-n-blue-11 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="emit('detalhe', { tabela: 'ativas' })"
        >
          {{ fmt.t(`${NS}.VER_ATIVAS`) }}
        </button>
      </CartaoDoPainel>
    </div>
    <CartaoDoPainel
      v-if="maisPedem.length"
      data-mais-pedem
      :titulo="
        fmt.t(`${NS}.MAIS_PEDEM`, {
          compra: minusculo(painel.meta.nomes.compra),
          fechou: minusculo(painel.meta.nomes.fechou),
        })
      "
      :descricao="fmt.t(`${NS}.MAIS_PEDEM_DESCRICAO`)"
    >
      <div class="overflow-x-auto">
        <table class="w-full text-sm border-collapse min-w-[32rem]">
          <thead>
            <tr class="text-xs text-start text-n-slate-11">
              <th scope="col" class="py-2 font-semibold text-start">
                {{ fmt.t(`${NS}.COL.CONVERSA`) }}
              </th>
              <th scope="col" class="py-2 font-semibold text-end">
                {{ painel.meta.nomes.compra }}
              </th>
              <th scope="col" class="py-2 font-semibold text-end">
                {{ painel.meta.nomes.fechou }}
              </th>
              <th scope="col" class="py-2 ps-4 font-semibold text-start">
                {{ fmt.t(`${NS}.COL.O_QUE_FAZER`) }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="linha in maisPedem"
              :key="linha.conversa"
              :data-mais-pedem-linha="linha.conversa"
            >
              <td class="py-1">
                <LinkDaConversa :prova="{ conversa: linha.conversa }" />
              </td>
              <td class="py-1 tabular-nums text-end text-n-slate-12">
                {{ fmt.n(linha.compra) }}
              </td>
              <td
                class="py-1 tabular-nums text-end"
                :class="linha.fecharam ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                {{ fmt.n(linha.fecharam) }}
              </td>
              <td class="py-1 text-xs ps-4 text-n-slate-11">
                {{
                  linha.fecharam
                    ? fmt.t(`${NS}.ACAO_OK`)
                    : fmt.t(`${NS}.ACAO_CONFERIR`, {
                        fechou: minusculo(painel.meta.nomes.fechou),
                      })
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </CartaoDoPainel>
  </section>
</template>
