<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';

const props = defineProps({
  show: { type: Boolean, default: false },
  inboxes: { type: Array, default: () => [] },
  settings: { type: Array, default: () => [] },
  pipelines: { type: Array, default: () => [] },
  stagesByPipeline: { type: Object, default: () => ({}) },
  isLoading: { type: Boolean, default: false },
  isLoadingStages: { type: Boolean, default: false },
  // Resultado do último salvamento, vindo da página: { inboxId, ok, at }.
  saveResult: { type: Object, default: null },
});

const emit = defineEmits(['close', 'save', 'loadPipelineStages']);

const { t } = useI18n();
const forms = reactive({});
// Caixas com salvamento em andamento e caixas salvas nesta abertura da janela.
const pending = reactive(new Set());
const saved = reactive(new Set());

const settingByInboxId = computed(() =>
  props.settings.reduce((result, setting) => {
    result[Number(setting.inbox_id)] = setting;
    return result;
  }, {})
);

const sortedInboxes = computed(() =>
  [...props.inboxes].sort((first, second) =>
    String(first.name || '').localeCompare(String(second.name || ''))
  )
);

// Caixa ainda sem configuração nasce com a criação automática marcada: é o que
// quase toda implantação quer, e era o passo que mais ficava para trás.
// Configuração já salva mantém o que a pessoa escolheu.
const toForm = (setting = {}) => {
  const jaConfigurada = Boolean(setting.inbox_id);
  return {
    crm_enabled: Boolean(setting.crm_enabled),
    visibility_mode: setting.visibility_mode || 'all_inbox_cards',
    auto_create_card: jaConfigurada ? Boolean(setting.auto_create_card) : true,
    default_pipeline_id: setting.default_pipeline_id || '',
    default_stage_id: setting.default_stage_id || '',
  };
};

const formFromSetting = inboxId =>
  toForm(settingByInboxId.value[Number(inboxId)]);

const FIELDS = [
  'crm_enabled',
  'visibility_mode',
  'auto_create_card',
  'default_pipeline_id',
  'default_stage_id',
];

const sameForm = (first, second) =>
  FIELDS.every(field => String(first[field]) === String(second[field]));

const formFor = inbox => forms[inbox.id] || {};
const isDirty = inbox =>
  Boolean(forms[inbox.id]) &&
  !sameForm(forms[inbox.id], formFromSetting(inbox.id));
const isSavingInbox = inbox => pending.has(Number(inbox.id));
const isSavedInbox = inbox => saved.has(Number(inbox.id)) && !isDirty(inbox);

const dirtyCount = computed(
  () => sortedInboxes.value.filter(inbox => isDirty(inbox)).length
);

const resetForms = () => {
  Object.keys(forms).forEach(key => {
    delete forms[key];
  });
  pending.clear();
  saved.clear();
  sortedInboxes.value.forEach(inbox => {
    forms[inbox.id] = formFromSetting(inbox.id);
  });
};

// Dados novos do servidor só substituem o formulário da caixa que acabou de
// salvar ou que não tem alteração pendente: salvar uma caixa não pode apagar o
// que a pessoa mudou em outra.
const syncForms = previousSettings => {
  const previousById = (previousSettings || []).reduce((result, setting) => {
    result[Number(setting.inbox_id)] = setting;
    return result;
  }, {});

  sortedInboxes.value.forEach(inbox => {
    const fresh = formFromSetting(inbox.id);
    const current = forms[inbox.id];
    if (!current) {
      forms[inbox.id] = fresh;
      return;
    }
    const previous = previousById[Number(inbox.id)];
    const hadNoEdits = !previous || sameForm(current, toForm(previous));
    if (hadNoEdits) forms[inbox.id] = fresh;
  });
};

const toOption = (value, label) => ({ value, label });

const visibilityOptions = computed(() => [
  toOption('all_inbox_cards', t('CRM_KANBAN.INBOX_SETTINGS.ALL_INBOX_CARDS')),
  toOption('assigned_only', t('CRM_KANBAN.INBOX_SETTINGS.ASSIGNED_ONLY')),
]);

const pipelineOptions = computed(() => [
  toOption('', t('CRM_KANBAN.INBOX_SETTINGS.NO_DEFAULT_PIPELINE')),
  ...props.pipelines.map(pipeline => toOption(pipeline.id, pipeline.name)),
]);

