<script setup>
import { computed, nextTick, reactive, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmAiSettingsPanel from './CrmAiSettingsPanel.vue';
import CrmStageAutomationsPanel from './CrmStageAutomationsPanel.vue';
import FunilHeroi from './funil/FunilHeroi.vue';
import FunilPassos from './funil/FunilPassos.vue';
import FunilTelaNome from './funil/FunilTelaNome.vue';
import FunilTelaEtapas from './funil/FunilTelaEtapas.vue';
import FunilEtapaAberta from './funil/FunilEtapaAberta.vue';
import FunilResumo from './funil/FunilResumo.vue';
import FunilConfira from './funil/FunilConfira.vue';
import FunilSobre from './funil/FunilSobre.vue';
import FunilVendas from './funil/FunilVendas.vue';
import FunilCaixas from './funil/FunilCaixas.vue';
import FunilAnuncios from './funil/FunilAnuncios.vue';
import FunilAnunciosFacebook from './funil/FunilAnunciosFacebook.vue';
import FunilAnunciosGoogle from './funil/FunilAnunciosGoogle.vue';
import FunilLado from './funil/FunilLado.vue';
import { MODELOS, corLivre, modeloDoFunil } from './funil/funil';
import { useFunilMoldura } from './funil/useFunilMoldura';
import { useFunilSugestao } from './funil/useFunilSugestao';
import { useFunilModelo } from './funil/useFunilModelo';
import {
  avisarEm,
  etapaDoAviso,
  lerGoogleSync,
  lerMetaSync,
  lerResultados,
  metaDoMes,
  moedaDoFunil,
  payloadDoFunil,
  resultadosPadrao,
  simboloDaMoeda,
} from './funil/funilForm';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import { useCrmPermissions } from '../composables/useCrmPermissions';

// #1384 — gaveta de funil. Criar: Nome → Etapas → Confira; editar abre em
// cartões-resumo com "Alterar". Toda tela tem, à direita, a prévia do que
// muda, tirada do mesmo estado do formulário.
const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, default: 'create' },
  pipeline: { type: Object, default: null },
  stages: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  pipelineInboxes: { type: Array, default: () => [] },
  isSaving: { type: Boolean, default: false },
  isArchiving: { type: Boolean, default: false },
  isDeletingStage: { type: Boolean, default: false },
  isLoadingPipelineInboxes: { type: Boolean, default: false },
  agents: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'save', 'archive', 'deleteStage']);

const { t, locale } = useI18n();
const store = useStore();
const { canManageAi } = useCrmPermissions();

const isCrmAiEnabled = computed(
  () =>
    store.getters['globalConfig/get']?.crmAiEnabled === true ||
    window.globalConfig?.CRM_AI_ENABLED === 'true'
);
const ia = computed(() => isCrmAiEnabled.value && canManageAi.value);
const isEditing = computed(() => props.mode === 'edit');

const form = reactive({
  name: '',
  description: '',
  whenToUse: '',
  monthlyTarget: '',
  countsAsSale: true,
  outcomeLabels: lerResultados(),
  stages: [],
  metaSync: lerMetaSync(),
  googleSync: lerGoogleSync(),
});

const aiPanel = ref(null);
const drawerRoot = ref(null);
const drawerContent = ref(null);
const view = ref('nome');
// Telas abertas por cima da principal: de onde veio e uma cópia do que havia,
// para "Cancelar" devolver tudo como estava.
const pilha = ref([]);
const selectedStage = ref(null);
const editorSession = ref(0);
// #1548 (passo 2) — pacote da conta ("seguros.<tipo>" ou null), que escolhe a
// variante do modelo de funil.
const pacote = computed(
  () =>
    store.getters['accounts/getAccount']?.(store.getters.getCurrentAccountId)
      ?.autonomia_pacote || null
);
const {
  tipo,
  modelo,
  modeloAtual,
  modelosDisponiveis,
  modeloPendente,
  copiarEtapas,
  escolherTipo,
  escolherModelo,
  confirmarModelo,
  manterModelo,
  reiniciarModelo,
} = useFunilModelo({ t, ia, form, editorSession, pacote });
// O aviso de troca de modelo vale só enquanto a pessoa está no passo Nome.
watch(view, () => manterModelo());
const focoCaixa = ref(null);
const passoGoogle = ref(1);

