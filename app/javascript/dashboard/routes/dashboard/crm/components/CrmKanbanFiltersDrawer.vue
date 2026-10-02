<script setup>
import { computed, nextTick, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { defaultFilters } from 'dashboard/store/modules/crmKanban';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  filters: { type: Object, required: true },
  viewMode: { type: String, default: 'kanban' },
  pipelineName: { type: String, default: '' },
  currentUserId: { type: [String, Number], default: '' },
  inboxChoices: { type: Array, default: () => [] },
  ownerChoices: { type: Array, default: () => [] },
  priorityChoices: { type: Array, default: () => [] },
  followUpStatusChoices: { type: Array, default: () => [] },
  companyChoices: { type: Array, default: () => [] },
  companySearch: { type: String, default: '' },
  companyLoading: { type: Boolean, default: false },
  responsibleChoices: { type: Array, default: () => [] },
  teamChoices: { type: Array, default: () => [] },
  stageOptions: { type: Array, default: () => [] },
  labelOptions: { type: Array, default: () => [] },
  campaignFilterOptions: { type: Array, default: () => [] },
  staleChoices: { type: Array, default: () => [] },
  linkedChoices: { type: Array, default: () => [] },
  resultChoices: { type: Array, default: () => [] },
  canManageAi: { type: Boolean, default: false },
  companyFilterAvailable: { type: Boolean, default: true },
});

const emit = defineEmits(['close', 'apply', 'clear', 'search-company']);
const { t } = useI18n();
const drawerElement = ref(null);
const draft = reactive(defaultFilters());
const selectedCompanyOption = ref(null);
let previousActiveElement = null;