const stagesFor = inbox => {
  const pipelineId = formFor(inbox).default_pipeline_id;
  if (!pipelineId) return [];
  return props.stagesByPipeline[String(pipelineId)] || [];
};

const stageOptionsFor = inbox => [
  toOption('', t('CRM_KANBAN.INBOX_SETTINGS.FIRST_STAGE')),
  ...stagesFor(inbox).map(stage => toOption(stage.id, stage.name)),
];

const onVisibilityChange = (inbox, value) => {
  // Clicar de novo na opção escolhida desmarca no ComboBox; visibilidade não
  // pode ficar vazia.
  if (value) formFor(inbox).visibility_mode = value;
};

const onPipelineChange = (inbox, value) => {
  const form = formFor(inbox);
  form.default_pipeline_id = value || '';
  form.default_stage_id = '';
  if (form.default_pipeline_id) {
    emit('loadPipelineStages', form.default_pipeline_id);
  }
};

const onStageChange = (inbox, value) => {
  formFor(inbox).default_stage_id = value || '';
};

const nomeDoFunil = pipelineId => {
  const pipeline = props.pipelines.find(
    item => String(item.id) === String(pipelineId)
  );
  return pipeline?.name || '';
};

// Salvar aqui passa a mover a criação automática de cards para o funil
// escolhido. Quando a caixa já alimentava outro funil, a pessoa precisa saber
// disso antes de salvar, com os dois nomes na tela.
const trocaDeFunil = inbox => {
  const anterior =
    settingByInboxId.value[Number(inbox.id)]?.default_pipeline_id;
  const atual = formFor(inbox).default_pipeline_id;
  if (!anterior || !atual) return null;
  if (String(anterior) === String(atual)) return null;
  if (!formFor(inbox).crm_enabled) return null;

  return { de: nomeDoFunil(anterior), para: nomeDoFunil(atual) };
};

const onCrmEnabledChange = inbox => {
  const form = formFor(inbox);
  if (!form.crm_enabled) {
    form.auto_create_card = false;
  }
};

const saveInbox = inbox => {
  const form = formFor(inbox);
  saved.delete(Number(inbox.id));
  pending.add(Number(inbox.id));
  emit('save', {
    inboxId: inbox.id,
    crm_enabled: form.crm_enabled,
    visibility_mode: form.visibility_mode,
    auto_create_card: form.crm_enabled && form.auto_create_card,
    default_pipeline_id: form.default_pipeline_id || null,
    default_stage_id: form.default_stage_id || null,
  });
};

watch(
  () => props.show,
  show => {
    if (show) resetForms();
  },
  { immediate: true }
);

watch(
  () => [props.inboxes, props.settings],
  (_current, previous) => {
    if (props.show) syncForms(previous?.[1]);
  }
);

