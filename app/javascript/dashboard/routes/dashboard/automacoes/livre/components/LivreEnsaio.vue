<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';
import { fraseDoPasso } from '../frases';
import { acharPasso, todosOsPassos } from '../receita';
import { linhasDoEnsaio } from '../ensaio';
import {
  ensaiarComPassosNovos,
  temPassoNovo,
} from '../passosNovos/adaptadorFalso';
import { blocoDe, carregarBlocos } from '../passosNovos/dadosDaConta';
import LivreBuscaNoEnsaio from '../passosNovos/LivreBuscaNoEnsaio.vue';

// #2498 — Ensaiar: o que a automação faria nas conversas recentes que a pessoa
// enxerga, sem fazer nada. A automação salva ensaia a versão dela; com
// rascunho (ou a nova, sem id), vai a receita da tela.
const props = defineProps({
  automacaoId: { type: Number, default: null },
  receita: { type: Object, required: true },
  rascunho: { type: Boolean, default: false },
  catalogo: { type: Object, required: true },
});
const emit = defineEmits(['fechar']);

const { t, locale } = useI18n();
const estado = ref('carregando');
const problemas = ref([]);
const erro = ref('');
const conversas = ref([]);
const outras = ref([]);
const escolhida = ref(null);
const extra = ref(null);
// #2635 (G7): no recorrente, só quantos a seleção pegaria agora ({ alvo,
// pegaria }); pegaria nulo = quem pede não vê os contatos da conta.
const recorrente = ref(null);
const CHAVES_DO_RECORRENTE = {
  Contact: 'AUTOMACAO_LIVRE.ENSAIO.RECORRENTE_CONTATOS',
  Account: 'AUTOMACAO_LIVRE.ENSAIO.RECORRENTE_CONTA',
};
const chaveDoRecorrente = alvo =>
  CHAVES_DO_RECORRENTE[alvo] || 'AUTOMACAO_LIVRE.ENSAIO.RECORRENTE_CARDS';

// #2631: no gatilho de card a lista é de cards (`alvo: 'card'`), com o id e o
// título no lugar do número da conversa e do nome do contato. G10: no de
// etiqueta no contato, de contatos (`alvo: 'contato'`), com o id e o nome.
const alvoDoEnsaio = ref('conversa');
// O gatilho de etiqueta sem etiqueta escolhida ('posta' ou 'tirada'): o motor
// só entra quando alguém põe ou tira uma etiqueta, então a lista é de
// exemplos, sem a contagem e sem o "entraria" como se fosse certo.
const qualquerEtiqueta = ref(null);
const ROTULOS_DO_ALVO = {
  card: {
    SEM_CONVERSAS: 'SEM_CARDS',
    QUANTAS: 'QUANTOS_CARDS',
    OUTRA: 'OUTRO_CARD',
    ESCOLHA: 'ESCOLHA_CARD',
    CONVERSA_N: 'CARD_N',
    NA_CONVERSA: 'NO_CARD',
  },
  contato: {
    SEM_CONVERSAS: 'SEM_CONTATOS',
    QUANTAS: 'QUANTOS_CONTATOS',
    OUTRA: 'OUTRO_CONTATO',
    ESCOLHA: 'ESCOLHA_CONTATO',
    CONVERSA_N: 'CONTATO_N',
    NA_CONVERSA: 'NO_CONTATO',
  },
};
const rotulo = (chave, valores) => {
  const nome = ROTULOS_DO_ALVO[alvoDoEnsaio.value]?.[chave] || chave;
  return t(`AUTOMACAO_LIVRE.ENSAIO.${nome}`, valores);
};

const raiz = ref(null);
const passosRef = ref(null);

const corpo = conversaId => ({
  receita: props.rascunho || !props.automacaoId ? props.receita : undefined,
  conversaId,
});

// Um passo novo que o servidor ainda não conheça (emTeste) não passa no
// servidor; o ensaio dessa receita vem do adaptador falso, com as duas conversas
// de exemplo. Hoje os seis passos novos (#2931–#2936) ensaiam no servidor. O
// caminho do "decidir" sem nome vira "Caminho N".
const rotuloDoGalho = ramo =>
  t('AUTOMACAO_LIVRE.RAMOS.CAMINHO', { n: Number(ramo.split('.')[1]) + 1 });
