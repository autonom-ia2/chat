<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['saved', 'continue']);
const { t } = useI18n();
const isSaving = ref(false);
const pendingAction = ref('');
const dialog = ref(null);

const stateCode = computed(() => props.agent.state?.code || '');
const isDraft = computed(() =>
  ['E1', 'E2', 'E2m', 'E3', 'E4'].includes(stateCode.value)
);
const isActive = computed(
  () => props.agent.status === 'active' || stateCode.value === 'E5'
);
const isInternal = computed(() => props.agent.actuation === 'internal');
const isQuote = computed(() => props.agent.agent_type === 'insurance_quote');

const responseAgent = response =>
  response?.data?.payload || response?.data || response;

const openAction = action => {
  if (!props.canManage || isSaving.value) return;
  pendingAction.value = action;
  dialog.value?.open();
};

const closeAction = () => {
  pendingAction.value = '';
};

const runAction = async () => {
  const action = pendingAction.value;
  dialog.value?.close();
  pendingAction.value = '';
  if (!action || !props.canManage || isSaving.value) return;

  if (action === 'delete') {
    isSaving.value = true;
    try {
      await AutonomiaAgentsAPI.delete(props.agentId);
      useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.DELETED'));
      emit('saved', null);
    } catch (error) {
      useAlert(
        error?.message ||
          t('AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.ACTION_ERROR')
      );
    } finally {
      isSaving.value = false;
    }
    return;
  }

  const status = action === 'pause' ? 'paused' : 'active';
  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.update(props.agentId, {
      agent: { status, enabled: status === 'active' },
    });
    emit('saved', responseAgent(response));
    useAlert(
      t(
        status === 'paused'
          ? 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.PAUSED'
          : 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.ACTIVATED'
      )
    );
  } catch (error) {
    useAlert(
      error?.message ||
        t('AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.ACTION_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <section
    data-test="settings-lifecycle"
    class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{
          t(
            isInternal
              ? 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.INTERNAL_DESCRIPTION'
              : isQuote
                ? 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.QUOTE_DESCRIPTION'
                : 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.DESCRIPTION',
            { name: agent.name }
          )
        }}
      </p>
    </div>

    <Button
      v-if="isDraft"
      solid
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.CONTINUE')"
      :disabled="!canManage"
      class="self-start !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
      data-test="continue-build"
      @click="emit('continue')"
    />
    <Button
      v-else-if="isActive"
      outline
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.PAUSE')"
      :disabled="!canManage || isSaving"
      data-test="pause-agent"
      @click="openAction('pause')"
    />
    <Button
      class="!bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
      v-else
      solid
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.ACTIVATE')"
      :disabled="!canManage || isSaving"
      data-test="activate-agent"
      @click="openAction('activate')"
    />

    <Button
      v-if="!isDraft"
      link
      sm
      color="ruby"
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.DELETE')"
      :disabled="!canManage || isSaving"
      class="self-start !text-n-ruby-11 hover:enabled:!text-n-ruby-12"
      data-test="delete-agent"
      @click="openAction('delete')"
    />
  </section>

  <Dialog
    ref="dialog"
    type="alert"
    :title="
      t(
        pendingAction === 'delete'
          ? 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.DELETE_TITLE'
          : pendingAction === 'pause'
            ? 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.PAUSE_TITLE'
            : 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.ACTIVATE_TITLE'
      )
    "
    :description="
      t(
        pendingAction === 'delete'
          ? 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.DELETE_DESCRIPTION'
          : pendingAction === 'pause'
            ? 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.PAUSE_DESCRIPTION'
            : 'AGENTS.PANEL.REDESIGN_SETTINGS.LIFECYCLE.ACTIVATE_DESCRIPTION',
        { name: agent.name }
      )
    "
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="closeAction"
  >
    <template #footer>
      <div class="flex flex-wrap justify-end gap-3">
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl border border-n-strong text-n-slate-12 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-test="cancel-lifecycle"
          @click="dialog.close()"
        >
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.CANCEL') }}
        </button>
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl font-semibold bg-n-ruby-11 text-white dark:text-n-navy hover:bg-n-ruby-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-test="confirm-lifecycle"
          @click="runAction"
        >
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.CONFIRM') }}
        </button>
      </div>
    </template>
  </Dialog>
</template>