// A página informa o resultado de cada salvamento. Sucesso: a caixa passa a
// mostrar "Salvo" e adota o que o servidor gravou. Falha: a página já avisou
// por alerta; aqui só libera o botão e mantém o que a pessoa digitou.
watch(
  () => props.saveResult,
  result => {
    const inboxId = Number(result?.inboxId);
    if (!result || !pending.has(inboxId)) return;
    pending.delete(inboxId);
    if (!result.ok) return;
    saved.add(inboxId);
    forms[inboxId] = formFromSetting(inboxId);
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
      class="fixed inset-y-0 ltr:right-0 rtl:left-0 z-50 flex h-full w-[44rem] max-w-full flex-col overflow-hidden border-n-weak bg-n-surface-2 shadow-lg ltr:border-l rtl:border-r"
    >
      <div
        class="flex items-start justify-between gap-4 border-b border-n-weak px-6 py-5"
      >
        <div class="min-w-0">
          <h2 class="mb-1 text-lg font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.TITLE') }}
          </h2>
          <p class="mb-0 text-sm leading-5 text-n-slate-11">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.SUBTITLE') }}
          </p>
        </div>
        <Button icon="i-lucide-x" slate ghost sm @click="$emit('close')" />
      </div>

      <div class="flex-1 overflow-y-auto px-6 py-5">
        <div v-if="isLoading" class="flex h-full items-center justify-center">
          <Spinner />
        </div>

        <div v-else-if="sortedInboxes.length === 0" class="py-12 text-center">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.EMPTY_TITLE') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.EMPTY_DESCRIPTION') }}
          </p>
        </div>

        <div v-else class="grid gap-4">
          <section
            v-for="inbox in sortedInboxes"
            :key="inbox.id"
            class="grid gap-4 rounded-lg border bg-n-alpha-black2 p-4"
            :class="isDirty(inbox) ? 'border-n-amber-7' : 'border-n-weak'"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="mb-1 truncate text-sm font-medium text-n-slate-12">
                  {{ inbox.name }}
                </p>
                <p class="mb-0 truncate text-xs text-n-slate-11">
                  {{ inbox.channel_type }}
                </p>
              </div>
              <label
                class="flex shrink-0 items-center gap-2 text-sm text-n-slate-12"
              >
                <input
                  v-model="formFor(inbox).crm_enabled"
                  type="checkbox"
                  class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                  @change="onCrmEnabledChange(inbox)"
                />
                <span>{{ t('CRM_KANBAN.INBOX_SETTINGS.CRM_ENABLED') }}</span>
              </label>
            </div>

            <div class="grid gap-3 md:grid-cols-[1fr_1fr]">
              <div class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.INBOX_SETTINGS.VISIBILITY') }}
                </span>
                <ComboBox
                  :model-value="formFor(inbox).visibility_mode"
                  :options="visibilityOptions"
                  @update:model-value="onVisibilityChange(inbox, $event)"
                />
              </div>

              <div class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.INBOX_SETTINGS.DEFAULT_PIPELINE') }}
                </span>
                <ComboBox
                  :model-value="formFor(inbox).default_pipeline_id"
                  :options="pipelineOptions"
                  :placeholder="
                    t('CRM_KANBAN.INBOX_SETTINGS.NO_DEFAULT_PIPELINE')
                  "
                  @update:model-value="onPipelineChange(inbox, $event)"
                />
              </div>

              <div class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.INBOX_SETTINGS.DEFAULT_STAGE') }}
                </span>
                <ComboBox
                  :model-value="formFor(inbox).default_stage_id"
                  :options="stageOptionsFor(inbox)"
                  :placeholder="t('CRM_KANBAN.INBOX_SETTINGS.FIRST_STAGE')"
                  :disabled="!formFor(inbox).default_pipeline_id"
                  @update:model-value="onStageChange(inbox, $event)"
                />
              </div>

              <p
                v-if="trocaDeFunil(inbox)"
                class="mb-0 flex items-start gap-2 rounded-lg bg-n-amber-3 px-3 py-2 text-sm text-n-slate-12"
                role="status"
              >
                <span
                  class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
                />
                <span>
                  {{
                    t('CRM_KANBAN.INBOX_SETTINGS.PIPELINE_SWITCH', {
                      de: trocaDeFunil(inbox).de,
                      para: trocaDeFunil(inbox).para,
                    })
                  }}
                </span>
              </p>

              <div class="flex items-end justify-between gap-3">
                <label
                  class="flex min-w-0 items-center gap-2 text-sm text-n-slate-12"
                >
                  <input
                    v-model="formFor(inbox).auto_create_card"
                    type="checkbox"
                    class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                    :disabled="!formFor(inbox).crm_enabled"
                  />
                  <span>
                    {{ t('CRM_KANBAN.INBOX_SETTINGS.AUTO_CREATE') }}
                  </span>
                </label>
                <span
                  v-if="isSavedInbox(inbox)"
                  class="inline-flex shrink-0 items-center gap-1 text-sm font-medium text-n-teal-11"
                  role="status"
                >
                  <span class="i-lucide-circle-check size-4" />
                  {{ t('CRM_KANBAN.INBOX_SETTINGS.SAVED') }}
                </span>
                <Button
                  v-else
                  :label="t('CRM_KANBAN.INBOX_SETTINGS.SAVE')"
                  icon="i-lucide-check"
                  sm
                  :disabled="!isDirty(inbox) || isLoadingStages"
                  :is-loading="isSavingInbox(inbox)"
                  @click="saveInbox(inbox)"
                />
              </div>
            </div>
          </section>
        </div>
      </div>

      <div
        class="flex items-center justify-between gap-3 border-t border-n-weak px-6 py-4"
      >
        <p class="mb-0 text-sm text-n-slate-11">
          <template v-if="dirtyCount">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.UNSAVED', { count: dirtyCount }) }}
          </template>
        </p>
        <Button
          :label="t('CRM_KANBAN.INBOX_SETTINGS.DONE')"
          :color="dirtyCount ? 'slate' : 'blue'"
          @click="$emit('close')"
        />
      </div>
    </div>
  </transition>
</template>
