<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  ref,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import {
  useEventListener,
  useResizeObserver,
  watchDebounced,
} from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { filenameFromDisposition } from 'dashboard/store/modules/crmKanban';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import BarraDaLista from './BarraDaLista.vue';
import LinhaCliente from './LinhaCliente.vue';
import CombinarRetorno from './CombinarRetorno.vue';
import PassarPara from './PassarPara.vue';
import {
  cardStatusLabel,
  outcomeLabels,
  outcomeStatuses,
} from '../../helpers/cardOutcome';
import { scheduleToUtc } from 'dashboard/components-next/CampaignJourney/scheduleTime';
import {
  COLUNAS,
  GRUPOS_DE_ACAO,
  GRUPOS_EM_ANDAMENTO,
  LARGURA_DA_TABELA,
  LARGURA_DA_TABELA_CHEIA,
  montarGrupos,
  somar,
} from './grupos';
import { quandoFuturo, situacaoDoCard } from './situacao';
import { emAndamento, parametrosDaLista } from './parametros';
import { useFaixas } from './useFaixas';
import { useListaAcaoDados } from './useListaAcaoDados';
import { useAcoesDaLista } from './useAcoesDaLista';

// #2283 — a Lista nova "o que fazer agora", atrás da flag crm_lista_acao. Os
// grupos e os números vêm do servidor; cada linha tem a ação que pede.
const props = defineProps({
  pipelineId: { type: [Number, String], default: '' },
  pipeline: { type: Object, default: null },
  filtros: { type: Object, required: true },
  filtrosAtivos: { type: Number, default: 0 },
  meuId: { type: [Number, String], default: null },
  meuNome: { type: String, default: '' },
  pessoas: { type: Array, default: () => [] },
  fuso: { type: String, required: true },
  podePassar: { type: Boolean, default: false },
  podeMexer: { type: Boolean, default: false },
  podeBaixar: { type: Boolean, default: false },
  podeMarcar: { type: Boolean, default: false },
  podeConfigurar: { type: Boolean, default: false },
  selecionados: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'filtros',
  'configurar',
  'abrir',
  'conversa',
  'selecionar',
  'limparFiltros',
]);

const { t, locale } = useI18n();
const store = useStore();
const L = 'CRM_LISTA_ACAO';

const aba = ref('aberto');
const quem = ref('todos');
const grupoSo = ref(null);
const busca = ref('');
const marcando = ref(false);
const aviso = ref('');
const larga = ref(false);
const colunas = ref(COLUNAS.cheia);
const agora = ref(new Date());

const statuses = computed(() => outcomeStatuses(props.pipeline));
const estado = () => ({
  filtros: props.filtros,
  pipelineId: props.pipelineId,
  aba: aba.value,
  statuses: statuses.value,
  quem: quem.value,
  grupoSo: grupoSo.value,
  busca: busca.value,
});
const dados = useListaAcaoDados({ store, estado });
const faixas = useFaixas();
const anunciar = texto => {
  aviso.value = texto;
};
const nomeDe = card => card.contact?.name || card.title || '';
const lista = useTemplateRef('lista');
const combinar = useTemplateRef('combinar');
const passarPara = useTemplateRef('passarPara');
useResizeObserver(lista, ([entrada]) => {
  const largura = entrada.contentRect.width;
  larga.value = largura >= LARGURA_DA_TABELA;
  colunas.value =
    largura >= LARGURA_DA_TABELA_CHEIA ? COLUNAS.cheia : COLUNAS.compacta;
});

// O relógio da tela: o retorno de hoje fica vermelho na hora em que passa.
const relogio = setInterval(() => {
  agora.value = new Date();
}, 60 * 1000);
onBeforeUnmount(() => clearInterval(relogio));

const contexto = computed(() => ({
  agora: agora.value,
  fuso: props.fuso,
  locale: locale.value,
  rotuloDoStatus: status => cardStatusLabel(t, status, props.pipeline),
}));
const rotulos = computed(() => outcomeLabels(t, props.pipeline));
const rotulosDasAbas = computed(() => ({
  ganho: rotulos.value.success,
  perdido: rotulos.value.failure,
}));

