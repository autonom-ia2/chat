<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  reactive,
  ref,
  useId,
  watch,
} from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmCardRelationshipPanel from './CrmCardRelationshipPanel.vue';
import CrmOpportunityForm from './CrmOpportunityForm.vue';
import { useAlert } from 'dashboard/composables';
import { useRelationshipPermissions } from 'dashboard/composables/useRelationshipPermissions';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import ContactAPI from 'dashboard/api/contacts';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';
import CrmCardAiPanel from './CrmCardAiPanel.vue';
import CrmCardSummaryPanel from './CrmCardSummaryPanel.vue';
import CrmCardAutoFollowupStatus from './CrmCardAutoFollowupStatus.vue';
import WhatsappApiMessageTemplatesAPI from 'dashboard/api/whatsappApiMessageTemplates';
import MetaConversionsAPI from 'dashboard/api/metaConversions';
import { useCrmOrigin } from '../composables/useCrmOrigin';
import CrmCardPill from './CrmCardPill.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, default: 'create' },
  card: { type: Object, default: null },
  // Tab to land on when the drawer opens (e.g. 'followups' from the calendar
  // quick-add). Null → default 'summary'.
  initialTab: { type: String, default: null },
  initialContact: { type: Object, default: null },
  stages: { type: Array, default: () => [] },
  pipelines: { type: Array, default: () => [] },
  pipelineId: { type: [String, Number], default: '' },
  agents: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  followUps: { type: Array, default: () => [] },
  canManageCards: { type: Boolean, default: false },
  canManageAi: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
  isLoadingDetails: { type: Boolean, default: false },
  isArchiving: { type: Boolean, default: false },
  isFetchingFollowUps: { type: Boolean, default: false },
  isSavingFollowUp: { type: Boolean, default: false },
  meetingsEnabled: { type: Boolean, default: false },
});

const emit = defineEmits([
  'close',
  'save',
  'archive',
  'closeDeal',
  'createFollowUp',
  'completeFollowUp',
  'cancelFollowUp',
  'refreshCard',
  'scheduleMeeting',
]);

const archiveCard = () => {
  if (props.canManageCards) emit('archive');
};
const completeFollowUp = followUp => {
  if (props.canManageCards) emit('completeFollowUp', followUp);
};
const cancelFollowUp = followUp => {
  if (props.canManageCards) emit('cancelFollowUp', followUp);
};
const scheduleMeeting = () => {
  if (props.canManageCards) emit('scheduleMeeting', { cardId: props.card.id });
};

const { t, locale } = useI18n();
const { originFromCampaigns, humanizedOriginLabel, formatOriginTitle } =
  useCrmOrigin();

const store = useStore();
const { canManageRelationshipRecords } = useRelationshipPermissions();
const isCrmAiEnabled = computed(
  () =>
    store.getters['globalConfig/get']?.crmAiEnabled === true ||
    window.globalConfig?.CRM_AI_ENABLED === 'true'
);
const route = useRoute();
const router = useRouter();

const form = reactive({
  title: '',
  description: '',
  stageId: '',
  valueAmount: '',
  currency: 'BRL',
  priority: 'medium',
  score: 0,
  expectedCloseAt: '',
  ownerId: '',
  inboxId: '',
  contactId: '',
});
// Editable contact fields shown in the Contact tab. Native columns (name/email/
// phone) + Chatwoot-standard additional_attributes (company/city/country) +
// non-native custom_attributes (address/job title). Persisted via the existing
// contacts update API, which merges additional/custom attributes server-side.
const contactForm = reactive({
  name: '',
  email: '',
  phoneNumber: '',
  company: '',
  jobTitle: '',
  address: '',
  city: '',
  country: '',
});
const formSnapshot = ref('');
const contactSnapshot = ref('');
const contactEditId = ref(null);
const isEditingContact = ref(false);
const isSavingContact = ref(false);
const contactError = ref('');
const relationshipPanel = ref(null);
const creationForm = ref(null);
const companyAction = computed(() => relationshipPanel.value?.companyAction);
const relationshipLinking = computed(
  () => relationshipPanel.value?.linking === true
);
const discardDialog = ref(null);
const discardOpen = ref(false);
const discardDescription = ref('');
let discardAction = null;
const relationshipLabel = key => t(`CRM_KANBAN.RELATIONSHIP.${key}`);
const followUpForm = reactive({
  title: '',
  dueAt: '',
  automationMode: 'reminder_only',
  description: '',
  messageBody: '',
  whatsappApiTemplateId: '',
  nativeTemplateKey: '',
  templateName: '',
  templateLanguage: 'pt_BR',
  templateNamespace: '',
});
const followUpDraftSnapshot = ref('');
const followUpDraftDirty = computed(
  () => JSON.stringify({ ...followUpForm }) !== followUpDraftSnapshot.value
);
const newFollowUpOpen = ref(false);
const followUpMessagingWindow = ref(null);
const isLoadingMessagingWindow = ref(false);
const whatsappApiTemplates = ref([]);
const isLoadingWhatsappTemplates = ref(false);

const activeTab = ref('summary');
const additionalDetailsOpen = ref(false);
const tabButtons = ref([]);
const drawerElement = ref(null);
const drawerId = `crm-card-drawer-${useId()}`;
let previousActiveElement = null;

const isEditing = computed(() => props.mode === 'edit');
const headerCompanyName = computed(() =>
  String(props.card?.company?.name || '').trim()
);
const headerContactName = computed(() =>
  String(
    props.card?.contact?.name || props.card?.contact?.phone_number || ''
  ).trim()
);
const headerBusinessName = computed(() =>
  String(form.title || props.card?.title || '').trim()
);
const headerHasDistinctContact = computed(
  () =>
    Boolean(headerCompanyName.value) &&
    Boolean(headerContactName.value) &&
    headerCompanyName.value !== headerContactName.value
);
const headerHasDistinctBusiness = computed(() => {
  const title = headerBusinessName.value;
  return Boolean(
    title && ![headerCompanyName.value, headerContactName.value].includes(title)
  );
});
const panelTitle = computed(() => {
  if (!isEditing.value) return t('CRM_KANBAN.DRAWER.CREATE_TITLE');
  return (
    headerCompanyName.value ||
    headerContactName.value ||
    headerBusinessName.value ||
    relationshipLabel('OPPORTUNITY_DETAILS')
  );
});
const panelSubtitle = computed(() => {
  if (!isEditing.value) return t('CRM_KANBAN.DRAWER.CREATE_SUBTITLE');
  const context = [];
  if (headerHasDistinctContact.value) context.push(headerContactName.value);
  if (headerHasDistinctBusiness.value) {
    context.push(
      `${t('CRM_KANBAN.CARD.BUSINESS_LABEL')} ${headerBusinessName.value}`
    );
  }
  return context.join(' · ') || t('CRM_KANBAN.DRAWER.EDIT_SUBTITLE');
});

