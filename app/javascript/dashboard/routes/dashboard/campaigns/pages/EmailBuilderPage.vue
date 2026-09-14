<script setup>
import { computed, onActivated, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRecipientImportPolling } from 'dashboard/composables/useRecipientImportPolling';
import RecipientImportStatus from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import GrapesEditor from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/GrapesEditor.vue';
import AiComposerDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/AiComposerDialog.vue';
import AiGeneratingDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/AiGeneratingDialog.vue';
import AiBlockActions from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/AiBlockActions.vue';
import PlaceholderChips from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/PlaceholderChips.vue';
import BlocksPanel from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/BlocksPanel.vue';
import PropertiesPanel from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/PropertiesPanel.vue';
import WelcomeChooser from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/WelcomeChooser.vue';
import { useEmailEditor } from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/composables/useEmailEditor';
import { STARTER_MJML } from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/starterMjml';
import EmailCampaignTemplatesAPI from 'dashboard/api/emailCampaignTemplates';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const campaigns = useMapGetter('emailCampaigns/getCampaigns');
const uiFlags = useMapGetter('emailCampaigns/getUIFlags');

const campaignId = computed(() => Number(route.params.campaignId));
const campaign = computed(() =>
  campaigns.value.find(item => item.id === campaignId.value)
);

useRecipientImportPolling(campaign);

// UNICA fonte da verdade do editor: o composable singleton.
const { isReady, device, getMjml, getHtml, setMjml, setDevice } =
  useEmailEditor();

const placeholders = ref([]);
const subjectInput = ref(campaign.value?.subject || '');
const showAiDialog = ref(false);
const showGeneratingDialog = ref(false);
// Current design captured when opening the AI dialog, so the AI can ADAPT a
// chosen template (preserve structure, rewrite copy) instead of only generating
// from scratch. Empty when there's no design yet.
const aiBaseMjml = ref('');
const showTestPopover = ref(false);
const testEmail = ref('');
const isSendingTest = ref(false);
const showSaveTemplatePopover = ref(false);
const templateName = ref('');
const isSavingTemplate = ref(false);
const isPersistingSubject = ref(false);

// The two top-bar popovers (send test / save as template) are mutually exclusive so they
// never overlap: opening one closes the other.
const toggleTestPopover = () => {
  showSaveTemplatePopover.value = false;
  showTestPopover.value = !showTestPopover.value;
};
const toggleSaveTemplatePopover = () => {
  showTestPopover.value = false;
  showSaveTemplatePopover.value = !showSaveTemplatePopover.value;
};
const pendingAiDialog = ref(false);
const lastAppliedCampaignMjml = ref('');

// Welcome "como criar" = ESTADO dentro da pagina (amendments §5.2): mostrado
// quando a campanha ainda nao tem corpo. forceEditor permite "Do zero" entrar
// no editor imediatamente com um MJML base.
const forceEditor = ref(false);
const campaignHasBody = computed(
  () => Boolean(campaign.value?.body_mjml) || Boolean(campaign.value?.body_html)
);
const showWelcome = computed(
  () => !forceEditor.value && !campaignHasBody.value
);

const previewLabel = computed(() =>
  device.value === 'desktop'
    ? t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PREVIEW_MOBILE')
    : t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PREVIEW_DESKTOP')
);

const goBack = () => {
  router.push({
    name: 'campaigns_email_index',
    params: { accountId: route.params.accountId },
  });
};

const openGallery = () => {
  router.push({
    name: 'campaigns_email_templates',
    params: {
      accountId: route.params.accountId,
      campaignId: campaignId.value,
    },
  });
};

const isBlankEditorMjml = mjml => {
  const normalized = (mjml || '').replace(/\s+/g, '').toLowerCase();
  return (
    !normalized ||
    normalized === '<mjml><mj-body></mj-body></mjml>' ||
    normalized === '<mj-body></mj-body>' ||
    normalized ===
      '<mjml><mj-body><mj-section><mj-column></mj-column></mj-section></mj-body></mjml>'
  );
};

