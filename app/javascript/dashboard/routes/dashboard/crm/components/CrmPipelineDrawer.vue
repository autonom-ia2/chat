<script setup>
import { computed, nextTick, reactive, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmGoogleConversionFeedAPI from 'dashboard/api/crmGoogleConversionFeed';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmStageAutomationsPanel from './CrmStageAutomationsPanel.vue';
import CrmAiSettingsPanel from './CrmAiSettingsPanel.vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import { useCrmPermissions } from '../composables/useCrmPermissions';

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
  isSavingPipelineInbox: { type: Boolean, default: false },
  isRemovingPipelineInbox: { type: Boolean, default: false },
  agents: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'close',
  'save',
  'archive',
  'deleteStage',
  'addPipelineInbox',
  'removePipelineInbox',
]);

const { t } = useI18n();
const store = useStore();
const { canManageAi } = useCrmPermissions();

const isCrmAiEnabled = computed(
  () =>
    store.getters['globalConfig/get']?.crmAiEnabled === true ||
    window.globalConfig?.CRM_AI_ENABLED === 'true'
);

const stageColors = [
  '#2563eb',
  '#0891b2',
  '#ca8a04',
  '#16a34a',
  '#dc2626',
  '#9333ea',
];
const stageColorChoices = [
  { value: '#2563eb', name: 'BLUE', swatch: 'bg-[#2563eb]' },
  { value: '#0891b2', name: 'TEAL', swatch: 'bg-[#0891b2]' },
  { value: '#ca8a04', name: 'AMBER', swatch: 'bg-[#ca8a04]' },
  { value: '#16a34a', name: 'GREEN', swatch: 'bg-[#16a34a]' },
  { value: '#dc2626', name: 'RED', swatch: 'bg-[#dc2626]' },
  { value: '#9333ea', name: 'PURPLE', swatch: 'bg-[#9333ea]' },
];
const stageBadgeClasses = {
  '#2563eb': 'bg-n-blue-3 text-n-blue-11',
  '#0891b2': 'bg-n-teal-3 text-n-teal-11',
  '#ca8a04': 'bg-n-amber-3 text-n-amber-11',
  '#16a34a': 'bg-green-50 text-green-700',
  '#dc2626': 'bg-n-ruby-3 text-n-ruby-11',
  '#9333ea': 'bg-n-violet-3 text-n-violet-11',
};
const defaultStages = () => [
  { name: t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_STAGE_NEW'), color: '#2563eb' },
  {
    name: t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_STAGE_WORKING'),
    color: '#0891b2',
  },
  {
    name: t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_STAGE_PROPOSAL'),
    color: '#ca8a04',
  },
  {
    name: t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_STAGE_CLOSING'),
    color: '#16a34a',
  },
  {
    name: t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_STAGE_LOST'),
    color: '#dc2626',
  },
];

// Native Meta funnel classifications a stage can map to for CTWA conversion sync.
const metaProgressChoices = computed(() =>
  [
    { value: '', key: 'NONE', icon: 'i-lucide-circle-minus' },
    { value: 'lead', key: 'INTEREST', icon: 'i-lucide-message-circle' },
    { value: 'qualified', key: 'QUALIFIED', icon: 'i-lucide-user-check' },
    { value: 'opportunity', key: 'PROPOSAL', icon: 'i-lucide-file-text' },
    { value: 'negotiation', key: 'NEGOTIATION', icon: 'i-lucide-handshake' },
  ].map(choice => ({
    ...choice,
    label: t(`CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.${choice.key}.TITLE`),
    description: t(
      `CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.${choice.key}.HELP`
    ),
  }))
);

// Meta Pixel ids are digits only (contract #1011: up to 20). Filtering on input
// keeps pasted spaces or letters out instead of failing on save.
const PIXEL_ID_MAX_LENGTH = 20;
const onlyDigits = value =>
  [...String(value || '')]
    .filter(char => char >= '0' && char <= '9')
    .join('')
    .slice(0, PIXEL_ID_MAX_LENGTH);
const form = reactive({
  name: '',
  description: '',
  monthlyTarget: '',
  stages: [],
  metaSync: {
    enabled: false,
    datasetId: '',
    pixelId: '',
    events: { won: true, lost: false, moved: false },
  },
  googleSync: {
    enabled: false,
    events: { won: true, lost: false, moved: false },
    conversionNames: { won: '' },
  },
});
const newPipelineInbox = reactive({
  inboxId: '',
  defaultStageId: '',
  autoCreateCard: true,
});
const expandedAutomationStages = ref({});
const aiPanel = ref(null);
const onPixelInput = event => {
  const digits = onlyDigits(event.target.value);
  form.metaSync.pixelId = digits;
  event.target.value = digits;
};

const view = ref('home');
const drawerContent = ref(null);
const selectedStage = ref(null);
const improving = ref(false);
const suggestion = ref(null);
const improvementError = ref(false);
const editorSession = ref(0);
const orderAnnouncement = ref('');
const stageDragHandles = ref({});
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
const hasSelectedCriteria = computed(
  () => selectedCriteria.value.trim() !== ''
);
const hasUnnamedStages = computed(() =>
  form.stages.some(stage => !stage.name.trim())
);
const isEditing = computed(() => props.mode === 'edit');
const criteriaReady = computed(
  () =>
    !isEditing.value ||
    (aiPanel.value && !aiPanel.value.isLoading && !aiPanel.value.loadFailed)
);
const openStage = stage => {
  selectedStage.value = stage;
  suggestion.value = null;
  improvementError.value = false;
  view.value = 'stage';
};
const improveCriteria = async () => {
  const target = selectedStage.value;
  const session = editorSession.value;
  const snapshot = form.stages.map(stage => ({
    name: stage.name,
    description: criteriaFor(stage),
  }));
  improving.value = true;
  suggestion.value = null;
  improvementError.value = false;
  try {
    const { data } = await CrmKanbanAPI.improveStageCriteria(
      props.pipeline.id,
      {
        stages: snapshot,
        stage_index: form.stages.indexOf(target),
      }
    );
    if (
      session !== editorSession.value ||
      selectedStage.value !== target ||
      !props.show
    )
      return;
    if (
      JSON.stringify(snapshot) !==
      JSON.stringify(
        form.stages.map(stage => ({
          name: stage.name,
          description: criteriaFor(stage),
        }))
      )
    ) {
      improvementError.value = true;
      return;
    }
    suggestion.value = data;
  } catch {
    if (session === editorSession.value) improvementError.value = true;
  } finally {
    if (session === editorSession.value) improving.value = false;
  }
};
const applySuggestion = () => {
  selectedCriteria.value = suggestion.value.description;
  suggestion.value = null;
};

const title = computed(() =>
  isEditing.value
    ? t('CRM_KANBAN.PIPELINE_DRAWER.EDIT_TITLE')
    : t('CRM_KANBAN.PIPELINE_DRAWER.CREATE_TITLE')
);
const subtitle = computed(() =>
  isEditing.value
    ? t('CRM_KANBAN.PIPELINE_DRAWER.EDIT_SUBTITLE')
    : t('CRM_KANBAN.PIPELINE_DRAWER.CREATE_SUBTITLE')
);
const canSubmit = computed(
  () =>
    form.name.trim() &&
    form.stages.length > 0 &&
    form.stages.every(stage => stage.name.trim())
);
const linkedInboxIds = computed(() =>
  props.pipelineInboxes.map(item => Number(item.inbox_id))
);
const availableInboxes = computed(() =>
  props.inboxes.filter(
    inbox => !linkedInboxIds.value.includes(Number(inbox.id))
  )
);
const stageOptions = computed(() => form.stages.filter(stage => stage.id));
const inboxChoices = computed(() => [
  { value: '', label: t('CRM_KANBAN.PIPELINE_DRAWER.SELECT_INBOX') },
  ...availableInboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  })),
]);
const entryStageChoices = computed(() => [
  { value: '', label: t('CRM_KANBAN.PIPELINE_DRAWER.FIRST_STAGE') },
  ...stageOptions.value.map(stage => ({ value: stage.id, label: stage.name })),
]);
const canAddPipelineInbox = computed(
  () =>
    isEditing.value &&
    props.pipeline?.id &&
    !props.isSavingPipelineInbox &&
    !props.isRemovingPipelineInbox &&
    availableInboxes.value.some(inbox => inbox.id === newPipelineInbox.inboxId)
);
// The feed URL is account-level and minted on demand by the backend (token in
// account custom_attributes); fetch it lazily when the Google section is enabled.
const fetchedFeedUrl = ref('');
const googleFeedUrl = computed(() => fetchedFeedUrl.value);