const drawerFocusableSelector = [
  'button:not([disabled])',
  '[href]',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  'summary',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

const copyFilters = source => ({
  ...defaultFilters(),
  ...source,
  stageIds: [...(source.stageIds || [])],
  labelIds: [...(source.labelIds || [])],
  campaignSourceIds: [...(source.campaignSourceIds || [])],
});

const syncDraft = () => {
  Object.assign(draft, copyFilters(props.filters));
};

const isSelected = (items, value) =>
  items.some(item => String(item) === String(value));

const toggleValue = (key, value) => {
  const current = draft[key] || [];
  draft[key] = isSelected(current, value)
    ? current.filter(item => String(item) !== String(value))
    : [...current, value];
};

const isStageSelected = stageId => isSelected(draft.stageIds, stageId);
const isLabelSelected = labelId => isSelected(draft.labelIds, labelId);
const isCampaignSelected = sourceId =>
  isSelected(draft.campaignSourceIds, sourceId);

const shortcutIsActive = shortcut => {
  switch (shortcut) {
    case 'any-owner':
      return !draft.ownerId && !draft.responsibleKind;
    case 'mine':
      return (
        Boolean(props.currentUserId) &&
        String(draft.ownerId) === String(props.currentUserId) &&
        !draft.responsibleKind
      );
    case 'none':
      return draft.responsibleKind === 'none' && !draft.ownerId;
    case 'overdue':
      return draft.followUpStatus === 'overdue';
    default:
      return false;
  }
};

const applyShortcut = shortcut => {
  switch (shortcut) {
    case 'any-owner':
      draft.ownerId = '';
      draft.responsibleKind = '';
      break;
    case 'mine':
      if (props.currentUserId) {
        draft.ownerId = props.currentUserId;
        draft.responsibleKind = '';
      }
      break;
    case 'none':
      draft.ownerId = '';
      draft.responsibleKind = 'none';
      break;
    case 'overdue':
      draft.followUpStatus =
        draft.followUpStatus === 'overdue' ? '' : 'overdue';
      break;
    default:
      break;
  }
};

const scoreRangeError = computed(() => {
  const invalidValue = value => {
    if (value === '') return false;
    const number = Number(value);
    return !Number.isInteger(number) || number < 0 || number > 100;
  };
  if (invalidValue(draft.scoreMin) || invalidValue(draft.scoreMax)) {
    return t('CRM_KANBAN.FILTERS.SCORE_INVALID');
  }

  if (
    draft.scoreMin !== '' &&
    draft.scoreMax !== '' &&
    Number(draft.scoreMin) > Number(draft.scoreMax)
  ) {
    return t('CRM_KANBAN.FILTERS.SCORE_ORDER_INVALID');
  }

  return '';
});

const companyChoicesWithSelection = computed(() => {
  const choices = [...props.companyChoices];
  const selected = selectedCompanyOption.value;
  if (
    selected &&
    !choices.some(item => String(item.value) === String(selected.value))
  ) {
    choices.push(selected);
  }
  return choices;
});

const rememberCompanySelection = value => {
  if (value === '' || value === 'none' || value == null) {
    selectedCompanyOption.value = null;
    return;
  }

  selectedCompanyOption.value =
    props.companyChoices.find(item => String(item.value) === String(value)) ||
    selectedCompanyOption.value;
};

const apply = () => {
  if (scoreRangeError.value) return;
  emit('apply', copyFilters(draft));
};
const clear = () => emit('clear');

watch(
  () => props.show,
  show => {
    if (!show) {
      if (previousActiveElement?.isConnected) previousActiveElement.focus();
      previousActiveElement = null;
      return;
    }
    previousActiveElement =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    syncDraft();
    selectedCompanyOption.value =
      props.companyChoices.find(
        item => String(item.value) === String(draft.companyId)
      ) || null;
    nextTick(() => drawerElement.value?.focus());
  }
);

const trapDrawerFocus = event => {
  if (event.key !== 'Tab' || document.querySelector('dialog[open]')) return;

  const focusable = Array.from(
    drawerElement.value?.querySelectorAll(drawerFocusableSelector) || []
  ).filter(element => element.getClientRects().length > 0);
  if (!focusable.length) {
    event.preventDefault();
    drawerElement.value?.focus();
    return;
  }

  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (
    event.shiftKey &&
    (document.activeElement === first ||
      document.activeElement === drawerElement.value)
  ) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
};

useKeyboardEvents({
  Escape: {
    action: () => {
      if (props.show) emit('close');
    },
    allowOnFocusedInput: true,
  },
});

useFixedPanelPresence(computed(() => props.show));
</script>

<template>
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
  >
    <aside
      v-if="show"
      ref="drawerElement"
      data-crm-kanban-filters-drawer
      role="dialog"
      aria-modal="true"
      aria-labelledby="crm-kanban-filters-title"
      tabindex="-1"
      class="fixed inset-y-0 z-50 flex h-full w-[40rem] max-w-full flex-col overflow-hidden border-n-weak bg-n-surface-1 shadow-lg ltr:right-0 ltr:border-l rtl:left-0 rtl:border-r"
      @keydown="trapDrawerFocus"
    >
      <header
        class="flex items-start justify-between gap-4 bg-n-blue-12 px-6 py-5 sm:px-8"
      >
        <div class="min-w-0">
          <h2
            id="crm-kanban-filters-title"
            tabindex="-1"
            class="mb-1 text-2xl font-semibold text-n-slate-1 outline-none"
          >
            {{ t('CRM_KANBAN.FILTERS.DRAWER_TITLE') }}
          </h2>
          <p
            v-if="pipelineName"
            class="mb-0 truncate text-sm leading-6 text-n-slate-4"
          >
            {{ pipelineName }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          slate
          ghost
          :aria-label="t('CRM_KANBAN.ACTIONS.CLOSE')"
          class="!text-n-slate-1"
          @click="emit('close')"
        />
      </header>

      <div class="min-h-0 flex-1 overflow-y-auto px-5 py-5 sm:px-8">
        <p class="mb-5 text-sm leading-6 text-n-slate-11">
          {{ t('CRM_KANBAN.FILTERS.DRAWER_DESCRIPTION') }}
        </p>

        <div class="mb-5">
          <p
            class="mb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('CRM_KANBAN.FILTERS.SHORTCUTS') }}
          </p>
          <div class="flex flex-wrap gap-2">
            <Button
              :label="t('CRM_KANBAN.FILTERS.SHORTCUT_ANY_OWNER')"
              outline
              slate
              :aria-pressed="shortcutIsActive('any-owner')"
              class="!min-h-11 !rounded-lg"
              :class="
                shortcutIsActive('any-owner')
                  ? '!outline-n-blue-7 !bg-n-blue-2 !text-n-blue-11'
                  : '!outline-n-weak !bg-n-surface-1'
              "
              @click="applyShortcut('any-owner')"
            />
            <Button
              :label="t('CRM_KANBAN.FILTERS.SHORTCUT_MINE')"
              outline
              slate
              :aria-pressed="shortcutIsActive('mine')"
              class="!min-h-11 !rounded-lg"
              :class="
                shortcutIsActive('mine')
                  ? '!outline-n-blue-7 !bg-n-blue-2 !text-n-blue-11'
                  : '!outline-n-weak !bg-n-surface-1'
              "
              @click="applyShortcut('mine')"
            />
            <Button
              :label="t('CRM_KANBAN.FILTERS.SHORTCUT_NONE')"
              outline
              slate
              :aria-pressed="shortcutIsActive('none')"
              class="!min-h-11 !rounded-lg"
              :class="
                shortcutIsActive('none')
                  ? '!outline-n-blue-7 !bg-n-blue-2 !text-n-blue-11'
                  : '!outline-n-weak !bg-n-surface-1'
              "
              @click="applyShortcut('none')"
            />
            <Button
              :label="t('CRM_KANBAN.FILTERS.SHORTCUT_OVERDUE')"
              outline
              slate
              :aria-pressed="shortcutIsActive('overdue')"
              class="!min-h-11 !rounded-lg"
              :class="
                shortcutIsActive('overdue')
                  ? '!outline-n-blue-7 !bg-n-blue-2 !text-n-blue-11'
                  : '!outline-n-weak !bg-n-surface-1'
              "
              @click="applyShortcut('overdue')"
            />
          </div>
        </div>

        <div class="grid">
          <details class="group border-t border-n-weak">
            <summary
              class="flex min-h-16 cursor-pointer list-none items-center justify-between gap-3 py-4 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
            >
              <span class="min-w-0">
                <strong class="block text-base font-semibold text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.COMPANY') }}
                </strong>
                <span class="mt-1 block text-sm leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.FILTERS.COMPANY_HELP') }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-down size-5 shrink-0 text-n-slate-10 group-open:rotate-180"
                aria-hidden="true"
              />
            </summary>
            <div class="grid gap-4 pb-5">
              <div v-if="companyFilterAvailable" class="grid gap-3">
                <Input
                  custom-input-class="!min-h-11 !rounded-lg !bg-n-surface-1"
                  :model-value="companySearch"
                  :label="t('CRM_KANBAN.FILTERS.COMPANY_SEARCH')"
                  :placeholder="
                    t('CRM_KANBAN.FILTERS.COMPANY_SEARCH_PLACEHOLDER')
                  "
                  @input="emit('search-company', $event.target.value)"
                />
                <ChoiceSelect
                  v-model="draft.companyId"
                  :options="companyChoicesWithSelection"
                  :aria-label="t('CRM_KANBAN.FILTERS.COMPANY')"
                  :placeholder="t('CRM_KANBAN.FILTERS.ALL_COMPANIES')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                  @change="rememberCompanySelection"
                />
                <p v-if="companyLoading" class="mb-0 text-xs text-n-slate-10">
                  {{ t('CRM_KANBAN.FILTERS.COMPANY_SEARCHING') }}
                </p>
                <p
                  v-else-if="companySearch && !companyChoices.length"
                  class="mb-0 text-xs text-n-slate-10"
                >
                  {{ t('CRM_KANBAN.FILTERS.COMPANY_EMPTY') }}
                </p>
              </div>
              <span
                v-else
                class="inline-flex rounded-lg border border-n-weak px-3 py-2 text-xs font-medium text-n-slate-10"
              >
                {{ t('CRM_KANBAN.FILTERS.UNAVAILABLE') }}
              </span>
            </div>
          </details>

          <details class="group border-t border-n-weak">
            <summary
              class="flex min-h-16 cursor-pointer list-none items-center justify-between gap-3 py-4 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
            >
              <span class="min-w-0">
                <strong class="block text-base font-semibold text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.GROUP_OPPORTUNITY') }}
                </strong>
                <span class="mt-1 block text-sm leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.FILTERS.GROUP_OPPORTUNITY_HELP') }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-down size-5 shrink-0 text-n-slate-10 group-open:rotate-180"
                aria-hidden="true"
              />
            </summary>
            <div class="grid gap-5 pb-5">
              <div class="grid gap-2">
                <span
                  id="crm-kanban-filters-stage-label"
                  class="text-sm font-medium text-n-slate-12"
                >
                  {{ t('CRM_KANBAN.FILTERS.STAGE') }}
                </span>
                <div
                  role="group"
                  aria-labelledby="crm-kanban-filters-stage-label"
                  class="flex max-h-40 flex-wrap gap-2 overflow-y-auto rounded-lg border border-n-weak p-3"
                >
                  <button
                    v-for="stage in stageOptions"
                    :key="stage.value"
                    type="button"
                    :aria-pressed="isStageSelected(stage.value)"
                    class="inline-flex min-h-11 items-center gap-1 rounded-lg border px-3 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    :class="
                      isStageSelected(stage.value)
                        ? 'border-n-brand bg-n-blue-2 text-n-blue-11'
                        : 'border-n-weak bg-n-surface-1 text-n-slate-11 hover:border-n-slate-6 hover:text-n-slate-12'
                    "
                    @click="toggleValue('stageIds', stage.value)"
                  >
                    {{ stage.label }}
                  </button>
                  <span
                    v-if="!stageOptions.length"
                    class="p-2 text-sm text-n-slate-10"
                  >
                    {{ t('CRM_KANBAN.FILTERS.STAGE_PLACEHOLDER') }}
                  </span>
                </div>
              </div>

              <div class="grid gap-2">
                <span
                  id="crm-kanban-filters-labels-label"
                  class="text-sm font-medium text-n-slate-12"
                >
                  {{ t('CRM_KANBAN.FILTERS.LABELS') }}
                </span>
                <div
                  role="group"
                  aria-labelledby="crm-kanban-filters-labels-label"
                  class="flex max-h-40 flex-wrap gap-2 overflow-y-auto rounded-lg border border-n-weak p-3"
                >
                  <button
                    v-for="label in labelOptions"
                    :key="label.value"
                    type="button"
                    :aria-pressed="isLabelSelected(label.value)"
                    class="inline-flex min-h-11 items-center gap-2 rounded-lg border px-3 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    :class="
                      isLabelSelected(label.value)
                        ? 'border-n-brand bg-n-blue-2 text-n-blue-11'
                        : 'border-n-weak bg-n-surface-1 text-n-slate-11 hover:border-n-slate-6 hover:text-n-slate-12'
                    "
                    @click="toggleValue('labelIds', label.value)"
                  >
                    <span class="i-lucide-tag size-3.5" aria-hidden="true" />
                    {{ label.label }}
                  </button>
                  <span
                    v-if="!labelOptions.length"
                    class="p-2 text-sm text-n-slate-10"
                  >
                    {{ t('CRM_KANBAN.FILTERS.LABELS_PLACEHOLDER') }}
                  </span>
                </div>
              </div>

              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.LINKED') }}
                </span>
                <ChoiceSelect
                  v-model="draft.standalone"
                  :options="linkedChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.LINKED')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>

              <label v-if="viewMode === 'list'" class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.RESULT') }}
                </span>
                <ChoiceSelect
                  v-model="draft.result"
                  :options="resultChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.RESULT')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>
            </div>
          </details>

          <details class="group border-t border-n-weak">
            <summary
              class="flex min-h-16 cursor-pointer list-none items-center justify-between gap-3 py-4 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
            >
              <span class="min-w-0">
                <strong class="block text-base font-semibold text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.GROUP_ATTENTION') }}
                </strong>
                <span class="mt-1 block text-sm leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.FILTERS.GROUP_ATTENTION_HELP') }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-down size-5 shrink-0 text-n-slate-10 group-open:rotate-180"
                aria-hidden="true"
              />
            </summary>
            <div class="grid gap-5 pb-5">
              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.PRIORITY') }}
                </span>
                <ChoiceSelect
                  v-model="draft.priority"
                  :options="priorityChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.PRIORITY')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>

              <div class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.SCORE_RANGE') }}
                </span>
                <p class="mb-0 text-xs leading-5 text-n-slate-10">
                  {{ t('CRM_KANBAN.FILTERS.SCORE_HELP') }}
                </p>
                <div class="grid grid-cols-2 gap-3">
                  <Input
                    custom-input-class="!min-h-11 !rounded-lg !bg-n-surface-1"
                    v-model="draft.scoreMin"
                    type="number"
                    min="0"
                    max="100"
                    step="1"
                    :label="t('CRM_KANBAN.FILTERS.SCORE_MIN')"
                  />
                  <Input
                    custom-input-class="!min-h-11 !rounded-lg !bg-n-surface-1"
                    v-model="draft.scoreMax"
                    type="number"
                    min="0"
                    max="100"
                    step="1"
                    :label="t('CRM_KANBAN.FILTERS.SCORE_MAX')"
                  />
                </div>
                <p
                  v-if="scoreRangeError"
                  role="alert"
                  class="mb-0 text-xs leading-5 text-n-ruby-11"
                >
                  {{ scoreRangeError }}
                </p>
              </div>

              <label
                v-if="canManageAi"
                class="flex min-h-11 items-center gap-3 text-sm text-n-slate-12"
              >
                <input
                  v-model="draft.aiPending"
                  type="checkbox"
                  class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
                />
                {{ t('CRM_KANBAN.FILTERS.AI_PENDING') }}
              </label>
            </div>
          </details>

          <details class="group border-t border-n-weak">
            <summary
              class="flex min-h-16 cursor-pointer list-none items-center justify-between gap-3 py-4 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
            >
              <span class="min-w-0">
                <strong class="block text-base font-semibold text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.GROUP_ATTENDANCE') }}
                </strong>
                <span class="mt-1 block text-sm leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.FILTERS.GROUP_ATTENDANCE_HELP') }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-down size-5 shrink-0 text-n-slate-10 group-open:rotate-180"
                aria-hidden="true"
              />
            </summary>
            <div class="grid gap-5 pb-5">
              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.OWNER') }}
                </span>
                <ChoiceSelect
                  v-model="draft.ownerId"
                  :options="ownerChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.OWNER')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.RESPONSIBLE') }}
                </span>
                <ChoiceSelect
                  v-model="draft.responsibleKind"
                  :options="responsibleChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.RESPONSIBLE')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.TEAM') }}
                </span>
                <ChoiceSelect
                  v-model="draft.teamId"
                  :options="teamChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.TEAM')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.INBOX') }}
                </span>
                <ChoiceSelect
                  v-model="draft.inboxId"
                  :options="inboxChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.INBOX')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>

              <div class="grid gap-2">
                <span
                  id="crm-kanban-filters-campaign-label"
                  class="text-sm font-medium text-n-slate-12"
                >
                  {{ t('CRM_KANBAN.FILTERS.CAMPAIGN') }}
                </span>
                <div
                  role="group"
                  aria-labelledby="crm-kanban-filters-campaign-label"
                  class="flex max-h-40 flex-wrap gap-2 overflow-y-auto rounded-lg border border-n-weak p-3"
                >
                  <button
                    v-for="campaign in campaignFilterOptions"
                    :key="campaign.value"
                    type="button"
                    :aria-pressed="isCampaignSelected(campaign.value)"
                    class="inline-flex min-h-11 items-center rounded-lg border px-3 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    :class="
                      isCampaignSelected(campaign.value)
                        ? 'border-n-brand bg-n-blue-2 text-n-blue-11'
                        : 'border-n-weak bg-n-surface-1 text-n-slate-11 hover:border-n-slate-6 hover:text-n-slate-12'
                    "
                    @click="toggleValue('campaignSourceIds', campaign.value)"
                  >
                    {{ campaign.label }}
                  </button>
                  <span
                    v-if="!campaignFilterOptions.length"
                    class="p-2 text-sm text-n-slate-10"
                  >
                    {{ t('CRM_KANBAN.FILTERS.CAMPAIGN_PLACEHOLDER') }}
                  </span>
                </div>
              </div>
            </div>
          </details>

          <details class="group border-t border-n-weak">
            <summary
              class="flex min-h-16 cursor-pointer list-none items-center justify-between gap-3 py-4 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
            >
              <span class="min-w-0">
                <strong class="block text-base font-semibold text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.GROUP_ACTIVITY') }}
                </strong>
                <span class="mt-1 block text-sm leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.FILTERS.GROUP_ACTIVITY_HELP') }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-down size-5 shrink-0 text-n-slate-10 group-open:rotate-180"
                aria-hidden="true"
              />
            </summary>
            <div class="grid gap-5 pb-5">
              <div class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.VALUE_RANGE') }}
                </span>
                <div class="grid grid-cols-2 gap-3">
                  <Input
                    custom-input-class="!min-h-11 !rounded-lg !bg-n-surface-1"
                    v-model="draft.valueMin"
                    type="number"
                    min="0"
                    :label="t('CRM_KANBAN.FILTERS.VALUE_MIN')"
                  />
                  <Input
                    custom-input-class="!min-h-11 !rounded-lg !bg-n-surface-1"
                    v-model="draft.valueMax"
                    type="number"
                    min="0"
                    :label="t('CRM_KANBAN.FILTERS.VALUE_MAX')"
                  />
                </div>
              </div>

              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.FOLLOW_UP') }}
                </span>
                <ChoiceSelect
                  v-model="draft.followUpStatus"
                  :options="followUpStatusChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.FOLLOW_UP')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.FILTERS.STALE') }}
                </span>
                <ChoiceSelect
                  v-model="draft.staleDays"
                  :options="staleChoices"
                  :aria-label="t('CRM_KANBAN.FILTERS.STALE')"
                  class="w-full [&>button]:!min-h-11 [&>button]:!bg-n-surface-1 [&>button]:!outline-n-weak"
                />
              </label>
            </div>
          </details>
        </div>
      </div>

      <footer
        class="flex shrink-0 items-center justify-between gap-3 border-t border-n-weak bg-n-surface-1 px-5 py-4 sm:px-8"
      >
        <Button
          :label="t('CRM_KANBAN.ACTIONS.CLEAR_FILTERS')"
          outline
          slate
          class="!min-h-11 !rounded-lg !outline-n-weak"
          @click="clear"
        />
        <Button
          :label="t('CRM_KANBAN.ACTIONS.VIEW_OPPORTUNITIES')"
          :disabled="Boolean(scoreRangeError)"
          class="!min-h-11 !rounded-lg"
          @click="apply"
        />
      </footer>
    </aside>
  </transition>
</template>