const defaultOutcomeLabels = computed(() =>
  resultadosPadrao(form.countsAsSale, t)
);
// #1498 — o nome dos dois desfechos como a pessoa vai ver, e o modelo do
// funil (num funil salvo, vem de metadata.template; sem ele, o 1º do tipo).
const sucesso = computed(
  () => form.outcomeLabels.success.trim() || defaultOutcomeLabels.value.success
);
const fracasso = computed(
  () => form.outcomeLabels.failure.trim() || defaultOutcomeLabels.value.failure
);
const modeloEmUso = computed(() =>
  isEditing.value
    ? modeloDoFunil({
        counts_as_sale: form.countsAsSale,
        metadata: props.pipeline?.metadata,
      })
    : modeloAtual.value || MODELOS[0]
);

const criteriaFor = stage =>
  stage.id
    ? (aiPanel.value?.form?.stageCriteria[stage.id] ?? '')
    : (stage.aiCriteria ?? '');
const selectedCriteria = computed({
  get: () => (selectedStage.value ? criteriaFor(selectedStage.value) : ''),
  set: value => {
    if (!selectedStage.value) return;
    if (selectedStage.value.id && aiPanel.value?.form) {
      aiPanel.value.form.stageCriteria[selectedStage.value.id] = value;
    } else selectedStage.value.aiCriteria = value;
  },
});
const hasUnnamedStages = computed(() =>
  form.stages.some(stage => !stage.name.trim())
);
const criteriaReady = computed(
  () =>
    !isEditing.value ||
    (aiPanel.value && !aiPanel.value.isLoading && !aiPanel.value.loadFailed)
);
const semFrase = computed(() =>
  ia.value && criteriaReady.value
    ? form.stages.filter(stage => !criteriaFor(stage).trim())
    : []
);
const selectedIndex = computed(() => form.stages.indexOf(selectedStage.value));

// ——— Navegação entre telas ———
const copiar = valor => JSON.parse(JSON.stringify(valor));
const fotografar = () => ({
  form: copiar(form),
  ai: aiPanel.value?.form ? copiar(aiPanel.value.form) : null,
});
const restaurar = foto => {
  const existentes = new Set(props.stages.map(stage => stage.id));
  Object.assign(form, foto.form, {
    // Etapa já apagada no servidor não volta.
    stages: foto.form.stages.filter(
      stage => !stage.id || existentes.has(stage.id)
    ),
  });
  if (foto.ai && aiPanel.value?.form)
    Object.assign(aiPanel.value.form, foto.ai);
  // As etapas voltaram como objetos novos: a etapa aberta passa a ser a cópia.
  const aberta = selectedStage.value?.editorKey;
  if (aberta)
    selectedStage.value =
      form.stages.find(stage => stage.editorKey === aberta) || null;
};
const abrir = (destino, foto = fotografar()) => {
  pilha.value = [...pilha.value, { de: view.value, foto }];
  view.value = destino;
};
const fechar = () => emit('close');
const pronto = () => {
  const topo = pilha.value.at(-1);
  if (!topo) return;
  pilha.value = pilha.value.slice(0, -1);
  view.value = topo.de;
};
const cancelar = () => {
  const topo = pilha.value.at(-1);
  if (!topo) return;
  restaurar(topo.foto);
  pronto();
};
const emSubtela = computed(() => pilha.value.length > 0);

const {
  improving,
  suggestion,
  improvementError,
  improveCriteria,
  applySuggestion,
} = useFunilSugestao({
  form,
  criteriaFor,
  selectedStage,
  selectedCriteria,
  editorSession,
  editando: isEditing,
  pipelineId: computed(() => props.pipeline?.id),
  aberta: computed(() => props.show),
});
const openStage = (stage, foto = fotografar()) => {
  selectedStage.value = stage;
  suggestion.value = null;
  improvementError.value = false;
  abrir('stage', foto);
};
const criarComIa = stage => {
  openStage(stage);
  improveCriteria();
};

const mudarEtapa = mudanca => {
  if (selectedStage.value) Object.assign(selectedStage.value, mudanca);
};

// ——— Dados de apoio ———
// #1876 — a meta mostra a moeda do funil, não sempre real.
const moedaDaMeta = computed(() => moedaDoFunil(props.pipeline));
const simboloDaMeta = computed(() =>
  simboloDaMoeda(moedaDaMeta.value, locale.value.replace('_', '-'))
);
const formatMoney = value =>
  new Intl.NumberFormat(locale.value.replace('_', '-'), {
    style: 'currency',
    currency: moedaDaMeta.value,
    maximumFractionDigits: 0,
  }).format(Number(value));
