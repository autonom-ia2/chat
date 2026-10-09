<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AgentSwitch from '../AgentSwitch.vue';
import BuilderChat from '../../../components/builder/BuilderChat.vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import AutonomiaBuilderImagesAPI from 'dashboard/api/autonomia/builderImages';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  resumeBuild: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();
const store = useStore();
const { run, abort } = useAbortableRequest();
const reconverseOpen = ref(false);

const builderMessages = useMapGetter('autonomiaBuildThreads/getMessages');
const builderStatus = useMapGetter('autonomiaBuildThreads/getStatus');
const builderPhase = useMapGetter('autonomiaBuildThreads/getPhase');
const builderThread = useMapGetter('autonomiaBuildThreads/getThread');
const builderUiFlags = useMapGetter('autonomiaBuildThreads/getUIFlags');

const manualMode = ref(false);
const manualText = ref('');
const localHasGuidedVersion = ref(false);
const isSaving = ref(false);
const isOpening = ref(false);
const isAttaching = ref(false);
const confirmation = ref(null);
const confirmDialog = ref(null);
const reconverseDialog = ref(null);

const CONFIRM_ACTIONS = { MANUAL: 'manual', GUIDED: 'guided' };

const syncAgent = agent => {
  manualMode.value = agent?.mode === 'manual';
  // A manual instruction belongs to the person and is safe to show. A guided
  // instruction is generated product IP and must never hydrate this field.
  manualText.value = manualMode.value ? agent?.instruction || '' : '';
  localHasGuidedVersion.value = agent?.has_guided_version === true;
};

watch(
  [
    () => props.agentId,
    () => props.agent?.mode,
    () => props.agent?.instruction,
    () => props.agent?.has_guided_version,
  ],
  () => syncAgent(props.agent),
  { immediate: true }
);

const hasGuidedVersion = computed(
  () => localHasGuidedVersion.value || props.agent.has_guided_version === true
);
const modeLabel = computed(() =>
  manualMode.value
    ? t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.MANUAL')
    : t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.GUIDED')
);
const isBuilding = computed(
  () =>
    builderUiFlags.value?.sending ||
    builderUiFlags.value?.creating ||
    builderStatus.value === 'processing'
);

const responseAgent = response =>
  response?.data?.payload || response?.data || response;

const openConfirmation = action => {
  if (!props.canManage) return;
  confirmation.value = { action };
  confirmDialog.value?.open();
};

const closeConfirmation = () => {
  confirmation.value = null;
};

