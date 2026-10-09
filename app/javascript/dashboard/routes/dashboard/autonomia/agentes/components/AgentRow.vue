<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AgentAvatar from './AgentAvatar.vue';
import AgentStatusPill from './AgentStatusPill.vue';
import AgentSwitch from './AgentSwitch.vue';
import ConfirmDialog from './ConfirmDialog.vue';

const props = defineProps({
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(['open', 'continue', 'toggleStatus', 'delete']);

const { t } = useI18n();
const dialogRef = ref(null);
const dialogAction = ref(null);
const isMenuOpen = ref(false);
const menuButtonRef = ref(null);
const dialogRestoreRef = ref(null);

const VALID_STATE_CODES = new Set(['E1', 'E2', 'E2m', 'E3', 'E4', 'E5', 'E6']);
const PENDING_CODES = new Set(['E1', 'E2', 'E2m', 'E3', 'E4']);

const code = computed(() => {
  const value = props.agent?.state?.code;
  if (!VALID_STATE_CODES.has(value)) {
    throw new Error(`agents_list_invalid_state.code:${value || 'missing'}`);
  }
  return value;
});

const isPending = computed(() => PENDING_CODES.has(code.value));
const isLive = computed(() => code.value === 'E5' || code.value === 'E6');
const isInternal = computed(() => props.agent.actuation === 'internal');
const channels = computed(() => props.agent.channels || []);
const firstChannel = computed(() => channels.value[0]);
const channelCount = computed(() => channels.value.length);
const isMissingChannel = computed(
  () => isLive.value && !isInternal.value && !firstChannel.value
);
const switchState = computed(() => (code.value === 'E5' ? 'active' : 'paused'));
const switchLabel = computed(() =>
  t('AGENTS.V2.actions.toggle', {
    name: props.agent.name,
    status: t(`AGENTS.V2.status.${switchState.value}`),
  })
);

const typeBadge = computed(() => {
  if (props.agent.agent_type === 'insurance_quote') {
    return t('AGENTS.V2.badges.insurance');
  }
  if (props.agent.actuation === 'internal') {
    return t('AGENTS.V2.badges.internal');
  }
  if (props.agent.actuation === 'both') {
    return t('AGENTS.V2.badges.both');
  }
  return '';
});

const retentionDays = computed(() => {
  const hours = Number(props.agent.state?.retention_hours || 0);
  return Math.max(1, Math.ceil(hours / 24));
});

const article = computed(() =>
  props.agent.voice === 'masculina'
    ? t('AGENTS.V2.invalidation.article.male')
    : t('AGENTS.V2.invalidation.article.female')
);

const context = computed(() => {
  if (code.value === 'E1') {
    return t('AGENTS.V2.states.E1.context', { days: retentionDays.value });
  }
  if (code.value === 'E2') return t('AGENTS.V2.states.E2.context');
  if (code.value === 'E2m') return t('AGENTS.V2.states.E2m.context');
  if (code.value === 'E3') {
    return props.agent.state?.test_invalidated_by === 'material'
      ? t('AGENTS.V2.invalidation.material', {
          article: article.value,
          name: props.agent.name,
        })
      : t('AGENTS.V2.invalidation.person');
  }
  if (code.value === 'E4') {
    return isInternal.value
      ? t('AGENTS.V2.states.E4.internalContext')
      : t('AGENTS.V2.states.E4.externalContext');
  }
  if (isInternal.value) return t('AGENTS.V2.list.internalContext');
  if (!firstChannel.value) {
    return t('AGENTS.V2.list.noChannel', {
      pronoun: t(
        props.agent.voice === 'masculina'
          ? 'AGENTS.V2.invalidation.pronoun.male'
          : 'AGENTS.V2.invalidation.pronoun.female'
      ),
    });
  }
  return t(
    channelCount.value > 1
      ? 'AGENTS.V2.list.channelMore'
      : 'AGENTS.V2.list.channel',
    {
      name: firstChannel.value.name,
      more: Math.max(channelCount.value - 1, 0),
    }
  );
});

const stats = computed(() => props.agent.stats || {});
const statsLine = computed(() => {
  if (isInternal.value) return '';
  const week = stats.value.week || {};
  const month = stats.value.month || {};
  if (Number(week.replies || 0) > 0) {
    return t('AGENTS.V2.list.weekStats', {
      replies: week.replies,
      handoffs: week.handoffs || 0,
    });
  }
  if (Number(month.replies || 0) > 0) {
    return t('AGENTS.V2.list.monthStats', { replies: month.replies });
  }
  return t('AGENTS.V2.list.noConversations');
});

const focusElement = element => {
  if (element && typeof element.focus === 'function') element.focus();
};

const closeMenu = () => {
  isMenuOpen.value = false;
  nextTick(() => focusElement(menuButtonRef.value));
};

const handleMenuKeydown = event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    closeMenu();
  }
};

const restoreTargetFor = trigger => {
  if (trigger && typeof trigger.focus === 'function') return trigger;
  if (typeof document !== 'undefined') return document.activeElement;
  return null;
};

const openDialog = (action, trigger = null) => {
  dialogAction.value = action;
  dialogRestoreRef.value = restoreTargetFor(trigger);
  isMenuOpen.value = false;
  nextTick(() => dialogRef.value?.open());
};

