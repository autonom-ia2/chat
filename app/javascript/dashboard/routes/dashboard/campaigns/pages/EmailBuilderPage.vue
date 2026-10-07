<script setup>
import {
  computed,
  nextTick,
  onActivated,
  onBeforeUnmount,
  onDeactivated,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRecipientImportPolling } from 'dashboard/composables/useRecipientImportPolling';
import RecipientImportStatus from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue';
import EmailRecipientStep from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailRecipientStep.vue';

import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Input from 'dashboard/components-next/input/Input.vue';
import { testSendAddress, testSendErrorMessage } from './emailTestSend';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import GrapesEditor from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/GrapesEditor.vue';
import AiComposerDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/AiComposerDialog.vue';
import AiGeneratingDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/AiGeneratingDialog.vue';
import AiBlockActions from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/AiBlockActions.vue';
import BrandEmailIdentityPanel from 'dashboard/components-next/BrandKits/BrandEmailIdentityPanel.vue';
import { useBrandKits } from 'dashboard/components-next/BrandKits/useBrandKits';
import AiAdjustPreview from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/AiAdjustPreview.vue';
import { hasEmailContent } from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/canvasContent';
import EmailCampaignAiAPI from 'dashboard/api/emailCampaignAi';
import TestSendForm from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/TestSendForm.vue';
import PlaceholderChips from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/PlaceholderChips.vue';
import BlocksPanel from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/BlocksPanel.vue';
import PropertiesPanel from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/PropertiesPanel.vue';
import WelcomeChooser from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/WelcomeChooser.vue';
import { useEmailEditor } from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/composables/useEmailEditor';
import { STARTER_MJML } from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/starterMjml';
import EmailCampaignTemplatesAPI from 'dashboard/api/emailCampaignTemplates';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EmailCampaignReview from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignReview.vue';
import EmailCampaignDetailsDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDetailsDialog.vue';
import EmailCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue';

const { t } = useI18n();
const stepNumbers = [1, 2, 3];
const store = useStore();
const route = useRoute();
const router = useRouter();
const canManage = useCanManage('campaign_manage');

const campaigns = useMapGetter('emailCampaigns/getCampaigns');
const uiFlags = useMapGetter('emailCampaigns/getUIFlags');
const currentUser = useMapGetter('getCurrentUser');

const campaignId = computed(() => Number(route.params.campaignId));
const campaign = computed(() =>
  campaigns.value.find(item => item.id === campaignId.value)
);

useRecipientImportPolling(campaign);

// Identity of this e-mail (#1076): the one Nova campanha chose (?brand_kit=&brand_mode=), else the one
// the last generation used; "Criar com IA" starts from it.
const { isEnabled: brandKitsEnabled } = useBrandKits();
const initialBrand = computed(() => {
  const used = campaign.value?.brand_identity || {};
  return {
    kitId: Number(route.query.brand_kit) || used.kit_id || null,
    mode: route.query.brand_mode || used.mode || 'light',
  };
});

// UNICA fonte da verdade do editor: o composable singleton.
const {
  isReady,
  device,
  getMjml,
  getHtml,
  setMjml,
  compileMjml,
  contentVersion,
  setDevice,
  selectedComponent,
  isTextSelected,
  setSelectedText,
  adjustCanvasScroll,
  setCanvasPreview,
} = useEmailEditor();

const placeholders = ref([]);
const activePanel = ref('canvas');
const subjectInput = ref(campaign.value?.subject || '');
const preheaderInput = ref(campaign.value?.preheader || '');

const showAiDialog = ref(false);
const showGeneratingDialog = ref(false);
// "Ajustar com IA" (#1095): with content on the canvas the AI changes only what the person asks, and
// the result waits in a before/after preview until it is applied or discarded.
const aiCanAdjust = ref(false);
const generationMode = ref('create');
const adjustPreview = ref(null);
const pendingAdjustment = ref(null);
const undoMjml = ref('');
const showUndo = ref(false);
const canvasHasContent = ref(false);
const CONTENT_CHECK_MS = 300;
let contentTimer = null;
const showTestPopover = ref(false);
// #1093: the test goes to any typed address (up to 5); the field starts with the user's own.
const testEmail = computed(() => testSendAddress(currentUser.value));
const isSendingTest = ref(false);
const testSendError = ref('');
const showSaveTemplatePopover = ref(false);
const templateName = ref('');
const isSavingTemplate = ref(false);
const isPersistingSubject = ref(false);

