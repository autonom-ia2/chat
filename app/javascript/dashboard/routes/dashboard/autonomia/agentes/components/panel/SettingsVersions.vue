<script setup>
import { ref, watch } from 'vue';
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

const emit = defineEmits(['saved']);
const { t } = useI18n();
const versions = ref([]);
const isLoading = ref(false);
const error = ref(false);
const restoringVersionId = ref(null);
const pendingVersion = ref(null);
const dialog = ref(null);

const reasonKeys = {
  builder: 'BUILDER',
  before_manual: 'BEFORE_MANUAL',
  manual_edit: 'MANUAL_EDIT',
  rollback: 'ROLLBACK',
  kb_refresh: 'KB_REFRESH',
};

const reasonLabel = reason =>
  t(
    `AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.REASONS.${
      reasonKeys[reason] || 'OTHER'
    }`
  );

const formatDate = value =>
  value
    ? new Date(value).toLocaleString(undefined, {
        dateStyle: 'medium',
        timeStyle: 'short',
      })
    : '';

const authorName = version => {
  if (version.author && typeof version.author === 'object') {
    return version.author.name || '';
  }
  return version.author || version.created_by_name || '';
};

const load = async () => {
  if (props.agent.agent_type === 'insurance_quote') return;
  isLoading.value = true;
  error.value = false;
  try {
    const response = await AutonomiaAgentsAPI.getInstructionVersions(
      props.agentId
    );
    const data = response?.data || response || {};
    versions.value = Array.isArray(data) ? data : data.payload || [];
  } catch {
    error.value = true;
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const openRestore = version => {
  if (!props.canManage || restoringVersionId.value) return;
  pendingVersion.value = version;
  dialog.value?.open();
};

const closeRestore = () => {
  pendingVersion.value = null;
};

const restore = async () => {
  const version = pendingVersion.value;
  dialog.value?.close();
  pendingVersion.value = null;
  if (!version || !props.canManage || restoringVersionId.value) return;

  restoringVersionId.value = version.id;
  try {
    const response = await AutonomiaAgentsAPI.restoreInstructionVersion(
      props.agentId,
      version.id
    );
    emit('saved', response?.data?.payload || response?.data || response);
    await load();
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.RESTORED'));
  } catch {
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.RESTORE_ERROR'));
  } finally {
    restoringVersionId.value = null;
  }
};

watch(
  [
    () => props.agentId,
    () => props.agent?.mode,
    () => props.agent?.instruction,
    () => props.agent?.has_guided_version,
  ],
  () => load(),
  { immediate: true }
);
</script>

<template>
  <section
    data-test="settings-versions"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.DESCRIPTION') }}
      </p>
    </div>

    <p v-if="isLoading" class="m-0 text-xs text-n-slate-11">
      {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.LOADING') }}
    </p>
    <p v-else-if="error" class="m-0 text-xs text-n-ruby-11" role="alert">
      {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.LOAD_ERROR') }}
    </p>
    <p
      v-else-if="!versions.length"
      class="m-0 text-xs text-n-slate-11"
      data-test="versions-empty"
    >
      {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.EMPTY') }}
    </p>
    <ul v-else class="list-none flex flex-col gap-2">
      <li
        v-for="version in versions"
        :key="version.id"
        class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 border rounded-xl border-n-weak"
      >
        <div class="flex flex-col min-w-0 gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{
              version.current
                ? t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.CURRENT')
                : reasonLabel(version.reason)
            }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.META', {
                date: formatDate(version.created_at),
                author:
                  authorName(version) ||
                  t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.AUTOMATIC'),
              })
            }}
          </span>
          <!-- Only manual-authored text may be shown. Guided text stays hidden. -->
          <p
            v-if="version.origin === 'manual' && version.instruction"
            class="m-0 text-xs break-words text-n-slate-11"
          >
            {{ version.instruction }}
          </p>
        </div>
        <Button
          outline
          sm
          :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.RESTORE')"
          :is-loading="restoringVersionId === version.id"
          :disabled="!canManage || !!restoringVersionId || version.current"
          :data-test="`restore-version-${version.id}`"
          @click="openRestore(version)"
        />
      </li>
    </ul>
  </section>

  <Dialog
    ref="dialog"
    :title="t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.CONFIRM_TITLE')"
    :description="
      t('AGENTS.PANEL.REDESIGN_SETTINGS.VERSIONS.CONFIRM_DESCRIPTION')
    "
    :show-confirm-button="false"
    :show-cancel-button="false"
    @confirm="restore"
    @close="closeRestore"
  >
    <template #footer>
      <div class="flex flex-wrap justify-end gap-3">
        <Button
          faded
          color="slate"
          size="md"
          class="min-h-11"
          :disabled="Boolean(restoringVersionId)"
          :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.CANCEL')"
          data-test="cancel-restore"
          @click="dialog.close()"
        />
        <Button
          solid
          size="md"
          type="submit"
          class="min-h-11 !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
          :disabled="Boolean(restoringVersionId)"
          :is-loading="Boolean(restoringVersionId)"
          :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.CONFIRM')"
          data-test="confirm-restore"
        />
      </div>
    </template>
  </Dialog>
</template>
