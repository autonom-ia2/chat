<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

defineProps({
  agentOptions: { type: Array, default: () => [] },
});

const form = defineModel({ type: Object, required: true });

const { t } = useI18n();

const FLOW_OPTIONS = ['r2_direct', 'r3_invite'];
const POOL_OPTIONS = ['inbox', 'user'];
const ACTION_OPTIONS = ['renotify', 'escalate'];
const SELECTOR_MODES = ['round_robin', 'direct'];

const OPTION_KEYS = {
  r2_direct: 'FLOW_DIRECT',
  r3_invite: 'FLOW_INVITE',
  inbox: 'POOL_INBOX',
  user: 'POOL_USER',
  renotify: 'ACTION_RENOTIFY',
  escalate: 'ACTION_ESCALATE',
};

const DEFAULT_PICKUP_THRESHOLD_SECONDS = 900;

const pickupThresholdMinutes = computed({
  get: () => {
    const seconds =
      Number(form.value.pickup_threshold_seconds) ||
      DEFAULT_PICKUP_THRESHOLD_SECONDS;
    return Math.max(1, Math.round(seconds / 60));
  },
  set: value => {
    const minutes = Number(value);
    form.value.pickup_threshold_seconds =
      (minutes > 0 ? Math.round(minutes) : 1) * 60;
  },
});

const optionLabel = option =>
  t(`CRM_KANBAN.HANDOFF_SETTINGS.${OPTION_KEYS[option]}`);
const optionDescription = option =>
  t(`CRM_KANBAN.HANDOFF_SETTINGS.${OPTION_KEYS[option]}_DESC`);

const setFlow = option => {
  form.value.handoff_mode = option;
};
const setPool = option => {
  form.value.pool_type = option;
  if (option === 'inbox') form.value.pool_id = null;
};
const setAction = option => {
  form.value.escalation_action = option;
};
</script>