// O ensaio de exemplo avisa no topo: as conversas são inventadas.
const deExemplo = computed(() => temPassoNovo(props.receita.passos));
const pedirEnsaio = conversaId =>
  deExemplo.value
    ? ensaiarComPassosNovos(props.receita, rotuloDoGalho)
    : AutomacoesAPI.ensaiar(props.automacaoId, corpo(conversaId));

const carregar = async () => {
  estado.value = 'carregando';
  problemas.value = [];
  extra.value = null;
  try {
    const { data } = await pedirEnsaio();
    recorrente.value = data.recorrente || null;
    if (recorrente.value) {
      estado.value = 'pronto';
      return;
    }
    alvoDoEnsaio.value = data.alvo || 'conversa';
    qualquerEtiqueta.value = data.qualquer_etiqueta || null;
    conversas.value = data.conversas;
    outras.value = data.outras || [];
    escolhida.value =
      (data.conversas.find(item => item.entraria) || data.conversas[0])
        ?.conversa_id ?? null;
    estado.value = 'pronto';
  } catch (e) {
    erro.value = e.response?.data?.error || '';
    problemas.value = e.response?.data?.problemas || [];
    estado.value = 'erro';
  }
};

// Outra conversa: ensaia só ela e a põe no fim da lista.
const ensaiarOutra = async conversaId => {
  if (conversas.value.some(item => item.conversa_id === conversaId)) {
    escolhida.value = conversaId;
    return;
  }
  try {
    const { data } = await pedirEnsaio(conversaId);
    [extra.value] = data.conversas;
    escolhida.value = conversaId;
  } catch {
    erro.value = t('AUTOMACAO_LIVRE.ENSAIO.ERRO');
  }
};

const todas = computed(() =>
  extra.value ? [...conversas.value, extra.value] : conversas.value
);
const casaram = computed(
  () => conversas.value.filter(item => item.entraria).length
);
const atual = computed(() =>
  todas.value.find(item => item.conversa_id === escolhida.value)
);

// O passo de dentro de um bloco (#2933) vem com `bloco`: o id é da receita do
// bloco, não desta.
const passoDe = no => {
  const passos = no?.bloco
    ? blocoDe(no.bloco)?.passos || []
    : props.receita.passos || [];
  return acharPasso(passos, no?.id);
};
const fraseDe = (id, no) => {
  const passo = passoDe(no || { id });
  return passo ? fraseDoPasso(passo, props.catalogo, t) : '';
};
const linhas = computed(() =>
  atual.value?.entraria
    ? linhasDoEnsaio(atual.value.passos, fraseDe, t, 0, passoDe)
    : []
);

const nomeDe = item =>
  item.nome || rotulo('CONVERSA_N', { n: item.conversa_id });
const opcoes = computed(() =>
  [...conversas.value, ...outras.value].map(item => ({
    value: item.conversa_id,
    // Duas conversas do mesmo contato: o número separa uma da outra.
    label: t('AUTOMACAO_LIVRE.ENSAIO.OPCAO', {
      nome: nomeDe(item),
      n: item.conversa_id,
    }),
  }))
);

const iniciais = item =>
  nomeDe(item)
    .split(' ')
    .slice(0, 2)
    .map(parte => parte[0])
    .join('')
    .toUpperCase();

watch(escolhida, () => {
  if (window.matchMedia('(max-width: 767px)').matches)
    requestAnimationFrame(() =>
      passosRef.value?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    );
});

onMounted(() => {
  raiz.value?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  // Os passos de dentro dos blocos (#2933) saem em frase pela receita deles.
  if (
    todosOsPassos(props.receita.passos || []).some(
      passo => passo.tipo === 'usar_bloco'
    )
  )
    carregarBlocos();
  carregar();
});

const ICONE = {
  mensagem: 'i-lucide-message-circle',
  avisar: 'i-lucide-bell',
  email: 'i-lucide-mail',
  esperar: 'i-lucide-hourglass',
  esperar_ate: 'i-lucide-timer',
  se: 'i-lucide-split',
  decidir: 'i-lucide-sparkles',
  extrair: 'i-lucide-sparkles',
  escrever: 'i-lucide-sparkles',
  resumir: 'i-lucide-sparkles',
  parar: 'i-lucide-octagon',
  acao: 'i-lucide-zap',
  card: 'i-lucide-kanban',
};
</script>