const ensureGoogleFeedUrl = async () => {
  if (fetchedFeedUrl.value) return;
  try {
    const { data } = await CrmGoogleConversionFeedAPI.create();
    fetchedFeedUrl.value = data.url || '';
  } catch {
    fetchedFeedUrl.value = '';
  }
};

watch(
  () => form.googleSync.enabled,
  enabled => {
    if (enabled) ensureGoogleFeedUrl();
  },
  { immediate: true }
);

const cloneStage = (stage, index) => ({
  editorKey: crypto.randomUUID(),
  id: stage.id,
  name: stage.name || '',
  description: stage.description || '',
  color: stage.color || stageColors[index % stageColors.length],
  // Board stages expose funnel_stage_type top-level; stages API payloads carry it
  // inside metadata. Read both so opening the drawer never wipes the mapping.
  funnel_stage_type:
    stage.funnel_stage_type || stage.metadata?.funnel_stage_type || '',
  // All-status count (open + won + lost + archived) — the Kanban badge only ever shows
  // open cards, so this is what tells the delete flow a "0 cards" stage isn't really empty.
  total_cards_count: stage.total_cards_count ?? 0,
});

const resetNewPipelineInbox = () => {
  newPipelineInbox.inboxId = availableInboxes.value[0]?.id || '';
  newPipelineInbox.defaultStageId = stageOptions.value[0]?.id || '';
  newPipelineInbox.autoCreateCard = true;
};

const resetForm = () => {
  editorSession.value += 1;
  improving.value = false;
  suggestion.value = null;
  selectedStage.value = null;
  view.value = 'home';
  const pipeline = props.pipeline || {};
  form.name = pipeline.name || t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_NAME');
  form.description =
    pipeline.description || t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_DESCRIPTION');
  const targetCents = pipeline.metadata?.goals?.monthly_target_cents;
  form.monthlyTarget = targetCents ? Number(targetCents) / 100 : '';
  const metaSync = pipeline.metadata?.meta_sync || {};
  form.metaSync = {
    enabled: Boolean(metaSync.enabled),
    datasetId: metaSync.dataset_id || '',
    pixelId: metaSync.pixel_id || '',
    events: {
      won: metaSync.events?.won ?? true,
      lost: metaSync.events?.lost ?? false,
      moved: metaSync.events?.moved ?? false,
    },
  };
  const googleSync = pipeline.metadata?.google_sync || {};
  form.googleSync = {
    enabled: Boolean(googleSync.enabled),
    events: {
      won: googleSync.events?.won ?? true,
      lost: googleSync.events?.lost ?? false,
      moved: googleSync.events?.moved ?? false,
    },
    conversionNames: {
      won: googleSync.conversion_names?.won || '',
    },
  };
  const sourceStages = isEditing.value ? props.stages : defaultStages();
  form.stages = sourceStages.map(cloneStage);
  resetNewPipelineInbox();
};

const addStage = () => {
  form.stages.push({
    editorKey: crypto.randomUUID(),
    name: t('CRM_KANBAN.PIPELINE_DRAWER.NEW_STAGE_NAME', {
      count: form.stages.length + 1,
    }),
    description: '',
    color: stageColors[form.stages.length % stageColors.length],
    funnel_stage_type: '',
    aiCriteria: '',
  });
  openStage(form.stages.at(-1));
};

const removeStage = index => {
  const stage = form.stages[index];
  if (stage.id) {
    emit('deleteStage', stage);
    return;
  }
  form.stages.splice(index, 1);
  view.value = 'home';
};

const announceStageOrder = stage => {
  orderAnnouncement.value = t('CRM_KANBAN.PIPELINE_EDITOR.ORDER_CHANGED', {
    name: stage.name,
    position: form.stages.indexOf(stage) + 1,
    total: form.stages.length,
  });
};

const moveStage = (fromIndex, direction) => {
  const toIndex = fromIndex + direction;
  if (toIndex < 0 || toIndex >= form.stages.length) return;

  const stages = [...form.stages];
  const [stage] = stages.splice(fromIndex, 1);
  const usingHandle =
    stageDragHandles.value[stage.editorKey] === document.activeElement;
  stages.splice(toIndex, 0, stage);
  form.stages = stages;
  announceStageOrder(stage);
  if (usingHandle)
    nextTick(() => stageDragHandles.value[stage.editorKey]?.focus());
};

const toggleStageAutomations = stage => {
  if (!stage.id) return;
  expandedAutomationStages.value = {
    ...expandedAutomationStages.value,
    [stage.id]: !expandedAutomationStages.value[stage.id],
  };
};

const isStageAutomationsExpanded = stage =>
  Boolean(stage.id && expandedAutomationStages.value[stage.id]);

const pipelineInboxName = pipelineInbox =>
  pipelineInbox.inbox?.name ||
  props.inboxes.find(
    inbox => Number(inbox.id) === Number(pipelineInbox.inbox_id)
  )?.name ||
  t('CRM_KANBAN.PIPELINE_DRAWER.UNKNOWN_INBOX');

const pipelineInboxStageName = pipelineInbox =>
  pipelineInbox.default_stage?.name ||
  stageOptions.value.find(
    stage => Number(stage.id) === Number(pipelineInbox.default_stage_id)
  )?.name ||
  t('CRM_KANBAN.PIPELINE_DRAWER.FIRST_STAGE');

const addPipelineInbox = () => {
  if (!canAddPipelineInbox.value) return;

  emit('addPipelineInbox', {
    pipelineId: props.pipeline.id,
    inbox_id: newPipelineInbox.inboxId,
    default_stage_id: newPipelineInbox.defaultStageId || null,
    auto_create_card: newPipelineInbox.autoCreateCard,
  });
};

const removePipelineInbox = pipelineInbox => {
  emit('removePipelineInbox', {
    pipelineId: props.pipeline.id,
    inboxId: pipelineInbox.inbox_id,
  });
};

const copyGoogleFeedUrl = async () => {
  if (!googleFeedUrl.value) return;

  try {
    await copyTextToClipboard(googleFeedUrl.value);
    useAlert(t('CRM_KANBAN.GOOGLE_SYNC.COPIED'));
  } catch {
    useAlert(t('CRM_KANBAN.GOOGLE_SYNC.COPY_ERROR'));
  }
};