const priorityOptions = computed(() => [
  { value: 'low', label: t('CRM_KANBAN.PRIORITY.LOW') },
  { value: 'medium', label: t('CRM_KANBAN.PRIORITY.MEDIUM') },
  { value: 'high', label: t('CRM_KANBAN.PRIORITY.HIGH') },
  { value: 'urgent', label: t('CRM_KANBAN.PRIORITY.URGENT') },
]);
const withEmptyChoice = (label, options) => [{ value: '', label }, ...options];
const detailTabs = computed(() => [
  { id: 'summary', label: t('CRM_KANBAN.DRAWER.TAB_SUMMARY') },
  { id: 'contact', label: relationshipLabel('TAB') },
  { id: 'conversations', label: t('CRM_KANBAN.DRAWER.TAB_CONVERSATIONS') },
  { id: 'followups', label: t('CRM_KANBAN.DRAWER.TAB_RETURNS') },
  { id: 'timeline', label: t('CRM_KANBAN.DRAWER.TAB_HISTORY') },
]);
const tabId = tab => `${drawerId}-tab-${tab}`;
const detailPanelId = tab => `${drawerId}-panel-${tab}`;
const drawerFocusableSelector = [
  'button:not([disabled])',
  '[href]',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(',');
const rememberAndFocusDrawer = async show => {
  if (show) {
    previousActiveElement =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    await nextTick();
    if (!props.show) return;
    drawerElement.value?.focus();
    return;
  }

  if (previousActiveElement?.isConnected) previousActiveElement.focus();
  previousActiveElement = null;
};
const trapDrawerFocus = event => {
  if (event.key !== 'Tab' || document.querySelector('dialog[open]')) return;

  const focusable = Array.from(
    drawerElement.value?.querySelectorAll(drawerFocusableSelector) || []
  ).filter(element => element.getClientRects().length > 0);
  if (!focusable.length) {
    event.preventDefault();
    drawerElement.value?.focus();
    return;
  }

  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (
    event.shiftKey &&
    (document.activeElement === first ||
      document.activeElement === drawerElement.value)
  ) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
};
const linkedConversationDisplayId = computed(
  () => props.card?.conversation?.display_id || ''
);
const originPill = computed(() => originFromCampaigns(props.card?.campaigns));
const hasLinkedContext = computed(
  () =>
    isEditing.value &&
    (props.card?.contact ||
      props.card?.inbox ||
      linkedConversationDisplayId.value)
);
const linkedConversations = computed(() => {
  if (props.card?.linked_conversations?.length) {
    return props.card.linked_conversations;
  }
  if (props.card?.conversation) return [props.card.conversation];
  return [];
});
const activities = computed(() => props.card?.activities || []);
const linkedConversationId = computed(
  () => props.card?.conversation_id || props.card?.conversation?.id || ''
);
const canSnoozeConversation = computed(() =>
  Boolean(linkedConversationId.value)
);
const canAutoSendMessage = computed(() => Boolean(linkedConversationId.value));
const linkedInboxId = computed(
  () => props.card?.inbox_id || props.card?.inbox?.id || ''
);
const isWhatsappApiInbox = computed(
  () => followUpMessagingWindow.value?.whatsapp_api_inbox === true
);
const isWhatsappNativeInbox = computed(
  () => followUpMessagingWindow.value?.whatsapp_native_inbox === true
);
const requiresTemplateNow = computed(
  () => followUpMessagingWindow.value?.requires_template === true
);
const whatsappApiTemplateOptions = computed(() =>
  whatsappApiTemplates.value.map(template => ({
    value: template.id,
    label: template.name,
  }))
);
// Official WhatsApp inboxes reuse the native template engine: the already
// imported/approved templates for that inbox's number, sourced from the
// inboxes store getter (channel.message_templates). The custom path stays for
// Channel::Api campaign inboxes.
const nativeWhatsappTemplates = computed(() => {
  if (!isWhatsappNativeInbox.value || !linkedInboxId.value) return [];
  return (
    store.getters['inboxes/getFilteredWhatsAppTemplates'](
      linkedInboxId.value
    ) || []
  );
});
const nativeWhatsappTemplateOptions = computed(() =>
  nativeWhatsappTemplates.value.map(template => ({
    value: `${template.name}::${template.language}`,
    label: `${template.name} (${template.language})`,
  }))
);
const whatsappApiTemplateChoices = computed(() =>
  withEmptyChoice(
    t('CRM_KANBAN.DRAWER.FOLLOW_UP_TEMPLATE_PLACEHOLDER'),
    whatsappApiTemplateOptions.value
  )
);
const nativeWhatsappTemplateChoices = computed(() =>
  withEmptyChoice(
    t('CRM_KANBAN.DRAWER.FOLLOW_UP_TEMPLATE_PLACEHOLDER'),
    nativeWhatsappTemplateOptions.value
  )
);
const followUpModeChoices = computed(() => [
  {
    value: 'reminder_only',
    label: t('CRM_KANBAN.FOLLOW_UP_MODE.REMINDER_ONLY'),
  },
  {
    value: 'snooze_conversation',
    label: t('CRM_KANBAN.FOLLOW_UP_MODE.SNOOZE_CONVERSATION'),
    disabled: !canSnoozeConversation.value,
  },
  {
    value: 'auto_send_message',
    label: t('CRM_KANBAN.FOLLOW_UP_MODE.AUTO_SEND_MESSAGE'),
    disabled: !canAutoSendMessage.value,
  },
]);
const activeFollowUps = computed(() =>
  props.followUps.filter(
    followUp => followUp.status === 'pending' || followUp.status === 'overdue'
  )
);
// Done/canceled — shown collapsed at the bottom of the Follow-ups tab.
const completedFollowUps = computed(() =>
  props.followUps.filter(
    followUp => followUp.status !== 'pending' && followUp.status !== 'overdue'
  )
);
// --- Deal close (Win / Lose / Reopen) ---------------------------------------
const cardStatus = computed(() => props.card?.status || 'open');
const isDealOpen = computed(() => cardStatus.value === 'open');
const statusLabel = computed(() =>
  t(`CRM_KANBAN.DRAWER.STATUS_${String(cardStatus.value).toUpperCase()}`)
);
const statusPillClass = computed(
  () =>
    ({
      won: 'bg-n-teal-3 text-n-teal-11',
      lost: 'bg-n-ruby-3 text-n-ruby-11',
      archived: 'bg-n-slate-4 text-n-slate-10',
    })[cardStatus.value] || 'bg-n-blue-3 text-n-blue-11'
);

const conversationStatusLabel = status => {
  switch (String(status || '').toLowerCase()) {
    case 'open':
      return t('CRM_KANBAN.DRAWER.CONVERSATION_STATUS_OPEN');
    case 'pending':
      return t('CRM_KANBAN.DRAWER.CONVERSATION_STATUS_PENDING');
    case 'resolved':
      return t('CRM_KANBAN.DRAWER.CONVERSATION_STATUS_RESOLVED');
    case 'snoozed':
      return t('CRM_KANBAN.DRAWER.CONVERSATION_STATUS_SNOOZED');
    default:
      return t('CRM_KANBAN.DRAWER.CONVERSATION_STATUS_UNKNOWN');
  }
};
const aiFilledValue = computed(() => props.card?.ai_value?.source === 'ai');

// CTWA conversion sync-state for the open card (FE-5 badge). Read-only ledger row
// fetched when the drawer opens, reset on close/card change so no stale badge shows.
const cardId = computed(() => props.card?.id || '');
const metaConversion = ref(null);
const metaConversionPill = computed(() => {
  const pills = {
    accepted: {
      class: 'bg-n-teal-3 text-n-teal-11',
      label: 'CRM_KANBAN.META_SYNC_STATUS.CARD_SENT',
    },
    pending: {
      class: 'bg-n-amber-3 text-n-amber-11',
      label: 'CRM_KANBAN.META_SYNC_STATUS.LABEL_PENDING',
    },
    error: {
      class: 'bg-n-ruby-3 text-n-ruby-11',
      label: 'CRM_KANBAN.META_SYNC_STATUS.LABEL_ERROR',
    },
  };
  // 'skipped' or no row → no badge, keep the drawer uncluttered.
  return pills[metaConversion.value?.status] || null;
});

const showWinDialog = ref(false);
const showLoseDialog = ref(false);
const winAmount = ref('');
const winCurrency = ref('BRL');
const loseReason = ref('');

const openWinDialog = () => {
  if (!props.canManageCards) return;
  winAmount.value = props.card?.value_cents
    ? Number(props.card.value_cents) / 100
    : '';
  winCurrency.value = props.card?.currency || 'BRL';
  showWinDialog.value = true;
};
const openLoseDialog = () => {
  if (!props.canManageCards) return;
  loseReason.value = props.card?.lost_reason || '';
  showLoseDialog.value = true;
};
const confirmWin = () => {
  if (!props.canManageCards) return;
  const amount = Number(winAmount.value);
  emit('closeDeal', {
    result: 'won',
    value_cents:
      Number.isFinite(amount) && amount > 0
        ? Math.round(amount * 100)
        : undefined,
    currency: winCurrency.value || 'BRL',
  });
  showWinDialog.value = false;
};
const confirmLose = () => {
  if (!props.canManageCards) return;
  emit('closeDeal', {
    result: 'lost',
    lost_reason: loseReason.value || undefined,
  });
  showLoseDialog.value = false;
};
const reopenDeal = () => {
  if (props.canManageCards) emit('closeDeal', { result: 'reopen' });
};

const hydrateContactForm = card => {
  const contact = card?.contact || {};
  contactEditId.value = contact.id || null;
  const add = contact.additional_attributes || {};
  const custom = contact.custom_attributes || {};
  contactForm.name = contact.name || '';
  contactForm.email = contact.email || '';
  contactForm.phoneNumber = contact.phone_number || '';
  contactForm.company = add.company_name || '';
  contactForm.city = add.city || '';
  contactForm.country = add.country || '';
  contactForm.address = custom.address || '';
  contactForm.jobTitle = custom.job_title || '';
  contactSnapshot.value = JSON.stringify({ ...contactForm });
};

const resetForm = () => {
  const card = props.card || {};
  form.title = card.title || '';
  form.description = card.description || '';
  form.stageId = card.stage_id || props.stages[0]?.id || '';
  form.valueAmount = card.value_cents ? Number(card.value_cents) / 100 : '';
  form.currency = card.currency || 'BRL';
  form.priority = card.priority || 'medium';
  form.score = card.score || 0;
  form.expectedCloseAt = card.expected_close_at
    ? card.expected_close_at.slice(0, 10)
    : '';
  additionalDetailsOpen.value = Boolean(form.score || form.expectedCloseAt);
  form.ownerId = card.owner_id || '';
  form.inboxId = card.inbox_id || '';
  form.contactId = card.contact_id || '';
  hydrateContactForm(card);
  activeTab.value = props.initialTab || 'summary';
  newFollowUpOpen.value = false;
  followUpForm.title = t('CRM_KANBAN.DRAWER.FOLLOW_UP_DEFAULT_TITLE');
  followUpForm.dueAt = '';
  followUpForm.automationMode = 'reminder_only';
  followUpForm.description = '';
  followUpForm.messageBody = '';
  followUpForm.whatsappApiTemplateId = '';
  followUpForm.nativeTemplateKey = '';
  followUpForm.templateName = '';
  followUpForm.templateLanguage = 'pt_BR';
  followUpForm.templateNamespace = '';
  followUpDraftSnapshot.value = JSON.stringify({ ...followUpForm });
  followUpMessagingWindow.value = null;
  whatsappApiTemplates.value = [];
  formSnapshot.value = JSON.stringify({ ...form });
};

const loadFollowUpMessagingWindow = async () => {
  if (!linkedConversationId.value) {
    followUpMessagingWindow.value = null;
    return;
  }

  isLoadingMessagingWindow.value = true;
  try {
    const dueAtIso = followUpForm.dueAt
      ? new Date(followUpForm.dueAt).toISOString()
      : undefined;
    const response = await CrmKanbanAPI.getFollowUpMessagingWindow(
      linkedConversationId.value,
      dueAtIso
    );
    followUpMessagingWindow.value = response.data;
  } catch {
    followUpMessagingWindow.value = null;
  } finally {
    isLoadingMessagingWindow.value = false;
  }
};

const loadWhatsappApiTemplates = async () => {
  if (!linkedInboxId.value) {
    whatsappApiTemplates.value = [];
    return;
  }

  isLoadingWhatsappTemplates.value = true;
  try {
    const response = await WhatsappApiMessageTemplatesAPI.get(
      linkedInboxId.value
    );
    whatsappApiTemplates.value = response.data.payload || [];
  } catch {
    whatsappApiTemplates.value = [];
  } finally {
    isLoadingWhatsappTemplates.value = false;
  }
};

// Maps the chosen native template (name::language) back onto the metadata
// fields the backend MessageSender native path consumes (template_params).
const onNativeTemplateSelected = () => {
  const selected = nativeWhatsappTemplates.value.find(
    template =>
      `${template.name}::${template.language}` ===
      followUpForm.nativeTemplateKey
  );
  if (!selected) {
    followUpForm.templateName = '';
    followUpForm.templateLanguage = '';
    followUpForm.templateNamespace = '';
    return;
  }
  followUpForm.templateName = selected.name;
  followUpForm.templateLanguage = selected.language || 'pt_BR';
  followUpForm.templateNamespace = selected.namespace || '';
};

// Reset when the drawer opens or the selected card object changes. We intentionally
// drop props.stages from the deps: realtime card events and the board poll rebuild
// board.stages into a new array reference on every update, and a busy board would
// re-run resetForm mid-edit, wiping the title/contact/follow-up fields being typed.
// props.card is kept because the parent only rebinds selectedCard on explicit flows
// (open, then shallow->detailed hydration) — never from realtime — so it does not
// churn and its change must still re-hydrate the form. Stage choice options bind
// to props.stages directly, so they stay live without a reset.
watch(
  () => [props.show, props.card],
  (_next, previous) => {
    if (!props.show) return;
    const sameCard = previous?.[0] && props.card?.id === previous[1]?.id;
    const tab = activeTab.value;
    if (
      sameCard &&
      (isEditingContact.value ||
        JSON.stringify({ ...form }) !== formSnapshot.value ||
        followUpDraftDirty.value)
    ) {
      if (!isEditingContact.value) hydrateContactForm(props.card);
      return;
    }
    resetForm();
    if (sameCard) activeTab.value = tab;
    else isEditingContact.value = false;
  },
  { immediate: true }
);
watch(() => props.show, rememberAndFocusDrawer, { immediate: true });

onBeforeUnmount(() => {
  if (props.show && previousActiveElement?.isConnected)
    previousActiveElement.focus();
});

// Fetch the card's Meta conversion row whenever the drawer opens or switches card.
// Reset first so a stale badge never lingers; failures simply hide the badge. The
// requestedId guard drops slow responses that arrive after the card changed, and
// only the row matching THIS card is accepted (never another card's conversion).
const fetchMetaConversion = async () => {
  metaConversion.value = null;
  if (!props.show || !cardId.value) return;
  const requestedId = cardId.value;
  try {
    const { data } = await MetaConversionsAPI.getForCards([requestedId]);
    if (requestedId !== cardId.value) return;
    const payload = data?.payload || [];
    metaConversion.value =
      payload.find(row => Number(row.card_id) === Number(requestedId)) || null;
  } catch {
    if (requestedId === cardId.value) metaConversion.value = null;
  }
};
watch(() => [props.show, cardId.value], fetchMetaConversion, {
  immediate: true,
});

// Re-evaluate the messaging window whenever auto-send is selected OR the chosen
// due date changes: the window must be computed at dueAt, not at Time.current,
// so the template UI shows when the send will fall outside the 24h window.
const refreshMessagingWindow = async () => {
  if (
    followUpForm.automationMode !== 'auto_send_message' ||
    !linkedConversationId.value
  ) {
    return;
  }
  await loadFollowUpMessagingWindow();
  if (
    isWhatsappApiInbox.value &&
    followUpMessagingWindow.value?.requires_template
  ) {
    await loadWhatsappApiTemplates();
  }
};

watch(() => followUpForm.automationMode, refreshMessagingWindow);
watch(() => followUpForm.dueAt, refreshMessagingWindow);

const buildPayload = () => {
  const payload = {
    title: form.title.trim(),
    description: form.description.trim(),
    value_cents: form.valueAmount
      ? Math.round(Number(form.valueAmount) * 100)
      : 0,
    currency: form.currency || 'BRL',
    priority: form.priority,
    score: Number(form.score || 0),
    expected_close_at: form.expectedCloseAt || null,
  };

  if (!isEditing.value) {
    payload.stage_id = form.stageId;
    payload.pipeline_id = props.pipelineId;
    if (props.canManageCards && form.ownerId) payload.owner_id = form.ownerId;
    if (form.inboxId) payload.inbox_id = form.inboxId;
    if (form.contactId) payload.contact_id = form.contactId;
  }

  return payload;
};

const contactDirty = computed(
  () => JSON.stringify({ ...contactForm }) !== contactSnapshot.value
);

// Send ONLY the keys the drawer manages — the server shallow-merges additional/
// custom attributes, so every other key (incl. nested social_profiles) is preserved
// untouched. Avoids re-writing stale values for fields we don't edit here.
const buildContactPayload = () => {
  const initial = JSON.parse(contactSnapshot.value);
  const changed = entries =>
    Object.fromEntries(
      entries
        .filter(
          ([, field]) => contactForm[field].trim() !== initial[field].trim()
        )
        .map(([key, field]) => [key, contactForm[field].trim()])
    );
  const custom = changed([
    ['address', 'address'],
    ['job_title', 'jobTitle'],
  ]);
  const additional = changed([
    ['city', 'city'],
    ['country', 'country'],
  ]);
  return {
    ...changed([
      ['name', 'name'],
      ['email', 'email'],
      ['phone_number', 'phoneNumber'],
    ]),
    ...(Object.keys(additional).length
      ? { additional_attributes: additional }
      : {}),
    ...(Object.keys(custom).length ? { custom_attributes: custom } : {}),
  };
};

const persistContactIfChanged = async () => {
  if (!isEditing.value || !contactEditId.value || !contactDirty.value) return;
  await ContactAPI.update(contactEditId.value, buildContactPayload());
};

const relationshipDiscardHelp = () =>
  isEditing.value
    ? relationshipLabel('DISCARD_HELP')
    : t('CRM_KANBAN.OPPORTUNITY.DISCARD_HELP');
const discardRelationship = () => {
  isEditingContact.value = false;
  contactError.value = '';
  if (contactSnapshot.value)
    Object.assign(contactForm, JSON.parse(contactSnapshot.value));
  relationshipPanel.value?.reset();
};
// `leaving`: the action takes the user out of the drawer (close, open the
// conversation). Only then do the commercial and follow-up drafts — which
// survive tab switches — need the discard prompt.
const guardRelationship = (action, { leaving = false } = {}) => {
  if (
    props.isSaving ||
    creationForm.value?.sending ||
    isSavingContact.value ||
    relationshipPanel.value?.saving
  )
    return;
  const relationshipDirty =
    (isEditingContact.value && contactDirty.value) ||
    relationshipPanel.value?.dirty ||
    (!isEditing.value && creationForm.value?.dirty);
  const draftDirty =
    leaving &&
    ((isEditing.value && JSON.stringify({ ...form }) !== formSnapshot.value) ||
      followUpDraftDirty.value);
  if (relationshipDirty || draftDirty) {
    discardAction = action;
    discardDescription.value = relationshipDirty
      ? relationshipDiscardHelp()
      : t('CRM_KANBAN.DRAWER.DISCARD_DRAFT_HELP');
    discardOpen.value = true;
    discardDialog.value?.open();
    return;
  }
  discardRelationship();
  action();
};
const closeDrawer = () =>
  guardRelationship(() => emit('close'), { leaving: true });
const moveTabFocus = event => {
  const keys = ['ArrowLeft', 'ArrowRight', 'Home', 'End'];
  if (!keys.includes(event.key)) return;

  event.preventDefault();
  const currentIndex = detailTabs.value.findIndex(
    tab => tab.id === activeTab.value
  );
  if (currentIndex < 0) return;

  const isRtl = event.currentTarget.closest('[dir="rtl"]');
  const step = event.key === 'ArrowRight' ? 1 : -1;
  let nextIndex =
    (currentIndex + (isRtl ? -step : step) + detailTabs.value.length) %
    detailTabs.value.length;
  if (event.key === 'Home') nextIndex = 0;
  if (event.key === 'End') nextIndex = detailTabs.value.length - 1;

  const nextTab = detailTabs.value[nextIndex];
  guardRelationship(() => {
    activeTab.value = nextTab.id;
    nextTick(() => tabButtons.value[nextIndex]?.focus());
  });
};
const footerCancelLabel = computed(() => {
  if (isEditingContact.value || companyAction.value)
    return relationshipLabel('CANCEL');
  return isEditing.value && activeTab.value !== 'summary'
    ? relationshipLabel('CLOSE')
    : t('CRM_KANBAN.DRAWER.CANCEL');
});
const confirmDiscard = () => {
  const action = discardAction;
  discardAction = null;
  discardRelationship();
  discardDialog.value?.close();
  action?.();
};
const startContactEdit = contact => {
  if (!canManageRelationshipRecords.value) return;
  hydrateContactForm({ contact });
  isEditingContact.value = true;
  contactError.value = '';
};
const saveContact = async () => {
  if (!canManageRelationshipRecords.value) return;
  if (isSavingContact.value || !contactForm.name.trim()) return;
  const cardIdAtSave = props.card?.id;
  isSavingContact.value = true;
  contactError.value = '';
  try {
    await persistContactIfChanged();
    if (props.card?.id !== cardIdAtSave) return;
    contactSnapshot.value = JSON.stringify({ ...contactForm });
    isEditingContact.value = false;
    await relationshipPanel.value?.reload();
    emit('refreshCard');
    useAlert(relationshipLabel('SAVED'));
  } catch {
    contactError.value = relationshipLabel('SAVE_ERROR');
  } finally {
    isSavingContact.value = false;
  }
};
const onSubmit = () => {
  if (!props.canManageCards) return;
  if (!form.title.trim() || (!isEditing.value && !form.stageId)) return;
  emit('save', buildPayload());
};

const buildAutoSendMetadata = () => {
  const metadata = {
    message_body: followUpForm.messageBody.trim(),
  };

  if (isWhatsappApiInbox.value && followUpForm.whatsappApiTemplateId) {
    metadata.whatsapp_api_message_template_id = Number(
      followUpForm.whatsappApiTemplateId
    );
  } else if (followUpForm.templateName.trim()) {
    metadata.template_name = followUpForm.templateName.trim();
    metadata.template_language =
      followUpForm.templateLanguage.trim() || 'pt_BR';
    if (followUpForm.templateNamespace.trim()) {
      metadata.template_namespace = followUpForm.templateNamespace.trim();
    }
  }

  return metadata;
};

const hasAutoSendTemplateFallback = () => {
  if (isWhatsappApiInbox.value) {
    return Boolean(followUpForm.whatsappApiTemplateId);
  }

  return (
    Boolean(followUpForm.templateName.trim()) &&
    Boolean(followUpForm.templateLanguage.trim())
  );
};

const resetFollowUpForm = () => {
  followUpForm.title = t('CRM_KANBAN.DRAWER.FOLLOW_UP_DEFAULT_TITLE');
  followUpForm.dueAt = '';
  followUpForm.automationMode = 'reminder_only';
  followUpForm.description = '';
  followUpForm.messageBody = '';
  followUpForm.whatsappApiTemplateId = '';
  followUpForm.nativeTemplateKey = '';
  followUpForm.templateName = '';
  followUpForm.templateLanguage = 'pt_BR';
  followUpForm.templateNamespace = '';
  newFollowUpOpen.value = false;
  followUpDraftSnapshot.value = JSON.stringify({ ...followUpForm });
};

defineExpose({ resetFollowUpForm, guardNavigation: guardRelationship });

const createFollowUp = () => {
  if (!props.canManageCards) return;
  if (!props.card?.id || !followUpForm.title.trim() || !followUpForm.dueAt) {
    return;
  }

  if (
    followUpForm.automationMode === 'auto_send_message' &&
    !followUpForm.messageBody.trim()
  ) {
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_MESSAGE_BODY_REQUIRED'));
    return;
  }

  if (
    followUpForm.automationMode === 'auto_send_message' &&
    requiresTemplateNow.value &&
    !hasAutoSendTemplateFallback()
  ) {
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_TEMPLATE_REQUIRED'));
    return;
  }

  const payload = {
    card_id: props.card.id,
    conversation_id: linkedConversationId.value || null,
    title: followUpForm.title.trim(),
    description: followUpForm.description.trim(),
    follow_up_type: 'task',
    automation_mode: followUpForm.automationMode,
    due_at: new Date(followUpForm.dueAt).toISOString(),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
  };

  if (followUpForm.automationMode === 'auto_send_message') {
    payload.metadata = buildAutoSendMetadata();
  }

  emit('createFollowUp', payload);
};

const openConversationByDisplayId = displayId => {
  if (!displayId) return;
  guardRelationship(
    () =>
      router.push({
        name: 'inbox_conversation',
        params: {
          accountId: route.params.accountId,
          conversation_id: displayId,
        },
      }),
    { leaving: true }
  );
};

const openConversation = () => {
  openConversationByDisplayId(linkedConversationDisplayId.value);
};

const formatDate = value => {
  if (!value) return t('CRM_KANBAN.DRAWER.EMPTY_VALUE');
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
};

// Per-event-type metadata: i18n label key, lucide icon and a colour tone.
// Keyed on the actual backend Crm::Activity#event_type values.
const ACTIVITY_META = {
  create: { key: 'ACTIVITY_CREATE', icon: 'i-lucide-plus', tone: 'positive' },
  update: { key: 'ACTIVITY_UPDATE', icon: 'i-lucide-pencil', tone: 'neutral' },
  move: { key: 'ACTIVITY_MOVE', icon: 'i-lucide-arrow-right', tone: 'info' },
  won: { key: 'ACTIVITY_WON', icon: 'i-lucide-trophy', tone: 'positive' },
  lost: { key: 'ACTIVITY_LOST', icon: 'i-lucide-circle-x', tone: 'negative' },
  reopen: {
    key: 'ACTIVITY_REOPEN',
    icon: 'i-lucide-rotate-ccw',
    tone: 'neutral',
  },
  archive: { key: 'ACTIVITY_ARCHIVE', icon: 'i-lucide-archive', tone: 'muted' },
  conversation_linked: {
    key: 'ACTIVITY_LINK_CONVERSATION',
    icon: 'i-lucide-link',
    tone: 'info',
  },
  conversation_unlinked: {
    key: 'ACTIVITY_UNLINK_CONVERSATION',
    icon: 'i-lucide-unlink',
    tone: 'muted',
  },
  contact_linked: {
    key: 'ACTIVITY_LINK_CONTACT',
    icon: 'i-lucide-user-plus',
    tone: 'info',
  },
  contact_unlinked: {
    key: 'ACTIVITY_UNLINK_CONTACT',
    icon: 'i-lucide-user-minus',
    tone: 'muted',
  },
  conversation_sync: {
    key: 'ACTIVITY_CONVERSATION_SYNC',
    icon: 'i-lucide-refresh-cw',
    tone: 'neutral',
  },
  conversation_dedup_reuse: {
    key: 'ACTIVITY_CONVERSATION_DEDUP_REUSE',
    icon: 'i-lucide-layers',
    tone: 'neutral',
  },
  follow_up_created: {
    key: 'ACTIVITY_FOLLOW_UP_CREATED',
    icon: 'i-lucide-bell-plus',
    tone: 'info',
  },
  follow_up_updated: {
    key: 'ACTIVITY_FOLLOW_UP_UPDATED',
    icon: 'i-lucide-bell',
    tone: 'neutral',
  },
  follow_up_completed: {
    key: 'ACTIVITY_FOLLOW_UP_COMPLETED',
    icon: 'i-lucide-check',
    tone: 'positive',
  },
  follow_up_canceled: {
    key: 'ACTIVITY_FOLLOW_UP_CANCELED',
    icon: 'i-lucide-bell-off',
    tone: 'muted',
  },
  follow_up_overdue: {
    key: 'ACTIVITY_FOLLOW_UP_OVERDUE',
    icon: 'i-lucide-alarm-clock',
    tone: 'negative',
  },
  follow_up_message_sent: {
    key: 'ACTIVITY_FOLLOW_UP_MESSAGE_SENT',
    icon: 'i-lucide-send',
    tone: 'positive',
  },
  follow_up_message_failed: {
    key: 'ACTIVITY_FOLLOW_UP_DELIVERY_FAILED',
    icon: 'i-lucide-triangle-alert',
    tone: 'negative',
  },
  follow_up_rescheduled: {
    key: 'ACTIVITY_FOLLOW_UP_RESCHEDULED',
    icon: 'i-lucide-calendar-clock',
    tone: 'info',
  },
  meeting_scheduled: {
    key: 'ACTIVITY_MEETING_SCHEDULED',
    icon: 'i-lucide-video',
    tone: 'info',
  },
  meeting_rescheduled: {
    key: 'ACTIVITY_MEETING_RESCHEDULED',
    icon: 'i-lucide-calendar-clock',
    tone: 'info',
  },
  meeting_canceled: {
    key: 'ACTIVITY_MEETING_CANCELED',
    icon: 'i-lucide-calendar-x',
    tone: 'negative',
  },
  meeting_outcome_recorded: {
    key: 'ACTIVITY_MEETING_OUTCOME',
    icon: 'i-lucide-circle-check',
    tone: 'info',
  },
  automation_owner_assigned: {
    key: 'ACTIVITY_AUTOMATION_OWNER_ASSIGNED',
    icon: 'i-lucide-user-check',
    tone: 'info',
  },
  automation_stage_moved: {
    key: 'ACTIVITY_AUTOMATION_STAGE_MOVED',
    icon: 'i-lucide-arrow-right',
    tone: 'info',
  },
  automation_follow_up_created: {
    key: 'ACTIVITY_AUTOMATION_FOLLOW_UP_CREATED',
    icon: 'i-lucide-bell-plus',
    tone: 'info',
  },
  ai_auto_moved: {
    key: 'ACTIVITY_AI_AUTO_MOVED',
    icon: 'i-lucide-sparkles',
    tone: 'info',
  },
  ai_suggested: {
    key: 'ACTIVITY_AI_SUGGESTED',
    icon: 'i-lucide-lightbulb',
    tone: 'info',
  },
  ai_dismissed: {
    key: 'ACTIVITY_AI_DISMISSED',
    icon: 'i-lucide-x',
    tone: 'muted',
  },
  ai_handoff: {
    key: 'ACTIVITY_AI_HANDOFF',
    icon: 'i-lucide-user-round-check',
    tone: 'info',
  },
  // Fase D: handoff do agente nativo Autonom.ia. Reusa o mesmo visual do handoff
  // do Kanban; o detalhe nunca expõe motivo bruto do LLM (payload só ids/strategy).
  autonomia_handoff: {
    key: 'ACTIVITY_AUTONOMIA_HANDOFF',
    icon: 'i-lucide-user-round-check',
    tone: 'info',
  },
  ai_followup_planned: {
    key: 'ACTIVITY_AI_FOLLOWUP_PLANNED',
    icon: 'i-lucide-calendar-clock',
    tone: 'info',
  },
  ai_followup_reset: {
    key: 'ACTIVITY_AI_FOLLOWUP_RESET',
    icon: 'i-lucide-rotate-ccw',
    tone: 'neutral',
  },
  ai_followup_stopped: {
    key: 'ACTIVITY_AI_FOLLOWUP_STOPPED',
    icon: 'i-lucide-circle-stop',
    tone: 'muted',
  },
  ai_followup_failed: {
    key: 'ACTIVITY_AI_FOLLOWUP_FAILED',
    icon: 'i-lucide-triangle-alert',
    tone: 'negative',
  },
  ai_followup_sent: {
    key: 'ACTIVITY_AI_FOLLOWUP_SENT',
    icon: 'i-lucide-send',
    tone: 'positive',
  },
  ai_followup_capped: {
    key: 'ACTIVITY_AI_FOLLOWUP_CAPPED',
    icon: 'i-lucide-circle-stop',
    tone: 'muted',
  },
  ai_followup_completed: {
    key: 'ACTIVITY_AI_FOLLOWUP_COMPLETED',
    icon: 'i-lucide-check-circle-2',
    tone: 'positive',
  },
  ai_handoff_invite: {
    key: 'ACTIVITY_AI_HANDOFF_INVITE',
    icon: 'i-lucide-user-round-plus',
    tone: 'info',
  },
  ai_handoff_pickup: {
    key: 'ACTIVITY_AI_HANDOFF_PICKUP',
    icon: 'i-lucide-user-round-check',
    tone: 'positive',
  },
  ai_handoff_escalation: {
    key: 'ACTIVITY_AI_HANDOFF_ESCALATION',
    icon: 'i-lucide-triangle-alert',
    tone: 'negative',
  },
  ai_handoff_renotify: {
    key: 'ACTIVITY_AI_HANDOFF_RENOTIFY',
    icon: 'i-lucide-bell-ring',
    tone: 'neutral',
  },
};

const FALLBACK_META = { icon: 'i-lucide-history', tone: 'neutral' };

const ACTIVITY_TONE_CLASSES = {
  positive: 'bg-n-teal-3 text-n-teal-11',
  negative: 'bg-n-ruby-3 text-n-ruby-11',
  info: 'bg-n-blue-3 text-n-blue-11',
  neutral: 'bg-n-alpha-2 text-n-slate-11',
  muted: 'bg-n-slate-4 text-n-slate-10',
};

// AI work runs as a system actor (actor_type === 'system'). ai_dismissed is a
// human action (actor_type === 'user'), so it is NOT keyed on the 'ai_' prefix.
const activityActor = activity => {
  if (activity.actor_type === 'system') {
    return activity.event_type?.startsWith('ai_')
      ? t('CRM_KANBAN.DRAWER.AI_ACTOR')
      : t('CRM_KANBAN.DRAWER.SYSTEM_ACTOR');
  }
  return activity.actor_name || t('CRM_KANBAN.DRAWER.UNKNOWN_ACTOR');
};

// Returns the readable label for an id-bearing payload key, preferring the
// backend-provided labels{} map and falling back to a "#id" reference.
const activityLabelValue = (activity, key) => {
  const labels = activity.labels || {};
  if (labels[key]) return labels[key];
  const raw = activity.payload?.[key];
  return raw ? `#${raw}` : '';
};

// Provider/LLM errors are diagnostic data, not user-facing copy. Never read
// payload.error or metadata.send_error in the drawer because they can contain
// arbitrary provider text.

// Attempt copy is shown only when the activity carries an explicit counter.
// `touch` is a cadence position, not a retry count, so it must not be used here.
const activityAttemptDetail = activity => {
  const attempts = Number(activity.payload?.attempts);
  if (!Number.isInteger(attempts) || attempts < 1) return '';
  return t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPT', {
    attempt: attempts,
  });
};