const totalDeAcao = computed(() => somar(dados.contagem.value, GRUPOS_DE_ACAO));
const totalAberto = computed(() =>
  somar(dados.contagem.value, GRUPOS_EM_ANDAMENTO)
);
const comHeroi = computed(() => emAndamento(aba.value));
const separaEmGrupos = computed(() => comHeroi.value && !grupoSo.value);
// Nas abas de desfecho, o número é o total da própria lista.
const contagemDaTela = computed(() =>
  comHeroi.value
    ? dados.contagem.value
    : {
        ganho: dados.total.value,
        perdido: dados.total.value,
        arquivado: dados.total.value,
      }
);

const tituloDoGrupo = grupo => {
  if (grupo === 'esperando' && quem.value === 'meus')
    return t(`${L}.GRUPOS.ESPERANDO_MEUS`);
  if (grupo === 'ganho') return rotulos.value.success;
  if (grupo === 'perdido') return rotulos.value.failure;
  return t(`${L}.GRUPOS.${grupo.toUpperCase()}`);
};
const grupos = computed(() =>
  montarGrupos({
    cards: dados.cards.value,
    contagem: contagemDaTela.value,
    grupoSo: grupoSo.value,
    meuId: props.meuId,
    opcoes: { podePassar: props.podePassar, podeMexer: props.podeMexer },
    tomDaLinha: card => situacaoDoCard(card, contexto.value).tom,
  }).map(grupo => ({ ...grupo, titulo: tituloDoGrupo(grupo.chave) }))
);
const semNinguem = computed(
  () =>
    !dados.carregando.value &&
    !dados.erro.value &&
    !dados.cards.value.length &&
    aba.value === 'aberto' &&
    !grupoSo.value &&
    !busca.value.trim() &&
    quem.value === 'todos' &&
    !props.filtrosAtivos
);

const pessoas = computed(() => [
  {
    value: props.meuId,
    label: t(`${L}.ACOES.EU`, { nome: props.meuNome }),
    eu: true,
  },
  ...props.pessoas
    .filter(pessoa => String(pessoa.id) !== String(props.meuId))
    .map(pessoa => ({ value: pessoa.id, label: pessoa.name })),
]);
const itensAlterar = computed(() =>
  props.podeMexer
    ? [
        { chave: 'combinar', rotulo: t(`${L}.ACOES.COMBINAR_RETORNO`) },
        { chave: 'etapa', rotulo: t(`${L}.ALTERAR.MUDAR_ETAPA`) },
        ...(props.podePassar
          ? [{ chave: 'passar', rotulo: t(`${L}.ACOES.PASSAR`) }]
          : []),
        { chave: 'valor', rotulo: t(`${L}.ALTERAR.MUDAR_VALOR`) },
        { chave: 'desfecho', rotulo: t(`${L}.ALTERAR.DESFECHO`) },
      ]
    : []
);

// Quem não vê o valor de venda (value_hidden, #2075) não ganha "Mudar valor": o
// servidor ignoraria a mudança (parecer de Funções do #2324).
const itensAlterarDoCard = card =>
  card.value_hidden
    ? itensAlterar.value.filter(item => item.chave !== 'valor')
    : itensAlterar.value;

// --- carregar -----------------------------------------------------------------
const chaveDaBusca = computed(() =>
  JSON.stringify({ ...estado(), busca: undefined })
);
watch(chaveDaBusca, () => dados.carregar(), { immediate: true });
watchDebounced(busca, () => dados.carregar(), { debounce: 350 });