// The two top-bar popovers (send test / save as template) are mutually exclusive so they
// never overlap: opening one closes the other.
const toggleTestPopover = () => {
  showSaveTemplatePopover.value = false;
  testSendError.value = '';
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
  const normalized = (mjml || '')
    .split('')
    .filter(character => character.trim())
    .join('')
    .toLowerCase();
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
    await persist({
      subject: subjectInput.value.trim(),
      preheader: preheaderInput.value.trim() || null,
    });
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_ERROR'));
  }
};

const sendTest = async toEmails => {
  isSendingTest.value = true;
  testSendError.value = '';
  try {
    await persist({
      subject: subjectInput.value.trim(),
      preheader: preheaderInput.value.trim() || null,
    });
    await store.dispatch('emailCampaigns/sendTest', {
      id: campaignId.value,
      toEmails,
    });
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_SUCCESS'));
    showTestPopover.value = false;
  } catch (error) {
    const { key, params } = testSendErrorMessage(error);
    testSendError.value = t(key, params);
  } finally {
    isSendingTest.value = false;
  }
};

const saveTemplate = async () => {
  if (!templateName.value) return;
  isSavingTemplate.value = true;
  try {
    const body = getEditorBodyPayload();
    await EmailCampaignTemplatesAPI.create({
      name: templateName.value,
      ...body,
      body_html: body.body_html ?? campaign.value?.body_html,
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

// Any content on the canvas (AI, library, saved models or by hand) turns "Criar com IA" into "Ajustar com
// IA". Checked a moment after the last change, not on every keystroke.
const refreshCanvasContent = () => {
  canvasHasContent.value =
    isReady.value && !showWelcome.value && hasEmailContent(getMjml());
};
watch([isReady, contentVersion, showWelcome], () => {
  clearTimeout(contentTimer);
  contentTimer = setTimeout(refreshCanvasContent, CONTENT_CHECK_MS);
});
onBeforeUnmount(() => clearTimeout(contentTimer));
const aiButtonLabel = computed(() =>
  canvasHasContent.value
    ? t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.AI_ADJUST')
    : t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.AI_COMPOSE')
);

const openAiDialog = () => {
  showUndo.value = false;
  aiCanAdjust.value = isReady.value && hasEmailContent(getMjml());
  if (isReady.value) {
    showAiDialog.value = true;
    return;
  }
  pendingAiDialog.value = true;
};

// Geração assíncrona: o composer só dispara o job; o popup de geração assume daqui.
const onGenerationStarted = ({ mode } = {}) => {
  generationMode.value = mode || 'create';
  showAiDialog.value = false;
  showGeneratingDialog.value = true;
};

const openAdjustPreview = adjustment => {
  adjustPreview.value = {
    after: adjustment.mjml,
    beforeHtml: compileMjml(adjustment.base),
    afterHtml: compileMjml(adjustment.mjml),
    summary: adjustment.summary || '',
    siteRequest: adjustment.site_request || null,
  };
};

// Concluiu (popup avisou). Ajuste: abre o antes/depois. Geração: recarrega a campanha -> o watcher
// applyCampaignMjml aplica o body_mjml gerado no canvas; sincroniza o assunto.
const onGenerationReady = async status => {
  showGeneratingDialog.value = false;
  if (status?.ai_adjustment?.status === 'proposed') {
    openAdjustPreview(status.ai_adjustment);
    return;
  }
  await store.dispatch('emailCampaigns/get');
  if (campaign.value?.subject) subjectInput.value = campaign.value.subject;
};

// The proposal is used up once the person decides. If this call fails the same proposal is offered
// again on the next visit, which is harmless; the decision itself already happened on the canvas.
const forgetAdjustment = async () => {
  try {
    await EmailCampaignAiAPI.discardAdjustment(campaignId.value);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn(
      '[EmailBuilderPage] could not discard the AI adjustment',
      error
    );
  }
};

// Applied: the server uses the proposal up and records a site identity the adjustment used (#1111). It runs before
// the save, whose answer brings the campaign back with that identity for the identity panel.
const recordAppliedAdjustment = async () => {
  try {
    await EmailCampaignAiAPI.applyAdjustment(campaignId.value);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn(
      '[EmailBuilderPage] could not record the applied AI adjustment',
      error
    );
  }
};

const persistBody = async () => {
  try {
    await persist();
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_ERROR'));
  }
};

const applyAdjustment = async () => {
  const proposal = adjustPreview.value;
  adjustPreview.value = null;
  undoMjml.value = getMjml();
  setMjml(proposal.after);
  showUndo.value = true;
  await recordAppliedAdjustment();
  await persistBody();
};

const discardAdjustment = () => {
  adjustPreview.value = null;
  forgetAdjustment();
};

const undoAdjustment = async () => {
  showUndo.value = false;
  setMjml(undoMjml.value);
  await persistBody();
};

// Came back after leaving during an adjustment: the proposal waits for the editor to be ready.
const resumeAdjustment = async () => {
  try {
    const { data } = await EmailCampaignAiAPI.status(campaignId.value);
    if (data.ai_adjustment?.status === 'proposed') {
      pendingAdjustment.value = data.ai_adjustment;
    }
  } catch (error) {
    // Network hiccup: the proposal stays on the server and is offered on the next visit.
  }
};
watch([isReady, pendingAdjustment], ([ready, adjustment]) => {
  if (!ready || !adjustment) return;
  pendingAdjustment.value = null;
  openAdjustPreview(adjustment);
});

// Welcome handlers
const chooseAi = () => {
  activePanel.value = 'canvas';
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
  try {
    if (!campaign.value) {
      await store.dispatch('emailCampaigns/get');
    }
    await store.dispatch('emailCampaigns/getOne', campaignId.value);
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.ERROR'));
  }
  // Durabilidade: se a campanha já está sendo gerada (usuário saiu e voltou), retoma o popup.
  if (campaign.value?.ai_status === 'processing') {
    showGeneratingDialog.value = true;
  }
  if (campaign.value?.ai_status === 'ready') resumeAdjustment();
  fetchPlaceholders();
});

onActivated(() => {
  applyCampaignMjml();
});

const UX = 'CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE';
const reviewStep = computed(() => route.query.step === 'review');
const showPersonalize = ref(false);
const detailsOpen = ref(false);
const problemsOnly = ref(false);
const senderOpen = ref(false);
const previewDialog = ref(null);
const previewHtml = ref('');
const importStatus = ref(null);
const emailDetailsOpen = ref(false);
const compactHeader = ref(false);
const fullView = ref(false);
const fitToView = ref(true);
const canvasHost = ref(null);
const COLLAPSE_SCROLL = 120;
const RESTORE_SCROLL = 60;
let lastScrollTop = 0;
let upwardScroll = 0;
let adjustingScroll = false;
let scrollGeneration = 0;
const onCanvasScroll = async top => {
  if (fullView.value || emailDetailsOpen.value || adjustingScroll) return;
  const delta = top - lastScrollTop;
  lastScrollTop = top;
  upwardScroll = delta < 0 ? upwardScroll - delta : 0;
  const collapse = top > COLLAPSE_SCROLL && delta > 0;
  const restore = top < 8 || upwardScroll > RESTORE_SCROLL;
  if ((!compactHeader.value && !collapse) || (compactHeader.value && !restore))
    return;
  const oldTop = canvasHost.value.getBoundingClientRect().top;
  const generation = scrollGeneration;
  adjustingScroll = true;
  compactHeader.value = !compactHeader.value;
  upwardScroll = 0;
  await nextTick();
  if (generation !== scrollGeneration || !canvasHost.value?.isConnected) return;
  const offset = canvasHost.value.getBoundingClientRect().top - oldTop;
  adjustCanvasScroll(offset);
  lastScrollTop = Math.max(0, top + offset);
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      if (generation === scrollGeneration) adjustingScroll = false;
    });
  });
};
const previewEmail = () => {
  previewHtml.value =
    isReady.value && !showWelcome.value
      ? (getEditorBodyPayload().body_html ?? campaign.value?.body_html)
      : campaign.value?.body_html;
  previewDialog.value.open();
};
const toggleFullView = () => {
  if (
    !fullView.value &&
    campaign.value?.body_html &&
    !campaign.value?.body_mjml &&
    isBlankEditorMjml(getMjml())
  ) {
    previewEmail();
    return;
  }
  adjustingScroll = true;
  // Save the canvas position before the full-view layout resizes its iframe.
  // The post-layout watcher then completes the preview with the new viewport.
  if (!fullView.value) setCanvasPreview(true);
  fullView.value = !fullView.value;
  fitToView.value = true;
  showPersonalize.value = false;
  showTestPopover.value = false;
  showSaveTemplatePopover.value = false;
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      adjustingScroll = false;
    });
  });
};
watch(reviewStep, () => {
  fullView.value = false;
});
onDeactivated(() => {
  scrollGeneration += 1;
  fullView.value = false;
  compactHeader.value = false;
  lastScrollTop = 0;
  upwardScroll = 0;
  adjustingScroll = false;
});
watch(
  () => campaign.value?.preheader,
  value => {
    preheaderInput.value = value || '';
  }
);
const setStep = step =>
  router.replace({
    query: { ...route.query, step: step === 'review' ? 'review' : undefined },
  });