const activityRetryAtDetail = activity => {
  const retryAt = activity.payload?.retry_at;
  if (!retryAt || Number.isNaN(new Date(retryAt).getTime())) return '';
  return t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_RETRY_AT', {
    time: relativeTimeFromISO(retryAt, locale.value),
  });
};

const activityRetryDetail = activity => {
  const details = [
    activityAttemptDetail(activity),
    activityRetryAtDetail(activity),
  ];
  if (activity.payload?.final === true) {
    details.push(t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPTS_FINISHED'));
  }
  return details.filter(Boolean).join(' · ');
};

// Builds a friendly one-line description for the activity. Returns '' when the
// event type has no extra detail worth rendering.
const activityDetail = activity => {
  switch (activity.event_type) {
    case 'move':
    case 'ai_auto_moved':
    case 'ai_suggested': {
      const from = activityLabelValue(activity, 'from_stage_id');
      const to = activityLabelValue(activity, 'to_stage_id');
      if (from && to)
        return t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_STAGE_CHANGE', {
          from,
          to,
        });
      if (to) return t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_STAGE_TO', { to });
      return '';
    }
    case 'automation_stage_moved': {
      const to = activityLabelValue(activity, 'target_stage_id');
      return to ? t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_STAGE_TO', { to }) : '';
    }
    case 'automation_owner_assigned': {
      const owner = activityLabelValue(activity, 'owner_id');
      return owner
        ? t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_OWNER', { owner })
        : '';
    }
    case 'ai_handoff': {
      const agent = activityLabelValue(activity, 'assignee_id');
      const reason = activity.payload?.reason;
      if (agent && reason)
        return t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_HANDOFF_REASON', {
          agent,
          reason,
        });
      if (agent)
        return t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_HANDOFF', { agent });
      return reason || '';
    }
    // Fase D: handoff do agente nativo. Mostra só o destino (membro do inbox ou
    // time); nunca há `reason` no payload (IP oculto).
    case 'autonomia_handoff': {
      const assignee = activityLabelValue(activity, 'assignee_id');
      if (assignee)
        return t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_HANDOFF', {
          agent: assignee,
        });
      const team = activityLabelValue(activity, 'team_id');
      return team
        ? t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_AUTONOMIA_HANDOFF_TEAM', {
            team,
          })
        : '';
    }
    case 'contact_linked':
    case 'contact_unlinked': {
      const contact = activityLabelValue(activity, 'contact_id');
      return contact
        ? t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_CONTACT', { contact })
        : '';
    }
    // chat#737: follow-up automático cancelado porque o contato recusou mensagens ativas.
    case 'follow_up_canceled': {
      const title = activity.payload?.title || '';
      if (activity.payload?.reason !== 'opt_out') return title;
      const reason = t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_FOLLOW_UP_OPT_OUT');
      return title ? `${title} · ${reason}` : reason;
    }
    case 'follow_up_created':
    case 'follow_up_updated':
    case 'follow_up_completed':
    case 'follow_up_overdue':
    case 'follow_up_message_sent': {
      const title = activity.payload?.title;
      return title || activityAttemptDetail(activity);
    }
    case 'follow_up_message_failed':
      return [activity.payload?.title, activityRetryDetail(activity)]
        .filter(Boolean)
        .join(' · ');
    case 'ai_followup_failed':
      return activityRetryDetail(activity);
    case 'ai_followup_sent':
    case 'ai_followup_capped':
    case 'ai_followup_completed':
      return activityAttemptDetail(activity);
    case 'follow_up_rescheduled': {
      const dueAt = activity.payload?.due_at;
      if (!dueAt || Number.isNaN(new Date(dueAt).getTime())) return '';
      return t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_FOLLOW_UP_RESCHEDULED', {
        time: relativeTimeFromISO(dueAt, locale.value),
      });
    }
    case 'meeting_scheduled':
    case 'meeting_rescheduled':
    case 'meeting_canceled': {
      const title = activity.payload?.title;
      return title
        ? t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_MEETING', { title })
        : '';
    }
    default:
      return '';
  }
};

