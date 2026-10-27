<script setup>
import { computed, ref } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import {
  MINIMO_DO_DESTAQUE,
  pct as pctDe,
  podeDestacar,
  poucosCasos,
} from '../../../utils/desempenhoContrato';
import { picoDoMapa } from '../../../utils/desempenhoGrafico';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import MiniEstatistica from '../comum/MiniEstatistica.vue';
import Segmento from '../comum/Segmento.vue';
import MapaDeCalor from './MapaDeCalor.vue';

// #2226 v2 (§2.6) — quando a demanda chega, para dimensionar a equipe: o mapa de calor 7×24 sempre
// visível na largura toda (as 24 horas e o Total), com a troca para "ficaram sem uma pessoa" (em que
// hora a fila da equipe falha). Embaixo, a tabela de quando chega e quanto fecha (no horário, fora,
// fim de semana e noite) e o resumo de quando a fila falha. O fuso é o da conta.
const props = defineProps({
  painel: { type: Object, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.HORARIOS';
const FAIXAS = ['dentro', 'fora', 'fim_de_semana', 'noite'];

const horarios = computed(
  () => props.painel.horarios || { mapa: [], faixas: {} }
);
const meta = computed(() => props.painel.meta);
const minusculo = texto =>
  String(texto || '').toLocaleLowerCase(fmt.idioma.value);

const visao = ref('procuras');
const temMapaSemPessoa = computed(() =>
  Boolean(horarios.value.mapa_sem_pessoa?.length)
);
const opcoesDoMapa = computed(() => [
  { value: 'procuras', label: fmt.t(`${NS}.VISAO.PROCURAS`) },
  { value: 'sem_pessoa', label: fmt.t(`${NS}.VISAO.SEM_PESSOA`) },
]);
const mapaVisivel = computed(() =>
  visao.value === 'sem_pessoa' && temMapaSemPessoa.value
    ? horarios.value.mapa_sem_pessoa
    : horarios.value.mapa || []
);

const pico = computed(() => picoDoMapa(mapaVisivel.value));
const picoSemPessoa = computed(() =>
  picoDoMapa(horarios.value.mapa_sem_pessoa || [])
);

const nomeDoFuso = computed(() => fmt.fuso(meta.value.fuso));

const somaDoMapa = mapa => mapa.flat().reduce((acc, valor) => acc + valor, 0);

const estatisticas = computed(() => {
  const semPessoa = visao.value === 'sem_pessoa';
  const lista = [];
  if (pico.value.valor) {
    lista.push({
      id: 'pico',
      valor: fmt.n(pico.value.valor),
      legenda: fmt.t(`${NS}.PICO`, {
        dia: fmt.diaDaSemanaLongo(pico.value.dia),
        hora: pico.value.hora,
      }),
      cor: semPessoa ? 'alerta' : 'volume',
    });
  }
  lista.push({
    id: 'total',
    valor: fmt.n(somaDoMapa(mapaVisivel.value)),
    legenda: fmt.t(
      semPessoa ? `${NS}.TOTAL_SEM_PESSOA` : `${NS}.TOTAL_PROCURAS`
    ),
  });
  if (!semPessoa && horarios.value.faixas?.fora) {
    lista.push({
      id: 'fora',
      valor: fmt.pct(horarios.value.faixas.fora.pct),
      legenda: fmt.t(`${NS}.FORA_DO_HORARIO`),
      cor: 'tempo',
    });
  }
  return lista;
});

// Onde a fila da equipe falha: quantas ficaram sem uma pessoa, quantas fora do horário e o pico.
const fila = computed(() => {
  const pessoa = props.painel.pessoa || {};
  if (!pessoa.sem_pessoa) return [];
  const lista = [
    {
      id: 'sem',
      valor: fmt.n(pessoa.sem_pessoa),
      legenda: fmt.t(`${NS}.FILA.SEM`, { m: fmt.n(pessoa.precisavam) }),
      cor: 'alerta',
    },
    {
      id: 'fora',
      valor: fmt.pct(
        pctDe(pessoa.sem_pessoa_fora_do_horario, pessoa.sem_pessoa)
      ),
      legenda: fmt.t(`${NS}.FILA.FORA`, {
        n: fmt.n(pessoa.sem_pessoa_fora_do_horario),
      }),
      cor: 'tempo',
    },
  ];
  if (picoSemPessoa.value.valor) {
    lista.push({
      id: 'pico',
      valor: fmt.n(picoSemPessoa.value.valor),
      legenda: fmt.t(`${NS}.FILA.PICO`, {
        dia: fmt.diaDaSemanaLongo(picoSemPessoa.value.dia),
        hora: picoSemPessoa.value.hora,
      }),
    });
  }
  return lista;
});

const linhas = computed(() =>
  FAIXAS.filter(id => horarios.value.faixas?.[id]).map(id => {
    const faixa = horarios.value.faixas[id];
    return {
      id,
      ...faixa,
      sem_pessoa: Math.max(
        0,
        (faixa.precisavam_pessoa || 0) - (faixa.tiveram_pessoa || 0)
      ),
    };
  })
);
// A maior taxa em destaque, só entre as linhas com base suficiente para destacar.
const melhorTaxa = computed(() =>
  Math.max(
    -1,
    ...linhas.value
      .filter(linha => podeDestacar(linha.compra))
      .map(linha => linha.taxa_pct ?? -1)
  )
);

// "seg a sex" quando os dias são seguidos; senão, a lista ("seg, qua, sex").
const diasDoHorario = computed(() => {
  const dias = [...(meta.value.horario_comercial?.dias_semana || [])].sort(
    (a, b) => a - b
  );
  if (!dias.length) return '';
  const nomes = dias.map(dia => minusculo(fmt.diaDaSemana(dia - 1)));
  const seguidos = dias.every((dia, i) => !i || dia === dias[i - 1] + 1);
  if (seguidos && dias.length > 2) {
    return fmt.t(`${NS}.DIAS_SEGUIDOS`, {
      de: nomes[0],
      ate: nomes[nomes.length - 1],
    });
  }
  return nomes.join(', ');
});
const notaDoHorario = computed(() => {
  const horario = meta.value.horario_comercial;
  if (!horario) return '';
  return fmt.t(`${NS}.HORARIO_COMERCIAL`, {
    dias: diasDoHorario.value,
    inicio: horario.inicio_hora,
    fim: horario.fim_hora,
  });
});
</script>

<template>
  <section
    id="horarios"
    aria-labelledby="horarios-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="horarios-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />
    <CartaoDoPainel
      :titulo="
        fmt.t(
          visao === 'sem_pessoa' ? `${NS}.MAPA_SEM_PESSOA` : `${NS}.MAPA_TITULO`
        )
      "
      :descricao="nomeDoFuso ? fmt.t(`${NS}.FUSO`, { fuso: nomeDoFuso }) : ''"
      :unidade="
        fmt.t(
          visao === 'sem_pessoa' ? `${NS}.UNIDADE_SEM_PESSOA` : `${NS}.UNIDADE`
        )
      "
    >
      <template v-if="temMapaSemPessoa" #acoes>
        <Segmento
          v-model="visao"
          data-visao-mapa
          :opcoes="opcoesDoMapa"
          :rotulo="fmt.t(`${NS}.VISAO.ROTULO`)"
        />
      </template>
      <div class="grid grid-cols-3 gap-2 sm:flex sm:flex-wrap">
        <MiniEstatistica
          v-for="item in estatisticas"
          :key="item.id"
          :data-estatistica="item.id"
          :valor="item.valor"
          :legenda="item.legenda"
          :cor="item.cor || ''"
        />
      </div>
      <MapaDeCalor
        v-if="mapaVisivel.length"
        :mapa="mapaVisivel"
        :tom="visao === 'sem_pessoa' ? 'alerta' : 'volume'"
        :rotulo="
          fmt.t(
            visao === 'sem_pessoa'
              ? `${NS}.MAPA_SEM_PESSOA`
              : `${NS}.MAPA_ROTULO`
          )
        "
      />
    </CartaoDoPainel>

    <div class="flex flex-col gap-4">
      <CartaoDoPainel
        data-faixas
        :titulo="
          fmt.t(`${NS}.FAIXAS_TITULO`, { fechou: painel.meta.nomes.fechou })
        "
        :descricao="fmt.t(`${NS}.FAIXAS_DESCRICAO`)"
        :unidade="notaDoHorario"
      >
        <!-- Em tela estreita, uma faixa por bloco: o que importa (fecharam, taxa, sem pessoa) sem rolar. -->
        <ul
          data-faixas-lista
          class="flex flex-col gap-2 p-0 m-0 list-none sm:hidden"
        >
          <li
            v-for="linha in linhas"
            :key="linha.id"
            :data-faixa-horario-lista="linha.id"
            class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1"
          >
            <span class="text-sm font-semibold text-n-slate-12">
              {{ fmt.t(`${NS}.FAIXA.${linha.id.toUpperCase()}`) }}
            </span>
            <dl class="grid grid-cols-3 gap-2 m-0 tabular-nums">
              <div class="flex flex-col min-w-0">
                <dt class="text-xs text-n-slate-11">
                  {{ painel.meta.nomes.fechou }}
                </dt>
                <dd class="m-0 text-sm font-semibold text-n-slate-12">
                  {{
                    fmt.t(`${NS}.N_DE_M`, {
                      n: fmt.n(linha.fecharam),
                      m: fmt.n(linha.compra),
                    })
                  }}
                </dd>
              </div>
              <div class="flex flex-col min-w-0">
                <dt class="text-xs text-n-slate-11">
                  {{ fmt.t(`${NS}.COL.TAXA`) }}
                </dt>
                <dd
                  class="m-0 text-sm font-semibold"
                  :class="
                    linha.taxa_pct !== null && linha.taxa_pct === melhorTaxa
                      ? 'text-n-teal-11'
                      : 'text-n-slate-12'
                  "
                >
                  {{ fmt.pct(linha.taxa_pct) }}
                  <span
                    v-if="poucosCasos(linha.compra)"
                    class="block text-xs font-normal text-n-amber-11"
                  >
                    {{ fmt.t('AGENTS.DESEMPENHO2.A.COMUM.POUCOS_CASOS') }}
                  </span>
                </dd>
              </div>
              <div class="flex flex-col min-w-0">
                <dt class="text-xs text-n-slate-11">
                  {{ fmt.t(`${NS}.COL.SEM_PESSOA`) }}
                </dt>
                <dd
                  class="m-0 text-sm font-semibold"
                  :class="
                    linha.sem_pessoa ? 'text-n-ruby-11' : 'text-n-slate-11'
                  "
                >
                  {{ fmt.n(linha.sem_pessoa) }}
                </dd>
              </div>
            </dl>
            <span class="text-xs text-n-slate-11">
              {{
                fmt.t(`${NS}.PROCURAS_DO_TOTAL`, {
                  n: fmt.n(linha.procuras),
                  pct: fmt.pct(linha.pct),
                })
              }}
            </span>
          </li>
        </ul>
        <div class="hidden overflow-x-auto sm:block">
          <table class="w-full text-sm border-collapse tabular-nums">
            <thead>
              <tr class="text-xs font-semibold text-n-slate-11">
                <th
                  scope="col"
                  class="py-2 pr-2 font-semibold text-start whitespace-nowrap"
                >
                  {{ fmt.t(`${NS}.COL.QUANDO`) }}
                </th>
                <th
                  scope="col"
                  class="px-2 py-2 font-semibold text-end whitespace-nowrap"
                >
                  {{ fmt.t(`${NS}.COL.PROCURAS`) }}
                </th>
                <th
                  scope="col"
                  class="px-2 py-2 font-semibold text-end whitespace-nowrap"
                >
                  {{ fmt.t(`${NS}.COL.DO_TOTAL`) }}
                </th>
                <th
                  scope="col"
                  class="px-2 py-2 font-semibold text-end whitespace-nowrap"
                >
                  {{ painel.meta.nomes.compra }}
                </th>
                <th
                  scope="col"
                  class="px-2 py-2 font-semibold text-end whitespace-nowrap"
                >
                  {{ painel.meta.nomes.fechou }}
                </th>
                <th
                  scope="col"
                  class="px-2 py-2 font-semibold text-end whitespace-nowrap"
                >
                  {{ fmt.t(`${NS}.COL.TAXA`) }}
                </th>
                <th
                  scope="col"
                  class="py-2 pl-2 font-semibold text-end whitespace-nowrap"
                >
                  {{ fmt.t(`${NS}.COL.SEM_PESSOA`) }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="linha in linhas"
                :key="linha.id"
                :data-faixa-horario="linha.id"
              >
                <th
                  scope="row"
                  class="py-2 pr-2 font-normal text-start text-n-slate-12 min-w-36"
                >
                  {{ fmt.t(`${NS}.FAIXA.${linha.id.toUpperCase()}`) }}
                </th>
                <td class="px-2 py-2 text-end text-n-slate-12">
                  {{ fmt.n(linha.procuras) }}
                </td>
                <td class="px-2 py-2 text-end text-n-slate-11">
                  {{ fmt.pct(linha.pct) }}
                </td>
                <td class="px-2 py-2 text-end text-n-slate-12">
                  {{ fmt.n(linha.compra) }}
                </td>
                <td class="px-2 py-2 text-end text-n-slate-12">
                  {{ fmt.n(linha.fecharam) }}
                </td>
                <td
                  class="px-2 py-2 text-end"
                  :class="
                    linha.taxa_pct !== null && linha.taxa_pct === melhorTaxa
                      ? 'text-n-teal-11 font-semibold'
                      : 'text-n-slate-12'
                  "
                >
                  {{ fmt.pct(linha.taxa_pct) }}
                  <span
                    v-if="poucosCasos(linha.compra)"
                    class="block text-xs font-normal text-n-amber-11"
                  >
                    {{ fmt.t('AGENTS.DESEMPENHO2.A.COMUM.POUCOS_CASOS') }}
                  </span>
                </td>
                <td
                  class="py-2 pl-2 text-end"
                  :class="
                    linha.sem_pessoa ? 'text-n-ruby-11' : 'text-n-slate-11'
                  "
                >
                  {{ fmt.n(linha.sem_pessoa) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="m-0 text-xs text-n-slate-11">
          {{
            fmt.t(`${NS}.FAIXAS_NOTA`, {
              fechou: painel.meta.nomes.fechou,
              compra: minusculo(painel.meta.nomes.compra),
              minimo: MINIMO_DO_DESTAQUE,
            })
          }}
        </p>
      </CartaoDoPainel>

      <CartaoDoPainel
        v-if="fila.length"
        data-fila
        :titulo="fmt.t(`${NS}.FILA.TITULO`)"
        :descricao="fmt.t(`${NS}.FILA.DESCRICAO`)"
      >
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <MiniEstatistica
            v-for="item in fila"
            :key="item.id"
            :data-estatistica="`fila-${item.id}`"
            :valor="item.valor"
            :legenda="item.legenda"
            :cor="item.cor || ''"
          />
        </div>
      </CartaoDoPainel>
    </div>
  </section>
</template>