const juntarNomes = nomes =>
  new Intl.ListFormat(locale.value.replace('_', '-'), {
    style: 'long',
    type: 'conjunction',
  }).format(nomes);
const canSubmit = computed(
  () =>
    form.name.trim() &&
    form.stages.length > 0 &&
    form.stages.every(stage => stage.name.trim())
);
const retorno = computed(() => aiPanel.value?.form?.autoFollowup || null);
// #1498 — os lembretes de Atender ligados (andamento, deu certo?, pagamento).
const lembretesAtender = computed(
  () => aiPanel.value?.form?.serviceReminders || null
);
const comRetorno = computed(
  () => isEditing.value && Boolean(props.pipeline?.id) && ia.value
);

// ——— Anúncios ———
const abrirGoogle = () => {
  passoGoogle.value = 1;
  abrir('ads-google');
};
const ligarGoogle = () => {
  form.googleSync = { ...form.googleSync, enabled: true };
  pronto();
};
// A etapa em que também avisamos o Facebook e o Instagram (a "quer comprar").
const etapaAvisada = computed(() => etapaDoAviso(form.stages));
const avisarNaEtapa = chave => avisarEm(form.stages, chave);
const anunciosLigados = computed(() => [
  ...(form.metaSync.enabled
    ? [t('CRM_FUNIL.RESUMO.O_FACEBOOK'), t('CRM_FUNIL.RESUMO.O_INSTAGRAM')]
    : []),
  ...(form.googleSync.enabled ? [t('CRM_FUNIL.RESUMO.O_GOOGLE')] : []),
]);

// #1149 (R16): só as caixas com o CRM ligado. A que saiu do CRM guarda o
// vínculo, mas não traz conversa nenhuma.
const caixasLigadas = computed(() =>
  props.pipelineInboxes.filter(item => item.caixa_no_crm)
);
const nomesCaixas = computed(() =>
  caixasLigadas.value
    .map(
      item =>
        item.inbox?.name ||
        props.inboxes.find(inbox => Number(inbox.id) === Number(item.inbox_id))
          ?.name
    )
    .filter(Boolean)
);

// ——— Etapas ———

const resetForm = () => {
  editorSession.value += 1;
  improving.value = false;
  suggestion.value = null;
  selectedStage.value = null;
  pilha.value = [];
  view.value = isEditing.value ? 'home' : 'nome';
  reiniciarModelo();
  const pipeline = props.pipeline || {};
  const metadata = pipeline.metadata || {};
  // #1498 — funil novo começa vazio: as etapas vêm do tipo e do modelo.
  Object.assign(form, {
    name: pipeline.name || '',
    description:
      pipeline.description ||
      t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_DESCRIPTION'),
    whenToUse: pipeline.when_to_use || '',
    monthlyTarget: metaDoMes(metadata.goals?.monthly_target_cents),
    countsAsSale: pipeline.counts_as_sale ?? true,
    outcomeLabels: lerResultados(metadata.outcome_labels),
    metaSync: lerMetaSync(metadata.meta_sync),
    googleSync: lerGoogleSync(metadata.google_sync),
    stages: copiarEtapas(isEditing.value ? props.stages : []),
  });
};

const addStage = () => {
  // A cópia é de antes da etapa nova: "Cancelar" tira ela de volta.
  const foto = fotografar();
  form.stages.push({
    editorKey: crypto.randomUUID(),
    name: t('CRM_KANBAN.PIPELINE_DRAWER.NEW_STAGE_NAME', {
      count: form.stages.length + 1,
    }),
    description: '',
    color: corLivre(form.stages.map(stage => stage.color)),
    funnel_stage_type: '',
    aiCriteria: '',
  });
  openStage(form.stages.at(-1), foto);
};

const removeStage = index => {
  const stage = form.stages[index];
  if (stage.id) {
    emit('deleteStage', stage);
    return;
  }
  form.stages.splice(index, 1);
  pronto();
};

const onSubmit = async () => {
  if (!canSubmit.value || props.isSaving || aiPanel.value?.isSaving) return;
  // Master save: also persists the embedded AI panel (auto_move, criteria,
  // handoff) before emit('save'), because saving the pipeline closes the drawer
  // and unmounts the panel. Keep it open if its settings fail.
  if (aiPanel.value) {
    const saved = await aiPanel.value.saveSettings({ silent: true });
    if (saved === false) return;
  }
  emit(
    'save',
    payloadDoFunil({
      form,
      pipeline: props.pipeline,
      editando: isEditing.value,
      ia: ia.value,
      modelo: modelo.value,
    })
  );
};