// Single source of truth for rendering a timeline entry. Hard non-JSON
// fallback: unknown event types still produce a humanized label + icon.
const describeActivity = activity => {
  const meta = ACTIVITY_META[activity.event_type] || FALLBACK_META;
  const title = meta.key
    ? t(`CRM_KANBAN.DRAWER.${meta.key}`)
    : t('CRM_KANBAN.DRAWER.ACTIVITY_GENERIC');
  return {
    title,
    icon: meta.icon,
    toneClass:
      ACTIVITY_TONE_CLASSES[meta.tone] || ACTIVITY_TONE_CLASSES.neutral,
    actor: activityActor(activity),
    detail: activityDetail(activity),
    relativeTime: relativeTimeFromISO(activity.created_at, locale.value),
  };
};

// Um auto-move da IA grava DUAS atividades para um único movimento físico:
// 'ai_auto_moved' (auditoria da decisão do modelo) e 'move' (evento canônico do
// Crm::Cards::Mover). As duas TÊM que continuar existindo no banco — só 'move'
// está na allowlist de webhooks do Crm::Webhooks::Emitter e alimenta o sync de
// conversão Meta CAPI. Aqui a timeline colapsa o par em uma linha só, mantendo
// a da IA (mais informativa). Nada muda no backend.
const AI_MOVE_DEDUP_WINDOW_MS = 60 * 1000;

