<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { COR_DA_QUALIDADE, corDe } from '../../../utils/desempenhoCores';
import { nomeCurtoDoAgente } from '../../../utils/desempenhoContrato';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import LinkDaConversa from '../comum/LinkDaConversa.vue';
import MiniEstatistica from '../comum/MiniEstatistica.vue';
import RankingDeBarras from '../comum/RankingDeBarras.vue';
import Ressalva from '../comum/Ressalva.vue';
import RessalvasDaConferencia from '../comum/RessalvasDaConferencia.vue';

// #2226 v2 (§2.7) — como o agente se saiu: a barra empilhada (acertou, erro leve, erro grave; a base
// é quem o agente atendeu, e "não atuou" aparece só como contagem), o tempo de resposta, as regras
// mais quebradas com as conversas que provam, os temas em que ele vai bem e onde mais erra. Quando a
// conferência achou estes números otimistas, a ressalva diz, colada ao número.
const props = defineProps({
  painel: { type: Object, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.QUALIDADE';
const LIMITE_DE_REGRAS = 10;
// Só as 2 regras mais quebradas ficam em vermelho; o resto, em tom neutro.
const REGRAS_EM_ALERTA = 2;

const qualidade = computed(() => props.painel.qualidade || {});
const nome = computed(() =>
  nomeCurtoDoAgente(
    props.painel.meta.agente?.nome,
    fmt.t('AGENTS.DESEMPENHO2.A.COMUM.AGENTE')
  )
);

const partes = computed(() => {
  let inicio = 0;
  return (qualidade.value.distribuicao || []).map(parte => {
    const largura = Math.max(0, parte.pct || 0);
    const item = {
      ...parte,
      inicio,
      largura,
      cor: COR_DA_QUALIDADE[parte.id] || 'neutro',
    };
    inicio += largura;
    return item;
  });
});
const valorDaParte = parte =>
  parte.pct === null || parte.pct === undefined
    ? fmt.t(`${NS}.FORA_DA_BASE`)
    : fmt.pct(parte.pct);
const descricaoDaBarra = computed(() =>
  partes.value
    .map(
      parte =>
        `${fmt.t(`${NS}.DIST.${parte.id.toUpperCase()}`)} ${fmt.n(parte.procuras)} (${valorDaParte(parte)})`
    )
    .join(', ')
);

// O tempo típico e o "9 em cada 10" já estão nos números do topo; aqui ficam só os que existem aqui.
const estatisticas = computed(() => {
  const tempo = qualidade.value.tempo_resposta;
  const mensagens = qualidade.value.mensagens;
  const lista = [];
  if (tempo) {
    lista.push({
      id: 'lentas',
      valor: fmt.n(tempo.acima_5_min),
      legenda: fmt.t(`${NS}.ACIMA_5_MIN`),
      cor: 'tempo',
    });
  }
  if (mensagens?.agente_por_mensagem_do_contato) {
    lista.push({
      id: 'mensagens',
      valor: fmt.decimal(mensagens.agente_por_mensagem_do_contato),
      legenda: fmt.t(`${NS}.MENSAGENS`, { nome: nome.value }),
    });
  }
  return lista;
});

const otimista = computed(() =>
  (props.painel.confianca?.campos || []).find(
    campo =>
      campo.leitura === 'otimista' && (campo.afeta || []).includes('qualidade')
  )
);

const listas = computed(() => [
  {
    id: 'fortes',
    itens: qualidade.value.pontos_fortes || [],
    cor: 'resultado',
  },
  { id: 'piores', itens: qualidade.value.piores_temas || [], cor: 'alerta' },
]);

const regras = computed(() =>
  (qualidade.value.regras || []).map((regra, indice) => ({
    ...regra,
    valor: regra.procuras,
    cor: indice < REGRAS_EM_ALERTA ? 'alerta' : 'neutro',
  }))
);
</script>

<template>
  <section
    id="qualidade"
    aria-labelledby="qualidade-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="qualidade-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`, { nome })"
      :descricao="fmt.t(`${NS}.DESCRICAO`, { nome })"
    />
    <div class="grid items-start gap-4 xl:grid-cols-[1fr_1.45fr]">
      <div class="flex flex-col min-w-0 gap-4">
        <CartaoDoPainel
          :titulo="fmt.t(`${NS}.COMO_SE_SAIU`)"
          :descricao="
            fmt.t(`${NS}.COMO_SE_SAIU_DESCRICAO`, {
              n: fmt.n(qualidade.base),
              nome,
            })
          "
        >
          <svg
            data-barra-qualidade
            viewBox="0 0 100 16"
            preserveAspectRatio="none"
            class="w-full h-4 rounded-full"
            role="img"
            :aria-label="descricaoDaBarra"
          >
            <rect width="100" height="16" class="fill-n-slate-3" />
            <rect
              v-for="parte in partes"
              :key="parte.id"
              :x="parte.inicio"
              :width="parte.largura"
              height="16"
              :class="corDe(parte.cor).fill"
            />
          </svg>
          <ul class="grid grid-cols-2 p-0 m-0 list-none gap-x-4 gap-y-1.5">
            <li
              v-for="parte in partes"
              :key="parte.id"
              :data-qualidade="parte.id"
              class="flex items-center justify-between gap-2 text-sm"
            >
              <span class="flex items-center gap-1.5 text-n-slate-12">
                <span
                  class="rounded-full size-2.5"
                  :class="corDe(parte.cor).fundo"
                  aria-hidden="true"
                />
                {{ fmt.t(`${NS}.DIST.${parte.id.toUpperCase()}`) }}
              </span>
              <span class="tabular-nums">
                <strong class="font-semibold text-n-slate-12">{{
                  fmt.n(parte.procuras)
                }}</strong>
                <span class="ms-1 text-xs text-n-slate-11">{{
                  valorDaParte(parte)
                }}</span>
              </span>
            </li>
          </ul>
          <RessalvasDaConferencia :painel="painel" parte="qualidade" />
          <Ressalva
            v-if="otimista && !otimista.nota"
            data-otimista
            :destaque="
              fmt.t(`${NS}.OTIMISTA`, { pct: fmt.pct(otimista.acerto_pct) })
            "
            :texto="fmt.t(`${NS}.OTIMISTA_ERROS`)"
          />
          <div class="grid grid-cols-2 gap-2">
            <MiniEstatistica
              v-for="item in estatisticas"
              :key="item.id"
              :data-estatistica="item.id"
              :valor="item.valor"
              :legenda="item.legenda"
              :cor="item.cor || ''"
            />
          </div>
        </CartaoDoPainel>

        <CartaoDoPainel
          v-for="lista in listas"
          :key="lista.id"
          :data-lista="lista.id"
          :titulo="fmt.t(`${NS}.LISTA.${lista.id.toUpperCase()}`)"
        >
          <p v-if="!lista.itens.length" class="m-0 text-sm text-n-slate-11">
            {{ fmt.t('AGENTS.DESEMPENHO2.A.COMUM.NADA_NO_PERIODO') }}
          </p>
          <ul
            v-else
            class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak"
          >
            <li
              v-for="tema in lista.itens"
              :key="tema.tema_id"
              class="flex flex-col gap-0.5 py-2"
            >
              <span class="flex flex-wrap items-baseline justify-between gap-2">
                <span class="text-sm font-semibold text-n-slate-12">{{
                  tema.nome
                }}</span>
                <span
                  class="text-xs tabular-nums"
                  :class="corDe(lista.cor).texto"
                >
                  {{
                    lista.id === 'fortes'
                      ? fmt.t(`${NS}.ACERTO_EM`, {
                          pct: fmt.pct(tema.acerto_pct),
                          n: fmt.n(tema.procuras),
                        })
                      : fmt.t(`${NS}.ERRO_GRAVE_EM`, {
                          pct: fmt.pct(tema.erro_grave_pct),
                          acerto: fmt.pct(tema.acerto_pct),
                          n: fmt.n(tema.procuras),
                        })
                  }}
                </span>
              </span>
              <LinkDaConversa
                v-if="tema.exemplos?.length"
                :prova="tema.exemplos[0]"
                com-resumo
              />
            </li>
          </ul>
        </CartaoDoPainel>
      </div>

      <CartaoDoPainel
        data-regras
        :titulo="fmt.t(`${NS}.REGRAS`)"
        :descricao="fmt.t(`${NS}.REGRAS_DESCRICAO`, { nome })"
        :unidade="fmt.t(`${NS}.REGRAS_UNIDADE`)"
      >
        <RessalvasDaConferencia :painel="painel" parte="regras" />
        <RankingDeBarras
          :itens="regras"
          cor="alerta"
          :limite="LIMITE_DE_REGRAS"
          :rotulo="fmt.t(`${NS}.REGRAS`)"
        >
          <template #extra="{ item }">
            <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
              <span>{{ item.descricao }}</span>
              <span
                v-if="item.sistemica"
                data-sistemica
                class="px-2 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11 font-semibold"
              >
                {{ fmt.t(`${NS}.SISTEMICA`) }}
              </span>
            </span>
          </template>
        </RankingDeBarras>
      </CartaoDoPainel>
    </div>
  </section>
</template>