const openReview = async () => {
  try {
    if (canManage.value && !showWelcome.value && isReady.value) {
      await persist({
        subject: subjectInput.value.trim(),
        preheader: preheaderInput.value.trim() || null,
      });
    }
    await setStep('review');
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_ERROR'));
  }
};
const openRecipients = (problems = false) => {
  problemsOnly.value = problems;
  detailsOpen.value = true;
};
const openRecipientStep = () => {
  if (
    campaign.value?.recipient_import?.status === 'failed' &&
    canManage.value &&
    campaign.value.status === 'draft'
  ) {
    importStatus.value.openRecovery();
    return;
  }
  openRecipients(false);
};
const onSenderSaved = () => {
  senderOpen.value = false;
  store.dispatch('emailCampaigns/getOne', campaignId.value);
};
const insertPlaceholder = key => {
  if (isTextSelected.value) {
    setSelectedText(`${selectedComponent.value.getInnerHTML()} {{ ${key} }}`);
  }
  showPersonalize.value = false;
};
</script>

<template>
  <section
    class="flex min-h-0 min-w-0 flex-1 flex-col bg-n-surface-1"
    :class="fullView ? 'fixed inset-0 z-50' : 'h-full'"
    @keydown.esc="fullView && toggleFullView()"
  >
    <EmailCampaignReview
      v-if="reviewStep && campaign"
      :campaign="campaign"
      @edit="setStep('content')"
      @recipients="openRecipients"
      @sender="senderOpen = true"
      @done="goBack"
    />
    <template v-else>
      <header
        class="flex shrink-0 flex-wrap items-center justify-between gap-3 border-b border-n-weak bg-n-solid-1 px-4 py-3 lg:px-6"
      >
        <div
          class="flex min-w-0 flex-1 basis-full items-center gap-3 sm:basis-0"
        >
          <Button
            :aria-label="t(`${UX}.BACK_CAMPAIGNS`)"
            icon="i-lucide-arrow-left"
            slate
            ghost
            class="!size-11"
            @click="goBack"
          />
          <div class="min-w-0">
            <h1 class="mb-1 truncate text-base font-semibold text-n-slate-12">
              {{ campaign?.name || t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.TITLE') }}
            </h1>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t(`${UX}.EDIT_DRAFT`) }}
            </p>
          </div>
        </div>
        <div class="flex max-w-full shrink-0 flex-wrap items-center gap-2">
          <EmailRecipientStep
            v-if="compactHeader || fullView"
            :campaign="campaign"
            @click="openRecipientStep"
          />
          <Button
            :aria-label="t(`${UX}.PREVIEW`)"
            :title="t(`${UX}.PREVIEW`)"
            icon="i-lucide-eye"
            slate
            outline
            class="!min-h-11 !rounded-xl"
            :disabled="!campaignHasBody && !isReady"
            @click="previewEmail"
          />
          <Button
            v-if="canManage"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE')"
            icon="i-lucide-save"
            slate
            outline
            class="!min-h-11 !rounded-xl"
            :disabled="!isReady"
            :is-loading="uiFlags.isUpdating"
            @click="save"
          />
          <Button
            v-if="canManage"
            :label="t(`${UX}.REVIEW_SEND`)"
            icon="i-lucide-arrow-right"
            trailing-icon
            class="!min-h-11 !rounded-xl"
            :is-loading="uiFlags.isUpdating"
            @click="openReview"
          />
        </div>
      </header>
      <div
        v-show="!compactHeader && !fullView"
        class="flex shrink-0 items-center gap-3 border-b border-n-weak bg-n-solid-1 px-4 py-2 lg:px-6"
      >
        <nav
          class="flex min-w-0 flex-1 items-center gap-2 overflow-x-auto text-xs"
          :aria-label="t(`${UX}.STEPS`)"
        >
          <span
            class="flex min-h-11 shrink-0 items-center gap-2 whitespace-nowrap rounded-xl bg-n-blue-3 px-3 font-medium text-n-blue-11"
            aria-current="step"
          >
            <span
              class="flex size-6 items-center justify-center rounded-full bg-n-brand text-white"
            >
              {{ stepNumbers[0] }}
            </span>
            {{ t(`${UX}.CONTENT`) }}
          </span>
          <EmailRecipientStep :campaign="campaign" @click="openRecipientStep" />
          <button
            type="button"
            class="flex min-h-11 shrink-0 items-center gap-2 whitespace-nowrap rounded-xl px-3 text-n-slate-11 hover:bg-n-alpha-1"
            @click="openReview"
          >
            <span
              class="flex size-6 items-center justify-center rounded-full bg-n-alpha-2"
            >
              {{ stepNumbers[2] }}
            </span>
            {{ t(`${UX}.REVIEW_SEND`) }}
          </button>
        </nav>
        <Button
          :aria-label="t(`${UX}.EMAIL_DETAILS`)"
          :title="t(`${UX}.EMAIL_DETAILS`)"
          :icon="
            emailDetailsOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
          "
          trailing-icon
          slate
          outline
          class="!min-h-11 shrink-0 !rounded-xl"
          :aria-expanded="emailDetailsOpen"
          aria-controls="email-campaign-details"
          @click="emailDetailsOpen = !emailDetailsOpen"
        >
          <span class="hidden sm:inline">{{ t(`${UX}.EMAIL_DETAILS`) }}</span>
        </Button>
      </div>
      <div
        v-show="emailDetailsOpen && !fullView"
        id="email-campaign-details"
        class="grid max-h-[40dvh] shrink-0 gap-4 overflow-y-auto border-b border-n-weak bg-n-solid-1 px-5 py-3 sm:grid-cols-2 lg:px-6"
      >
        <Input
          v-model="subjectInput"
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SUBJECT_LABEL')"
          :placeholder="
            t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SUBJECT_PLACEHOLDER')
          "
          :readonly="!canManage"
          @blur="persistSubject"
          @enter="persistSubject"
        />
        <Input
          v-model="preheaderInput"
          :label="t(`${UX}.PREHEADER`)"
          :placeholder="t(`${UX}.PREHEADER_HINT`)"
          :readonly="!canManage"
        />
      </div>
      <RecipientImportStatus
        v-if="campaign"
        ref="importStatus"
        compact
        :campaign="campaign"
        :can-recover="canManage"
        auto-recover
      />
      <div v-if="!campaign" class="flex flex-1 items-center justify-center">
        <Spinner />
      </div>
      <div
        v-else
        class="flex min-h-0 flex-1 flex-col overflow-hidden xl:flex-row"
      >
        <div
          v-show="!fullView"
          class="flex shrink-0 items-center gap-2 overflow-x-auto border-b border-n-weak px-4 py-2 xl:hidden"
        >
          <Button
            :label="t(`${UX}.BLOCKS`)"
            slate
            :variant="activePanel === 'blocks' ? 'faded' : 'ghost'"
            @click="
              activePanel = activePanel === 'blocks' ? 'canvas' : 'blocks'
            "
          />
          <Button
            :label="t(`${UX}.CONTENT`)"
            slate
            :variant="activePanel === 'canvas' ? 'faded' : 'ghost'"
            @click="activePanel = 'canvas'"
          />
          <Button
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.TITLE')"
            slate
            :variant="activePanel === 'properties' ? 'faded' : 'ghost'"
            @click="
              activePanel =
                activePanel === 'properties' ? 'canvas' : 'properties'
            "
          />
        </div>
        <aside
          v-show="!fullView"
          class="min-h-0 w-full flex-1 shrink-0 overflow-y-auto border-e border-n-weak bg-n-solid-1 xl:w-60 xl:flex-none"
          :class="activePanel === 'blocks' ? 'block' : 'hidden xl:block'"
        >
          <div v-if="canManage" class="space-y-2 border-b border-n-weak p-4">
            <Button
              :label="aiButtonLabel"
              icon="i-lucide-sparkles"
              class="!min-h-11 w-full !rounded-xl"
              data-test="ai-compose-button"
              @click="showWelcome ? chooseAi() : openAiDialog()"
            />
            <Button
              :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.TEMPLATES')"
              icon="i-lucide-layout-template"
              slate
              outline
              class="!min-h-11 w-full !rounded-xl"
              @click="openGallery"
            />
          </div>
          <BlocksPanel v-if="isReady && canManage" />
          <p v-else class="m-0 p-4 text-xs leading-5 text-n-slate-11">
            {{ t(`${UX}.CHOOSE_START`) }}
          </p>
        </aside>
        <div
          class="flex min-h-0 min-w-0 flex-1 flex-col"
          :class="
            activePanel === 'canvas' || fullView ? 'flex' : 'hidden xl:flex'
          "
        >
          <div
            class="relative flex shrink-0 flex-wrap items-center justify-between gap-2 border-b border-n-weak bg-n-solid-1 px-4 py-2"
          >
            <div
              v-show="!fullView"
              class="flex gap-1 rounded-lg bg-n-alpha-1 p-1"
            >
              <Button
                v-for="option in ['desktop', 'mobile']"
                :key="option"
                :aria-label="t(`${UX}.DEVICES.${option}`)"
                :title="t(`${UX}.DEVICES.${option}`)"
                :icon="
                  option === 'desktop'
                    ? 'i-lucide-monitor'
                    : 'i-lucide-smartphone'
                "
                :aria-pressed="device === option"
                :variant="device === option ? 'solid' : 'ghost'"
                :color="device === option ? 'slate' : 'slate'"
                class="!min-h-11"
                :disabled="!isReady"
                @click="setDevice(option)"
              >
                <span class="hidden 2xl:inline">
                  {{ t(`${UX}.DEVICES.${option}`) }}
                </span>
              </Button>
            </div>
            <div v-show="!fullView" class="relative flex flex-wrap gap-2">
              <Button
                v-if="placeholders.length && canManage"
                :aria-label="t(`${UX}.PERSONALIZE`)"
                :title="t(`${UX}.PERSONALIZE`)"
                icon="i-lucide-braces"
                slate
                ghost
                class="!min-h-11"
                @click="showPersonalize = !showPersonalize"
              >
                <span class="hidden 2xl:inline">
                  {{ t(`${UX}.PERSONALIZE`) }}
                </span>
              </Button>
              <Button
                v-if="canManage"
                :aria-label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST')"
                :title="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST')"
                icon="i-lucide-mail-check"
                slate
                ghost
                class="!min-h-11"
                :disabled="!isReady"
                @click="toggleTestPopover"
              >
                <span class="hidden 2xl:inline">
                  {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST') }}
                </span>
              </Button>
              <Button
                v-if="canManage"
                :aria-label="t(`${UX}.SAVE_MODEL`)"
                :title="t(`${UX}.SAVE_MODEL`)"
                icon="i-lucide-bookmark-plus"
                slate
                ghost
                class="!min-h-11"
                :disabled="!isReady"
                @click="toggleSaveTemplatePopover"
              >
                <span class="hidden 2xl:inline">
                  {{ t(`${UX}.SAVE_MODEL`) }}
                </span>
              </Button>
              <div
                v-if="showTestPopover"
                class="absolute end-0 z-50 flex flex-col w-[min(20rem,calc(100vw-3rem))] gap-3 p-4 border rounded-lg shadow-lg top-12 border-n-weak bg-n-solid-1"
                data-test="test-send-popover"
              >
                <TestSendForm
                  :default-email="testEmail"
                  :is-sending="isSendingTest"
                  :error-message="testSendError"
                  @send="sendTest"
                  @cancel="showTestPopover = false"
                />
              </div>
              <div
                v-if="showSaveTemplatePopover"
                class="absolute end-0 z-50 flex flex-col w-[min(20rem,calc(100vw-3rem))] gap-3 p-4 border rounded-lg shadow-lg top-12 border-n-weak bg-n-solid-1"
              >
                <Input
                  v-model="templateName"
                  :label="
                    t(
                      'CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_NAME_LABEL'
                    )
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
                    :label="
                      t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_SUBMIT')
                    "
                    color="blue"
                    size="sm"
                    :is-loading="isSavingTemplate"
                    @click="saveTemplate()"
                  />
                </div>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <Button
                v-if="fullView"
                :label="t(`${UX}.${fitToView ? 'ENLARGE' : 'FIT_EMAIL'}`)"
                :icon="fitToView ? 'i-lucide-zoom-in' : 'i-lucide-minimize'"
                slate
                outline
                class="!min-h-11 !rounded-xl"
                @click="fitToView = !fitToView"
              />
              <Button
                :aria-label="
                  t(`${UX}.${fullView ? 'BACK_EDITOR' : 'FULL_VIEW'}`)
                "
                :title="t(`${UX}.${fullView ? 'BACK_EDITOR' : 'FULL_VIEW'}`)"
                :icon="fullView ? 'i-lucide-arrow-left' : 'i-lucide-maximize'"
                slate
                :variant="fullView ? 'solid' : 'ghost'"
                class="!min-h-11 !rounded-xl"
                :disabled="!isReady || showWelcome"
                :aria-pressed="fullView"
                @click="toggleFullView"
              >
                <span :class="fullView ? 'inline' : 'hidden xl:inline'">
                  {{ t(`${UX}.${fullView ? 'BACK_EDITOR' : 'FULL_VIEW'}`) }}
                </span>
              </Button>
            </div>
          </div>
          <div
            v-if="showPersonalize && !fullView"
            class="shrink-0 border-b border-n-weak bg-n-solid-1 p-4"
          >
            <PlaceholderChips
              :placeholders="placeholders"
              @insert="insertPlaceholder"
            />
          </div>
          <WelcomeChooser
            v-if="showWelcome"
            class="min-h-0 flex-1 overflow-y-auto"
            @choose-ai="chooseAi"
            @choose-template="openGallery"
            @start-blank="startBlank"
          />
          <div
            v-if="showUndo && !showWelcome && !fullView"
            role="status"
            class="flex shrink-0 flex-wrap items-center justify-between gap-2 border-b border-n-weak bg-n-teal-2 px-4 py-1.5 text-sm text-n-teal-12"
            data-test="ai-adjust-undo"
          >
            <span class="flex items-center gap-2">
              <span class="i-lucide-check size-4 shrink-0" />
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.AI.ADJUST_PREVIEW.APPLIED') }}
            </span>
            <span class="flex items-center gap-1">
              <Button
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.AI.ADJUST_PREVIEW.UNDO')"
                icon="i-lucide-undo-2"
                slate
                outline
                class="!min-h-11 !rounded-xl"
                data-test="ai-adjust-undo-button"
                @click="undoAdjustment"
              />
              <Button
                :aria-label="
                  t('CAMPAIGN.EMAIL_CAMPAIGN.AI.ADJUST_PREVIEW.DISMISS')
                "
                icon="i-lucide-x"
                slate
                ghost
                class="!size-11"
                @click="showUndo = false"
              />
            </span>
          </div>
          <div v-if="!showWelcome" ref="canvasHost" class="min-h-0 flex-1">
            <GrapesEditor
              :mjml="campaign.body_mjml || ''"
              :full-view="fullView"
              :fit-to-view="fitToView"
              class="min-h-0 [&_.gjs-pn-devices-c]:hidden"
              @scroll="onCanvasScroll"
            />
          </div>
        </div>
        <aside
          v-show="!fullView"
          class="min-h-0 w-full flex-1 shrink-0 overflow-y-auto border-s border-n-weak bg-n-solid-1 xl:w-[17rem] xl:flex-none"
          :class="activePanel === 'properties' ? 'block' : 'hidden xl:block'"
        >
          <BrandEmailIdentityPanel
            v-if="isReady && brandKitsEnabled && campaign"
            :identity="campaign.brand_identity || {}"
            :warnings="campaign.ai_quality_warnings || []"
            :can-manage="canManage"
            @change="openAiDialog"
          />
          <AiBlockActions v-if="isReady && canManage" class="p-3" />
          <PropertiesPanel v-if="isReady" />
          <p v-else class="m-0 p-6 text-sm leading-6 text-n-slate-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.EMPTY') }}
          </p>
        </aside>
      </div>
      <Dialog
        ref="previewDialog"
        :title="t(`${UX}.PREVIEW`)"
        width="3xl"
        :show-confirm-button="false"
        overflow-y-auto
      >
        <div
          class="mx-auto w-full"
          :class="device === 'mobile' ? 'max-w-[22rem]' : 'max-w-[37.5rem]'"
        >
          <iframe
            :srcdoc="previewHtml"
            sandbox=""
            referrerpolicy="no-referrer"
            :title="t(`${UX}.PREVIEW`)"
            class="h-[60vh] w-full rounded-xl border border-n-weak bg-white"
          />
        </div>
      </Dialog>
    </template>
    <div
      v-if="senderOpen"
      class="fixed inset-0 z-40 flex items-center justify-center bg-n-alpha-black2 p-5"
      @click.self="senderOpen = false"
    >
      <div class="relative h-[80vh] w-full max-w-xl">
        <EmailCampaignDialog
          :campaign="campaign"
          @saved="onSenderSaved"
          @close="senderOpen = false"
        />
      </div>
    </div>
    <EmailCampaignDetailsDialog
      v-if="detailsOpen && campaign"
      :campaign="campaign"
      :initial-problem="problemsOnly"
      @close="detailsOpen = false"
      @review="
        detailsOpen = false;
        openReview();
      "
      @updated="store.dispatch('emailCampaigns/getOne', campaignId)"
    />
    <AiComposerDialog
      v-if="showAiDialog"
      :campaign-id="campaignId"
      :placeholders="placeholders"
      :can-adjust="aiCanAdjust"
      :read-current-mjml="getMjml"
      :initial-brand="initialBrand"
      @generation-started="onGenerationStarted"
      @close="showAiDialog = false"
    />
    <AiGeneratingDialog
      v-if="showGeneratingDialog"
      :campaign-id="campaignId"
      :mode="generationMode"
      @ready="onGenerationReady"
      @close="showGeneratingDialog = false"
    />
    <AiAdjustPreview
      v-if="adjustPreview"
      :before-html="adjustPreview.beforeHtml"
      :after-html="adjustPreview.afterHtml"
      :summary="adjustPreview.summary"
      :site-request="adjustPreview.siteRequest"
      @apply="applyAdjustment"
      @discard="discardAdjustment"
    />
  </section>
</template>