const getEditorBodyPayload = () => {
  const bodyMjml = getMjml();
  const isLegacyHtmlOnly =
    Boolean(campaign.value?.body_html) && !campaign.value?.body_mjml;

  if (isLegacyHtmlOnly && isBlankEditorMjml(bodyMjml)) return {};

  return {
    body_mjml: bodyMjml,
    body_html: getHtml(),
  };
};

const persist = async extra => {
  await store.dispatch('emailCampaigns/update', {
    id: campaignId.value,
    ...getEditorBodyPayload(),
    ...extra,
  });
};

// Keep the local subject input in sync when the campaign subject changes
// elsewhere (e.g. the async AI generation persists a new subject on the campaign).
watch(
  () => campaign.value?.subject,
  value => {
    // Don't clobber the field while a save is in flight (the in-flight value is
    // the source of truth until it lands); only sync external changes otherwise.
    if (isPersistingSubject.value) return;
    if (value !== undefined && value !== subjectInput.value)
      subjectInput.value = value;
  }
);

const persistSubject = async () => {
  // Guard against the @keyup.enter + @blur double-fire.
  if (isPersistingSubject.value) return;
  if (subjectInput.value.trim() === (campaign.value?.subject || '')) return;
  isPersistingSubject.value = true;
  let saved = false;
  try {
    await persist({ subject: subjectInput.value.trim() });
    saved = true;
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_ERROR'));
  } finally {
    isPersistingSubject.value = false;
  }
  // Re-persist ONLY after a successful save (campaign.subject advanced) if the
  // user kept typing meanwhile. On error we stop — no infinite recursion.
  if (saved && subjectInput.value.trim() !== (campaign.value?.subject || '')) {
    persistSubject();
  }
};

const save = async () => {
  try {
    await persist();
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_ERROR'));
  }
};

const sendTest = async () => {
  if (!testEmail.value) return;
  isSendingTest.value = true;
  try {
    await persist();
    await store.dispatch('emailCampaigns/sendTest', {
      id: campaignId.value,
      toEmail: testEmail.value,
    });
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_SUCCESS'));
    showTestPopover.value = false;
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_ERROR'));
  } finally {
    isSendingTest.value = false;
  }
};

const saveTemplate = async () => {
  if (!templateName.value) return;
  isSavingTemplate.value = true;
  try {
    await EmailCampaignTemplatesAPI.create({
      name: templateName.value,
      body_mjml: getMjml(),
      body_html: getHtml(),
      category: 'meus-modelos',
    });
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_SUCCESS'));
    showSaveTemplatePopover.value = false;
    templateName.value = '';
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_ERROR'));
  } finally {
    isSavingTemplate.value = false;
  }
};

const togglePreview = () => {
  setDevice(device.value === 'desktop' ? 'mobile' : 'desktop');
};

const openAiDialog = () => {
  // Capture the current canvas as the adaptation base when there's a design loaded
  // (e.g. a template was chosen). Generating with no design yet -> empty (from scratch).
  aiBaseMjml.value = isReady.value && campaignHasBody.value ? getMjml() : '';
  if (isReady.value) {
    showAiDialog.value = true;
    return;
  }
  pendingAiDialog.value = true;
};

// Geração assíncrona: o composer só dispara o job; o popup de geração assume daqui.
const onGenerationStarted = () => {
  showAiDialog.value = false;
  showGeneratingDialog.value = true;
};

// Concluiu (popup avisou): recarrega a campanha -> o watcher applyCampaignMjml aplica o
// body_mjml gerado no canvas; sincroniza o assunto.
const onGenerationReady = async () => {
  showGeneratingDialog.value = false;
  await store.dispatch('emailCampaigns/get');
  if (campaign.value?.subject) subjectInput.value = campaign.value.subject;
};

// Welcome handlers
const chooseAi = () => {
  forceEditor.value = true;
  openAiDialog();
};
const startBlank = () => {
  forceEditor.value = true;
};

const applyCampaignMjml = () => {
  const mjml = campaign.value?.body_mjml;
  if (!isReady.value || !mjml || lastAppliedCampaignMjml.value === mjml) return;

  setMjml(mjml);
  lastAppliedCampaignMjml.value = mjml;
};