const saveGuidedMode = async () => {
  if (!props.canManage || isSaving.value || !hasGuidedVersion.value) return;
  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.update(props.agentId, {
      agent: { mode: 'guided' },
    });
    manualMode.value = false;
    manualText.value = '';
    emit('saved', responseAgent(response));
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const confirmModeChange = async () => {
  const action = confirmation.value?.action;
  confirmDialog.value?.close();
  confirmation.value = null;

  if (action === CONFIRM_ACTIONS.MANUAL) {
    manualMode.value = true;
    manualText.value = '';
    await nextTick();
    return;
  }

  if (action === CONFIRM_ACTIONS.GUIDED) {
    await saveGuidedMode();
  }
};

const onModeToggle = checked => {
  if (checked === manualMode.value) return;
  if (checked) {
    openConfirmation(CONFIRM_ACTIONS.MANUAL);
    return;
  }
  if (!hasGuidedVersion.value) return;
  openConfirmation(CONFIRM_ACTIONS.GUIDED);
};

const saveManual = async () => {
  if (!props.canManage || isSaving.value) return;
  const instruction = manualText.value.trim();
  if (!instruction) {
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.EMPTY'));
    return;
  }

  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.update(props.agentId, {
      agent: { mode: 'manual', instruction },
    });
    emit('saved', responseAgent(response));
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const resumeConversation = async () => {
  if (!props.canManage || manualMode.value || isOpening.value) return;
  isOpening.value = true;
  try {
    const payload = await run(signal =>
      store.dispatch('autonomiaBuildThreads/resume', {
        agentId: Number(props.agentId),
        signal,
      })
    );
    if (!payload) return;
    reconverseOpen.value = true;
    reconverseDialog.value?.open();
  } catch (error) {
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.RESUME_ERROR'));
  } finally {
    isOpening.value = false;
  }
};

const uploadImages = async images => {
  if (!images?.length) return [];
  const results = await Promise.all(
    images.map(file => AutonomiaBuilderImagesAPI.upload(file))
  );
  return results.map(({ data }) => data.signed_id);
};

const onReconverseSend = async ({ content, images = [] }) => {
  const threadId = builderThread.value?.id;
  if (!threadId) {
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.RESUME_ERROR'));
    return;
  }

  try {
    await run(
      async signal => {
        const imageSignedIds = await uploadImages(images);
        if (signal.aborted || builderThread.value?.id !== threadId) return;

        await store.dispatch('autonomiaBuildThreads/send', {
          threadId,
          content,
          extra: { image_signed_ids: imageSignedIds },
        });
      },
      { onAbort: null }
    );
  } catch (error) {
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.SEND_ERROR'));
  }
};

const onReconverseAttach = async ({ files }) => {
  if (!files?.length) return;
  isAttaching.value = true;
  try {
    await Promise.all(
      files.map(file =>
        store.dispatch('autonomiaSources/create', {
          agentId: props.agentId,
          descriptor: { file, kind: 'knowledge' },
        })
      )
    );
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.ATTACHED'));
  } catch (error) {
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.ATTACH_ERROR'));
  } finally {
    isAttaching.value = false;
  }
};

const closeReconverse = () => {
  abort();
  reconverseOpen.value = false;
  if (builderThread.value?.agent_id !== Number(props.agentId)) return;
  store.dispatch('autonomiaBuildThreads/stopPolling');
  store.commit('autonomiaBuildThreads/RESET');
};

watch(builderPhase, phase => {
  if (
    phase !== 'reviewing' ||
    !reconverseOpen.value ||
    builderThread.value?.agent_id !== Number(props.agentId)
  )
    return;
  store.dispatch('autonomiaAgents/show', Number(props.agentId));
  reconverseDialog.value?.close();
  useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVED'));
});

onBeforeUnmount(closeReconverse);

onMounted(async () => {
  if (props.resumeBuild && !manualMode.value) await resumeConversation();
});
</script>

<template>
  <section
    data-test="settings-instructions"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <h2 class="text-base font-semibold text-n-slate-12">
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.TITLE') }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-sm text-n-slate-11">{{ modeLabel }}</span>
        <AgentSwitch
          :checked="manualMode"
          :disabled="
            !canManage || isSaving || (manualMode && !hasGuidedVersion)
          "
          :label="modeLabel"
          :aria-label="
            t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.MODE_LABEL', {
              name: agent.name,
            })
          "
          data-test="mode-switch"
          @toggle="onModeToggle"
        />
      </div>
    </div>

    <div
      v-if="!manualMode"
      class="flex flex-col gap-4 px-4 py-4 border rounded-xl border-n-iris-4 bg-n-iris-2"
    >
      <div class="flex items-start gap-2">
        <Icon
          icon="i-lucide-sparkles"
          class="flex-shrink-0 mt-0.5 text-n-iris-11"
        />
        <div class="flex flex-col gap-1">
          <span class="text-xs font-semibold uppercase text-n-iris-11">
            {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.GUIDED') }}
          </span>
          <p class="m-0 text-sm leading-relaxed text-n-slate-12">
            {{
              agent.human_card ||
              t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.NO_SUMMARY')
            }}
          </p>
        </div>
      </div>
      <p
        v-if="!hasGuidedVersion"
        class="m-0 text-xs text-n-slate-11"
        data-test="no-guided-version"
      >
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.NO_GUIDED_VERSION') }}
      </p>
      <Button
        outline
        sm
        :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.RECONVERSE')"
        :is-loading="isOpening"
        :disabled="!canManage || isOpening || !hasGuidedVersion"
        class="self-start"
        data-test="reconverse"
        @click="resumeConversation"
      />
    </div>

    <div v-else class="flex flex-col gap-3">
      <div
        class="flex items-start gap-2 px-4 py-3 text-xs rounded-lg bg-n-amber-9/10 text-n-amber-12"
      >
        <Icon icon="i-lucide-shield" class="flex-shrink-0 mt-0.5" />
        <span>{{
          t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.MANUAL_WARNING')
        }}</span>
      </div>
      <TextArea
        v-model="manualText"
        :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.MANUAL_LABEL')"
        :placeholder="
          t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.MANUAL_PLACEHOLDER')
        "
        :max-length="50000"
        show-character-count
        :disabled="!canManage || isSaving"
        data-test="manual-instruction"
      />
      <div class="flex flex-wrap items-center gap-3">
        <Button
          class="!bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
          solid
          sm
          :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE')"
          :is-loading="isSaving"
          :disabled="!canManage || isSaving"
          data-test="save-manual"
          @click="saveManual"
        />
        <Button
          v-if="hasGuidedVersion"
          outline
          sm
          :label="
            t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.RETURN_GUIDED')
          "
          :disabled="!canManage || isSaving"
          data-test="return-guided"
          @click="openConfirmation(CONFIRM_ACTIONS.GUIDED)"
        />
      </div>
    </div>

    <Button
      v-if="!manualMode"
      outline
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.WRITE_MANUALLY')"
      :disabled="!canManage"
      class="self-start"
      data-test="open-manual"
      @click="openConfirmation(CONFIRM_ACTIONS.MANUAL)"
    />
  </section>

  <Dialog
    ref="confirmDialog"
    :title="t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.CONFIRM_TITLE')"
    :description="
      t(
        confirmation?.action === 'guided'
          ? 'AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.CONFIRM_GUIDED'
          : 'AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.CONFIRM_MANUAL'
      )
    "
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="closeConfirmation"
  >
    <template #footer>
      <div class="flex flex-wrap justify-end gap-3">
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl border border-n-strong text-n-slate-12 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-test="cancel-confirmation"
          @click="confirmDialog.close()"
        >
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.CANCEL') }}
        </button>
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl font-semibold bg-n-blue-11 text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :data-test="
            confirmation?.action === 'manual'
              ? 'confirm-manual'
              : 'confirm-guided'
          "
          @click="confirmModeChange"
        >
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.CONFIRM') }}
        </button>
      </div>
    </template>
  </Dialog>

  <Dialog
    ref="reconverseDialog"
    :title="t('AGENTS.PANEL.REDESIGN_SETTINGS.INSTRUCTIONS.RECONVERSE_TITLE')"
    width="2xl"
    :show-confirm-button="false"
    :cancel-button-label="t('AGENTS.PANEL.REDESIGN_SETTINGS.CANCEL')"
    @close="closeReconverse"
  >
    <div class="h-[28rem]">
      <BuilderChat
        :messages="builderMessages"
        :is-sending="isBuilding"
        :disabled="builderPhase === 'reviewing'"
        can-attach
        :is-attaching="isAttaching"
        @send="onReconverseSend"
        @attach="onReconverseAttach"
      />
    </div>
  </Dialog>
</template>
