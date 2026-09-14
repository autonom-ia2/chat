<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// The parent pipeline drawer still passes :inboxes, but the AI now picks the
// re-engagement template server-side, so this panel no longer declares/reads it
// (an extra attr on the parent is a harmless no-op in Vue 3).
const props = defineProps({
  pipelineId: { type: [String, Number], required: true },
  stages: { type: Array, default: () => [] },
});

const { t } = useI18n();

const isLoading = ref(false);
const isSaving = ref(false);
const loadFailed = ref(false);
const form = reactive({
  enabled: true,
  autoMoveEnabled: false,
  attributeExtractionEnabled: false,
  scoreEnabled: false,
  callbackEnabled: true,
  callbackMode: 'reminder',
  staleHours: 48,
  stageCriteria: {},
  autoFollowup: {
    enabled: false,
    mode: 'auto_send',
    allowedDays: [1, 2, 3, 4, 5],
    maxTouches: 3,
    intervalsHours: [20, 72, 168],
    quietHours: { start: 8, end: 20, tz: 'contact' },
    toneInstructions: '',
  },
});

// Keep the editable interval list in sync with the requested number of touches,
// padding new slots with sensible defaults and trimming extras.
const FOLLOWUP_DEFAULT_INTERVALS = [20, 72, 168];
const syncIntervals = () => {
  const count = Math.max(
    1,
    Math.min(3, Number(form.autoFollowup.maxTouches) || 1)
  );
  const next = [];
  for (let index = 0; index < count; index += 1) {
    const existing = form.autoFollowup.intervalsHours[index];
    next.push(
      Number.isFinite(existing)
        ? existing
        : (FOLLOWUP_DEFAULT_INTERVALS[index] ?? 168)
    );
  }
  form.autoFollowup.maxTouches = count;
  form.autoFollowup.intervalsHours = next;
};

const followupModes = ['auto_send', 'ai_reminder'];
const weekdays = [1, 2, 3, 4, 5, 6, 0];
const isReminder = computed(() => form.autoFollowup.mode === 'ai_reminder');
const toggleDay = day => {
  const days = form.autoFollowup.allowedDays;
  if (days.includes(day)) {
    if (days.length > 1)
      form.autoFollowup.allowedDays = days.filter(value => value !== day);
  } else {
    form.autoFollowup.allowedDays = [...days, day];
  }
};
const scheduleValid = computed(() => {
  const { allowedDays, quietHours, intervalsHours, maxTouches } =
    form.autoFollowup;
  return (
    allowedDays.length > 0 &&
    Number.isInteger(quietHours.start) &&
    Number.isInteger(quietHours.end) &&
    quietHours.start >= 0 &&
    quietHours.end <= 24 &&
    quietHours.start < quietHours.end &&
    maxTouches >= 1 &&
    maxTouches <= 3 &&
    intervalsHours.length === maxTouches &&
    intervalsHours.every(
      (hours, index) =>
        Number.isInteger(hours) &&
        hours > 0 &&
        (!index || hours > intervalsHours[index - 1])
    )
  );
});
const canSave = computed(
  () =>
    Boolean(props.pipelineId) &&
    (!form.autoFollowup.enabled || scheduleValid.value)
);