const onSubmit = async () => {
  if (!canSubmit.value || props.isSaving || aiPanel.value?.isSaving) return;
  // Master save: "Salvar funil" also persists the embedded AI panel (auto_move,
  // criteria, handoff) so the user never loses it for forgetting "Salvar IA".
  // Done BEFORE emit('save') because saving the pipeline closes the drawer and
  // unmounts the panel. Keep it open if its settings fail validation or persistence.
  if (aiPanel.value) {
    const saved = await aiPanel.value.saveSettings({ silent: true });
    if (saved === false) return;
  }
  emit('save', {
    pipeline: {
      id: props.pipeline?.id,
      name: form.name.trim(),
      description: form.description.trim(),
      is_default: props.pipeline?.is_default ?? !isEditing.value,
      position: props.pipeline?.position || 1,
      goal: {
        monthly_target_cents:
          Number(form.monthlyTarget) > 0
            ? Math.round(Number(form.monthlyTarget) * 100)
            : 0,
        currency: 'BRL',
      },
      // Always emitted so toggling Meta sync off persists enabled:false.
      meta_sync: {
        enabled: form.metaSync.enabled,
        events: { ...form.metaSync.events },
        dataset_id: form.metaSync.datasetId.trim() || null,
        pixel_id: form.metaSync.pixelId || null,
      },
      // Always emitted so toggling Google sync off persists enabled:false.
      google_sync: {
        enabled: form.googleSync.enabled,
        events: { ...form.googleSync.events },
        conversion_names: {
          won: form.googleSync.conversionNames.won.trim() || null,
        },
      },
    },
    stages: form.stages.map((stage, index) => ({
      id: stage.id,
      color: stage.color,
      total_cards_count: stage.total_cards_count,
      name: stage.name.trim(),
      description: stage.description?.trim() || '',
      ...(!stage.id &&
      canManageAi.value &&
      isCrmAiEnabled.value &&
      stage.aiCriteria !== undefined
        ? { aiCriteria: stage.aiCriteria.trim() }
        : {}),
      position: index + 1,
      funnel_stage_type: stage.funnel_stage_type || null,
    })),
  });
};

// Reset only when the drawer opens or the target pipeline identity changes.
// We intentionally do NOT depend on props.stages content: realtime card events
// rebuild board.stages into a new array reference on every update, and a busy
// board would re-run resetForm mid-typing, wiping the stage name being edited.
watch(view, async () => {
  await nextTick();
  if (drawerContent.value) drawerContent.value.scrollTop = 0;
});

watch(selectedCriteria, () => {
  suggestion.value = null;
});

watch(
  [() => props.show, () => props.pipeline?.id],
  () => {
    if (props.show) resetForm();
  },
  { immediate: true }
);

// Deleting a stage keeps the drawer open and removes it server-side, so we still
// need to drop it from the form and refresh the destination's card count for the
// next deletion. Preserve local edits rather than resetting the entire form.
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
    if (selectedStage.value && !next.includes(selectedStage.value))
      view.value = 'home';
  }
);

watch(
  [
    () => props.pipelineInboxes,
    () => props.inboxes,
    () => props.pipelineInboxes.length,
  ],
  () => {
    if (props.show && isEditing.value) resetNewPipelineInbox();
  }
);

useKeyboardEvents({
  Escape: {
    action: () => {
      if (props.show) emit('close');
    },
    allowOnFocusedInput: true,
  },
});