// --- foco depois que a linha sai ---------------------------------------------
const focar = async (...seletores) => {
  await nextTick();
  seletores
    .map(seletor => lista.value?.querySelector(seletor))
    .find(Boolean)
    ?.focus();
};
const proximoAlvo = id => {
  const todos = [
    ...(lista.value?.querySelectorAll('[data-card-id], [data-cab-grupo]') ||
      []),
  ];
  const alvo =
    todos[todos.findIndex(el => el.dataset.cardId === String(id)) + 1];
  if (!alvo) return null;
  return alvo.dataset.cabGrupo
    ? `[data-cab-grupo="${alvo.dataset.cabGrupo}"] h2`
    : `[data-card-id="${alvo.dataset.cardId}"] button`;
};
// A faixa sai: o foco, se estava nela, vai para a próxima linha ou grupo.
const seguirFoco = id => {
  const linha = lista.value?.querySelector(`[data-card-id="${id}"]`);
  const tinhaFoco =
    linha?.contains(document.activeElement) ||
    document.activeElement === document.body;
  const alvo = proximoAlvo(id);
  return () => {
    if (tinhaFoco && alvo) focar(alvo);
  };
};
// --- ações --------------------------------------------------------------------
const acoes = useAcoesDaLista({
  t,
  fuso: () => props.fuso,
  dados,
  faixas,
  anunciar,
  nomeDe,
  focoDepois: seguirFoco,
});
const feito = card => {
  acoes.feito(card);
  focar(`[data-card-id="${card.id}"] [data-lista-acao-desfazer]`);
};
const desfazer = card => {
  acoes.desfazer(card);
  focar(
    `[data-card-id="${card.id}"] [data-lista-acao-feito]`,
    `[data-card-id="${card.id}"] button`
  );
};
const abrirCombinar = card =>
  combinar.value?.abrir(card, {
    nome: nomeDe(card),
    combinarOutro: Boolean(card.next_follow_up_id),
  });
const aoCombinar = (card, quando) => {
  const dueAt = scheduleToUtc(quando, props.fuso);
  const futuro = dueAt
    ? quandoFuturo(new Date(dueAt), contexto.value)
    : { tipo: 'HOJE', valores: {} };
  return acoes.combinar(card, {
    quando,
    formatado: t(`${L}.QUANDO_FUTURO.${futuro.tipo}`, futuro.valores),
  });
};
const passar = (card, pessoa) =>
  acoes.passar(
    card,
    { id: pessoa.value, name: pessoa.label },
    { eu: Boolean(pessoa.eu) }
  );
const fazer = (tipo, card) => {
  if (tipo === 'feito') return feito(card);
  if (tipo === 'combinar') return abrirCombinar(card);
  if (tipo === 'ficar') return passar(card, pessoas.value[0]);
  if (tipo === 'responder' || tipo === 'ver-conversa')
    return emit('conversa', card);
  return emit('abrir', card);
};
const aoAlterar = (card, chave) => {
  if (chave === 'combinar') return abrirCombinar(card);
  if (chave === 'passar')
    return passarPara.value?.abrir(card, { nome: nomeDe(card) });
  return emit('abrir', card);
};

// Ao sair da tela (outra rota) e ao fechar a aba: o "Feito" pendente vale.
onBeforeUnmount(() => faixas.sairTodas());
useEventListener(window, 'pagehide', () =>
  faixas.sairTodas({ saindoDaPagina: true })
);

// --- barra, abas e grupos -----------------------------------------------------
const trocarQuem = valor => {
  quem.value = valor;
  grupoSo.value = null;
};
const trocarAba = valor => {
  aba.value = valor;
  grupoSo.value = null;
};
const verSo = grupo => {
  grupoSo.value = grupo;
};
const limpar = () => {
  grupoSo.value = null;
  busca.value = '';
  quem.value = 'todos';
  emit('limparFiltros');
};
// A planilha leva o mesmo recorte que a Lista mostra (aba, chave, grupo e busca).
const baixarPlanilha = async () => {
  try {
    const resposta = await CrmKanbanAPI.exportCards(
      parametrosDaLista(estado())
    );
    const endereco = URL.createObjectURL(resposta.data);
    const link = document.createElement('a');
    link.setAttribute('href', endereco);
    link.setAttribute(
      'download',
      filenameFromDisposition(resposta.headers?.['content-disposition'])
    );
    link.click();
    URL.revokeObjectURL(endereco);
  } catch {
    useAlert(t('CRM_KANBAN.ACTIONS.EXPORT_ERROR'));
  }
};
const aoMais = chave => {
  if (chave === 'baixar') baixarPlanilha();
  if (chave === 'marcar') marcando.value = !marcando.value;
  if (chave === 'configurar') emit('configurar');
};
const atualizar = () => dados.carregar();