const stageTransitionKey = activity => {
  const from = activity.payload?.from_stage_id;
  const to = activity.payload?.to_stage_id;
  return from && to ? `${from}->${to}` : null;
};

const activityTime = activity => new Date(activity.created_at).getTime();

// Só o 'move' escrito PELA IA é candidato: o Mover recebe actor nil no caminho
// do SuggestionApplier (-> actor_type 'system'), enquanto movimento humano leva
// Current.user (-> actor_type 'user'). Sem esse filtro, um humano refazendo a
// mesma transição logo depois do auto-move sumiria da timeline.
const isCollapsibleMove = activity =>
  activity.event_type === 'move' &&
  activity.actor_type === 'system' &&
  stageTransitionKey(activity) !== null;

// Janela DIRECIONAL: o 'move' da IA é sempre gravado DEPOIS do ai_auto_moved
// (o SuggestionRecorder roda antes do SuggestionApplier), então movimento
// anterior nunca é par. created_at chega serializado com .iso8601 — precisão de
// segundo —, logo empates de distância são esperados e o desempate é por id.
const matchesAiMove = (move, aiMove) => {
  if (stageTransitionKey(move) !== stageTransitionKey(aiMove)) return false;
  // O 'move' é sempre a linha inserida DEPOIS, então o id também tem que ser
  // maior. Isso desempata dois ciclos de IA da mesma transição no mesmo segundo,
  // que o timestamp truncado sozinho não distingue.
  if (Number(move.id) <= Number(aiMove.id)) return false;
  const delta = activityTime(move) - activityTime(aiMove);
  return delta >= 0 && delta <= AI_MOVE_DEDUP_WINDOW_MS;
};

// Pareamento 1:1: cada ai_auto_moved consome no máximo um 'move' — o mais
// próximo no tempo e, no empate, o de menor id. Dois auto-moves da mesma
// transição na janela nunca escondem três linhas.
const collapsedMoveIds = computed(() => {
  const aiMoves = activities.value.filter(
    activity => activity.event_type === 'ai_auto_moved'
  );
  if (aiMoves.length === 0) return new Set();

  const candidates = activities.value.filter(isCollapsibleMove);
  return aiMoves.reduce((collapsed, aiMove) => {
    const [nearest] = candidates
      .filter(move => !collapsed.has(move.id) && matchesAiMove(move, aiMove))
      .sort(
        (a, b) =>
          activityTime(a) - activityTime(b) || Number(a.id) - Number(b.id)
      );
    return nearest ? new Set([...collapsed, nearest.id]) : collapsed;
  }, new Set());
});

const visibleActivities = computed(() =>
  collapsedMoveIds.value.size === 0
    ? activities.value
    : activities.value.filter(
        activity => !collapsedMoveIds.value.has(activity.id)
      )
);

const timelineEntries = computed(() =>
  visibleActivities.value.map(activity => ({
    id: activity.id,
    ...describeActivity(activity),
  }))
);

const followUpStatusClass = followUp => {
  const map = {
    pending: 'bg-n-teal-3 text-n-teal-11',
    overdue: 'bg-n-ruby-3 text-n-ruby-11',
    done: 'bg-n-slate-4 text-n-slate-11',
    canceled: 'bg-n-slate-4 text-n-slate-10',
  };
  return map[followUp.status] || map.pending;
};

const followUpStatusLabel = followUp => {
  const map = {
    pending: t('CRM_KANBAN.FOLLOW_UP_STATUS.PENDING'),
    overdue: t('CRM_KANBAN.FOLLOW_UP_STATUS.OVERDUE'),
    done: t('CRM_KANBAN.FOLLOW_UP_STATUS.DONE'),
    canceled: t('CRM_KANBAN.FOLLOW_UP_STATUS.CANCELED'),
  };
  return map[followUp.status] || followUp.status;
};

const followUpAutomationLabel = followUp => {
  const map = {
    reminder_only: t('CRM_KANBAN.FOLLOW_UP_MODE.REMINDER_ONLY'),
    snooze_conversation: t('CRM_KANBAN.FOLLOW_UP_MODE.SNOOZE_CONVERSATION'),
    auto_send_message: t('CRM_KANBAN.FOLLOW_UP_MODE.AUTO_SEND_MESSAGE'),
  };
  return map[followUp.automation_mode] || followUp.automation_mode;
};

useKeyboardEvents({
  Escape: {
    action: () => {
      if (showWinDialog.value || showLoseDialog.value) {
        showWinDialog.value = false;
        showLoseDialog.value = false;
        return;
      }
      if (
        props.show &&
        !discardOpen.value &&
        !document.querySelector('dialog[open]')
      )
        closeDrawer();
    },
    allowOnFocusedInput: true,
  },
});

// #646 — a gaveta cobre o mesmo canto (`fixed ... right-0`) do lançador do
// Guia; sinaliza que está aberta para ele se desviar do rodapé Cancelar/Salvar.
useFixedPanelPresence(computed(() => props.show));
</script>

