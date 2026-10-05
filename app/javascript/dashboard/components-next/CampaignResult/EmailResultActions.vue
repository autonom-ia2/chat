<script setup>
// Actions of an e-mail campaign from its result (#1007, L8): Editar (draft), Pausar, Retomar,
// Cancelar, Duplicar, Salvar como modelo and Excluir rascunho — the same store actions and API the
// e-mail list uses, with the same rules (cancel/delete need confirmation; nothing while the
// recipient import runs). Only campaign_manage sees them (A4).
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { isRecipientImportActive } from 'dashboard/helper/emailCampaignImport';
import EmailCampaignTemplatesAPI from 'dashboard/api/emailCampaignTemplates';
import {
  canResumeCampaign,
  safeError,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  campaign: { type: Object, required: true },
});
const emit = defineEmits(['updated', 'deleted']);

const NS = 'RESULT_JOURNEY.ACTIONS';
const { t } = useI18n();
const store = useStore();
const router = useRouter();
const canManage = useCanManage('campaign_manage');

const busy = ref('');
const confirming = ref('');
const confirmDialog = ref(null);
const templateDialog = ref(null);
const templateName = ref('');

const importActive = computed(() => isRecipientImportActive(props.campaign));
const status = computed(() => props.campaign.status);
const isDraft = computed(() => status.value === 'draft');
const canPause = computed(() => status.value === 'sending');
const canResume = computed(() => canResumeCampaign(props.campaign));
const canCancel = computed(
  () =>
    !importActive.value &&
    ['draft', 'scheduled', 'sending', 'paused'].includes(status.value)
);
const canDelete = computed(() => isDraft.value && !importActive.value);
const canSaveTemplate = computed(() => Boolean(props.campaign.body_html));

const builderRoute = id => ({
  name: 'campaigns_email_builder',
  params: { campaignId: id },
});

const run = async (key, action, successKey) => {
  if (busy.value) return;
  busy.value = key;
  try {
    const payload = await action();
    if (successKey) useAlert(t(`${NS}.${successKey}`));
    emit('updated', payload);
  } catch (error) {
    useAlert(safeError(t, error));
  } finally {
    busy.value = '';
  }
};

const pause = () =>
  run(
    'pause',
    () => store.dispatch('emailCampaigns/pause', props.campaign.id),
    'PAUSED'
  );
const resume = () =>
  run(
    'resume',
    () => store.dispatch('emailCampaigns/resume', props.campaign.id),
    'RESUMED'
  );
const duplicate = () =>
  run(
    'duplicate',
    async () => {
      const copy = await store.dispatch(
        'emailCampaigns/duplicate',
        props.campaign.id
      );
      router.push(builderRoute(copy.id));
      return copy;
    },
    'DUPLICATED'
  );

const askConfirm = async action => {
  confirming.value = action;
  await nextTick();
  confirmDialog.value?.open();
};

const confirmAction = async () => {
  const action = confirming.value;
  if (action === 'delete') {
    await run(
      'delete',
      () => store.dispatch('emailCampaigns/delete', props.campaign.id),
      'DELETED'
    );
    confirmDialog.value?.close();
    emit('deleted');
    return;
  }
  await run(
    'cancel',
    () => store.dispatch('emailCampaigns/cancel', props.campaign.id),
    'CANCELLED'
  );
  confirmDialog.value?.close();
};

const openTemplate = async () => {
  templateName.value = props.campaign.name || '';
  await nextTick();
  templateDialog.value?.open();
};

const saveTemplate = async () => {
  const name = templateName.value.trim();
  if (!name) return;
  await run(
    'template',
    () =>
      EmailCampaignTemplatesAPI.create({
        name,
        body_mjml: props.campaign.body_mjml || undefined,
        body_html: props.campaign.body_html,
        category: 'meus-modelos',
      }),
    'TEMPLATE_SAVED'
  );
  templateDialog.value?.close();
};
</script>

<template>
  <div v-if="canManage" class="flex flex-wrap gap-2" data-email-actions>
    <Button
      v-if="isDraft"
      :label="t(`${NS}.EDIT`)"
      icon="i-lucide-pencil"
      slate
      outline
      class="!min-h-11 !rounded-xl"
      data-action="edit"
      @click="router.push(builderRoute(campaign.id))"
    />
    <Button
      v-if="canPause"
      :label="t(`${NS}.PAUSE`)"
      icon="i-lucide-pause"
      amber
      outline
      class="!min-h-11 !rounded-xl"
      :is-loading="busy === 'pause'"
      data-action="pause"
      @click="pause"
    />
    <Button
      v-if="canResume"
      :label="t(`${NS}.RESUME`)"
      icon="i-lucide-play"
      slate
      outline
      class="!min-h-11 !rounded-xl"
      :is-loading="busy === 'resume'"
      data-action="resume"
      @click="resume"
    />
    <Button
      :label="t(`${NS}.DUPLICATE`)"
      icon="i-lucide-copy"
      slate
      outline
      class="!min-h-11 !rounded-xl"
      :is-loading="busy === 'duplicate'"
      data-action="duplicate"
      @click="duplicate"
    />
    <Button
      v-if="canSaveTemplate"
      :label="t(`${NS}.SAVE_TEMPLATE`)"
      icon="i-lucide-bookmark-plus"
      slate
      outline
      class="!min-h-11 !rounded-xl"
      data-action="template"
      @click="openTemplate"
    />
    <Button
      v-if="canCancel"
      :label="t(`${NS}.CANCEL`)"
      icon="i-lucide-x"
      ruby
      outline
      class="!min-h-11 !rounded-xl"
      data-action="cancel"
      @click="askConfirm('cancel')"
    />
    <Button
      v-if="canDelete"
      :label="t(`${NS}.DELETE_DRAFT`)"
      icon="i-lucide-trash-2"
      ruby
      outline
      class="!min-h-11 !rounded-xl"
      data-action="delete"
      @click="askConfirm('delete')"
    />
    <Dialog
      v-if="confirming"
      ref="confirmDialog"
      type="alert"
      :title="t(`${NS}.CONFIRM_${confirming.toUpperCase()}`)"
      :description="campaign.name"
      :is-loading="Boolean(busy)"
      @confirm="confirmAction"
      @close="confirming = ''"
    />
    <Dialog
      ref="templateDialog"
      :title="t(`${NS}.SAVE_TEMPLATE`)"
      :confirm-button-label="t(`${NS}.TEMPLATE_SAVE`)"
      :is-loading="busy === 'template'"
      :disable-confirm-button="!templateName.trim()"
      @confirm="saveTemplate"
    >
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t(`${NS}.TEMPLATE_NAME`) }}
        <input
          v-model="templateName"
          type="text"
          maxlength="120"
          class="!mb-0 min-h-11 rounded-xl border border-n-weak px-3"
          data-template-name
        />
      </label>
    </Dialog>
  </div>
</template>