<template>
  <div class="grid gap-4">
    <button
      type="button"
      class="flex w-full items-center justify-between gap-3 text-left"
      role="switch"
      :aria-checked="form.enabled"
      @click="form.enabled = !form.enabled"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CRM_KANBAN.HANDOFF_SETTINGS.ENABLE_STAGE') }}
      </span>
      <span
        class="relative h-5 w-9 shrink-0 rounded-full transition-colors"
        :class="form.enabled ? 'bg-n-brand' : 'bg-n-slate-6'"
      >
        <span
          class="absolute top-0.5 h-4 w-4 rounded-full bg-white transition-all"
          :class="
            form.enabled
              ? 'ltr:left-[18px] rtl:right-[18px]'
              : 'ltr:left-0.5 rtl:right-0.5'
          "
        />
      </span>
    </button>

    <template v-if="form.enabled">
      <div class="grid gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.TRIGGER_LABEL') }}
        </span>
        <textarea
          v-model="form.trigger"
          rows="2"
          class="reset-base w-full rounded-lg border-0 bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
          :placeholder="t('CRM_KANBAN.AI_SETTINGS.HANDOFF.TRIGGER_PLACEHOLDER')"
        />
      </div>

      <div class="grid gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.FLOW_LABEL') }}
        </span>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <button
            v-for="option in FLOW_OPTIONS"
            :key="option"
            type="button"
            class="rounded-xl p-3 text-left outline transition-colors"
            :class="
              form.handoff_mode === option
                ? 'bg-n-surface-2 outline-2 outline-n-brand'
                : 'bg-n-surface-2 outline-1 outline-n-weak hover:outline-n-strong'
            "
            @click="setFlow(option)"
          >
            <span class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium text-n-slate-12">
                {{ optionLabel(option) }}
              </span>
              <span
                class="h-3.5 w-3.5 shrink-0 rounded-full border-2"
                :class="
                  form.handoff_mode === option
                    ? 'border-n-brand bg-n-brand'
                    : 'border-n-slate-7'
                "
              />
            </span>
            <span class="mt-1 block text-xs leading-5 text-n-slate-11">
              {{ optionDescription(option) }}
            </span>
          </button>
        </div>
      </div>

      <div class="grid gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.POOL_LABEL') }}
        </span>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <button
            v-for="option in POOL_OPTIONS"
            :key="option"
            type="button"
            class="rounded-xl p-3 text-left outline transition-colors"
            :class="
              form.pool_type === option
                ? 'bg-n-surface-2 outline-2 outline-n-brand'
                : 'bg-n-surface-2 outline-1 outline-n-weak hover:outline-n-strong'
            "
            @click="setPool(option)"
          >
            <span class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium text-n-slate-12">
                {{ optionLabel(option) }}
              </span>
              <span
                class="h-3.5 w-3.5 shrink-0 rounded-full border-2"
                :class="
                  form.pool_type === option
                    ? 'border-n-brand bg-n-brand'
                    : 'border-n-slate-7'
                "
              />
            </span>
            <span class="mt-1 block text-xs leading-5 text-n-slate-11">
              {{ optionDescription(option) }}
            </span>
          </button>
        </div>

        <label
          v-if="form.pool_type === 'user'"
          class="mt-1 flex items-center gap-2 text-xs text-n-slate-11"
        >
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.POOL_USER_SELECT') }}
          <select
            v-model="form.pool_id"
            class="reset-base max-w-56 rounded-lg border-0 bg-n-surface-2 px-2 py-1.5 text-xs text-n-slate-12 outline outline-1 outline-n-weak"
          >
            <option :value="null">
              {{ t('CRM_KANBAN.HANDOFF_SETTINGS.PERSON_NONE') }}
            </option>
            <option
              v-for="agent in agentOptions"
              :key="agent.value"
              :value="agent.value"
            >
              {{ agent.label }}
            </option>
          </select>
        </label>
        <label
          v-else
          class="mt-1 flex items-center gap-2 text-xs text-n-slate-11"
        >
          {{ t('CRM_KANBAN.AI_SETTINGS.HANDOFF.MODE') }}
          <select
            v-model="form.mode"
            class="reset-base rounded-lg border-0 bg-n-surface-2 px-2 py-1.5 text-xs text-n-slate-12 outline outline-1 outline-n-weak"
          >
            <option v-for="mode in SELECTOR_MODES" :key="mode" :value="mode">
              {{
                t(`CRM_KANBAN.AI_SETTINGS.HANDOFF.MODE_${mode.toUpperCase()}`)
              }}
            </option>
          </select>
        </label>
      </div>

      <div
        class="flex items-start gap-3 rounded-xl bg-n-alpha-black2 p-3 outline outline-1 outline-n-weak"
      >
        <button
          type="button"
          role="switch"
          :aria-checked="form.prefer_online"
          class="relative mt-0.5 h-5 w-9 shrink-0 rounded-full transition-colors"
          :class="form.prefer_online ? 'bg-n-brand' : 'bg-n-slate-6'"
          :aria-label="t('CRM_KANBAN.AI_SETTINGS.HANDOFF.PREFER_ONLINE')"
          @click="form.prefer_online = !form.prefer_online"
        >
          <span
            class="absolute top-0.5 h-4 w-4 rounded-full bg-white transition-all"
            :class="
              form.prefer_online
                ? 'ltr:left-[18px] rtl:right-[18px]'
                : 'ltr:left-0.5 rtl:right-0.5'
            "
          />
        </button>
        <div>
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.AI_SETTINGS.HANDOFF.PREFER_ONLINE') }}
          </p>
          <p
            v-if="form.prefer_online"
            class="mb-0 text-xs leading-5 text-n-slate-11"
          >
            {{
              form.handoff_mode === 'r3_invite'
                ? t('CRM_KANBAN.HANDOFF_SETTINGS.ONLINE_HINT_INVITE')
                : t('CRM_KANBAN.HANDOFF_SETTINGS.ONLINE_HINT_DIRECT')
            }}
          </p>
        </div>
      </div>

      <div v-if="form.handoff_mode === 'r3_invite'" class="grid gap-1.5">
        <p
          class="mb-0 flex flex-wrap items-center gap-2 text-sm text-n-slate-12"
        >
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.PICKUP_PREFIX') }}
          <input
            v-model="pickupThresholdMinutes"
            type="number"
            min="1"
            class="reset-base w-16 rounded-lg border-0 bg-n-surface-2 px-2 py-1 text-center text-sm text-n-slate-12 outline outline-1 outline-n-weak"
          />
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.PICKUP_SUFFIX') }}
        </p>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <button
            v-for="option in ACTION_OPTIONS"
            :key="option"
            type="button"
            class="rounded-xl p-3 text-left outline transition-colors"
            :class="
              form.escalation_action === option
                ? 'bg-n-surface-2 outline-2 outline-n-brand'
                : 'bg-n-surface-2 outline-1 outline-n-weak hover:outline-n-strong'
            "
            @click="setAction(option)"
          >
            <span class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium text-n-slate-12">
                {{ optionLabel(option) }}
              </span>
              <span
                class="h-3.5 w-3.5 shrink-0 rounded-full border-2"
                :class="
                  form.escalation_action === option
                    ? 'border-n-brand bg-n-brand'
                    : 'border-n-slate-7'
                "
              />
            </span>
            <span class="mt-1 block text-xs leading-5 text-n-slate-11">
              {{ optionDescription(option) }}
            </span>
          </button>
        </div>

        <label
          v-if="form.escalation_action === 'escalate'"
          class="mt-1 flex items-center gap-2 text-xs text-n-slate-11"
        >
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.ESCALATION_USER') }}
          <select
            v-model="form.escalation_user_id"
            class="reset-base max-w-56 rounded-lg border-0 bg-n-surface-2 px-2 py-1.5 text-xs text-n-slate-12 outline outline-1 outline-n-weak"
          >
            <option :value="null">
              {{ t('CRM_KANBAN.HANDOFF_SETTINGS.PERSON_NONE') }}
            </option>
            <option
              v-for="agent in agentOptions"
              :key="agent.value"
              :value="agent.value"
            >
              {{ agent.label }}
            </option>
          </select>
        </label>
      </div>
    </template>
  </div>
</template>