const closeDialog = () => {
  dialogAction.value = null;
  const restoreTarget = dialogRestoreRef.value;
  dialogRestoreRef.value = null;
  nextTick(() => focusElement(restoreTarget));
};

const currentFocus = () =>
  typeof document !== 'undefined' ? document.activeElement : null;

const confirmDialog = () => {
  if (dialogAction.value === 'pause') {
    emit('toggleStatus', { status: 'paused', enabled: false });
  }
  if (dialogAction.value === 'delete') emit('delete', props.agent);
  dialogRef.value?.close();
};

const switchStatus = nextChecked => {
  if (nextChecked) emit('toggleStatus', { status: 'active', enabled: true });
  else openDialog('pause', currentFocus());
};
</script>

<template>
  <article
    class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-4 rounded-xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center"
    :data-agent-id="agent.id"
    :data-state="code"
  >
    <AgentAvatar :agent="agent" />

    <div class="min-w-0">
      <div class="flex flex-wrap items-center gap-2">
        <h2 class="truncate text-base font-semibold text-n-slate-12">
          {{ agent.name }}
        </h2>
        <span
          v-if="typeBadge"
          class="inline-flex min-h-6 items-center rounded-full bg-n-iris-3 px-2 text-xs font-medium text-n-iris-11"
        >
          {{ typeBadge }}
        </span>
        <AgentStatusPill :code="code" />
      </div>
      <p
        class="mt-2 flex items-start gap-2 text-sm leading-relaxed"
        :class="isMissingChannel ? 'text-n-amber-11' : 'text-n-slate-11'"
      >
        <span
          class="mt-0.5 size-4 shrink-0"
          :class="
            isMissingChannel
              ? 'i-lucide-alert-triangle text-n-amber-11'
              : 'i-lucide-info text-n-slate-11'
          "
          aria-hidden="true"
        />
        <span>{{ context }}</span>
      </p>
      <p v-if="isLive && !isInternal" class="mt-1 text-xs text-n-slate-11">
        {{ statsLine }}
      </p>
    </div>

    <div
      class="col-span-2 flex flex-wrap items-center justify-end gap-2 sm:col-span-1 sm:max-w-xs"
    >
      <AgentSwitch
        v-if="canManage && isLive"
        :checked="code === 'E5'"
        :disabled="busy"
        :aria-label="switchLabel"
        :label="t(`AGENTS.V2.status.${switchState}`)"
        @toggle="switchStatus"
      />
      <button
        v-if="!canManage || isLive"
        type="button"
        class="inline-flex min-h-11 items-center justify-center rounded-lg border border-n-weak px-3 text-sm font-medium text-n-slate-12 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        data-action="open"
        @click="emit('open', agent)"
      >
        {{ t('AGENTS.V2.actions.open') }}
      </button>
      <button
        v-else-if="isPending"
        type="button"
        :disabled="busy"
        class="inline-flex min-h-11 items-center justify-center rounded-lg bg-n-blue-11 px-3 text-sm font-semibold text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        data-action="continue"
        @click="emit('continue', agent)"
      >
        {{
          code === 'E4'
            ? t(
                isInternal
                  ? 'AGENTS.V2.actions.connect'
                  : 'AGENTS.V2.actions.chooseChannel'
              )
            : t('AGENTS.V2.actions.continue')
        }}
      </button>
      <div v-if="canManage && isPending" class="relative">
        <button
          ref="menuButtonRef"
          type="button"
          :disabled="busy"
          class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-solid-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="t('AGENTS.V2.actions.more', { name: agent.name })"
          aria-haspopup="menu"
          :aria-expanded="isMenuOpen"
          data-action="more"
          @click="isMenuOpen = !isMenuOpen"
          @keydown.esc="closeMenu"
        >
          <span class="i-lucide-ellipsis size-5" aria-hidden="true" />
        </button>
        <div
          v-if="isMenuOpen"
          class="absolute end-0 top-12 z-10 min-w-44 rounded-lg border border-n-weak bg-n-solid-1 p-1 shadow-lg"
          role="menu"
          @keydown="handleMenuKeydown"
        >
          <button
            type="button"
            class="flex min-h-11 w-full items-center rounded-md px-3 text-left text-sm text-n-ruby-11 hover:bg-n-ruby-2"
            role="menuitem"
            data-action="delete"
            @click="openDialog('delete', menuButtonRef)"
          >
            {{ t('AGENTS.V2.actions.deleteDraft') }}
          </button>
        </div>
      </div>
    </div>

    <ConfirmDialog
      ref="dialogRef"
      :title="
        dialogAction === 'pause'
          ? t('AGENTS.V2.dialog.pauseTitle')
          : t('AGENTS.V2.dialog.deleteTitle')
      "
      :description="
        dialogAction === 'pause'
          ? t(
              isInternal
                ? 'AGENTS.V2.dialog.pauseInternalDescription'
                : 'AGENTS.V2.dialog.pauseDescription',
              { name: agent.name }
            )
          : t('AGENTS.V2.dialog.deleteDescription', { name: agent.name })
      "
      :confirm-label="
        dialogAction === 'pause'
          ? t('AGENTS.V2.actions.pause')
          : t('AGENTS.V2.actions.deleteDraft')
      "
      :cancel-label="t('AGENTS.V2.actions.cancel')"
      :destructive="dialogAction === 'delete'"
      @confirm="confirmDialog"
      @close="closeDialog"
    />
  </article>
</template>
