<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import {
  BORDA_DE_CIMA,
  corDe,
  serieDaEtapa,
} from '../../../utils/desempenhoCores';
import { MINIMO_DO_DESTAQUE } from '../../../utils/desempenhoContrato';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import Ressalva from '../comum/Ressalva.vue';

// #2226 v2 (§2.3) — até onde as procuras chegam: os passos do funil (nomes dos dados), cada um com o %
// do início e da etapa anterior, e por que o último passo e "fechou" não dão o mesmo número. Embaixo,
// o que muda o resultado (A × B), uma comparação por linha, com a ressalva de que aparecer junto não
// quer dizer que um causou o outro.
const props = defineProps({
  painel: { type: Object, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.FUNIL';
const VEZES_MINIMAS = 1.5;

const etapas = computed(() => props.painel.funil?.etapas || []);
const corDaEtapa = indice => serieDaEtapa(indice, etapas.value.length);
const fechou = computed(() => props.painel.meta.nomes.fechou);

// "Por que “Gerou o link” (13) e “Fecharam” (17) não dão o mesmo número: 1 chegou a este passo e
// não terminou em “Fecharam”; 5 terminaram em “Fecharam” sem passar por este passo."
const conciliacao = computed(() => {
  const dados = props.painel.funil?.conciliacao;
  const ultima = etapas.value[etapas.value.length - 1];
  if (!dados || !ultima) return '';
  const partes = [];
  if (dados.chegaram_e_nao_fecharam) {
    partes.push(
      fmt.t(
        `${NS}.CONCILIACAO_NAO_FECHARAM`,
        { n: fmt.n(dados.chegaram_e_nao_fecharam), fechou: fechou.value },
        dados.chegaram_e_nao_fecharam
      )
    );
  }
  if (dados.fecharam_sem_chegar) {
    partes.push(
      fmt.t(
        `${NS}.CONCILIACAO_FORA`,
        { n: fmt.n(dados.fecharam_sem_chegar), fechou: fechou.value },
        dados.fecharam_sem_chegar
      )
    );
  }
  if (!partes.length) return '';
  return fmt.t(`${NS}.CONCILIACAO`, {
    etapa: ultima.nome,
    a: fmt.n(dados.chegaram_ao_fim),
    fechou: fechou.value,
    b: fmt.n(dados.fecharam),
    partes: partes.join('; '),
  });
});

// Uma comparação A × B só vale com pelo menos MINIMO_DO_DESTAQUE de base em cada lado (igual ao PDF);
// abaixo, a taxa aparece sem destaque e o meio diz "poucos casos para comparar".
const ladoFraco = lado => !lado.m || lado.m < MINIMO_DO_DESTAQUE;

// "7,4× mais" e "2,1 pontos a mais" pela conta exata (n/m de cada lado), arredondando só no fim,
// nunca pelos % já arredondados.
const diferenca = comparacao => {
  const { a, b } = comparacao;
  if (a.pct === null || b.pct === null) return '';
  if (ladoFraco(a) || ladoFraco(b)) return fmt.t(`${NS}.SEM_COMPARAR`);
  const taxaA = a.n / a.m;
  const taxaB = b.n / b.m;
  if (taxaB > 0 && taxaA / taxaB >= VEZES_MINIMAS) {
    return fmt.t(`${NS}.VEZES`, { x: fmt.decimal(taxaA / taxaB) });
  }
  const bruto = (taxaA - taxaB) * 100;
  const pontos = (Math.sign(bruto) * Math.round(Math.abs(bruto) * 10)) / 10;
  if (!pontos) return fmt.t(`${NS}.IGUAL`);
  return fmt.t(pontos > 0 ? `${NS}.PONTOS_A_MAIS` : `${NS}.PONTOS_A_MENOS`, {
    pontos: fmt.pontos(Math.abs(pontos)),
  });
};
const recorteDe = comparacao =>
  fmt.tSeTiver(
    `${NS}.RECORTE.${String(comparacao.recorte).toUpperCase()}`,
    fmt.t(`${NS}.RECORTE.OUTRO`)
  );
const comparacoes = computed(() =>
  (props.painel.comparacoes || []).slice(0, 3)
);
</script>

<template>
  <section
    id="funil"
    aria-labelledby="funil-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="funil-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />
    <CartaoDoPainel
      :titulo="fmt.t(`${NS}.MARCOS`)"
      :descricao="
        fmt.t(`${NS}.MARCOS_DESCRICAO`, { n: fmt.n(painel.funil?.base) })
      "
      :unidade="painel.funil?.nota || ''"
    >
      <ol
        data-funil
        class="grid grid-cols-2 gap-3 p-0 m-0 list-none md:grid-cols-3 2xl:grid-cols-6"
      >
        <li
          v-for="(etapa, i) in etapas"
          :key="etapa.id"
          data-etapa
          class="relative flex flex-col gap-1 p-4 rounded-2xl"
          :class="[
            corDe(corDaEtapa(i)).fundoSuave,
            BORDA_DE_CIMA[corDaEtapa(i)],
          ]"
        >
          <span
            v-if="i"
            class="absolute items-center hidden -translate-y-1/2 2xl:flex top-1/2 -start-3"
            aria-hidden="true"
          >
            <span class="w-2 h-px bg-n-weak" />
            <span class="rounded-full size-1.5 bg-n-slate-8" />
          </span>
          <span
            class="text-xs font-semibold text-n-slate-12 line-clamp-2 min-h-8"
          >
            {{ etapa.nome }}
          </span>
          <span
            class="text-4xl font-bold leading-none tabular-nums"
            :class="corDe(corDaEtapa(i)).texto"
          >
            {{ fmt.n(etapa.procuras) }}
          </span>
          <span class="text-xs tabular-nums text-n-slate-11">
            {{
              fmt.t(`${NS}.DO_INICIO`, { pct: fmt.pct(etapa.pct_do_inicio) })
            }}
          </span>
          <span
            v-if="i && etapa.taxa_da_anterior !== null"
            class="text-xs tabular-nums text-n-slate-11"
          >
            {{
              fmt.t(`${NS}.DA_ANTERIOR`, {
                pct: fmt.pct(etapa.taxa_da_anterior),
              })
            }}
          </span>
        </li>
      </ol>
      <p
        v-if="conciliacao"
        data-conciliacao
        class="m-0 text-xs text-n-slate-12 tabular-nums"
      >
        {{ conciliacao }}
      </p>
    </CartaoDoPainel>

    <CartaoDoPainel
      v-if="comparacoes.length"
      data-comparacoes
      :titulo="fmt.t(`${NS}.COMPARACOES`)"
      :descricao="fmt.t(`${NS}.COMPARA_DESCRICAO`, { fechou })"
    >
      <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
        <li
          v-for="comparacao in comparacoes"
          :key="comparacao.id"
          data-comparacao
          class="grid items-center grid-cols-1 gap-x-4 gap-y-2 py-3 sm:grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] md:grid-cols-[10rem_minmax(0,1fr)_9rem_minmax(0,1fr)]"
        >
          <h4
            class="m-0 text-sm font-semibold sm:col-span-3 md:col-span-1 text-n-slate-12"
          >
            {{ recorteDe(comparacao) }}
          </h4>
          <div
            v-for="(lado, posicao) in [comparacao.a, null, comparacao.b]"
            :key="posicao"
            class="flex min-w-0"
            :class="
              lado
                ? 'flex-col gap-0.5'
                : 'flex-row items-center gap-2 sm:flex-col sm:justify-center sm:text-center'
            "
          >
            <template v-if="lado">
              <span class="flex flex-wrap items-baseline gap-x-2 tabular-nums">
                <span
                  class="text-2xl font-bold leading-none"
                  :class="
                    posicao === 0 && !ladoFraco(lado)
                      ? 'text-n-teal-11'
                      : 'text-n-slate-12'
                  "
                >
                  {{ fmt.pct(lado.pct) }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{
                    fmt.t(`${NS}.N_DE_M`, {
                      n: fmt.n(lado.n),
                      m: fmt.n(lado.m),
                    })
                  }}
                </span>
              </span>
              <span class="text-sm text-n-slate-12">{{ lado.nome }}</span>
            </template>
            <template v-else>
              <span
                class="i-lucide-arrow-left-right size-4 shrink-0 text-n-slate-10 rotate-90 sm:rotate-0"
                aria-hidden="true"
              />
              <span
                data-diferenca
                :data-poucos-casos="
                  ladoFraco(comparacao.a) || ladoFraco(comparacao.b)
                    ? ''
                    : undefined
                "
                class="text-xs font-semibold tabular-nums"
                :class="
                  ladoFraco(comparacao.a) || ladoFraco(comparacao.b)
                    ? 'text-n-amber-11'
                    : 'text-n-slate-12'
                "
              >
                {{ diferenca(comparacao) }}
              </span>
            </template>
          </div>
          <p
            v-if="comparacao.ressalva"
            class="m-0 text-xs sm:col-span-3 md:col-span-4 text-n-slate-11"
          >
            {{ comparacao.ressalva }}
          </p>
        </li>
      </ul>
      <Ressalva data-nao-causa :texto="fmt.t(`${NS}.NAO_CAUSA`)" />
    </CartaoDoPainel>
  </section>
</template>