// ——— Cabeçalho, prévia e rodapé de cada tela ———
const quadro = computed(() =>
  form.stages.map(stage => ({
    chave: stage.editorKey,
    nome: stage.name.trim() || '…',
    cor: stage.color,
    total: isEditing.value ? stage.total_cards_count : null,
    falta: semFrase.value.includes(stage),
  }))
);
const chegando = computed(() => {
  if (view.value === 'inboxes') {
    const id = focoCaixa.value?.etapa?.id;
    return id ? form.stages.findIndex(stage => stage.id === id) : -1;
  }
  return ['nome', 'etapas', 'confira'].includes(view.value) ? 0 : -1;
});

const { heroi, rodape } = useFunilMoldura({
  t,
  view,
  pilha,
  form,
  isEditing,
  selectedStage,
  selectedIndex,
  canSubmit,
  improving,
  aiPanel,
  salvando: computed(() => props.isSaving),
  apagandoEtapa: computed(() => props.isDeletingStage),
  hasUnnamedStages,
  passoGoogle,
  onSubmit,
  fechar,
  pronto,
  cancelar,
  removeStage,
  ligarGoogle,
  tipo,
});

// ——— Ciclo de vida ———
watch(view, async () => {
  await nextTick();
  if (drawerContent.value) drawerContent.value.scrollTop = 0;
  // Quem usa teclado ou leitor de tela ouve onde chegou.
  drawerRoot.value?.querySelector('[data-view-title]')?.focus();
});

watch(selectedCriteria, () => {
  suggestion.value = null;
});

// Reset only when the drawer opens or the target pipeline identity changes.
// We intentionally do NOT depend on props.stages content: realtime card events
// rebuild board.stages into a new array reference on every update.
watch(
  [() => props.show, () => props.pipeline?.id],
  () => {
    if (props.show) resetForm();
  },
  { immediate: true }
);

// Deleting a stage keeps the drawer open and removes it server-side, so drop it
// from the form and refresh card counts, preserving local edits.
watch(
  () => props.stages,
  serverStages => {
    if (!props.show || !isEditing.value) return;
    const serverStagesById = new Map(
      serverStages.map(stage => [stage.id, stage])
    );
    const next = form.stages.filter(
      stage => !stage.id || serverStagesById.has(stage.id)
    );
    next.forEach(stage => {
      if (stage.id)
        stage.total_cards_count = serverStagesById.get(
          stage.id
        ).total_cards_count;
    });
    if (next.length !== form.stages.length) form.stages = next;
    if (selectedStage.value && !next.includes(selectedStage.value)) pronto();
  }
);

useKeyboardEvents({
  Escape: {
    // Esc numa tela interna cancela e volta, sem fechar a gaveta. Com o foco
    // num campo de texto da tela interna, o Esc não descarta o que foi digitado.
    action: () => {
      if (!props.show) return;
      if (!emSubtela.value) {
        fechar();
        return;
      }
      const campo = document.activeElement?.tagName;
      if (campo === 'INPUT' || campo === 'TEXTAREA') return;
      cancelar();
    },
    allowOnFocusedInput: true,
  },
});

// #646 — a gaveta cobre o canto do lançador do Guia; sinaliza que está aberta.
useFixedPanelPresence(computed(() => props.show));
</script>