const loadSettings = async () => {
  if (!props.pipelineId) return;
  isLoading.value = true;
  loadFailed.value = false;
  try {
    const response = await CrmKanbanAPI.getAiSettings(props.pipelineId);
    const payload = response.data.payload || {};
    form.enabled = payload.enabled !== false;
    form.autoMoveEnabled = payload.auto_move_enabled === true;
    form.attributeExtractionEnabled =
      payload.attribute_extraction_enabled === true;
    form.scoreEnabled = payload.score_enabled === true;
    form.callbackEnabled = payload.callback_enabled !== false;
    form.callbackMode = ['reminder', 'message', 'both'].includes(
      payload.callback_mode
    )
      ? payload.callback_mode
      : 'reminder';
    form.staleHours = Number(payload.stale_hours || 48);
    form.stageCriteria = Object.fromEntries(
      (payload.stages || []).map(stage => [stage.id, stage.ai_criteria || ''])
    );
    const followup = payload.auto_followup || {};
    const intervals = Array.isArray(followup.intervals_hours)
      ? followup.intervals_hours.map(Number)
      : [20, 72, 168];
    form.autoFollowup = {
      enabled: followup.enabled === true,
      mode: followup.mode || 'auto_send',
      allowedDays: followup.allowed_days || [0, 1, 2, 3, 4, 5, 6],
      maxTouches: Number(followup.max_touches ?? 3),
      intervalsHours: intervals,
      quietHours: {
        start: Number(followup.quiet_hours?.start ?? 8),
        end: Number(followup.quiet_hours?.end ?? 20),
        tz: followup.quiet_hours?.tz || 'contact',
      },
      toneInstructions: followup.tone_instructions || '',
    };
    syncIntervals();
  } catch {
    loadFailed.value = true;
    useAlert(t('CRM_KANBAN.AI_SETTINGS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

// `silent` is set when the parent pipeline drawer's "Salvar funil" (master save)
// triggers this — it shows its own success alert and rethrows so the parent can
// react, avoiding a duplicate toast.
const saveSettings = async ({ silent = false } = {}) => {
  if (!canSave.value) {
    useAlert(t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.INVALID_SCHEDULE'));
    return false;
  }
  isSaving.value = true;
  try {
    const response = await CrmKanbanAPI.updateAiSettings(props.pipelineId, {
      ai_settings: {
        enabled: form.enabled,
        auto_move_enabled: form.autoMoveEnabled,
        attribute_extraction_enabled: form.attributeExtractionEnabled,
        score_enabled: form.scoreEnabled,
        callback_enabled: form.callbackEnabled,
        callback_mode: form.callbackMode,
        stale_hours: form.staleHours,
        auto_followup: form.autoFollowup.enabled
          ? {
              enabled: form.autoFollowup.enabled,
              mode: form.autoFollowup.mode,
              allowed_days: form.autoFollowup.allowedDays,
              max_touches: form.autoFollowup.maxTouches,
              intervals_hours: form.autoFollowup.intervalsHours,
              quiet_hours: {
                start: form.autoFollowup.quietHours.start,
                end: form.autoFollowup.quietHours.end,
                tz: form.autoFollowup.quietHours.tz,
              },
              tone_instructions: form.autoFollowup.toneInstructions,
            }
          : { enabled: false },
      },
      stage_criteria: form.stageCriteria,
    });
    const payload = response.data.payload || {};
    form.enabled = payload.enabled !== false;
    form.autoMoveEnabled = payload.auto_move_enabled === true;
    form.attributeExtractionEnabled =
      payload.attribute_extraction_enabled === true;
    form.scoreEnabled = payload.score_enabled === true;
    form.callbackEnabled = payload.callback_enabled !== false;
    form.callbackMode = ['reminder', 'message', 'both'].includes(
      payload.callback_mode
    )
      ? payload.callback_mode
      : 'reminder';
    form.staleHours = Number(payload.stale_hours || 48);
    if (!silent) useAlert(t('CRM_KANBAN.AI_SETTINGS.SAVE_SUCCESS'));
    return true;
  } catch {
    // Keep the drawer open when AI settings could not be saved.
    useAlert(t('CRM_KANBAN.AI_SETTINGS.SAVE_ERROR'));
    return false;
  } finally {
    isSaving.value = false;
  }
};

// Let the parent pipeline drawer save this panel as part of "Salvar funil".
defineExpose({ saveSettings });

watch(
  () => props.pipelineId,
  () => {
    loadSettings();
  },
  { immediate: true }
);
</script>

<template>
  <section
    class="grid gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 p-4"
  >
    <div>
      <h3 class="mb-1 text-sm font-medium text-n-slate-12">
        {{ t('CRM_KANBAN.AI_SETTINGS.TITLE') }}
      </h3>
      <p class="mb-0 text-xs leading-5 text-n-slate-11">
        {{ t('CRM_KANBAN.AI_SETTINGS.HELP') }}
      </p>
    </div>

    <p v-if="isLoading" class="mb-0 text-sm text-n-slate-11">
      {{ t('CRM_KANBAN.AI_SETTINGS.LOADING') }}
    </p>

    <p v-else-if="loadFailed" class="mb-0 text-sm text-n-ruby-11">
      {{ t('CRM_KANBAN.AI_SETTINGS.LOAD_ERROR') }}
    </p>

    <template v-else>
      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          v-model="form.enabled"
          type="checkbox"
          class="rounded border-n-weak"
        />
        {{ t('CRM_KANBAN.AI_SETTINGS.ENABLED') }}
      </label>

      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          v-model="form.autoMoveEnabled"
          type="checkbox"
          class="rounded border-n-weak"
        />
        {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_MOVE') }}
      </label>

      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <input
          v-model="form.attributeExtractionEnabled"
          type="checkbox"
          class="mt-0.5 rounded border-n-weak"
        />
        <span class="grid gap-0.5">
          <span>{{ t('CRM_KANBAN.AI_SETTINGS.ATTRIBUTE_EXTRACTION') }}</span>
          <span class="text-xs text-n-slate-11">
            {{ t('CRM_KANBAN.AI_SETTINGS.ATTRIBUTE_EXTRACTION_HELP') }}
          </span>
        </span>
      </label>

      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <input
          v-model="form.scoreEnabled"
          type="checkbox"
          class="mt-0.5 rounded border-n-weak"
        />
        <span class="grid gap-0.5">
          <span>{{ t('CRM_KANBAN.AI_SETTINGS.SCORE_ENABLED') }}</span>
          <span class="text-xs text-n-slate-11">
            {{ t('CRM_KANBAN.AI_SETTINGS.SCORE_ENABLED_HELP') }}
          </span>
        </span>
      </label>

      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <input
          v-model="form.callbackEnabled"
          type="checkbox"
          class="mt-0.5 rounded border-n-weak"
        />
        <span class="grid gap-0.5">
          <span>{{ t('CRM_KANBAN.AI_SETTINGS.CALLBACK') }}</span>
          <span class="text-xs text-n-slate-11">
            {{ t('CRM_KANBAN.AI_SETTINGS.CALLBACK_HELP') }}
          </span>
        </span>
      </label>

      <label v-if="form.callbackEnabled" class="grid gap-1 pl-6">
        <span class="text-xs text-n-slate-11">
          {{ t('CRM_KANBAN.AI_SETTINGS.CALLBACK_MODE') }}
        </span>
        <select
          v-model="form.callbackMode"
          class="reset-base w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
        >
          <option value="reminder">
            {{ t('CRM_KANBAN.AI_SETTINGS.CALLBACK_MODE_REMINDER') }}
          </option>
          <option value="message">
            {{ t('CRM_KANBAN.AI_SETTINGS.CALLBACK_MODE_MESSAGE') }}
          </option>
          <option value="both">
            {{ t('CRM_KANBAN.AI_SETTINGS.CALLBACK_MODE_BOTH') }}
          </option>
        </select>
      </label>

      <label class="grid gap-1">
        <span class="text-xs text-n-slate-11">
          {{ t('CRM_KANBAN.AI_SETTINGS.STALE_HOURS') }}
        </span>
        <input
          v-model.number="form.staleHours"
          type="number"
          min="1"
          class="reset-base w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
        />
      </label>

      <div class="grid gap-3">
        <div
          v-for="stage in stages.filter(item => item.id)"
          :key="stage.id"
          class="grid gap-1"
        >
          <span class="text-xs font-medium text-n-slate-12">
            {{ stage.name }}
          </span>
          <textarea
            v-model="form.stageCriteria[stage.id]"
            rows="3"
            class="reset-base w-full rounded-lg border-0 bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
            :placeholder="t('CRM_KANBAN.AI_SETTINGS.CRITERIA_PLACEHOLDER')"
          />
        </div>
      </div>

      <section class="grid gap-3 rounded-lg bg-n-alpha-2 p-3">
        <div>
          <h4
            class="mb-1 flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
          >
            <span class="i-lucide-message-circle-reply text-base" />
            {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.TITLE') }}
          </h4>
          <p class="mb-0 text-xs leading-5 text-n-slate-11">
            {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.AI_HELP') }}
          </p>
        </div>

        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input
            v-model="form.autoFollowup.enabled"
            type="checkbox"
            class="rounded border-n-weak"
          />
          {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.ENABLED') }}
        </label>

        <template v-if="form.autoFollowup.enabled">
          <div
            class="grid gap-3 sm:grid-cols-2"
            role="radiogroup"
            :aria-label="t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.ACTION_LABEL')"
          >
            <label
              v-for="mode in followupModes"
              :key="mode"
              class="flex min-w-0 cursor-pointer items-start gap-2 rounded-lg border p-3"
              :class="
                form.autoFollowup.mode === mode
                  ? 'border-n-brand bg-n-brand/5'
                  : 'border-n-weak bg-n-surface-2'
              "
            >
              <input
                v-model="form.autoFollowup.mode"
                type="radio"
                :name="`followup-mode-${pipelineId}`"
                :value="mode"
                class="mt-0.5 shrink-0"
              />
              <span class="min-w-0">
                <span class="block text-sm font-medium text-n-slate-12">{{
                  t(`CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.MODES.${mode}.TITLE`)
                }}</span>
                <span class="mt-1 block text-xs leading-5 text-n-slate-11">{{
                  t(`CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.MODES.${mode}.HELP`)
                }}</span>
              </span>
            </label>
          </div>
          <label class="grid gap-1">
            <span class="text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.MAX_TOUCHES') }}
            </span>
            <input
              v-model.number="form.autoFollowup.maxTouches"
              type="number"
              min="1"
              max="3"
              class="reset-base w-full rounded-lg border-0 bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
              @change="syncIntervals"
            />
          </label>

          <div class="grid gap-1.5">
            <span class="text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.EVALUATION_OFFSETS') }}
            </span>
            <div
              v-for="(interval, index) in form.autoFollowup.intervalsHours"
              :key="index"
              class="flex flex-wrap items-center gap-3"
            >
              <span class="w-20 shrink-0 text-xs text-n-slate-11">
                {{
                  t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.TOUCH_LABEL', {
                    n: index + 1,
                  })
                }}
              </span>
              <input
                v-model.number="form.autoFollowup.intervalsHours[index]"
                :aria-label="
                  t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.TOUCH_LABEL', {
                    n: index + 1,
                  })
                "
                type="number"
                min="1"
                class="reset-base box-border h-9 w-24 shrink-0 rounded-lg border-0 bg-n-surface-2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
              />
              <span
                v-if="isReminder"
                class="rounded bg-n-teal-3 px-2 py-1 text-[10px] font-medium text-n-teal-11"
              >
                {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.REMINDER_BADGE') }}
              </span>
              <span
                v-else-if="Number(interval) < 24"
                class="rounded px-2 py-1 text-[10px] font-medium text-n-teal-11 bg-n-teal-3"
              >
                {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.SESSION_BADGE') }}
              </span>
              <span
                v-else
                class="rounded px-2 py-1 text-[10px] font-medium text-n-amber-11 bg-n-amber-3"
              >
                {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.TEMPLATE_BADGE') }}
              </span>
            </div>
          </div>

          <div class="grid gap-3">
            <span class="text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.SCHEDULE_LABEL') }}
            </span>
            <div class="flex flex-wrap items-end gap-3">
              <label class="grid gap-1">
                <span class="text-xs text-n-slate-11">
                  {{
                    t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.QUIET_HOURS_START')
                  }}
                </span>
                <input
                  v-model.number="form.autoFollowup.quietHours.start"
                  type="number"
                  min="0"
                  max="23"
                  class="reset-base w-20 rounded-lg border-0 bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
                />
              </label>
              <label class="grid gap-1">
                <span class="text-xs text-n-slate-11">
                  {{
                    t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.QUIET_HOURS_END')
                  }}
                </span>
                <input
                  v-model.number="form.autoFollowup.quietHours.end"
                  type="number"
                  min="0"
                  max="23"
                  class="reset-base w-20 rounded-lg border-0 bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
                />
              </label>
              <div class="grid min-w-0 gap-1">
                <span class="text-xs text-n-slate-11">{{
                  t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.DAYS_LABEL')
                }}</span>
                <div
                  class="grid grid-cols-7 gap-1"
                  role="group"
                  :aria-label="
                    t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.DAYS_LABEL')
                  "
                >
                  <button
                    v-for="day in weekdays"
                    :key="day"
                    type="button"
                    :aria-pressed="form.autoFollowup.allowedDays.includes(day)"
                    :aria-label="
                      t(`CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.DAYS_FULL.${day}`)
                    "
                    class="h-9 rounded-md border px-1.5 text-xs font-medium"
                    :class="
                      form.autoFollowup.allowedDays.includes(day)
                        ? 'border-n-brand bg-n-brand/10 text-n-brand'
                        : 'border-n-weak bg-n-surface-2 text-n-slate-11'
                    "
                    @click="toggleDay(day)"
                  >
                    {{ t(`CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.DAYS.${day}`) }}
                  </button>
                </div>
              </div>
            </div>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.SCHEDULE_HELP') }}
            </p>
          </div>

          <p
            class="mb-0 flex items-start gap-1.5 rounded-lg bg-n-alpha-black2 p-3 text-xs leading-5 text-n-slate-11"
          >
            <span class="i-lucide-sparkles mt-0.5 shrink-0 text-sm" />
            {{
              t(
                isReminder
                  ? 'CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.REMINDER_INFO'
                  : 'CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.OFFICIAL_INFO'
              )
            }}
          </p>

          <label class="grid gap-1">
            <span class="text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.AI_INSTRUCTIONS') }}
            </span>
            <textarea
              v-model="form.autoFollowup.toneInstructions"
              rows="3"
              class="reset-base w-full rounded-lg border-0 bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
              :placeholder="
                t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.TONE_PLACEHOLDER')
              "
            />
          </label>
        </template>
      </section>

      <p
        v-if="form.autoFollowup.enabled && !scheduleValid"
        role="alert"
        class="mb-0 text-xs text-n-ruby-11"
      >
        {{ t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.INVALID_SCHEDULE') }}
      </p>
      <Button
        :label="t('CRM_KANBAN.AI_SETTINGS.SAVE')"
        :is-loading="isSaving"
        :disabled="!canSave"
        sm
        @click="saveSettings"
      />
    </template>
  </section>
</template>