// #646 — a gaveta cobre o mesmo canto (`fixed ... right-0`) do lançador do
// Guia; sinaliza que está aberta para ele se desviar do rodapé Cancelar/Salvar.
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
      data-crm-pipeline-drawer
      class="fixed inset-y-0 ltr:right-0 rtl:left-0 z-50 flex h-full w-[40rem] max-w-full flex-col overflow-hidden border-n-weak bg-n-surface-2 shadow-lg ltr:border-l rtl:border-r"
    >
      <div
        class="flex items-start justify-between gap-4 bg-n-blue-12 px-8 py-6"
      >
        <div class="min-w-0">
          <h2 class="mb-2 text-2xl font-semibold text-n-slate-1">
            {{ title }}
          </h2>
          <p class="mb-0 text-sm leading-6 text-n-slate-4">
            {{
              isCrmAiEnabled
                ? t('CRM_KANBAN.PIPELINE_EDITOR.INCLUDED')
                : subtitle
            }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          slate
          ghost
          :aria-label="t('CRM_KANBAN.PIPELINE_DRAWER.CANCEL')"
          class="!text-n-slate-1"
          @click="$emit('close')"
        />
      </div>

      <div
        ref="drawerContent"
        class="min-h-0 flex-1 overflow-y-auto px-5 pt-5 pb-8 sm:px-8"
      >
        <Button
          v-if="view !== 'home'"
          :label="t('CRM_KANBAN.PIPELINE_EDITOR.BACK')"
          icon="i-lucide-arrow-left"
          slate
          ghost
          class="mb-5"
          @click="view = 'home'"
        />
        <div class="grid min-w-0 grid-cols-1 gap-4">
          <div
            v-if="aiPanel?.loadFailed"
            role="alert"
            class="grid gap-2 rounded-xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
          >
            {{ t('CRM_KANBAN.AI_SETTINGS.LOAD_ERROR') }}
            <Button
              :label="t('CRM_KANBAN.PIPELINE_EDITOR.RETRY')"
              slate
              faded
              @click="aiPanel.loadSettings()"
            />
          </div>
          <Input
            v-show="view === 'home'"
            v-model="form.name"
            :label="t('CRM_KANBAN.PIPELINE_DRAWER.NAME')"
            :placeholder="t('CRM_KANBAN.PIPELINE_DRAWER.NAME_PLACEHOLDER')"
            :message="
              !form.name.trim() ? t('CRM_KANBAN.PIPELINE_DRAWER.REQUIRED') : ''
            "
            :message-type="!form.name.trim() ? 'error' : 'info'"
          />

          <label v-if="view === 'adjustments'" class="grid gap-1">
            <span class="text-heading-3 text-n-slate-12">
              {{ t('CRM_KANBAN.PIPELINE_DRAWER.DESCRIPTION') }}
            </span>
            <textarea
              v-model="form.description"
              rows="3"
              class="reset-base !mb-0 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 text-sm text-n-slate-12 outline outline-1 outline-n-weak transition-all placeholder:text-n-slate-10 focus:outline-n-brand"
              :placeholder="
                t('CRM_KANBAN.PIPELINE_DRAWER.DESCRIPTION_PLACEHOLDER')
              "
            />
          </label>

          <label v-if="view === 'adjustments'" class="grid gap-1">
            <span class="text-heading-3 text-n-slate-12">
              {{ t('CRM_KANBAN.PIPELINE_DRAWER.MONTHLY_TARGET') }}
            </span>
            <input
              v-model="form.monthlyTarget"
              type="number"
              min="0"
              step="0.01"
              class="reset-base !mb-0 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 text-sm text-n-slate-12 outline outline-1 outline-n-weak transition-all placeholder:text-n-slate-10 focus:outline-n-brand"
              :placeholder="
                t('CRM_KANBAN.PIPELINE_DRAWER.MONTHLY_TARGET_PLACEHOLDER')
              "
            />
            <span class="text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.PIPELINE_DRAWER.MONTHLY_TARGET_HELP') }}
            </span>
          </label>

          <CrmAiSettingsPanel
            v-if="isEditing && pipeline?.id && isCrmAiEnabled && canManageAi"
            v-show="view === 'returns'"
            :key="pipeline.id"
            ref="aiPanel"
            :pipeline-id="pipeline.id"
          />

          <section
            v-show="view === 'home'"
            class="grid min-w-0 grid-cols-1 gap-3"
          >
            <div class="flex items-center justify-between gap-3">
              <div>
                <h3 class="mb-1 text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.STAGES') }}
                </h3>
                <p class="mb-0 text-sm leading-6 text-n-slate-11">
                  {{ t('CRM_KANBAN.PIPELINE_EDITOR.STAGES_HELP') }}
                </p>
              </div>
              <Button
                :label="t('CRM_KANBAN.PIPELINE_DRAWER.ADD_STAGE')"
                class="shrink-0"
                icon="i-lucide-plus"
                slate
                faded
                sm
                @click="addStage"
              />
            </div>

            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_KANBAN.PIPELINE_EDITOR.REORDER_HELP') }}
            </p>
            <p class="sr-only" aria-live="polite">{{ orderAnnouncement }}</p>
            <Draggable
              v-model="form.stages"
              item-key="editorKey"
              handle=".stage-drag-handle"
              :animation="150"
              ghost-class="opacity-40"
              class="grid gap-3"
              :disabled="improving || isSaving"
              @change="announceStageOrder($event.moved.element)"
            >
              <template #item="{ element: stage, index }">
                <div
                  class="flex min-w-0 items-center rounded-2xl border border-n-slate-4 bg-n-surface-1 px-1 transition hover:border-n-slate-7"
                >
                  <button
                    :ref="
                      el => {
                        stageDragHandles[stage.editorKey] = el;
                      }
                    "
                    type="button"
                    class="stage-drag-handle flex min-h-11 min-w-11 shrink-0 touch-none items-center justify-center rounded-lg text-n-slate-10 cursor-grab active:cursor-grabbing focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    :aria-label="
                      t('CRM_KANBAN.PIPELINE_EDITOR.REORDER_STAGE', {
                        name: stage.name,
                      })
                    "
                    :title="
                      t('CRM_KANBAN.PIPELINE_EDITOR.REORDER_STAGE', {
                        name: stage.name,
                      })
                    "
                    @keydown.up.prevent="moveStage(index, -1)"
                    @keydown.down.prevent="moveStage(index, 1)"
                  >
                    <span
                      class="i-lucide-grip-vertical text-lg"
                      aria-hidden="true"
                    />
                  </button>
                  <button
                    type="button"
                    class="flex min-h-16 min-w-0 flex-1 items-center gap-3 rounded-xl py-3 pe-3 text-start transition hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    @click="openStage(stage)"
                  >
                    <span
                      class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-base font-semibold"
                      :class="
                        stageBadgeClasses[stage.color] ||
                        'bg-n-brand/10 text-n-brand'
                      "
                      aria-hidden="true"
                    >
                      {{ index + 1 }}
                    </span>
                    <span class="min-w-0 flex-1">
                      <span
                        class="block break-words text-base font-semibold leading-5 text-n-slate-12"
                      >
                        {{ stage.name }}
                      </span>
                      <span
                        class="mt-1 line-clamp-2 text-sm leading-5 text-n-slate-11"
                      >
                        {{
                          criteriaFor(stage) ||
                          t('CRM_KANBAN.PIPELINE_EDITOR.DESCRIBE')
                        }}
                      </span>
                    </span>
                    <span
                      class="i-lucide-chevron-right shrink-0 text-n-slate-10"
                      aria-hidden="true"
                    />
                  </button>
                  <Button
                    icon="i-lucide-trash-2"
                    ruby
                    ghost
                    class="min-h-11 min-w-11 shrink-0"
                    :aria-label="t('CRM_KANBAN.PIPELINE_DRAWER.DELETE_STAGE')"
                    :title="t('CRM_KANBAN.PIPELINE_DRAWER.DELETE_STAGE')"
                    :disabled="
                      form.stages.length === 1 || isDeletingStage || isSaving
                    "
                    @click="removeStage(index)"
                  />
                </div>
              </template>
            </Draggable>
            <button
              v-if="isEditing && isCrmAiEnabled && canManageAi"
              type="button"
              class="mt-2 flex min-h-14 items-center justify-between rounded-xl bg-n-alpha-black2 px-4 text-start text-sm font-medium text-n-slate-12"
              @click="view = 'returns'"
            >
              <span class="flex items-center gap-3">
                <span class="i-lucide-calendar-clock text-lg" />
                {{ t('CRM_KANBAN.PIPELINE_EDITOR.RETURNS') }}
              </span>
              <span class="i-lucide-chevron-right" />
            </button>
          </section>

          <section v-if="view === 'stage'" class="grid gap-5">
            <template
              v-for="(stage, index) in form.stages"
              :key="stage.id || index"
            >
              <div v-if="stage === selectedStage" class="grid gap-6">
                <div class="flex items-center gap-4">
                  <span
                    class="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl text-lg font-semibold"
                    :class="
                      stageBadgeClasses[stage.color] ||
                      'bg-n-brand/10 text-n-brand'
                    "
                    aria-hidden="true"
                  >
                    {{ index + 1 }}
                  </span>
                  <div class="min-w-0">
                    <p class="mb-1 text-xs font-medium text-n-slate-11">
                      {{
                        t('CRM_KANBAN.PIPELINE_EDITOR.STAGE_POSITION', {
                          current: index + 1,
                          total: form.stages.length,
                        })
                      }}
                    </p>
                    <h3
                      class="mb-0 break-words text-xl font-semibold leading-7 text-n-slate-12"
                    >
                      {{ stage.name }}
                    </h3>
                  </div>
                </div>
                <Input
                  v-model="stage.name"
                  :label="t('CRM_KANBAN.PIPELINE_DRAWER.STAGE_NAME')"
                  :placeholder="
                    t('CRM_KANBAN.PIPELINE_DRAWER.STAGE_NAME_PLACEHOLDER')
                  "
                  :message="
                    !stage.name.trim()
                      ? t('CRM_KANBAN.PIPELINE_DRAWER.REQUIRED')
                      : ''
                  "
                  :message-type="!stage.name.trim() ? 'error' : 'info'"
                />
                <div v-if="isCrmAiEnabled && canManageAi" class="grid gap-4">
                  <label for="stage-ai-criteria" class="grid gap-2">
                    <span
                      class="text-xl font-semibold leading-7 text-n-slate-12"
                    >
                      {{ t('CRM_KANBAN.PIPELINE_EDITOR.CRITERIA_QUESTION') }}
                    </span>
                    <span class="text-sm leading-6 text-n-slate-11">
                      {{ t('CRM_KANBAN.PIPELINE_EDITOR.CRITERIA_HELP') }}
                    </span>
                  </label>
                  <textarea
                    id="stage-ai-criteria"
                    v-model="selectedCriteria"
                    rows="7"
                    maxlength="4000"
                    :disabled="!criteriaReady || improving"
                    class="reset-base !mb-0 !h-auto min-h-[12rem] w-full rounded-2xl border border-n-weak bg-n-surface-1 px-4 py-4 text-base leading-7 text-n-slate-12 focus:outline focus:outline-2 focus:outline-n-brand"
                  />
                  <div
                    v-if="isEditing"
                    class="flex flex-wrap items-center justify-between gap-3"
                  >
                    <span class="text-xs text-n-slate-11">
                      {{
                        t(
                          hasUnnamedStages
                            ? 'CRM_KANBAN.PIPELINE_EDITOR.NAMES_REQUIRED'
                            : hasSelectedCriteria
                              ? 'CRM_KANBAN.PIPELINE_EDITOR.CRITERIA_TIP'
                              : 'CRM_KANBAN.PIPELINE_EDITOR.CREATE_HELP'
                        )
                      }}
                    </span>
                    <Button
                      v-if="isEditing"
                      :label="
                        t(
                          hasSelectedCriteria
                            ? 'CRM_KANBAN.PIPELINE_EDITOR.IMPROVE'
                            : 'CRM_KANBAN.PIPELINE_EDITOR.CREATE'
                        )
                      "
                      icon="i-lucide-sparkles"
                      slate
                      faded
                      :is-loading="improving"
                      :disabled="
                        !criteriaReady || improving || hasUnnamedStages
                      "
                      @click="improveCriteria"
                    />
                  </div>
                  <p
                    v-if="improvementError"
                    role="alert"
                    class="mb-0 text-sm text-n-ruby-11"
                  >
                    {{ t('CRM_KANBAN.PIPELINE_EDITOR.IMPROVE_ERROR') }}
                  </p>
                  <section
                    v-if="suggestion"
                    aria-live="polite"
                    class="grid gap-3 rounded-2xl border border-n-brand/30 bg-n-brand/5 p-5"
                  >
                    <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
                      {{ t('CRM_KANBAN.PIPELINE_EDITOR.SUGGESTION') }}
                    </h3>
                    <p
                      class="mb-0 whitespace-pre-wrap text-sm leading-6 text-n-slate-12"
                    >
                      {{ suggestion.description }}
                    </p>
                    <p
                      v-if="suggestion.note"
                      class="mb-0 text-sm text-n-slate-11"
                    >
                      {{ suggestion.note }}
                    </p>
                    <div class="flex flex-wrap gap-2">
                      <Button
                        :label="t('CRM_KANBAN.PIPELINE_EDITOR.APPLY')"
                        icon="i-lucide-check"
                        @click="applySuggestion"
                      />
                      <Button
                        :label="
                          t(
                            hasSelectedCriteria
                              ? 'CRM_KANBAN.PIPELINE_EDITOR.KEEP'
                              : 'CRM_KANBAN.PIPELINE_EDITOR.DISMISS'
                          )
                        "
                        slate
                        ghost
                        @click="suggestion = null"
                      />
                    </div>
                  </section>
                  <p v-if="!isEditing" class="mb-0 text-xs text-n-slate-11">
                    {{ t('CRM_KANBAN.PIPELINE_EDITOR.SAVE_FIRST') }}
                  </p>
                </div>
                <section
                  v-if="isEditing && stage.id"
                  class="grid gap-4 overflow-hidden rounded-2xl border border-n-slate-5 bg-n-surface-1"
                >
                  <div
                    class="flex flex-wrap items-start justify-between gap-4 p-4 sm:p-5"
                  >
                    <div class="flex min-w-0 items-start gap-3">
                      <span
                        class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
                        aria-hidden="true"
                      >
                        <span class="i-lucide-workflow text-xl" />
                      </span>
                      <div class="min-w-0">
                        <h3
                          class="mb-1 text-base font-semibold leading-6 text-n-slate-12"
                        >
                          {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.TITLE') }}
                        </h3>
                        <p class="mb-0 text-sm leading-5 text-n-slate-11">
                          {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.HELP') }}
                        </p>
                      </div>
                    </div>
                    <Button
                      :label="
                        t(
                          isStageAutomationsExpanded(stage)
                            ? 'CRM_KANBAN.STAGE_AUTOMATIONS.HIDE'
                            : 'CRM_KANBAN.STAGE_AUTOMATIONS.OPEN'
                        )
                      "
                      :icon="
                        isStageAutomationsExpanded(stage)
                          ? 'i-lucide-chevron-up'
                          : 'i-lucide-chevron-down'
                      "
                      trailing-icon
                      slate
                      outline
                      md
                      class="min-h-11 shrink-0 bg-n-surface-1 !outline-n-weak"
                      :aria-expanded="isStageAutomationsExpanded(stage)"
                      @click="toggleStageAutomations(stage)"
                    />
                  </div>
                  <CrmStageAutomationsPanel
                    v-if="isStageAutomationsExpanded(stage)"
                    :stage="stage"
                    :pipeline-stages="form.stages"
                    :agents="agents"
                    :expanded="isStageAutomationsExpanded(stage)"
                    :show-header="false"
                  />
                </section>

                <details class="border-t border-n-weak pt-4">
                  <summary
                    class="min-h-11 cursor-pointer text-sm font-medium text-n-slate-11"
                  >
                    {{ t('CRM_KANBAN.PIPELINE_EDITOR.STAGE_OPTIONS') }}
                  </summary>
                  <div class="mt-4 grid gap-4">
                    <fieldset class="grid gap-3">
                      <legend class="mb-3 text-sm font-medium text-n-slate-12">
                        {{ t('CRM_KANBAN.PIPELINE_DRAWER.COLOR') }}
                      </legend>
                      <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
                        <button
                          v-for="color in stageColorChoices"
                          :key="color.value"
                          type="button"
                          :aria-pressed="stage.color === color.value"
                          class="flex min-h-11 items-center gap-3 rounded-xl border px-3 py-2 text-sm text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                          :class="
                            stage.color === color.value
                              ? 'border-n-brand bg-n-brand/5'
                              : 'border-n-slate-4 bg-n-surface-1'
                          "
                          @click="stage.color = color.value"
                        >
                          <span
                            class="h-5 w-5 shrink-0 rounded-md"
                            :class="color.swatch"
                            aria-hidden="true"
                          />
                          {{
                            t(`CRM_KANBAN.PIPELINE_EDITOR.COLORS.${color.name}`)
                          }}
                          <span
                            v-if="stage.color === color.value"
                            class="i-lucide-check ms-auto shrink-0 text-n-brand"
                          />
                        </button>
                      </div>
                      <label
                        class="flex min-h-14 items-center gap-3 rounded-xl border border-n-slate-4 bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12"
                      >
                        <input
                          v-model="stage.color"
                          type="color"
                          class="h-11 w-11 shrink-0 cursor-pointer rounded-lg border border-n-weak bg-transparent p-1"
                        />
                        <span class="grid gap-0.5">
                          <span>
                            {{ t('CRM_KANBAN.PIPELINE_EDITOR.CUSTOM_COLOR') }}
                          </span>
                          <span class="text-xs text-n-slate-11">
                            {{ stage.color }}
                          </span>
                        </span>
                      </label>
                    </fieldset>

                    <div class="grid gap-3 border-t border-n-weak pt-4">
                      <div
                        class="flex flex-wrap items-center justify-between gap-3"
                      >
                        <div>
                          <p class="mb-1 text-sm font-medium text-n-slate-12">
                            {{ t('CRM_KANBAN.PIPELINE_EDITOR.ORDER_LABEL') }}
                          </p>
                          <p class="mb-0 text-xs leading-5 text-n-slate-11">
                            {{ t('CRM_KANBAN.PIPELINE_EDITOR.ORDER_HELP') }}
                          </p>
                        </div>
                        <div class="flex flex-wrap gap-2">
                          <Button
                            :label="t('CRM_KANBAN.PIPELINE_EDITOR.MOVE_BEFORE')"
                            icon="i-lucide-arrow-up"
                            slate
                            outline
                            md
                            class="min-h-11 bg-n-surface-1 !outline-n-weak"
                            :disabled="index === 0"
                            @click="moveStage(index, -1)"
                          />
                          <Button
                            :label="t('CRM_KANBAN.PIPELINE_EDITOR.MOVE_AFTER')"
                            icon="i-lucide-arrow-down"
                            slate
                            outline
                            md
                            class="min-h-11 bg-n-surface-1 !outline-n-weak"
                            :disabled="index === form.stages.length - 1"
                            @click="moveStage(index, 1)"
                          />
                        </div>
                      </div>
                      <div
                        class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-3"
                      >
                        <div>
                          <p class="mb-1 text-sm font-medium text-n-slate-12">
                            {{
                              t(
                                'CRM_KANBAN.PIPELINE_EDITOR.DELETE_STATUS_TITLE'
                              )
                            }}
                          </p>
                          <p class="mb-0 text-xs leading-5 text-n-slate-11">
                            {{
                              t('CRM_KANBAN.PIPELINE_EDITOR.DELETE_STATUS_HELP')
                            }}
                          </p>
                        </div>
                        <Button
                          :label="t('CRM_KANBAN.PIPELINE_EDITOR.DELETE_STATUS')"
                          icon="i-lucide-trash-2"
                          ruby
                          outline
                          md
                          class="min-h-11 shrink-0 bg-n-surface-1"
                          :disabled="
                            form.stages.length === 1 || isDeletingStage
                          "
                          @click="removeStage(index)"
                        />
                      </div>
                    </div>
                  </div>
                </details>
                <section
                  class="grid gap-4 rounded-2xl border border-n-slate-5 bg-n-surface-1 p-4 sm:p-5"
                >
                  <div class="flex items-start gap-3">
                    <span
                      class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
                      aria-hidden="true"
                    >
                      <span class="i-lucide-megaphone text-xl" />
                    </span>
                    <div class="grid gap-1">
                      <span class="text-xs font-medium text-n-blue-11">
                        {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_TITLE') }}
                      </span>
                      <h4
                        class="mb-0 text-base font-semibold leading-6 text-n-slate-12"
                      >
                        {{
                          t('CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.TITLE')
                        }}
                      </h4>
                    </div>
                  </div>
                  <p class="mb-0 text-sm leading-6 text-n-slate-11">
                    {{ t('CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.HELP') }}
                  </p>
                  <details class="group">
                    <summary
                      class="flex min-h-16 cursor-pointer list-none items-center justify-between gap-3 rounded-xl bg-n-blue-2 px-4 py-3 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
                    >
                      <span class="grid gap-1">
                        <span class="text-xs text-n-slate-11">
                          {{
                            t(
                              'CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.CURRENT'
                            )
                          }}
                        </span>
                        <span class="font-medium text-n-slate-12">
                          {{
                            metaProgressChoices.find(
                              choice => choice.value === stage.funnel_stage_type
                            )?.label
                          }}
                        </span>
                      </span>
                      <span
                        class="flex shrink-0 items-center gap-2 text-n-brand"
                      >
                        {{
                          t('CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.CHANGE')
                        }}
                        <span
                          class="i-lucide-chevron-down transition-transform group-open:rotate-180"
                          aria-hidden="true"
                        />
                      </span>
                    </summary>
                    <fieldset class="mt-3 grid gap-2 sm:grid-cols-2">
                      <legend class="sr-only">
                        {{
                          t('CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.TITLE')
                        }}
                      </legend>
                      <label
                        v-for="choice in metaProgressChoices"
                        :key="choice.value"
                        class="relative flex cursor-pointer items-start gap-3 rounded-xl border p-3 transition-colors focus-within:outline focus-within:outline-2 focus-within:outline-n-brand"
                        :class="[
                          choice.value === '' ? 'sm:col-span-2' : '',
                          stage.funnel_stage_type === choice.value
                            ? 'border-n-brand bg-n-blue-2'
                            : 'border-n-slate-4 bg-n-surface-1 hover:border-n-slate-7',
                        ]"
                      >
                        <input
                          v-model="stage.funnel_stage_type"
                          type="radio"
                          :name="`meta-progress-${stage.id || index}`"
                          :value="choice.value"
                          class="sr-only"
                        />
                        <span
                          class="mt-0.5 shrink-0 text-lg text-n-slate-11"
                          :class="choice.icon"
                          aria-hidden="true"
                        />
                        <span class="min-w-0 flex-1">
                          <span
                            class="block text-sm font-semibold leading-5 text-n-slate-12"
                          >
                            {{ choice.label }}
                          </span>
                          <span
                            class="mt-1 block text-sm leading-5 text-n-slate-11"
                          >
                            {{ choice.description }}
                          </span>
                        </span>
                        <span
                          class="mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border"
                          :class="
                            stage.funnel_stage_type === choice.value
                              ? 'border-n-brand bg-n-brand text-white'
                              : 'border-n-slate-7'
                          "
                          aria-hidden="true"
                        >
                          <span
                            v-if="stage.funnel_stage_type === choice.value"
                            class="i-lucide-check text-xs"
                          />
                        </span>
                      </label>
                    </fieldset>
                  </details>
                  <details class="text-sm text-n-slate-11">
                    <summary class="min-h-11 cursor-pointer leading-6">
                      {{ t('CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.SETUP') }}
                    </summary>
                    <p class="mb-0 text-sm leading-6">
                      {{
                        t(
                          'CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.REQUIREMENTS'
                        )
                      }}
                    </p>
                  </details>
                </section>
              </div>
            </template>
          </section>

          <div
            v-if="isEditing && view === 'adjustments'"
            class="mt-3 grid gap-2"
          >
            <h3 class="mb-0 text-lg font-semibold text-n-slate-12">
              {{ t('CRM_KANBAN.PIPELINE_EDITOR.AD_RESULTS') }}
            </h3>
            <p class="mb-0 text-sm leading-6 text-n-slate-11">
              {{ t('CRM_KANBAN.PIPELINE_EDITOR.AD_RESULTS_HELP') }}
            </p>
          </div>
          <section
            v-if="isEditing && view === 'adjustments'"
            class="grid gap-4 border-t border-n-weak pt-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h3 class="mb-1 text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.GOOGLE_SYNC.TITLE') }}
                </h3>
                <p class="mb-0 text-xs leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.PIPELINE_EDITOR.GOOGLE_HELP') }}
                </p>
              </div>
              <label
                class="relative inline-flex min-h-11 min-w-11 shrink-0 cursor-pointer items-center"
              >
                <input
                  v-model="form.googleSync.enabled"
                  type="checkbox"
                  class="peer sr-only"
                  :aria-label="t('CRM_KANBAN.GOOGLE_SYNC.TOGGLE')"
                />
                <span
                  class="h-5 w-9 rounded-full bg-n-alpha-2 transition-colors after:absolute after:left-0.5 after:top-[0.875rem] after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-transform peer-checked:bg-n-brand peer-checked:after:translate-x-4"
                />
              </label>
            </div>

            <div
              v-if="form.googleSync.enabled"
              class="grid gap-4 rounded-2xl border border-n-slate-4 bg-n-surface-1 p-5"
            >
              <p class="mb-0 text-xs font-medium text-n-slate-11">
                {{ t('CRM_KANBAN.GOOGLE_SYNC.EVENTS') }}
              </p>
              <label class="flex items-center gap-2 text-sm text-n-slate-12">
                <input
                  v-model="form.googleSync.events.won"
                  type="checkbox"
                  class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                />
                <span>{{ t('CRM_KANBAN.GOOGLE_SYNC.EVENT_WON') }}</span>
              </label>
              <details class="grid gap-3">
                <summary
                  class="min-h-11 cursor-pointer text-sm text-n-slate-11"
                >
                  {{ t('CRM_KANBAN.PIPELINE_EDITOR.OTHER_EVENTS') }}
                </summary>
                <label class="flex items-center gap-2 text-sm text-n-slate-12">
                  <input
                    v-model="form.googleSync.events.lost"
                    type="checkbox"
                    class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                  />
                  <span>{{ t('CRM_KANBAN.GOOGLE_SYNC.EVENT_LOST') }}</span>
                </label>
                <label class="flex items-center gap-2 text-sm text-n-slate-12">
                  <input
                    v-model="form.googleSync.events.moved"
                    type="checkbox"
                    class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                  />
                  <span>{{ t('CRM_KANBAN.GOOGLE_SYNC.EVENT_MOVED') }}</span>
                </label>
              </details>

              <label class="grid gap-1 border-t border-n-weak pt-3">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.GOOGLE_SYNC.CONVERSION_NAME_WON') }}
                </span>
                <input
                  v-model="form.googleSync.conversionNames.won"
                  type="text"
                  class="reset-base !mb-0 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 text-sm text-n-slate-12 outline outline-1 outline-n-weak transition-all placeholder:text-n-slate-10 focus:outline-n-brand"
                  :placeholder="
                    t('CRM_KANBAN.GOOGLE_SYNC.CONVERSION_NAME_WON_PLACEHOLDER')
                  "
                />
                <span class="text-xs text-n-slate-11">
                  {{ t('CRM_KANBAN.GOOGLE_SYNC.CONVERSION_NAME_WON_HELP') }}
                </span>
              </label>

              <div class="grid gap-1 border-t border-n-weak pt-3">
                <label
                  for="google-conversions-feed-url"
                  class="text-xs font-medium text-n-slate-11"
                >
                  {{ t('CRM_KANBAN.GOOGLE_SYNC.FEED_URL') }}
                </label>
                <div class="flex items-center gap-2">
                  <input
                    id="google-conversions-feed-url"
                    :value="googleFeedUrl"
                    type="url"
                    readonly
                    class="reset-base !mb-0 min-w-0 flex-1 rounded-lg border-0 bg-n-solid-1 px-3 py-2.5 text-sm text-n-slate-11 outline outline-1 outline-n-weak placeholder:text-n-slate-10"
                    :placeholder="t('CRM_KANBAN.GOOGLE_SYNC.FEED_URL_PENDING')"
                  />
                  <Button
                    :label="t('CRM_KANBAN.GOOGLE_SYNC.COPY')"
                    icon="i-lucide-copy"
                    slate
                    faded
                    sm
                    :disabled="!googleFeedUrl"
                    @click="copyGoogleFeedUrl"
                  />
                </div>
              </div>

              <p class="mb-0 text-xs leading-5 text-n-slate-11">
                {{ t('CRM_KANBAN.GOOGLE_SYNC.INSTRUCTIONS') }}
              </p>
            </div>
          </section>

          <section
            v-if="isEditing && view === 'adjustments'"
            class="grid gap-4 border-t border-n-weak pt-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h3 class="mb-1 text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_TITLE') }}
                </h3>
                <p class="mb-0 text-xs leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.PIPELINE_EDITOR.META_HELP') }}
                </p>
              </div>
              <label
                class="relative inline-flex min-h-11 min-w-11 shrink-0 cursor-pointer items-center"
              >
                <input
                  v-model="form.metaSync.enabled"
                  :aria-label="t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_TITLE')"
                  type="checkbox"
                  class="peer sr-only"
                />
                <span
                  class="h-5 w-9 rounded-full bg-n-alpha-2 transition-colors after:absolute after:left-0.5 after:top-[0.875rem] after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-transform peer-checked:bg-n-brand peer-checked:after:translate-x-4"
                />
              </label>
            </div>

            <div
              v-if="form.metaSync.enabled"
              class="grid gap-4 rounded-2xl border border-n-slate-4 bg-n-surface-1 p-5"
            >
              <p class="mb-0 text-xs font-medium text-n-slate-11">
                {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_EVENTS') }}
              </p>
              <label class="flex items-center gap-2 text-sm text-n-slate-12">
                <input
                  v-model="form.metaSync.events.won"
                  type="checkbox"
                  class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                />
                <span>
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_EVENT_WON') }}
                </span>
              </label>
              <details class="grid gap-3">
                <summary
                  class="min-h-11 cursor-pointer text-sm text-n-slate-11"
                >
                  {{ t('CRM_KANBAN.PIPELINE_EDITOR.OTHER_EVENTS') }}
                </summary>
                <label class="flex items-center gap-2 text-sm text-n-slate-12">
                  <input
                    v-model="form.metaSync.events.lost"
                    type="checkbox"
                    class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                  />
                  <span>
                    {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_EVENT_LOST') }}
                  </span>
                </label>
                <label class="flex items-center gap-2 text-sm text-n-slate-12">
                  <input
                    v-model="form.metaSync.events.moved"
                    type="checkbox"
                    class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                  />
                  <span>
                    {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_EVENT_MOVED') }}
                  </span>
                </label>
              </details>

              <label class="grid gap-1 border-t border-n-weak pt-3">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_DATASET') }}
                </span>
                <input
                  v-model="form.metaSync.datasetId"
                  type="text"
                  class="reset-base !mb-0 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 text-sm text-n-slate-12 outline outline-1 outline-n-weak transition-all placeholder:text-n-slate-10 focus:outline-n-brand"
                  :placeholder="
                    t(
                      'CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_DATASET_PLACEHOLDER'
                    )
                  "
                />
                <span class="text-xs text-n-slate-11">
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_DATASET_HELP') }}
                </span>
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_PIXEL') }}
                </span>
                <input
                  :value="form.metaSync.pixelId"
                  type="text"
                  inputmode="numeric"
                  autocomplete="off"
                  aria-describedby="crm-pipeline-pixel-help"
                  class="reset-base !mb-0 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 font-mono text-sm text-n-slate-12 outline outline-1 outline-n-weak transition-all placeholder:font-sans placeholder:text-n-slate-10 focus:outline-n-brand"
                  :placeholder="
                    t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_PIXEL_PLACEHOLDER')
                  "
                  @input="onPixelInput"
                />
                <span
                  id="crm-pipeline-pixel-help"
                  class="text-xs text-n-slate-11"
                >
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_PIXEL_HELP') }}
                </span>
              </label>
            </div>
          </section>

          <section
            v-if="isEditing && view === 'adjustments'"
            class="grid gap-4 border-t border-n-weak pt-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h3 class="mb-1 text-base font-semibold text-n-slate-12">
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.INBOX_AUTOMATION') }}
                </h3>
                <p class="mb-0 text-xs leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.PIPELINE_DRAWER.INBOX_AUTOMATION_HELP') }}
                </p>
              </div>
            </div>

            <div class="grid gap-2">
              <p class="mb-0 text-xs font-medium text-n-slate-11">
                {{ t('CRM_KANBAN.PIPELINE_DRAWER.LINKED_INBOXES') }}
              </p>
              <div
                v-if="isLoadingPipelineInboxes"
                class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-3 text-xs text-n-slate-11"
              >
                {{ t('CRM_KANBAN.PIPELINE_DRAWER.LOADING_INBOXES') }}
              </div>
              <div
                v-else-if="pipelineInboxes.length === 0"
                class="rounded-lg border border-dashed border-n-weak px-3 py-3 text-xs leading-5 text-n-slate-10"
              >
                {{ t('CRM_KANBAN.PIPELINE_DRAWER.NO_LINKED_INBOXES') }}
              </div>
              <template v-else>
                <div
                  v-for="pipelineInbox in pipelineInboxes"
                  :key="pipelineInbox.id || pipelineInbox.inbox_id"
                  class="flex items-center justify-between gap-3 rounded-xl border border-n-slate-4 bg-n-surface-1 px-4 py-4"
                >
                  <div class="min-w-0">
                    <p
                      class="mb-1 truncate text-sm font-medium text-n-slate-12"
                    >
                      {{ pipelineInboxName(pipelineInbox) }}
                    </p>
                    <p class="mb-0 truncate text-xs text-n-slate-11">
                      {{
                        t('CRM_KANBAN.PIPELINE_DRAWER.ENTRY_STAGE_VALUE', {
                          stage: pipelineInboxStageName(pipelineInbox),
                        })
                      }}
                    </p>
                  </div>
                  <div class="flex shrink-0 items-center gap-2">
                    <span
                      class="rounded-md px-2 py-1 text-xs"
                      :class="
                        pipelineInbox.auto_create_card
                          ? 'bg-n-teal-3 text-n-teal-11'
                          : 'bg-n-alpha-2 text-n-slate-11'
                      "
                    >
                      {{
                        pipelineInbox.auto_create_card
                          ? t('CRM_KANBAN.PIPELINE_DRAWER.AUTO_CREATE_ON')
                          : t('CRM_KANBAN.PIPELINE_DRAWER.AUTO_CREATE_OFF')
                      }}
                    </span>
                    <Button
                      icon="i-lucide-trash-2"
                      ruby
                      ghost
                      sm
                      :is-loading="isRemovingPipelineInbox"
                      :disabled="
                        isRemovingPipelineInbox || isSavingPipelineInbox
                      "
                      :title="t('CRM_KANBAN.PIPELINE_DRAWER.REMOVE_INBOX')"
                      @click="removePipelineInbox(pipelineInbox)"
                    />
                  </div>
                </div>
              </template>
            </div>

            <div
              class="grid gap-4 rounded-2xl border border-n-slate-4 bg-n-surface-1 p-5"
            >
              <div class="grid gap-3 md:grid-cols-[1fr_1fr]">
                <label class="grid gap-1">
                  <span class="text-xs font-medium text-n-slate-11">
                    {{ t('CRM_KANBAN.PIPELINE_DRAWER.INBOX') }}
                  </span>
                  <ChoiceSelect
                    v-model="newPipelineInbox.inboxId"
                    :options="inboxChoices"
                    :aria-label="t('CRM_KANBAN.PIPELINE_DRAWER.INBOX')"
                    :disabled="availableInboxes.length === 0"
                    class="w-full"
                  />
                </label>

                <label class="grid gap-1">
                  <span class="text-xs font-medium text-n-slate-11">
                    {{ t('CRM_KANBAN.PIPELINE_DRAWER.ENTRY_STAGE') }}
                  </span>
                  <ChoiceSelect
                    v-model="newPipelineInbox.defaultStageId"
                    :options="entryStageChoices"
                    :aria-label="t('CRM_KANBAN.PIPELINE_DRAWER.ENTRY_STAGE')"
                    class="w-full"
                  />
                </label>
              </div>

              <div class="flex flex-wrap items-center justify-between gap-3">
                <label
                  class="flex min-w-0 items-center gap-2 text-sm text-n-slate-12"
                >
                  <input
                    v-model="newPipelineInbox.autoCreateCard"
                    type="checkbox"
                    class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                  />
                  <span>
                    {{ t('CRM_KANBAN.PIPELINE_DRAWER.AUTO_CREATE_CARD') }}
                  </span>
                </label>
                <Button
                  :label="t('CRM_KANBAN.PIPELINE_DRAWER.ADD_INBOX')"
                  icon="i-lucide-plus"
                  slate
                  faded
                  sm
                  :is-loading="isSavingPipelineInbox"
                  :disabled="!canAddPipelineInbox"
                  @click="addPipelineInbox"
                />
              </div>
            </div>
          </section>
          <p
            v-if="!isEditing && view === 'adjustments'"
            class="mb-0 rounded-xl bg-n-alpha-black2 p-4 text-sm text-n-slate-11"
          >
            {{ t('CRM_KANBAN.PIPELINE_EDITOR.INBOX_SAVE_FIRST') }}
          </p>
          <div
            v-if="isEditing && view === 'adjustments'"
            data-pipeline-archive
            class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-ruby-4 p-4"
          >
            <p class="mb-0 text-sm text-n-slate-11">
              {{ t('CRM_KANBAN.PIPELINE_DRAWER.ARCHIVE_HINT') }}
            </p>
            <Button
              :label="t('CRM_KANBAN.PIPELINE_DRAWER.ARCHIVE')"
              icon="i-lucide-archive"
              ruby
              faded
              :is-loading="isArchiving"
              @click="$emit('archive')"
            />
          </div>
        </div>
      </div>

      <div
        class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak px-6 py-4"
      >
        <!-- #1047: arquivar não fica no lugar onde, um passo antes, estava "Mais ajustes" — o mesmo
             clique arquivava o funil. Ele mora no fim de Mais ajustes, longe do rodapé. -->
        <span v-if="view === 'adjustments'" />
        <Button
          v-else
          :label="t('CRM_KANBAN.PIPELINE_EDITOR.MORE')"
          icon="i-lucide-settings"
          slate
          ghost
          @click="view = 'adjustments'"
        />
        <div class="flex items-center gap-2">
          <Button
            :label="t('CRM_KANBAN.PIPELINE_DRAWER.CANCEL')"
            slate
            faded
            @click="$emit('close')"
          />
          <Button
            :label="
              view === 'stage'
                ? t('CRM_KANBAN.PIPELINE_EDITOR.DONE')
                : isEditing
                  ? t('CRM_KANBAN.PIPELINE_DRAWER.SAVE')
                  : t('CRM_KANBAN.PIPELINE_DRAWER.CREATE')
            "
            icon="i-lucide-check"
            :is-loading="isSaving"
            :disabled="
              !canSubmit ||
              improving ||
              aiPanel?.isLoading ||
              aiPanel?.isSaving ||
              aiPanel?.loadFailed
            "
            @click="view === 'stage' ? (view = 'home') : onSubmit()"
          />
        </div>
      </div>
    </div>
  </transition>
</template>