// Quando entra no editor "do zero" e o canvas estiver pronto sem corpo,
// semeia o MJML base uma unica vez.
watch(
  [isReady, showWelcome],
  ([ready, welcome]) => {
    if (ready && !welcome && !campaignHasBody.value) {
      setMjml(STARTER_MJML);
    }
  },
  { flush: 'post' }
);

watch(
  isReady,
  ready => {
    if (!ready) return;

    if (pendingAiDialog.value) {
      pendingAiDialog.value = false;
      showAiDialog.value = true;
    }
  },
  { flush: 'post' }
);

watch(
  [
    isReady,
    () => campaign.value?.body_mjml,
    () => campaign.value?.updated_at || campaign.value?.updatedAt,
  ],
  applyCampaignMjml,
  { flush: 'post' }
);

const fetchPlaceholders = async () => {
  try {
    const data = await store.dispatch(
      'emailCampaigns/fetchPlaceholders',
      campaignId.value
    );
    placeholders.value = data.placeholders || data.available || [];
  } catch (error) {
    placeholders.value = [];
  }
};

watch(
  () => campaign.value?.recipient_import?.status,
  status => {
    if (status === 'completed') fetchPlaceholders();
  }
);

onMounted(async () => {
  if (!campaign.value) {
    await store.dispatch('emailCampaigns/get');
  }
  // Durabilidade: se a campanha já está sendo gerada (usuário saiu e voltou), retoma o popup.
  if (campaign.value?.ai_status === 'processing') {
    showGeneratingDialog.value = true;
  }
  fetchPlaceholders();
});

onActivated(() => {
  applyCampaignMjml();
});
</script>

