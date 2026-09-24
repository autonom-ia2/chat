<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';

const props = defineProps({
  show: { type: Boolean, default: false },
  inboxes: { type: Array, default: () => [] },
  pipelines: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const WEEKDAYS = [
  { value: 1, key: 'MON' },
  { value: 2, key: 'TUE' },
  { value: 3, key: 'WED' },
  { value: 4, key: 'THU' },
  { value: 5, key: 'FRI' },
  { value: 6, key: 'SAT' },
  { value: 0, key: 'SUN' },
];

const isLoading = ref(false);
const isSaving = ref(false);
const profiles = ref([]);
const stagesByPipeline = reactive({});
// keyed by inbox id
const forms = reactive({});
// per_agent links keyed by profile id -> [{ agent_id, agent_name, agent_email, link }]
const agentLinks = reactive({});

// Only calendar-enabled email inboxes can host a booking page.
const calendarInboxes = computed(() =>
  [...props.inboxes]
    .filter(inbox => inbox.calendar_enabled || inbox.calendarEnabled)
    .sort((a, b) => String(a.name || '').localeCompare(String(b.name || '')))
);

const profileByInboxId = computed(() =>
  profiles.value.reduce((acc, profile) => {
    acc[Number(profile.inbox_id)] = profile;
    return acc;
  }, {})
);

const stagesFor = inbox => {
  const pipelineId = forms[inbox.id]?.default_pipeline_id;
  if (!pipelineId) return [];
  return stagesByPipeline[String(pipelineId)] || [];
};

const toChoices = items =>
  items.map(item => ({ value: item.id, label: item.name }));

const pipelineChoices = computed(() => [
  { value: '', label: t('CRM_KANBAN.BOOKING.ADMIN.PIPELINE_DEFAULT') },
  ...toChoices(props.pipelines),
]);

const stageChoicesFor = inbox => [
  { value: '', label: t('CRM_KANBAN.BOOKING.ADMIN.STAGE_DEFAULT') },
  ...toChoices(stagesFor(inbox)),
];

const assignmentModeChoices = computed(() => [
  { value: 'fixed', label: t('CRM_KANBAN.BOOKING.ADMIN.MODE_FIXED') },
  { value: 'per_agent', label: t('CRM_KANBAN.BOOKING.ADMIN.MODE_PER_AGENT') },
]);

const assigneeChoices = computed(() => [
  { value: '', label: t('CRM_KANBAN.BOOKING.ADMIN.ASSIGNEE_DEFAULT') },
  ...toChoices(props.agents),
]);

const loadStages = async pipelineId => {
  if (!pipelineId || stagesByPipeline[String(pipelineId)]) return;
  try {
    const stages = await store.dispatch(
      'crmKanban/fetchPipelineStages',
      pipelineId
    );
    stagesByPipeline[String(pipelineId)] = stages;
  } catch {
    stagesByPipeline[String(pipelineId)] = [];
  }
};

const buildForm = inbox => {
  const profile = profileByInboxId.value[Number(inbox.id)] || {};
  const wh = profile.working_hours || {};
  return {
    id: profile.id || null,
    enabled: profile.id ? Boolean(profile.enabled) : false,
    public_url: profile.public_url || '',
    title: profile.title || '',
    description: profile.description || '',
    duration_minutes: profile.duration_minutes || 30,
    buffer_minutes: profile.buffer_minutes ?? 0,
    booking_window_days: profile.booking_window_days || 14,
    timezone:
      profile.timezone ||
      Intl.DateTimeFormat().resolvedOptions().timeZone ||
      'UTC',
    start_hour: wh.start_hour ?? 9,
    end_hour: wh.end_hour ?? 17,
    weekdays: Array.isArray(wh.weekdays) ? [...wh.weekdays] : [1, 2, 3, 4, 5],
    default_pipeline_id: profile.default_pipeline_id || '',
    default_stage_id: profile.default_stage_id || '',
    default_assignee_id: profile.default_assignee_id || '',
    assignment_mode: profile.assignment_mode || 'fixed',
    calendar_shared: Boolean(profile.calendar_shared),
  };
};

const loadAgentLinks = async profileId => {
  if (!profileId) return;
  try {
    agentLinks[profileId] = await store.dispatch(
      'crmKanban/fetchBookingAgentLinks',
      profileId
    );
  } catch {
    agentLinks[profileId] = [];
  }
};

const generateLink = async (profileId, agentId, inboxId) => {
  try {
    await store.dispatch('crmKanban/upsertBookingAgentLink', {
      id: profileId,
      agent_id: agentId,
      inbox_id: inboxId,
    });
    await loadAgentLinks(profileId);
    useAlert(t('CRM_KANBAN.BOOKING.ADMIN.LINK_GENERATED'));
  } catch {
    useAlert(t('CRM_KANBAN.BOOKING.ADMIN.SAVE_ERROR'));
  }
};

const onAssignmentModeChange = inbox => {
  const form = forms[inbox.id];
  if (form.id && form.assignment_mode === 'per_agent') loadAgentLinks(form.id);
};

const resetForms = () => {
  Object.keys(forms).forEach(key => delete forms[key]);
  calendarInboxes.value.forEach(inbox => {
    forms[inbox.id] = buildForm(inbox);
    if (forms[inbox.id].default_pipeline_id) {
      loadStages(forms[inbox.id].default_pipeline_id);
    }
    if (forms[inbox.id].id && forms[inbox.id].assignment_mode === 'per_agent') {
      loadAgentLinks(forms[inbox.id].id);
    }
  });
};

const loadProfiles = async () => {
  isLoading.value = true;
  try {
    profiles.value = await store.dispatch('crmKanban/fetchBookingProfiles');
    resetForms();
  } catch {
    useAlert(t('CRM_KANBAN.BOOKING.ADMIN.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const onPipelineChange = inbox => {
  const form = forms[inbox.id];
  form.default_stage_id = '';
  if (form.default_pipeline_id) loadStages(form.default_pipeline_id);
};

const toggleWeekday = (inbox, day) => {
  const form = forms[inbox.id];
  if (form.weekdays.includes(day)) {
    form.weekdays = form.weekdays.filter(d => d !== day);
  } else {
    form.weekdays = [...form.weekdays, day];
  }
};

const payloadFor = inbox => {
  const form = forms[inbox.id];
  return {
    inbox_id: inbox.id,
    enabled: form.enabled,
    title: form.title,
    description: form.description,
    duration_minutes: Number(form.duration_minutes),
    buffer_minutes: Number(form.buffer_minutes),
    booking_window_days: Number(form.booking_window_days),
    timezone: form.timezone,
    default_pipeline_id: form.default_pipeline_id || null,
    default_stage_id: form.default_stage_id || null,
    default_assignee_id: form.default_assignee_id || null,
    assignment_mode: form.assignment_mode,
    calendar_shared: form.calendar_shared,
    working_hours: {
      start_hour: Number(form.start_hour),
      end_hour: Number(form.end_hour),
      weekdays: form.weekdays,
    },
  };
};

const saveProfile = async inbox => {
  const form = forms[inbox.id];
  isSaving.value = true;
  try {
    const payload = payloadFor(inbox);
    const saved = form.id
      ? await store.dispatch('crmKanban/updateBookingProfile', {
          id: form.id,
          ...payload,
        })
      : await store.dispatch('crmKanban/createBookingProfile', payload);

    profiles.value = [
      ...profiles.value.filter(p => Number(p.inbox_id) !== Number(inbox.id)),
      saved,
    ];
    forms[inbox.id] = buildForm(inbox);
    if (saved.assignment_mode === 'per_agent') loadAgentLinks(saved.id);
    useAlert(t('CRM_KANBAN.BOOKING.ADMIN.SAVED'));
  } catch {
    useAlert(t('CRM_KANBAN.BOOKING.ADMIN.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const copyUrl = async url => {
  await copyTextToClipboard(url);
  useAlert(t('CRM_KANBAN.BOOKING.ADMIN.URL_COPIED'));
};

watch(
  () => props.show,
  show => {
    if (show) loadProfiles();
  },
  { immediate: true }
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
// Guia; sinaliza que está aberta para ele se desviar do botão Salvar.
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
      class="fixed inset-y-0 ltr:right-0 rtl:left-0 z-50 flex h-full w-[44rem] max-w-full flex-col overflow-hidden border-n-weak bg-n-surface-2 shadow-lg ltr:border-l rtl:border-r"
    >
      <div
        class="flex items-start justify-between gap-4 border-b border-n-weak px-6 py-5"
      >
        <div class="min-w-0">
          <h2 class="mb-1 text-lg font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.BOOKING.ADMIN.TITLE') }}
          </h2>
          <p class="mb-0 text-sm leading-5 text-n-slate-11">
            {{ t('CRM_KANBAN.BOOKING.ADMIN.SUBTITLE') }}
          </p>
        </div>
        <Button icon="i-lucide-x" slate ghost sm @click="$emit('close')" />
      </div>

      <div class="flex-1 overflow-y-auto px-6 py-5">
        <div v-if="isLoading" class="flex h-full items-center justify-center">
          <Spinner />
        </div>

        <div v-else-if="calendarInboxes.length === 0" class="py-12 text-center">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.BOOKING.ADMIN.EMPTY_TITLE') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CRM_KANBAN.BOOKING.ADMIN.EMPTY_DESCRIPTION') }}
          </p>
        </div>

        <div v-else class="grid gap-4">
          <section
            v-for="inbox in calendarInboxes"
            :key="inbox.id"
            class="grid gap-4 rounded-lg border border-n-weak bg-n-alpha-black2 p-4"
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
                  v-model="forms[inbox.id].enabled"
                  type="checkbox"
                  class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                />
                <span>{{ t('CRM_KANBAN.BOOKING.ADMIN.ENABLED') }}</span>
              </label>
            </div>

            <!-- Public URL (fixed mode only — in per_agent the base slug 404s;
                 agents share their individual links instead) -->
            <div
              v-if="
                forms[inbox.id].public_url &&
                forms[inbox.id].assignment_mode === 'fixed'
              "
              class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2"
            >
              <span class="min-w-0 flex-1 truncate text-xs text-n-slate-11">
                {{ forms[inbox.id].public_url }}
              </span>
              <Button
                :label="t('CRM_KANBAN.BOOKING.ADMIN.COPY_URL')"
                icon="i-lucide-copy"
                xs
                slate
                faded
                @click="copyUrl(forms[inbox.id].public_url)"
              />
            </div>

            <div class="grid gap-3 md:grid-cols-2">
              <label class="grid gap-1 md:col-span-2">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.TITLE_LABEL') }}
                </span>
                <input
                  v-model="forms[inbox.id].title"
                  type="text"
                  :placeholder="t('CRM_KANBAN.BOOKING.ADMIN.TITLE_PLACEHOLDER')"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                />
              </label>

              <label class="grid gap-1 md:col-span-2">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.DESCRIPTION_LABEL') }}
                </span>
                <textarea
                  v-model="forms[inbox.id].description"
                  rows="2"
                  class="reset-base !mb-0 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.DURATION') }}
                </span>
                <input
                  v-model="forms[inbox.id].duration_minutes"
                  type="number"
                  min="5"
                  max="480"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.BUFFER') }}
                </span>
                <input
                  v-model="forms[inbox.id].buffer_minutes"
                  type="number"
                  min="0"
                  max="240"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.WINDOW') }}
                </span>
                <input
                  v-model="forms[inbox.id].booking_window_days"
                  type="number"
                  min="1"
                  max="90"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.TIMEZONE') }}
                </span>
                <input
                  v-model="forms[inbox.id].timezone"
                  type="text"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.START_HOUR') }}
                </span>
                <input
                  v-model="forms[inbox.id].start_hour"
                  type="number"
                  min="0"
                  max="23"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.END_HOUR') }}
                </span>
                <input
                  v-model="forms[inbox.id].end_hour"
                  type="number"
                  min="1"
                  max="24"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                />
              </label>

              <div class="grid gap-1 md:col-span-2">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.WEEKDAYS') }}
                </span>
                <div class="flex flex-wrap gap-1.5">
                  <button
                    v-for="day in WEEKDAYS"
                    :key="day.value"
                    type="button"
                    class="rounded-md border px-2.5 py-1 text-xs"
                    :class="
                      forms[inbox.id].weekdays.includes(day.value)
                        ? 'border-n-brand bg-n-brand/10 text-n-brand'
                        : 'border-n-weak text-n-slate-11'
                    "
                    @click="toggleWeekday(inbox, day.value)"
                  >
                    {{ t('CRM_KANBAN.BOOKING.ADMIN.WEEKDAY_' + day.key) }}
                  </button>
                </div>
              </div>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.PIPELINE') }}
                </span>
                <ChoiceSelect
                  v-model="forms[inbox.id].default_pipeline_id"
                  :options="pipelineChoices"
                  :aria-label="t('CRM_KANBAN.BOOKING.ADMIN.PIPELINE')"
                  class="w-full"
                  @change="onPipelineChange(inbox)"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.STAGE') }}
                </span>
                <ChoiceSelect
                  v-model="forms[inbox.id].default_stage_id"
                  :options="stageChoicesFor(inbox)"
                  :aria-label="t('CRM_KANBAN.BOOKING.ADMIN.STAGE')"
                  :disabled="!forms[inbox.id].default_pipeline_id"
                  class="w-full"
                />
              </label>

              <!-- Attribution mode: fixed (one assignee) vs per-agent (one link each) -->
              <label class="grid gap-1 md:col-span-2">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.ASSIGNMENT_MODE') }}
                </span>
                <ChoiceSelect
                  v-model="forms[inbox.id].assignment_mode"
                  :options="assignmentModeChoices"
                  :aria-label="t('CRM_KANBAN.BOOKING.ADMIN.ASSIGNMENT_MODE')"
                  class="w-full"
                  @change="onAssignmentModeChange(inbox)"
                />
              </label>

              <!-- Shared mailbox: per-agent availability from CRM instead of free/busy -->
              <label
                class="flex items-start gap-2 md:col-span-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
              >
                <input
                  v-model="forms[inbox.id].calendar_shared"
                  type="checkbox"
                  class="mt-0.5 h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                />
                <span class="min-w-0">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.CALENDAR_SHARED') }}
                  <span class="block text-xs text-n-slate-11">
                    {{ t('CRM_KANBAN.BOOKING.ADMIN.CALENDAR_SHARED_HINT') }}
                  </span>
                </span>
              </label>

              <!-- FIXED: single assignee -->
              <label
                v-if="forms[inbox.id].assignment_mode === 'fixed'"
                class="grid gap-1 md:col-span-2"
              >
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.ASSIGNEE') }}
                </span>
                <ChoiceSelect
                  v-model="forms[inbox.id].default_assignee_id"
                  :options="assigneeChoices"
                  :aria-label="t('CRM_KANBAN.BOOKING.ADMIN.ASSIGNEE')"
                  class="w-full"
                />
              </label>

              <!-- PER-AGENT: one link per eligible agent (mailbox members) -->
              <div
                v-else
                class="grid gap-2 md:col-span-2 rounded-lg border border-n-weak bg-n-solid-1 p-3"
              >
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.AGENT_LINKS') }}
                </span>
                <p
                  v-if="!forms[inbox.id].id"
                  class="mb-0 text-xs text-n-slate-11"
                >
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.AGENT_LINKS_SAVE_FIRST') }}
                </p>
                <p
                  v-else-if="!(agentLinks[forms[inbox.id].id] || []).length"
                  class="mb-0 text-xs text-n-slate-11"
                >
                  {{ t('CRM_KANBAN.BOOKING.ADMIN.AGENT_LINKS_EMPTY') }}
                </p>
                <div
                  v-for="row in agentLinks[forms[inbox.id].id] || []"
                  :key="row.agent_id"
                  class="flex items-center gap-2"
                >
                  <span class="min-w-0 flex-1 truncate text-sm text-n-slate-12">
                    {{ row.agent_name }}
                  </span>
                  <Button
                    v-if="row.link"
                    :label="t('CRM_KANBAN.BOOKING.ADMIN.COPY_URL')"
                    icon="i-lucide-copy"
                    xs
                    slate
                    faded
                    @click="copyUrl(row.link.public_url)"
                  />
                  <Button
                    v-else
                    :label="t('CRM_KANBAN.BOOKING.ADMIN.GENERATE_LINK')"
                    icon="i-lucide-link"
                    xs
                    slate
                    @click="
                      generateLink(forms[inbox.id].id, row.agent_id, inbox.id)
                    "
                  />
                </div>
              </div>
            </div>

            <div class="flex justify-end">
              <Button
                :label="t('CRM_KANBAN.BOOKING.ADMIN.SAVE')"
                icon="i-lucide-check"
                sm
                :is-loading="isSaving"
                @click="saveProfile(inbox)"
              />
            </div>
          </section>
        </div>
      </div>
    </div>
  </transition>
</template>