// --- marcados (a barra de ações em lote é a da página) -----------------------
const visiveis = computed(() =>
  grupos.value.flatMap(grupo => grupo.linhas.map(linha => linha.card.id))
);
const todosMarcados = computed(
  () =>
    visiveis.value.length > 0 &&
    visiveis.value.every(id => props.selecionados.includes(id))
);
const marcar = (card, ligado) =>
  emit(
    'selecionar',
    ligado
      ? [...props.selecionados, card.id]
      : props.selecionados.filter(id => id !== card.id)
  );
const marcarTodos = ligado =>
  emit('selecionar', ligado ? [...visiveis.value] : []);

defineExpose({ recarregar: atualizar });
</script>

<template>
  <div
    class="mx-auto flex w-full max-w-[1400px] flex-col gap-4 px-4 pb-24 pt-4 md:gap-5 md:px-8 md:pb-6 md:pt-6"
    data-lista-acao
  >
    <section
      v-if="comHeroi && totalDeAcao > 0"
      data-lista-acao-heroi
      class="flex items-center gap-4 rounded-3xl bg-n-heroi px-4 py-3 text-white shadow-sm dark:ring-1 dark:ring-n-blue-7 md:px-6 md:py-3.5"
      :aria-label="t(`${L}.HEROI.ROTULO`)"
    >
      <span
        class="hidden size-11 shrink-0 place-items-center rounded-2xl bg-white/10 sm:grid"
        aria-hidden="true"
      >
        <span class="i-lucide-clock size-6" />
      </span>
      <p class="mb-0 text-base font-semibold leading-snug md:text-xl">
        {{
          t(
            `${L}.HEROI.${quem === 'meus' ? 'MEUS' : 'TODOS'}`,
            { n: totalDeAcao },
            totalDeAcao
          )
        }}
        <span class="hidden font-normal text-white/85 sm:inline md:text-base">
          {{ t(`${L}.HEROI.DICA`) }}
        </span>
      </p>
    </section>
    <div
      v-else-if="comHeroi && totalAberto > 0"
      class="flex items-center gap-3 rounded-3xl bg-n-teal-3 px-5 py-4 text-n-slate-12"
    >
      <span
        class="i-lucide-check size-6 shrink-0 text-n-teal-11"
        aria-hidden="true"
      />
      <p class="mb-0 text-lg font-semibold">
        {{ t(`${L}.HEROI.TUDO_EM_DIA`) }}
      </p>
    </div>

    <BarraDaLista
      v-model:busca="busca"
      :quem="quem"
      :aba="aba"
      :total-aberto="totalAberto"
      :rotulos-das-abas="rotulosDasAbas"
      :filtros-ativos="filtrosAtivos"
      :pode-baixar="podeBaixar"
      :pode-marcar="podeMarcar"
      :pode-configurar="podeConfigurar"
      @quem="trocarQuem"
      @aba="trocarAba"
      @filtros="emit('filtros')"
      @mais="aoMais"
    />

    <div v-if="grupoSo" class="flex flex-wrap gap-2">
      <span
        class="inline-flex min-h-11 items-center gap-2 rounded-full bg-n-solid-1 pl-4 pr-1 font-medium text-n-slate-12 ring-1 ring-n-weak"
      >
        {{ t(`${L}.GRUPOS.MOSTRANDO_SO`, { grupo: tituloDoGrupo(grupoSo) }) }}
        <button
          type="button"
          class="min-h-11 rounded-full px-3 font-semibold text-n-blue-11 hover:bg-n-alpha-2"
          @click="grupoSo = null"
        >
          {{ t(`${L}.GRUPOS.VER_TODOS`) }}
        </button>
      </span>
    </div>

    <div
      v-if="dados.novidades.value"
      data-lista-acao-novidades
      class="flex items-center gap-3 rounded-2xl bg-n-blue-3 px-4 py-2 text-n-slate-12"
    >
      <span
        class="i-lucide-refresh-cw size-5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      <p class="mb-0 flex-1 font-medium">
        {{
          t(
            `${L}.NOVIDADES.TEXTO`,
            { n: dados.novidades.value },
            dados.novidades.value
          )
        }}
      </p>
      <Button
        :label="t(`${L}.NOVIDADES.ATUALIZAR`)"
        slate
        outline
        class="!h-11 !rounded-xl !px-4 !text-base !font-semibold !text-n-slate-12 !outline-n-weak bg-n-solid-1 hover:enabled:!bg-n-alpha-2"
        @click="atualizar"
      />
    </div>

    <section
      ref="lista"
      :aria-label="t(`${L}.LISTA.ROTULO`)"
      :aria-busy="dados.carregando.value"
      class="overflow-hidden rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
    >
      <div
        v-if="dados.erro.value && !dados.cards.value.length"
        class="flex flex-col items-center gap-5 px-6 py-12 text-center"
      >
        <p class="mb-0 text-lg font-semibold text-n-slate-12">
          {{ t(`${L}.ERROS.CARREGAR`) }}
        </p>
        <Button
          :label="t(`${L}.ERROS.TENTAR_DE_NOVO`)"
          slate
          outline
          class="!h-12 !rounded-xl !px-5 !text-base !font-semibold"
          @click="atualizar"
        />
      </div>
      <div
        v-else-if="semNinguem"
        class="flex flex-col items-center gap-5 px-6 py-12 text-center"
      >
        <span
          class="grid size-14 place-items-center rounded-2xl bg-n-blue-3 text-n-blue-11"
        >
          <span class="i-lucide-user-round size-7" aria-hidden="true" />
        </span>
        <p class="mb-0 text-lg font-semibold text-n-slate-12">
          {{ t(`${L}.VAZIO.NINGUEM`) }}
        </p>
      </div>
      <template v-else>
        <div
          v-if="larga"
          :class="colunas.linha"
          class="grid items-center gap-3 border-b border-n-weak px-4 py-2.5 text-sm font-medium text-n-slate-11"
        >
          <label
            v-if="podeMarcar"
            class="grid size-11 cursor-pointer place-items-center"
          >
            <Checkbox
              :model-value="todosMarcados"
              @update:model-value="marcarTodos"
            />
            <span class="sr-only">{{ t(`${L}.LISTA.MARCAR_TODOS`) }}</span>
          </label>
          <span v-else aria-hidden="true" />
          <span>{{ t(`${L}.LISTA.CLIENTE`) }}</span>
          <span>{{ t(`${L}.LISTA.SITUACAO`) }}</span>
          <span>{{ t(`${L}.LISTA.PROXIMO_PASSO`) }}</span>
        </div>

        <template v-for="grupo in grupos" :key="grupo.chave">
          <div
            v-if="separaEmGrupos"
            :data-cab-grupo="grupo.chave"
            class="flex min-h-12 items-center gap-2 border-b border-n-weak bg-n-slate-2 pl-4 pr-2"
          >
            <h2
              tabindex="-1"
              class="mb-0 flex min-w-0 items-center gap-2 whitespace-nowrap text-[15px] font-semibold text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            >
              <span
                class="grid size-7 shrink-0 place-items-center rounded-lg"
                :class="[grupo.tom.fundo, grupo.tom.icone]"
              >
                <span :class="grupo.icone" class="size-4" aria-hidden="true" />
              </span>
              {{ grupo.titulo }}
              <span
                class="grid h-7 min-w-7 place-items-center rounded-full bg-n-solid-1 px-2 text-sm tabular-nums ring-1 ring-n-weak"
              >
                <span aria-hidden="true">{{ grupo.conta }}</span>
                <span class="sr-only">
                  {{ t(`${L}.GRUPOS.CONTA`, { n: grupo.conta }, grupo.conta) }}
                </span>
              </span>
            </h2>
            <button
              v-if="grupo.deAcao"
              type="button"
              :data-lista-acao-ver-so="grupo.chave"
              :aria-label="
                t(`${L}.GRUPOS.VER_SO_ROTULO`, {
                  grupo: grupo.titulo,
                  n: grupo.conta,
                })
              "
              class="ml-auto hidden min-h-11 shrink-0 items-center whitespace-nowrap rounded-xl px-3 text-[15px] font-medium text-n-blue-11 underline-offset-4 hover:underline sm:inline-flex"
              @click="verSo(grupo.chave)"
            >
              {{ t(`${L}.GRUPOS.VER_SO`) }}
            </button>
          </div>
          <LinhaCliente
            v-for="linha in grupo.linhas"
            :key="linha.card.id"
            :data-card-id="linha.card.id"
            :card="linha.card"
            :acao="linha.acao"
            :cheio="linha.cheio"
            :larga="larga"
            :colunas="colunas"
            :quem="quem"
            :meu-id="meuId"
            :contexto="contexto"
            :pessoas="pessoas"
            :itens-alterar="itensAlterarDoCard(linha.card)"
            :faixa="faixas.faixas.value[linha.card.id]"
            :marcado="selecionados.includes(linha.card.id)"
            :marcavel="podeMarcar"
            :marcando="marcando"
            @acao="tipo => fazer(tipo, linha.card)"
            @alterar="chave => aoAlterar(linha.card, chave)"
            @passar="pessoa => passar(linha.card, pessoa)"
            @desfazer="desfazer(linha.card)"
            @pausar="faixas.pausar(linha.card.id)"
            @seguir="faixas.seguir(linha.card.id)"
            @marcar="ligado => marcar(linha.card, ligado)"
          />
          <div
            v-if="separaEmGrupos && grupo.deAcao"
            class="border-b border-n-weak px-2 sm:hidden"
          >
            <button
              type="button"
              :aria-label="
                t(`${L}.GRUPOS.VER_SO_ROTULO`, {
                  grupo: grupo.titulo,
                  n: grupo.conta,
                })
              "
              class="min-h-11 px-2 text-[15px] font-medium text-n-blue-11 underline-offset-4 hover:underline"
              @click="verSo(grupo.chave)"
            >
              {{ t(`${L}.GRUPOS.VER_SO_N`, { n: grupo.conta }) }}
            </button>
          </div>
        </template>

        <div
          v-if="!grupos.length && !dados.carregando.value"
          class="flex flex-col items-center gap-5 px-6 py-14 text-center"
        >
          <p class="mb-0 text-lg font-semibold text-n-slate-12">
            {{ t(`${L}.VAZIO.SEM_RESULTADO`) }}
          </p>
          <Button
            :label="t(`${L}.VAZIO.LIMPAR`)"
            slate
            outline
            class="!h-12 !rounded-xl !px-5 !text-base !font-semibold"
            @click="limpar"
          />
        </div>

        <div
          v-if="grupos.length && dados.temMais.value"
          class="flex items-center justify-center border-t border-n-weak p-4"
        >
          <Button
            :label="t(`${L}.LISTA.MOSTRAR_MAIS`)"
            slate
            outline
            :is-loading="dados.carregando.value"
            class="!h-11 !rounded-xl !px-5 !text-base !text-n-slate-12 !outline-n-weak hover:enabled:!bg-n-alpha-2"
            @click="dados.mostrarMais"
          />
        </div>
      </template>
      <p class="sr-only" aria-live="polite">{{ aviso }}</p>
    </section>

    <CombinarRetorno ref="combinar" :ao-combinar="aoCombinar" />
    <PassarPara
      ref="passarPara"
      :pessoas="pessoas"
      @passar="(card, pessoa) => passar(card, pessoa)"
    />
  </div>
</template>