<template>
  <div class="flex flex-col flex-1 h-full min-h-0 bg-n-surface-1">
    <RecipientImportStatus
      v-if="campaign"
      :campaign="campaign"
      class="px-4 py-2"
    />
    <!-- Top bar nova: hierarquia clara, "Criar com IA" = HERÓI -->
    <div
      class="flex items-center justify-between gap-3 px-4 py-3 border-b border-n-weak"
    >
      <div class="flex items-center min-w-0 gap-2">
        <Button
          icon="i-lucide-arrow-left"
          color="slate"
          variant="ghost"
          size="sm"
          @click="goBack()"
        />
        <div class="flex flex-col min-w-0">
          <p class="mb-0 font-medium truncate text-n-slate-12">
            {{ campaign?.name || t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.TITLE') }}
          </p>
          <input
            v-model="subjectInput"
            type="text"
            class="w-64 max-w-full p-0 text-xs bg-transparent border-0 truncate text-n-slate-11 focus:outline-none focus:ring-0"
            :aria-label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SUBJECT_LABEL')"
            :placeholder="
              t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SUBJECT_PLACEHOLDER')
            "
            @blur="persistSubject()"
            @keyup.enter="persistSubject()"
          />
        </div>
      </div>
      <div class="relative flex items-center gap-2">
        <!-- HERÓI: ação primária destacada (azul, solid) -->
        <Button
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.AI_COMPOSE')"
          icon="i-lucide-sparkles"
          color="blue"
          size="sm"
          :disabled="!isReady"
          @click="openAiDialog"
        />

        <div class="w-px h-6 mx-1 bg-n-weak" />

        <AiBlockActions v-if="isReady" />
        <Button
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.TEMPLATES')"
          icon="i-lucide-layout-template"
          color="slate"
          variant="link"
          size="sm"
          @click="openGallery()"
        />
        <Button
          :label="previewLabel"
          icon="i-lucide-smartphone"
          color="slate"
          variant="outline"
          size="sm"
          :disabled="!isReady"
          @click="togglePreview()"
        />
        <Button
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST')"
          icon="i-lucide-mail-check"
          color="slate"
          variant="outline"
          size="sm"
          :disabled="!isReady"
          @click="toggleTestPopover"
        />
        <Button
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE')"
          icon="i-lucide-save"
          color="slate"
          variant="outline"
          size="sm"
          :is-loading="uiFlags.isUpdating"
          :disabled="!isReady"
          @click="save()"
        />
        <Button
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE')"
          icon="i-lucide-bookmark-plus"
          color="slate"
          variant="outline"
          size="sm"
          :disabled="!isReady"
          @click="toggleSaveTemplatePopover"
        />
        <div
          v-if="showTestPopover"
          class="absolute right-0 z-50 flex flex-col w-72 gap-3 p-4 border rounded-lg shadow-lg top-10 border-n-weak bg-n-solid-1"
        >
          <Input
            v-model="testEmail"
            type="email"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_EMAIL_LABEL')"
            :placeholder="
              t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_EMAIL_PLACEHOLDER')
            "
            @enter="sendTest()"
          />
          <div class="flex justify-end gap-2">
            <Button
              :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.CANCEL')"
              color="slate"
              variant="ghost"
              size="sm"
              @click="showTestPopover = false"
            />
            <Button
              :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_SUBMIT')"
              color="blue"
              size="sm"
              :is-loading="isSendingTest"
              @click="sendTest()"
            />
          </div>
        </div>
        <div
          v-if="showSaveTemplatePopover"
          class="absolute right-0 z-50 flex flex-col w-72 gap-3 p-4 border rounded-lg shadow-lg top-10 border-n-weak bg-n-solid-1"
        >
          <Input
            v-model="templateName"
            :label="
              t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_NAME_LABEL')
            "
            :placeholder="
              t(
                'CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_NAME_PLACEHOLDER'
              )
            "
            @enter="saveTemplate()"
          />
          <div class="flex justify-end gap-2">
            <Button
              :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.CANCEL')"
              color="slate"
              variant="ghost"
              size="sm"
              @click="showSaveTemplatePopover = false"
            />
            <Button
              :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_SUBMIT')"
              color="blue"
              size="sm"
              :is-loading="isSavingTemplate"
              @click="saveTemplate()"
            />
          </div>
        </div>
      </div>
    </div>

    <!-- Barra de placeholders reais da base -->
    <div
      v-if="placeholders.length && !showWelcome"
      class="flex flex-wrap items-center gap-2 px-4 py-2 border-b border-n-weak"
    >
      <span class="text-xs text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PLACEHOLDERS_TITLE') }}
      </span>
      <PlaceholderChips :placeholders="placeholders" />
    </div>

    <!-- Conteúdo -->
    <div class="flex-1 min-h-0">
      <div
        v-if="!campaign"
        class="flex items-center justify-center h-full text-n-slate-11"
      >
        <Spinner />
      </div>

      <!-- Etapa2 "como criar" (estado, não rota) -->
      <WelcomeChooser
        v-else-if="showWelcome"
        @choose-ai="chooseAi"
        @choose-template="openGallery"
        @start-blank="startBlank"
      />

      <!-- Editor: blocos (esq) · canvas (centro) · props (dir) -->
      <div v-else class="flex h-full min-h-0">
        <aside
          class="w-64 shrink-0 h-full min-h-0 overflow-y-auto border-r border-n-weak bg-n-solid-1"
        >
          <BlocksPanel v-if="isReady" />
        </aside>
        <div class="flex-1 min-w-0 min-h-0">
          <GrapesEditor :mjml="campaign.body_mjml || ''" />
        </div>
        <aside
          class="w-72 shrink-0 h-full min-h-0 overflow-y-auto border-l border-n-weak bg-n-solid-1"
        >
          <PropertiesPanel v-if="isReady" />
        </aside>
      </div>
    </div>

    <AiComposerDialog
      v-if="showAiDialog"
      :campaign-id="campaignId"
      :placeholders="placeholders"
      :base-mjml="aiBaseMjml"
      @generation-started="onGenerationStarted"
      @close="showAiDialog = false"
    />

    <AiGeneratingDialog
      v-if="showGeneratingDialog"
      :campaign-id="campaignId"
      @ready="onGenerationReady"
      @close="showGeneratingDialog = false"
    />
  </div>
</template>