<template>
  <Dialog
    ref="discardDialog"
    type="alert"
    :title="relationshipLabel('DISCARD_TITLE')"
    :description="discardDescription"
    :confirm-button-label="relationshipLabel('DISCARD')"
    :cancel-button-label="relationshipLabel('KEEP_EDITING')"
    @confirm="confirmDiscard"
    @close="discardOpen = false"
  />
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
  >
    <div
      v-if="show"
      ref="drawerElement"
      data-crm-card-drawer
      role="dialog"
      aria-modal="true"
      :aria-labelledby="`${drawerId}-title`"
      :aria-describedby="`${drawerId}-subtitle`"
      tabindex="-1"
      class="fixed inset-y-0 ltr:right-0 rtl:left-0 z-50 flex h-full w-[40rem] max-w-full flex-col overflow-hidden border-n-weak bg-n-surface-2 shadow-lg ltr:border-l rtl:border-r"
      @keydown="trapDrawerFocus"
    >
      <div
        class="flex items-start justify-between gap-4 bg-n-blue-12 px-8 py-6"
      >
        <div class="min-w-0">
          <h2
            :id="`${drawerId}-title`"
            class="mb-2 text-2xl font-semibold text-n-slate-1"
          >
            {{ panelTitle }}
          </h2>
          <p
            :id="`${drawerId}-subtitle`"
            class="mb-0 grid gap-0.5 text-sm leading-6 text-n-slate-4"
          >
            <template
              v-if="
                isEditing &&
                (headerHasDistinctContact || headerHasDistinctBusiness)
              "
            >
              <span v-if="headerHasDistinctContact" class="truncate">
                {{ headerContactName }}
              </span>
              <span
                v-if="headerHasDistinctBusiness"
                class="truncate text-xs text-n-slate-5"
              >
                <span class="font-medium text-n-slate-4">
                  {{ t('CRM_KANBAN.CARD.BUSINESS_LABEL') }}
                </span>
                {{ headerBusinessName }}
              </span>
            </template>
            <span v-else>{{ panelSubtitle }}</span>
          </p>
          <Button
            v-if="!isEditing && initialContact"
            type="button"
            sm
            ghost
            slate
            icon="i-lucide-arrow-left"
            class="mt-2"
            :label="t('CRM_KANBAN.OPPORTUNITY.CONTEXT.BACK')"
            @click="
              guardRelationship(() =>
                router.push({
                  name: 'contacts_edit',
                  params: {
                    accountId: route.params.accountId,
                    contactId: initialContact.id,
                  },
                })
              )
            "
          />
        </div>
        <Button
          icon="i-lucide-x"
          slate
          ghost
          sm
          :aria-label="t('GENERAL.CLOSE')"
          class="!text-n-slate-1 min-h-11 min-w-11"
          @click="closeDrawer"
        />
      </div>

      <div class="flex-1 overflow-y-auto px-6 py-5">
        <div
          v-if="isEditing"
          class="flex flex-wrap items-center justify-between gap-3 p-3 mb-5 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <span
            class="px-2 py-1 text-xs font-medium rounded-md"
            :class="statusPillClass"
          >
            {{ statusLabel }}
          </span>
          <div v-if="canManageCards" class="flex items-center gap-2">
            <template v-if="isDealOpen">
              <Button
                sm
                teal
                faded
                icon="i-lucide-trophy"
                :label="t('CRM_KANBAN.DRAWER.WIN_DEAL')"
                @click="guardRelationship(openWinDialog)"
              />
              <Button
                sm
                ruby
                faded
                icon="i-lucide-circle-x"
                :label="t('CRM_KANBAN.DRAWER.LOSE_DEAL')"
                @click="guardRelationship(openLoseDialog)"
              />
            </template>
            <Button
              v-else
              sm
              slate
              faded
              icon="i-lucide-rotate-ccw"
              :label="t('CRM_KANBAN.DRAWER.REOPEN_DEAL')"
              @click="guardRelationship(reopenDeal)"
            />
          </div>
        </div>
        <div
          v-if="metaConversionPill"
          class="flex flex-wrap items-center gap-2 mb-5"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM_KANBAN.META_SYNC_STATUS.CARD_TITLE') }}
          </span>
          <span
            class="px-2 py-1 text-xs font-medium rounded-md"
            :class="metaConversionPill.class"
          >
            {{ t(metaConversionPill.label) }}
          </span>
          <span
            v-if="metaConversion?.event_type"
            class="w-full text-xs text-n-slate-10"
          >
            {{
              t('CRM_KANBAN.META_SYNC_STATUS.CARD_EVENT', {
                event: metaConversion.event_type,
              })
            }}
          </span>
        </div>
        <div v-if="isEditing" class="mb-5 grid gap-3">
          <div
            role="tablist"
            :aria-label="panelTitle"
            class="grid grid-cols-2 gap-1 rounded-lg bg-n-alpha-black2 p-1 sm:flex"
          >
            <button
              v-for="(tab, index) in detailTabs"
              :id="tabId(tab.id)"
              :key="tab.id"
              :ref="element => (tabButtons[index] = element)"
              type="button"
              role="tab"
              :aria-selected="activeTab === tab.id"
              :aria-controls="detailPanelId(tab.id)"
              :tabindex="activeTab === tab.id ? 0 : -1"
              class="min-h-11 min-w-0 whitespace-nowrap rounded-md px-3 text-xs font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand sm:flex-1"
              :class="
                activeTab === tab.id
                  ? 'bg-n-brand/10 text-n-blue-11 shadow-sm ring-1 ring-inset ring-n-brand/30'
                  : ''
              "
              @click="guardRelationship(() => (activeTab = tab.id))"
              @keydown="moveTabFocus"
            >
              {{ tab.label }}
            </button>
          </div>
          <div
            v-if="isLoadingDetails"
            class="flex items-center gap-2 text-xs text-n-slate-10"
          >
            <span class="i-lucide-loader-2 size-3 animate-spin" />
            {{ t('CRM_KANBAN.DRAWER.LOADING_DETAILS') }}
          </div>
        </div>

        <CrmOpportunityForm
          v-if="!isEditing"
          :key="`${route.params.accountId}:${initialContact?.id || 'new'}`"
          ref="creationForm"
          :initial-contact="initialContact"
          :pipelines="pipelines"
          :pipeline-id="pipelineId"
          :stages="stages"
          :agents="agents"
          :inboxes="inboxes"
          :can-manage="canManageCards"
          :can-create-contact="canManageRelationshipRecords"
          @save="(payload, failed) => emit('save', payload, failed)"
        />
        <div
          v-else-if="activeTab === 'summary'"
          :id="detailPanelId('summary')"
          role="tabpanel"
          :aria-labelledby="tabId('summary')"
          tabindex="-1"
          class="grid gap-4 outline-none"
        >
          <Input
            v-model="form.title"
            :readonly="!canManageCards"
            :label="t('CRM_KANBAN.DRAWER.TITLE_LABEL')"
            :placeholder="t('CRM_KANBAN.DRAWER.TITLE_PLACEHOLDER')"
            :message="!form.title.trim() ? t('CRM_KANBAN.DRAWER.REQUIRED') : ''"
            :message-type="!form.title.trim() ? 'error' : 'info'"
          />

          <label class="grid gap-1">
            <span class="text-heading-3 text-n-slate-12">
              {{ t('CRM_KANBAN.DRAWER.DESCRIPTION_LABEL') }}
            </span>
            <textarea
              v-model="form.description"
              :readonly="!canManageCards"
              rows="4"
              class="reset-base !mb-0 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 text-sm text-n-slate-12 outline outline-1 outline-n-weak transition-all placeholder:text-n-slate-10 focus:outline-n-brand"
              :placeholder="t('CRM_KANBAN.DRAWER.DESCRIPTION_PLACEHOLDER')"
            />
          </label>

          <CrmCardAiPanel
            v-if="isEditing && card?.id && isCrmAiEnabled"
            :card-id="card.id"
            :initial-suggestion="card.ai_suggestion"
            :can-manage-ai="canManageAi"
          />

          <section
            v-if="hasLinkedContext"
            class="grid gap-3 rounded-xl border border-n-weak bg-n-surface-1 p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="mb-1 text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.DRAWER.LINKS_TITLE') }}
                </p>
                <p class="mb-0 text-xs leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.DRAWER.LINKS_HELP') }}
                </p>
              </div>
              <Button
                v-if="linkedConversationDisplayId"
                :label="t('CRM_KANBAN.DRAWER.OPEN_CONVERSATION')"
                icon="i-lucide-message-circle"
                slate
                faded
                sm
                @click="openConversation"
              />
            </div>

            <div v-if="originPill" class="flex min-w-0 items-center">
              <CrmCardPill
                :icon="originPill.icon"
                tone="teal"
                :title="formatOriginTitle(originPill)"
              >
                {{ humanizedOriginLabel(originPill) }}
                <template v-if="originPill.extraCount > 0" #trail>
                  <span class="shrink-0 font-semibold">
                    {{ `+${originPill.extraCount}` }}
                  </span>
                </template>
              </CrmCardPill>
            </div>

            <div class="grid divide-y divide-n-weak text-sm">
              <div
                v-if="card?.contact"
                class="flex min-w-0 items-center justify-between gap-3 py-2 first:pt-0 last:pb-0"
              >
                <span class="text-n-slate-11">
                  {{ t('CRM_KANBAN.DRAWER.CONTACT') }}
                </span>
                <span class="truncate text-right text-n-slate-12">
                  {{ card.contact.name || card.contact.phone_number }}
                </span>
              </div>
              <div
                v-if="card?.inbox"
                class="flex min-w-0 items-center justify-between gap-3 py-2 first:pt-0 last:pb-0"
              >
                <span class="text-n-slate-11">
                  {{ t('CRM_KANBAN.DRAWER.INBOX') }}
                </span>
                <span class="truncate text-right text-n-slate-12">
                  {{ card.inbox.name }}
                </span>
              </div>
              <div
                v-if="linkedConversationDisplayId"
                class="flex min-w-0 items-center justify-between gap-3 py-2 first:pt-0 last:pb-0"
              >
                <span class="text-n-slate-11">
                  {{ t('CRM_KANBAN.DRAWER.CONVERSATION') }}
                </span>
                <span class="truncate text-right text-n-slate-12">
                  {{
                    t('CRM_KANBAN.DRAWER.CONVERSATION_NUMBER', {
                      id: linkedConversationDisplayId,
                    })
                  }}
                </span>
              </div>
            </div>
          </section>

          <div class="grid grid-cols-1 gap-3 min-[460px]:grid-cols-2">
            <Input
              v-model="form.valueAmount"
              :readonly="!canManageCards"
              type="number"
              min="0"
              :label="
                t('CRM_KANBAN.DRAWER.VALUE_WITH_CURRENCY', {
                  currency: form.currency || 'BRL',
                })
              "
              :placeholder="t('CRM_KANBAN.DRAWER.VALUE_PLACEHOLDER')"
            />
            <label class="grid gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('CRM_KANBAN.DRAWER.PRIORITY') }}
              </span>
              <ChoiceSelect
                v-model="form.priority"
                :disabled="!canManageCards"
                :options="priorityOptions"
                :aria-label="t('CRM_KANBAN.DRAWER.PRIORITY')"
                class="w-full"
              />
            </label>
          </div>

          <details
            class="group rounded-xl border border-n-weak bg-n-surface-1 p-1"
            :open="additionalDetailsOpen"
            @toggle="additionalDetailsOpen = $event.currentTarget.open"
          >
            <summary
              class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 rounded-lg px-3 py-2 text-sm font-medium text-n-slate-12 outline-none hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
            >
              <span class="flex min-w-0 items-center gap-2">
                <span
                  class="i-lucide-sliders-horizontal size-4 shrink-0 text-n-slate-10"
                  aria-hidden="true"
                />
                <span class="truncate">
                  {{ t('CRM_KANBAN.DRAWER.MORE_DETAILS') }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-10 transition-transform group-open:rotate-180"
                aria-hidden="true"
              />
            </summary>
            <div
              class="grid grid-cols-1 gap-3 px-2 pb-2 pt-3 min-[460px]:grid-cols-2"
            >
              <Input
                v-model="form.score"
                :readonly="!canManageCards"
                type="number"
                min="0"
                max="100"
                :label="t('CRM_KANBAN.DRAWER.SCORE')"
                :placeholder="t('CRM_KANBAN.DRAWER.SCORE_PLACEHOLDER')"
              />
              <Input
                v-model="form.expectedCloseAt"
                :readonly="!canManageCards"
                type="date"
                :label="t('CRM_KANBAN.DRAWER.EXPECTED_CLOSE_AT')"
              />
            </div>
          </details>
        </div>

        <CrmCardRelationshipPanel
          v-else-if="activeTab === 'contact' && card"
          :id="detailPanelId('contact')"
          ref="relationshipPanel"
          :key="`${route.params.accountId}:${card.id}`"
          role="tabpanel"
          :aria-labelledby="tabId('contact')"
          tabindex="-1"
          :card="card"
          :can-manage="canManageCards"
          :can-manage-records="canManageRelationshipRecords"
          :editing="isEditingContact && canManageRelationshipRecords"
          @edit="startContactEdit"
          @guard="guardRelationship"
          @linked="$emit('refreshCard')"
        >
          <template #editor>
            <form
              :id="`crm-contact-form-${card.id}`"
              class="grid gap-4"
              data-contact-editor
              @submit.prevent="saveContact"
            >
              <p class="mb-0 text-xs leading-5 text-n-slate-11">
                {{ relationshipLabel('EDIT_HELP') }}
              </p>
              <p
                v-if="contactError"
                role="alert"
                class="mb-0 rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
              >
                {{ contactError }}
              </p>
              <div class="grid grid-cols-1 gap-4 min-[440px]:grid-cols-2">
                <Input
                  v-model="contactForm.name"
                  :label="relationshipLabel('NAME')"
                  required
                  :disabled="isSavingContact"
                  class="min-[440px]:col-span-2"
                />
                <Input
                  v-model="contactForm.email"
                  type="email"
                  :label="relationshipLabel('EMAIL')"
                  :disabled="isSavingContact"
                />
                <label class="grid gap-2 text-sm text-n-slate-12">
                  <!-- Native phone input keeps its country selector and validation. -->
                  <span>{{ relationshipLabel('PHONE') }}</span>
                  <PhoneNumberInput
                    v-model="contactForm.phoneNumber"
                    :disabled="isSavingContact"
                  />
                </label>
                <Input
                  v-model="contactForm.jobTitle"
                  :label="relationshipLabel('ROLE')"
                  :disabled="isSavingContact"
                />
                <Input
                  v-model="contactForm.city"
                  :label="relationshipLabel('CITY')"
                  :disabled="isSavingContact"
                />
                <Input
                  v-model="contactForm.address"
                  :label="relationshipLabel('ADDRESS')"
                  :disabled="isSavingContact"
                  class="min-[440px]:col-span-2"
                />
                <Input
                  v-model="contactForm.country"
                  :label="relationshipLabel('COUNTRY')"
                  :disabled="isSavingContact"
                />
              </div>
            </form>
          </template>
        </CrmCardRelationshipPanel>

        <section
          v-else-if="activeTab === 'conversations'"
          :id="detailPanelId('conversations')"
          role="tabpanel"
          :aria-labelledby="tabId('conversations')"
          tabindex="-1"
          class="grid gap-3 outline-none"
        >
          <CrmCardSummaryPanel
            v-if="isEditing && card?.id && isCrmAiEnabled"
            :card="card"
            :detail-loaded="!isLoadingDetails"
            :can-manage-ai="canManageAi"
            :ai-enabled="isCrmAiEnabled"
          />

          <article
            v-for="conversation in linkedConversations"
            :key="conversation.id || conversation.display_id"
            class="grid gap-3 border-b border-n-weak py-4 first:pt-0 last:border-b-0 last:pb-0"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="mb-1 text-sm font-medium text-n-slate-12">
                  {{
                    t('CRM_KANBAN.DRAWER.CONVERSATION_NUMBER', {
                      id: conversation.display_id,
                    })
                  }}
                </p>
                <p class="mb-0 truncate text-xs text-n-slate-11">
                  {{
                    conversation.inbox_name ||
                    conversation.inbox?.name ||
                    t('CRM_KANBAN.DRAWER.NO_INBOX')
                  }}
                </p>
              </div>
              <Button
                :label="t('CRM_KANBAN.DRAWER.OPEN_CONVERSATION')"
                icon="i-lucide-message-circle"
                slate
                faded
                sm
                class="min-w-max shrink-0"
                @click="openConversationByDisplayId(conversation.display_id)"
              />
            </div>
            <div class="grid grid-cols-2 gap-2 text-xs text-n-slate-11">
              <div>
                {{ t('CRM_KANBAN.DRAWER.CONVERSATION_STATUS') }}
                <span class="text-n-slate-12">
                  {{ conversationStatusLabel(conversation.status) }}
                </span>
              </div>
              <div>
                {{ t('CRM_KANBAN.DRAWER.CONVERSATION_LAST_ACTIVITY') }}
                <span class="text-n-slate-12">
                  {{ formatDate(conversation.last_activity_at) }}
                </span>
              </div>
              <div v-if="conversation.assignee_name" class="col-span-2">
                {{ t('CRM_KANBAN.DRAWER.CONVERSATION_ASSIGNEE') }}
                <span class="text-n-slate-12">
                  {{ conversation.assignee_name }}
                </span>
              </div>
            </div>
          </article>

          <div
            v-if="linkedConversations.length === 0 && !isLoadingDetails"
            class="rounded-lg border border-dashed border-n-weak px-4 py-8 text-center"
          >
            <p class="mb-1 text-sm font-medium text-n-slate-12">
              {{ t('CRM_KANBAN.DRAWER.NO_CONVERSATIONS_TITLE') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_KANBAN.DRAWER.NO_CONVERSATIONS_HELP') }}
            </p>
          </div>
        </section>

        <section
          v-else-if="activeTab === 'followups'"
          :id="detailPanelId('followups')"
          role="tabpanel"
          :aria-labelledby="tabId('followups')"
          tabindex="-1"
          class="grid gap-3 outline-none"
        >
          <!-- 1) Open follow-ups (pending / overdue) on top -->
          <div
            v-if="isFetchingFollowUps"
            class="flex items-center gap-2 text-xs text-n-slate-10"
          >
            <span class="i-lucide-loader-2 size-3 animate-spin" />
            {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_LOADING') }}
          </div>
          <article
            v-for="followUp in activeFollowUps"
            :key="`active-${followUp.id}`"
            class="grid gap-3 rounded-xl border border-n-weak bg-n-surface-1 p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="mb-1 truncate text-sm font-medium text-n-slate-12">
                  {{ followUp.title }}
                </p>
                <p class="mb-0 flex flex-wrap gap-2 text-xs text-n-slate-11">
                  <span>{{ formatDate(followUp.due_at) }}</span>
                  <span>{{ followUpAutomationLabel(followUp) }}</span>
                </p>
              </div>
              <span
                class="shrink-0 rounded-md px-2 py-1 text-[11px] font-medium"
                :class="followUpStatusClass(followUp)"
              >
                {{ followUpStatusLabel(followUp) }}
              </span>
            </div>
            <p
              v-if="followUp.description"
              class="mb-0 text-xs leading-5 text-n-slate-11"
            >
              {{ followUp.description }}
            </p>
            <div v-if="canManageCards" class="flex justify-end gap-2">
              <Button
                :label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_COMPLETE')"
                icon="i-lucide-check"
                slate
                faded
                sm
                class="min-w-max"
                :is-loading="isSavingFollowUp"
                @click="completeFollowUp(followUp)"
              />
              <Button
                :label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_CANCEL')"
                icon="i-lucide-x"
                ruby
                ghost
                sm
                class="min-w-max"
                :is-loading="isSavingFollowUp"
                @click="cancelFollowUp(followUp)"
              />
            </div>
          </article>

          <!-- 2) New follow-up -->
          <details
            v-if="canManageCards"
            :open="newFollowUpOpen"
            class="group rounded-xl border border-n-weak bg-n-surface-1"
            @toggle="newFollowUpOpen = $event.currentTarget.open"
          >
            <summary
              class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 rounded-xl px-4 py-3 text-sm font-medium text-n-slate-12 outline-none hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
            >
              <span class="flex min-w-0 items-center gap-2">
                <span
                  class="i-lucide-plus size-4 shrink-0 text-n-blue-11"
                  aria-hidden="true"
                />
                <span class="truncate">
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_CREATE') }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-10 transition-transform group-open:rotate-180"
                aria-hidden="true"
              />
            </summary>

            <div class="grid gap-3 border-t border-n-weak p-4">
              <div>
                <p class="mb-1 text-sm font-medium text-n-slate-12">
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_CREATE_TITLE') }}
                </p>
                <p class="mb-0 text-xs leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_CREATE_HELP') }}
                </p>
              </div>

              <div class="grid grid-cols-1 gap-3 min-[460px]:grid-cols-2">
                <Input
                  v-model="followUpForm.title"
                  :label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_TITLE')"
                  :placeholder="
                    t('CRM_KANBAN.DRAWER.FOLLOW_UP_TITLE_PLACEHOLDER')
                  "
                />

                <label class="grid gap-1">
                  <span class="text-heading-3 text-n-slate-12">
                    {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_DUE_AT') }}
                  </span>
                  <input
                    v-model="followUpForm.dueAt"
                    type="datetime-local"
                    class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                  />
                </label>
              </div>

              <label class="grid gap-1">
                <span class="text-heading-3 text-n-slate-12">
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_MODE') }}
                </span>
                <ChoiceSelect
                  v-model="followUpForm.automationMode"
                  :options="followUpModeChoices"
                  :aria-label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_MODE')"
                  class="w-full"
                />
                <span
                  v-if="!canSnoozeConversation"
                  class="text-xs text-n-slate-10"
                >
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_SNOOZE_DISABLED') }}
                </span>
                <span
                  v-if="!canAutoSendMessage"
                  class="text-xs text-n-slate-10"
                >
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_AUTO_SEND_DISABLED') }}
                </span>
              </label>

              <div
                v-if="followUpForm.automationMode === 'auto_send_message'"
                class="grid gap-3 rounded-lg border border-n-blue-7/40 bg-n-blue-2/30 p-3"
              >
                <p class="mb-0 text-xs leading-5 text-n-slate-11">
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_AUTO_SEND_HELP') }}
                </p>
                <p
                  v-if="isLoadingMessagingWindow"
                  class="mb-0 text-xs text-n-slate-10"
                >
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_WINDOW_LOADING') }}
                </p>
                <p
                  v-else-if="requiresTemplateNow"
                  class="mb-0 text-xs text-n-ruby-11"
                >
                  {{
                    t('CRM_KANBAN.DRAWER.FOLLOW_UP_WINDOW_TEMPLATE_REQUIRED')
                  }}
                </p>
                <p v-else class="mb-0 text-xs text-n-teal-11">
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_WINDOW_SESSION_OK') }}
                </p>

                <Input
                  v-model="followUpForm.messageBody"
                  :label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_MESSAGE_BODY')"
                  :placeholder="
                    t('CRM_KANBAN.DRAWER.FOLLOW_UP_MESSAGE_BODY_PLACEHOLDER')
                  "
                />

                <label
                  v-if="isWhatsappApiInbox && requiresTemplateNow"
                  class="grid gap-1"
                >
                  <span class="text-heading-3 text-n-slate-12">
                    {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_API_TEMPLATE') }}
                  </span>
                  <ChoiceSelect
                    v-model="followUpForm.whatsappApiTemplateId"
                    :options="whatsappApiTemplateChoices"
                    :aria-label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_API_TEMPLATE')"
                    class="w-full"
                  />
                  <span
                    v-if="isLoadingWhatsappTemplates"
                    class="text-xs text-n-slate-10"
                  >
                    {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_TEMPLATES_LOADING') }}
                  </span>
                </label>

                <label
                  v-else-if="isWhatsappNativeInbox && requiresTemplateNow"
                  class="grid gap-1"
                >
                  <span class="text-heading-3 text-n-slate-12">
                    {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_API_TEMPLATE') }}
                  </span>
                  <ChoiceSelect
                    v-model="followUpForm.nativeTemplateKey"
                    :options="nativeWhatsappTemplateChoices"
                    :aria-label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_API_TEMPLATE')"
                    class="w-full"
                    @change="onNativeTemplateSelected"
                  />
                  <span
                    v-if="!nativeWhatsappTemplateOptions.length"
                    class="text-xs text-n-slate-10"
                  >
                    {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_NATIVE_TEMPLATE_EMPTY') }}
                  </span>
                </label>

                <template v-else-if="requiresTemplateNow">
                  <Input
                    v-model="followUpForm.templateName"
                    :label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_TEMPLATE_NAME')"
                    :placeholder="
                      t('CRM_KANBAN.DRAWER.FOLLOW_UP_TEMPLATE_NAME_PLACEHOLDER')
                    "
                  />
                  <Input
                    v-model="followUpForm.templateLanguage"
                    :label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_TEMPLATE_LANGUAGE')"
                    placeholder="pt_BR"
                  />
                </template>
              </div>

              <label class="grid gap-1">
                <span class="text-heading-3 text-n-slate-12">
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_DESCRIPTION') }}
                </span>
                <textarea
                  v-model="followUpForm.description"
                  rows="3"
                  class="reset-base !mb-0 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 text-sm text-n-slate-12 outline outline-1 outline-n-weak transition-all placeholder:text-n-slate-10 focus:outline-n-brand"
                  :placeholder="
                    t('CRM_KANBAN.DRAWER.FOLLOW_UP_DESCRIPTION_PLACEHOLDER')
                  "
                />
              </label>

              <div class="flex justify-end">
                <Button
                  :label="t('CRM_KANBAN.DRAWER.FOLLOW_UP_CREATE')"
                  icon="i-lucide-clock-3"
                  :is-loading="isSavingFollowUp"
                  :disabled="
                    !followUpForm.title.trim() ||
                    !followUpForm.dueAt ||
                    isSavingFollowUp
                  "
                  @click="createFollowUp"
                />
              </div>
            </div>
          </details>

          <!-- 3) Automatic follow-up -->
          <CrmCardAutoFollowupStatus
            :card="props.card"
            :can-manage-ai="canManageAi"
            :can-manage-records="canManageRelationshipRecords"
            @reset="$emit('refreshCard')"
          />

          <!-- 4) Completed follow-ups (bottom) -->
          <details
            v-if="completedFollowUps.length"
            class="group rounded-xl border border-n-weak bg-n-surface-1 p-1"
          >
            <summary
              class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 rounded-lg px-3 py-2 text-sm font-medium text-n-slate-12 outline-none hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
            >
              <span class="flex min-w-0 items-center gap-2">
                <span
                  class="i-lucide-check-check size-4 shrink-0 text-n-slate-10"
                  aria-hidden="true"
                />
                <span class="truncate">
                  {{ t('CRM_KANBAN.DRAWER.FOLLOW_UP_COMPLETED_SECTION') }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-10 transition-transform group-open:rotate-180"
                aria-hidden="true"
              />
            </summary>
            <div class="grid px-2 pb-2">
              <article
                v-for="followUp in completedFollowUps"
                :key="followUp.id"
                class="grid gap-3 border-b border-n-weak py-3 last:border-b-0"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p
                      class="mb-1 truncate text-sm font-medium text-n-slate-12"
                    >
                      {{ followUp.title }}
                    </p>
                    <p
                      class="mb-0 flex flex-wrap gap-2 text-xs text-n-slate-11"
                    >
                      <span>{{ formatDate(followUp.due_at) }}</span>
                      <span>{{ followUpAutomationLabel(followUp) }}</span>
                    </p>
                  </div>
                  <span
                    class="shrink-0 rounded-md px-2 py-1 text-[11px] font-medium"
                    :class="followUpStatusClass(followUp)"
                  >
                    {{ followUpStatusLabel(followUp) }}
                  </span>
                </div>
                <p
                  v-if="followUp.description"
                  class="mb-0 text-xs leading-5 text-n-slate-11"
                >
                  {{ followUp.description }}
                </p>
              </article>
            </div>
          </details>

          <div
            v-if="!isFetchingFollowUps && followUps.length === 0"
            class="rounded-lg border border-dashed border-n-weak px-4 py-8 text-center"
          >
            <p class="mb-1 text-sm font-medium text-n-slate-12">
              {{ t('CRM_KANBAN.DRAWER.NO_FOLLOW_UPS_TITLE') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_KANBAN.DRAWER.NO_FOLLOW_UPS_HELP') }}
            </p>
          </div>
        </section>

        <section
          v-else
          :id="detailPanelId('timeline')"
          role="tabpanel"
          :aria-labelledby="tabId('timeline')"
          tabindex="-1"
          class="grid gap-3 outline-none"
        >
          <article
            v-for="entry in timelineEntries"
            :key="entry.id"
            class="grid grid-cols-[auto_1fr] gap-3 border-b border-n-weak py-3 last:border-b-0 first:pt-0"
          >
            <span
              class="mt-0.5 flex size-7 items-center justify-center rounded-full"
              :class="entry.toneClass"
            >
              <span class="size-3.5" :class="[entry.icon]" />
            </span>
            <div class="min-w-0">
              <div
                class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1"
              >
                <p class="mb-0 text-sm font-medium text-n-slate-12">
                  {{ entry.title }}
                </p>
                <span class="shrink-0 text-xs text-n-slate-10">
                  {{ entry.relativeTime }}
                </span>
              </div>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ entry.actor }}
              </p>
              <p
                v-if="entry.detail"
                class="mb-0 mt-1 text-xs leading-5 text-n-slate-12"
              >
                {{ entry.detail }}
              </p>
            </div>
          </article>

          <div
            v-if="activities.length === 0 && !isLoadingDetails"
            class="rounded-lg border border-dashed border-n-weak px-4 py-8 text-center"
          >
            <p class="mb-1 text-sm font-medium text-n-slate-12">
              {{ t('CRM_KANBAN.DRAWER.NO_TIMELINE_TITLE') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_KANBAN.DRAWER.NO_TIMELINE_HELP') }}
            </p>
          </div>
        </section>
      </div>

      <div
        v-if="!relationshipLinking"
        data-crm-drawer-footer
        class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak px-6 py-4"
      >
        <div
          v-if="isEditing && !isEditingContact && !companyAction"
          class="flex items-center gap-2"
        >
          <Button
            v-if="canManageCards"
            :label="t('CRM_KANBAN.DRAWER.ARCHIVE')"
            icon="i-lucide-archive"
            ruby
            ghost
            :is-loading="isArchiving"
            @click="guardRelationship(archiveCard)"
          />
          <Button
            v-if="canManageCards && meetingsEnabled && card?.id"
            :label="t('CRM_KANBAN.DRAWER.SCHEDULE_MEETING')"
            icon="i-lucide-video"
            variant="outline"
            color="slate"
            @click="guardRelationship(scheduleMeeting)"
          />
        </div>
        <div
          v-else-if="!isEditing"
          class="flex min-w-0 items-center gap-2 text-xs text-n-slate-11"
        >
          <span
            class="i-lucide-link-2 size-4 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <span>{{ creationForm?.summary }}</span>
        </div>
        <span v-else />
        <div class="flex items-center gap-2">
          <Button
            :label="footerCancelLabel"
            slate
            faded
            :disabled="
              isSaving ||
              creationForm?.sending ||
              isSavingContact ||
              companyAction?.saving
            "
            @click="
              guardRelationship(
                isEditingContact || companyAction
                  ? discardRelationship
                  : () => $emit('close'),
                { leaving: !isEditingContact && !companyAction }
              )
            "
          />
          <Button
            v-if="!isEditing"
            type="submit"
            :form="creationForm?.formId"
            icon="i-lucide-check"
            :label="t('CRM_KANBAN.OPPORTUNITY.CREATE')"
            :disabled="!creationForm?.canSave"
            :is-loading="creationForm?.sending"
          />
          <Button
            v-else-if="isEditingContact"
            type="submit"
            :form="`crm-contact-form-${card.id}`"
            icon="i-lucide-check"
            :label="relationshipLabel('SAVE_CONTACT')"
            :is-loading="isSavingContact"
            :disabled="isSavingContact || !contactForm.name.trim()"
          />
          <Button
            v-else-if="companyAction"
            type="submit"
            :form="companyAction.formId"
            :icon="
              companyAction.destructive ? 'i-lucide-unlink' : 'i-lucide-check'
            "
            :label="companyAction.label"
            :ruby="companyAction.destructive"
            :is-loading="companyAction.saving"
            :disabled="companyAction.disabled"
          />
          <Button
            v-else-if="activeTab === 'summary' && canManageCards"
            :label="
              isEditing
                ? t('CRM_KANBAN.DRAWER.SAVE')
                : t('CRM_KANBAN.DRAWER.CREATE')
            "
            icon="i-lucide-check"
            :is-loading="isSaving"
            :disabled="!form.title.trim() || (!isEditing && !form.stageId)"
            @click="onSubmit"
          />
        </div>
      </div>

      <!-- Win deal dialog: value pre-filled (auto-filled by AI), confirm to win -->
      <div
        v-if="showWinDialog && canManageCards"
        class="absolute inset-0 z-[60] flex items-center justify-center bg-n-alpha-black2 p-6"
        @click.self="showWinDialog = false"
      >
        <div class="w-full max-w-sm p-5 rounded-xl bg-n-solid-1 shadow-lg">
          <h3 class="mb-1 text-base font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.DRAWER.WIN_DIALOG_TITLE') }}
          </h3>
          <p
            v-if="aiFilledValue"
            class="flex items-center gap-1 mb-3 text-xs text-n-slate-11"
          >
            <span class="i-lucide-sparkles" />
            {{ t('CRM_KANBAN.DRAWER.VALUE_AI_FILLED') }}
          </p>
          <div class="grid gap-3">
            <Input
              v-model="winAmount"
              type="number"
              :label="t('CRM_KANBAN.DRAWER.WIN_VALUE_LABEL')"
              placeholder="0,00"
            />
            <Input
              v-model="winCurrency"
              :label="t('CRM_KANBAN.DRAWER.WIN_CURRENCY_LABEL')"
              placeholder="BRL"
            />
          </div>
          <div class="flex items-center justify-end gap-2 mt-5">
            <Button
              :label="t('CRM_KANBAN.DRAWER.CANCEL')"
              slate
              faded
              sm
              @click="showWinDialog = false"
            />
            <Button
              :label="t('CRM_KANBAN.DRAWER.WIN_CONFIRM')"
              teal
              sm
              icon="i-lucide-trophy"
              @click="confirmWin"
            />
          </div>
        </div>
      </div>

      <!-- Lose deal dialog: optional reason -->
      <div
        v-if="showLoseDialog && canManageCards"
        class="absolute inset-0 z-[60] flex items-center justify-center bg-n-alpha-black2 p-6"
        @click.self="showLoseDialog = false"
      >
        <div class="w-full max-w-sm p-5 rounded-xl bg-n-solid-1 shadow-lg">
          <h3 class="mb-3 text-base font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.DRAWER.LOSE_DIALOG_TITLE') }}
          </h3>
          <Input
            v-model="loseReason"
            :label="t('CRM_KANBAN.DRAWER.LOSE_REASON_LABEL')"
            :placeholder="t('CRM_KANBAN.DRAWER.LOSE_REASON_PLACEHOLDER')"
          />
          <div class="flex items-center justify-end gap-2 mt-5">
            <Button
              :label="t('CRM_KANBAN.DRAWER.CANCEL')"
              slate
              faded
              sm
              @click="showLoseDialog = false"
            />
            <Button
              :label="t('CRM_KANBAN.DRAWER.LOSE_CONFIRM')"
              ruby
              sm
              icon="i-lucide-circle-x"
              @click="confirmLose"
            />
          </div>
        </div>
      </div>
    </div>
  </transition>
</template>