<template>
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
  >
    <div
      v-if="show"
      ref="drawerRoot"
      data-crm-pipeline-drawer
      role="dialog"
      aria-modal="true"
      aria-labelledby="crm-pipeline-drawer-title"
      class="fixed inset-y-0 z-50 flex h-full w-[80rem] max-w-full flex-col overflow-hidden bg-n-solid-1 shadow-2xl ltr:right-0 rtl:left-0"
    >
      <FunilHeroi v-bind="heroi" @voltar="pronto" @fechar="fechar" />

      <div ref="drawerContent" class="min-h-0 flex-1 overflow-y-auto">
        <div
          class="grid min-h-full grid-cols-[minmax(0,1fr)] lg:grid-cols-[minmax(0,1fr)_32rem]"
        >
          <main class="flex min-w-0 flex-col gap-6 px-5 py-7 sm:px-8">
            <div
              v-if="aiPanel?.loadFailed"
              role="alert"
              class="flex flex-wrap items-center gap-3 rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-[0.9375rem] text-n-ruby-11"
            >
              <span class="min-w-0 flex-1">
                {{ t('CRM_KANBAN.AI_SETTINGS.LOAD_ERROR') }}
              </span>
              <Button
                :label="t('CRM_KANBAN.PIPELINE_EDITOR.RETRY')"
                slate
                faded
                class="!min-h-11"
                @click="aiPanel.loadSettings()"
              />
            </div>

            <FunilPassos
              v-if="['nome', 'etapas', 'confira'].includes(view)"
              :atual="['nome', 'etapas', 'confira'].indexOf(view) + 1"
              @ir="view = ['nome', 'etapas'][$event - 1]"
            />

            <!-- Criar, passo 1: o nome e o modelo para começar pronto. -->
            <FunilTelaNome
              v-if="view === 'nome'"
              v-model="form.name"
              :tipo="tipo"
              :modelo="modelo"
              :modelos="modelosDisponiveis"
              :pendente="modeloPendente"
              @tipo="escolherTipo"
              @confirmar="confirmarModelo"
              @manter="manterModelo"
              @escolher="escolherModelo"
            />

            <!-- Criar, passo 2, e "Etapas" de um funil existente. -->
            <FunilTelaEtapas
              v-else-if="view === 'etapas' || view === 'stages'"
              v-model:etapas="form.stages"
              v-model:nome="form.name"
              :com-nome="view === 'stages'"
              :frase-de="criteriaFor"
              :ia="ia"
              :travada="improving || isSaving"
              @alterar="openStage"
              @criar="criarComIa"
              @adicionar="addStage"
            />

            <FunilConfira
              v-else-if="view === 'confira'"
              :nome="form.name"
              :etapas="form.stages"
              :sem-frase="semFrase"
              :quando-usar="form.whenToUse"
              :venda="form.countsAsSale"
              :meta="form.monthlyTarget"
              :dinheiro="formatMoney"
              :ia="ia"
              :sucesso="sucesso"
              :fracasso="fracasso"
              @etapas="view = 'etapas'"
              @abrir="abrir"
              @alterar-etapa="openStage"
              @criar="criarComIa"
            />

            <FunilResumo
              v-else-if="view === 'home'"
              :etapas="form.stages"
              :sem-frase="semFrase"
              :quando-usar="form.whenToUse"
              :venda="form.countsAsSale"
              :meta="form.monthlyTarget"
              :dinheiro="formatMoney"
              :com-retorno="comRetorno"
              :retorno="retorno"
              :lembretes-atender="lembretesAtender"
              :modelo="modeloEmUso.chave"
              :caixas="nomesCaixas"
              :anuncios="anunciosLigados"
              :arquivando="isArchiving"
              :juntar="juntarNomes"
              :sucesso="sucesso"
              :fracasso="fracasso"
              @abrir="abrir"
              @criar="criarComIa"
              @arquivar="$emit('archive')"
            />

            <FunilEtapaAberta
              v-else-if="view === 'stage' && selectedStage"
              v-model:frase="selectedCriteria"
              :etapa="selectedStage"
              :ia="ia"
              :pronta="criteriaReady"
              :melhorando="improving"
              :sugestao="suggestion"
              :erro="improvementError"
              :nomes-faltando="hasUnnamedStages"
              :editando="isEditing"
              @mudar="mudarEtapa"
              @melhorar="improveCriteria"
              @usar="applySuggestion"
              @manter="suggestion = null"
              @acoes="abrir('stage-actions')"
            />

            <CrmStageAutomationsPanel
              v-else-if="view === 'stage-actions' && selectedStage"
              :stage="selectedStage"
              :pipeline-stages="form.stages"
              :agents="agents"
              expanded
              :show-header="false"
            />

            <FunilSobre
              v-else-if="view === 'about'"
              v-model="form.whenToUse"
              v-model:nota="form.description"
              :nome="form.name"
              :ideias="modeloEmUso.ideias"
              :com-nota="isEditing"
            />

            <FunilVendas
              v-else-if="view === 'sales'"
              v-model:venda="form.countsAsSale"
              v-model:meta="form.monthlyTarget"
              v-model:sucesso="form.outcomeLabels.success"
              v-model:fracasso="form.outcomeLabels.failure"
              :moeda="simboloDaMeta"
              :padrao-sucesso="defaultOutcomeLabels.success"
              :padrao-fracasso="defaultOutcomeLabels.failure"
            />

            <FunilCaixas
              v-else-if="view === 'inboxes'"
              v-model:foco="focoCaixa"
              :caixas="inboxes"
              :ligadas="caixasLigadas"
              :etapas="stages"
              :carregando="isLoadingPipelineInboxes"
            />

            <FunilAnuncios
              v-else-if="view === 'ads'"
              v-model:meta="form.metaSync"
              v-model:google="form.googleSync"
              :etapa-avisada="etapaAvisada?.name || ''"
              @alterar-facebook="abrir('ads-facebook')"
              @abrir-google="abrirGoogle"
            />

            <FunilAnunciosFacebook
              v-else-if="view === 'ads-facebook'"
              v-model:meta="form.metaSync"
              :etapas="form.stages"
              :etapa-avisada="etapaAvisada?.editorKey || ''"
              @avisar-em="avisarNaEtapa"
            />

            <FunilAnunciosGoogle
              v-else-if="view === 'ads-google'"
              v-model:google="form.googleSync"
              :passo="passoGoogle"
              @ir="passoGoogle = $event"
            />

            <CrmAiSettingsPanel
              v-if="comRetorno"
              v-show="['returns', 'returns-detail'].includes(view)"
              :key="pipeline.id"
              ref="aiPanel"
              :atender="!form.countsAsSale"
              :modelo="modeloEmUso.chave"
              :sucesso="sucesso"
              :pipeline-id="pipeline.id"
              :detalhe="view === 'returns-detail'"
              @alterar="abrir('returns-detail')"
            />
          </main>

          <aside
            data-funil-lado
            class="min-w-0 border-t border-n-weak bg-n-alpha-1 px-5 py-7 sm:px-8 lg:border-s lg:border-t-0 lg:px-5"
          >
            <FunilLado
              :view="view"
              :editando="isEditing"
              :ia="ia"
              :nome="form.name"
              :quadro="quadro"
              :acesa="selectedIndex"
              :chegando="chegando"
              :etapa="selectedStage"
              :frase="selectedCriteria"
              :sugestao="suggestion?.description || ''"
              :quando-usar="form.whenToUse"
              :venda="form.countsAsSale"
              :meta="Number(form.monthlyTarget) || 0"
              :sucesso="sucesso"
              :fracasso="fracasso"
              :sem-tipo="!isEditing && !tipo"
              :dinheiro="formatMoney"
              :retorno="retorno"
              :lembretes-atender="lembretesAtender"
              :modelo="modeloEmUso.chave"
              :mensagem-no-dia="aiPanel?.form?.callbackMode === 'both'"
              :foco="focoCaixa"
              :meta-sync="form.metaSync"
              :google-sync="form.googleSync"
              :etapa-avisada="etapaAvisada?.name"
            />
          </aside>
        </div>
      </div>

      <footer
        class="flex flex-wrap items-center gap-2 border-t border-n-weak bg-n-solid-1 px-5 py-4 sm:px-8"
      >
        <!-- No celular, tirar a etapa vira só o ícone (com nome para leitor de
             tela) para os três botões caberem numa linha. -->
        <Button
          v-if="rodape.perigo"
          data-funil-tirar
          :label="rodape.perigo.rotulo"
          icon="i-lucide-trash-2"
          ruby
          ghost
          class="!hidden !min-h-11 sm:!inline-flex"
          :disabled="Boolean(rodape.perigo.desabilitado)"
          @click="rodape.perigo.acao"
        />
        <Button
          v-if="rodape.perigo"
          :aria-label="rodape.perigo.rotulo"
          :title="rodape.perigo.rotulo"
          icon="i-lucide-trash-2"
          ruby
          ghost
          class="!min-h-11 !min-w-11 sm:!hidden"
          :disabled="Boolean(rodape.perigo.desabilitado)"
          @click="rodape.perigo.acao"
        />
        <span class="flex-1" aria-hidden="true" />
        <Button
          v-if="rodape.secundaria"
          :label="rodape.secundaria.rotulo"
          slate
          ghost
          class="!min-h-11"
          @click="rodape.secundaria.acao"
        />
        <Button
          v-if="rodape.principal"
          data-funil-principal
          :label="rodape.principal.rotulo"
          :icon="rodape.principal.icone"
          :trailing-icon="Boolean(rodape.principal.depois)"
          :color="rodape.principal.neutro ? 'slate' : 'blue'"
          :variant="rodape.principal.neutro ? 'faded' : 'solid'"
          class="!min-h-11 min-w-32"
          :is-loading="Boolean(rodape.principal.carregando)"
          :disabled="Boolean(rodape.principal.desabilitado)"
          @click="rodape.principal.acao"
        />
      </footer>
    </div>
  </transition>
</template>