<template>
  <section
    ref="raiz"
    data-ensaio
    class="flex flex-col gap-5 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
    :aria-label="$t('AUTOMACAO_LIVRE.ENSAIO.TITULO')"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex flex-col gap-1">
        <h2 class="mb-0 text-lg font-semibold text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.ENSAIO.TITULO') }}
        </h2>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ENSAIO.SUBTITULO') }}
        </p>
      </div>
      <Button
        data-fechar-ensaio
        :label="$t('AUTOMACAO_LIVRE.ENSAIO.FECHAR')"
        icon="i-lucide-x"
        slate
        link
        class="min-h-11"
        @click="emit('fechar')"
      />
    </div>

    <p
      v-if="deExemplo"
      data-ensaio-de-exemplo
      role="note"
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
    >
      {{ $t('AUTOMACAO_LIVRE.PASSOS_NOVOS.ENSAIO_DE_EXEMPLO') }}
    </p>

    <div
      v-if="estado === 'carregando'"
      data-carregando
      aria-busy="true"
      :aria-label="$t('AUTOMACAO_LIVRE.ENSAIO.CARREGANDO')"
      class="h-40 rounded-2xl bg-n-alpha-2 animate-pulse"
    />

    <div
      v-else-if="estado === 'erro'"
      data-erro
      role="alert"
      class="flex flex-col items-start gap-3"
    >
      <p class="mb-0 text-[0.9375rem] text-n-slate-12">
        {{ erro || $t('AUTOMACAO_LIVRE.ENSAIO.ERRO') }}
      </p>
      <ul
        v-if="problemas.length"
        class="flex flex-col gap-1 m-0 text-sm ps-5 text-n-ruby-11"
      >
        <li v-for="problema in problemas" :key="problema">{{ problema }}</li>
      </ul>
      <Button
        v-else
        :label="$t('AUTOMACAO_LIVRE.LISTA.TENTAR_DE_NOVO')"
        icon="i-lucide-refresh-cw"
        slate
        faded
        class="min-h-11"
        @click="carregar"
      />
    </div>

    <p
      v-else-if="recorrente"
      data-recorrente
      role="status"
      class="mb-0 text-[0.9375rem] text-n-slate-12"
    >
      {{
        recorrente.pegaria === null
          ? $t('AUTOMACAO_LIVRE.ENSAIO.RECORRENTE_SEM_ACESSO')
          : $t(
              chaveDoRecorrente(recorrente.alvo),
              { total: recorrente.pegaria.toLocaleString(locale) },
              recorrente.pegaria
            )
      }}
    </p>

    <p
      v-else-if="!conversas.length"
      data-vazio
      class="mb-0 text-[0.9375rem] text-n-slate-11"
    >
      {{ rotulo('SEM_CONVERSAS') }}
    </p>

    <template v-else>
      <p
        v-if="qualquerEtiqueta"
        role="status"
        data-qualquer-etiqueta
        class="mb-0 text-base text-n-slate-11"
      >
        {{
          $t(
            `AUTOMACAO_LIVRE.ENSAIO.QUALQUER_ETIQUETA.${qualquerEtiqueta.toUpperCase()}`
          )
        }}
      </p>
      <p v-else role="status" class="flex flex-wrap items-baseline m-0 gap-x-3">
        <span
          data-casaram
          class="text-4xl font-bold tracking-tight tabular-nums text-n-teal-11"
        >
          {{ casaram }}
        </span>
        <span class="text-base text-n-slate-11">
          {{ rotulo('QUANTAS', { total: conversas.length }) }}
        </span>
      </p>

      <div class="grid gap-6 md:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
        <div class="flex flex-col gap-3">
          <ul
            class="flex flex-col p-0 m-0 list-none border divide-y rounded-2xl border-n-weak divide-n-weak"
          >
            <li v-for="item in todas" :key="item.conversa_id">
              <button
                type="button"
                data-ensaio-item
                :aria-pressed="item.conversa_id === escolhida"
                class="flex items-center w-full gap-3 px-3 py-2 text-start min-h-11"
                :class="
                  item.conversa_id === escolhida
                    ? 'bg-n-blue-2'
                    : 'hover:bg-n-alpha-1'
                "
                @click="escolhida = item.conversa_id"
              >
                <span
                  class="grid text-xs font-bold rounded-full place-items-center size-8 shrink-0 bg-n-slate-3 text-n-slate-11"
                  aria-hidden="true"
                >
                  {{ iniciais(item) }}
                </span>
                <span class="flex flex-col flex-1 min-w-0">
                  <span class="text-[0.9375rem] truncate text-n-slate-12">
                    {{ nomeDe(item) }}
                  </span>
                  <span class="text-xs text-n-slate-11">
                    {{ relativeTimeFromISO(item.ultima_atividade, locale) }}
                  </span>
                </span>
                <span
                  class="text-sm font-semibold shrink-0"
                  :class="item.entraria ? 'text-n-teal-11' : 'text-n-slate-10'"
                >
                  {{
                    item.entraria
                      ? $t(
                          `AUTOMACAO_LIVRE.ENSAIO.${qualquerEtiqueta ? 'PODERIA_ENTRAR' : 'ENTRARIA'}`
                        )
                      : $t('AUTOMACAO_LIVRE.ENSAIO.NAO_ENTRARIA')
                  }}
                </span>
              </button>
            </li>
          </ul>
          <div class="flex flex-col gap-1.5">
            <span class="text-sm font-medium text-n-slate-11">
              {{ rotulo('OUTRA') }}
            </span>
            <ChoiceSelect
              data-outra
              :model-value="escolhida"
              :aria-label="rotulo('OUTRA')"
              :placeholder="rotulo('ESCOLHA')"
              :options="opcoes"
              @update:model-value="ensaiarOutra"
            />
          </div>
        </div>

        <div
          v-if="atual"
          ref="passosRef"
          data-ensaio-passos
          class="flex flex-col gap-4 p-5 rounded-2xl bg-n-alpha-1"
        >
          <p class="mb-0 text-[0.9375rem] font-semibold text-n-slate-12">
            {{ rotulo('NA_CONVERSA', { nome: nomeDe(atual) }) }}
          </p>
          <p
            v-if="!atual.entraria"
            data-nao-entra
            class="mb-0 text-[0.9375rem] text-n-slate-11"
          >
            {{
              $t(`AUTOMACAO_LIVRE.ENSAIO.FORA.${atual.motivo.toUpperCase()}`)
            }}
          </p>
          <ol v-else class="flex flex-col gap-3 p-0 m-0 list-none">
            <li
              v-for="(linha, indice) in linhas"
              :key="indice"
              class="flex flex-col gap-2"
              :style="{ marginInlineStart: `${linha.nivel * 1.5}rem` }"
            >
              <span
                v-if="linha.caminho"
                data-caminho
                class="text-sm font-semibold tracking-wide uppercase text-n-slate-11"
              >
                {{ linha.texto }}
              </span>
              <template v-else>
                <span class="flex items-start gap-2.5">
                  <span
                    class="grid mt-0.5 rounded-lg place-items-center size-7 shrink-0 bg-n-solid-1 text-n-slate-11"
                    aria-hidden="true"
                  >
                    <span
                      :class="ICONE[linha.tipo] || 'i-lucide-circle-dot'"
                      class="size-4"
                    />
                  </span>
                  <span class="text-[0.9375rem] text-n-slate-12">
                    {{ linha.texto }}
                    <strong v-if="linha.destaque">{{ linha.destaque }}</strong>
                  </span>
                </span>
                <p
                  v-if="linha.aviso"
                  data-nao-sairia
                  class="mb-0 text-sm ms-9 text-n-amber-11"
                >
                  {{ linha.aviso }}
                </p>
                <div
                  v-if="linha.balao"
                  data-balao
                  class="self-start max-w-[18rem] px-4 py-2.5 ms-9 text-[0.9375rem] rounded-2xl rounded-ss-sm shadow-sm bg-n-teal-3 text-n-slate-12 whitespace-pre-line"
                >
                  {{ linha.balao }}
                </div>
                <LivreBuscaNoEnsaio
                  v-if="linha.consulta"
                  :passo="linha.consulta"
                  class="ms-9"
                />
              </template>
            </li>
          </ol>
        </div>
      </div>
    </template>
  </section>
</template>
