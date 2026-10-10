<script setup>
// Link de agenda por cliente (#1190, J1): "Agendar" na conversa e no card gera (ou reaproveita) o link
// do cliente, com o texto pronto para enviar na conversa ou copiar para qualquer canal. Autocontido:
// só aparece com a flag da conta `crm_booking_v2` e o calendário de reuniões da instalação ligados, e para quem vê
// os cards do CRM (mesma régua do backend, `HostEligibility`: administrador, agente sem função ou função com
// `crm_view`/`crm_admin`).
import { computed, ref, useId, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingInvitesAPI from 'dashboard/api/crmBookingInvites';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import {
  BADGE_STATES,
  formatValidUntil,
  inviteState,
  isActiveInvite,
  stateLabelKey,
  stateToneClass,
} from './bookingInvite';

const props = defineProps({
  // Um dos dois: a conversa aberta (cabeçalho) ou o card (gaveta do CRM).
  conversation: { type: Object, default: null },
  card: { type: Object, default: null },
  // Selo com o estado do último link ao lado do botão (card).
  showStatus: { type: Boolean, default: false },
});

const FEATURE_FLAG = 'crm_booking_v2';
const MANAGE_KEY = 'agendamento_manage';
const SETTINGS_ROUTE = 'settings_booking';
const ERROR_DISABLED = 'crm.booking_v2.disabled';
const ERROR_NO_PAGE = 'crm.booking_v2.no_page';
const ERROR_CANNOT_REPLY = 'crm.booking_v2.cannot_reply';
const HTTP_UNAUTHORIZED = 401;

const store = useStore();
const router = useRouter();
const { t, locale } = useI18n();
const { canViewCrm } = useCrmPermissions();
const textId = useId();

const dialogRef = ref(null);
const cancelConfirmRef = ref(null);
const isLoading = ref(false);
const isSending = ref(false);
const isCanceling = ref(false);
const isDisabledOnServer = ref(false);
const hasNoPage = ref(false);
const pages = ref([]);
const invite = ref(null);
const latestInvite = ref(null);
const pageId = ref('');
const text = ref('');

const accountId = computed(() => store.getters.getCurrentAccountId);
const isEnabled = computed(
  () =>
    window.globalConfig?.CRM_CALENDAR_MEETINGS_ENABLED === 'true' &&
    store.getters['accounts/isFeatureEnabledonAccount'](
      accountId.value,
      FEATURE_FLAG
    ) &&
    canViewCrm.value &&
    !isDisabledOnServer.value
);

// A API recebe o número da conversa no painel (display_id): no cabeçalho é o `id` da conversa; no card,
// `conversation_id` é o id do banco, então vale o `display_id` da conversa principal.
const conversationId = computed(
  () => props.conversation?.id || props.card?.conversation?.display_id || null
);
const cardId = computed(() => props.card?.id || null);
const scope = computed(() =>
  cardId.value
    ? { card_id: cardId.value }
    : { conversation_id: conversationId.value }
);
const hasScope = computed(() => Boolean(cardId.value || conversationId.value));

const contactName = computed(
  () =>
    invite.value?.contact?.name ||
    props.card?.contact?.name ||
    props.conversation?.meta?.sender?.name ||
    ''
);
const title = computed(() =>
  contactName.value
    ? t('CRM_KANBAN.BOOKING_INVITE.TITLE', { name: contactName.value })
    : t('CRM_KANBAN.BOOKING_INVITE.TITLE_NO_NAME')
);

const pageOptions = computed(() =>
  pages.value.map(page => ({ value: page.id, label: page.title }))
);
const pageTitle = computed(
  () => invite.value?.booking_page?.title || pages.value[0]?.title || ''
);
const validUntil = computed(() =>
  formatValidUntil(invite.value?.expires_at, locale.value)
);
const isInviteActive = computed(() => isActiveInvite(invite.value));
const shownState = computed(() => inviteState(invite.value));
const textHasLink = computed(
  () => Boolean(invite.value?.url) && text.value.includes(invite.value.url)
);

const badgeState = computed(() => {
  const state = inviteState(latestInvite.value);
  return BADGE_STATES.includes(state) ? state : '';
});

// Admin ou função com `agendamento_manage` vê o atalho para CRM › Agendamento (J8-A3).
const canOpenSettings = computed(() => {
  if (store.getters.getCurrentRole === 'administrator') return true;
  return getUserPermissions(
    store.getters.getCurrentUser,
    accountId.value
  ).includes(MANAGE_KEY);
});
const showSettingsShortcut = computed(
  () => canOpenSettings.value && router.hasRoute(SETTINGS_ROUTE)
);

const errorCode = error => error?.response?.data?.error;

// 401 = a pessoa não tem acesso a isto; senão a frase de quem chamou.
const alertError = (error, message) =>
  useAlert(
    error?.response?.status === HTTP_UNAUTHORIZED
      ? t('CRM_KANBAN.BOOKING_INVITE.ERRORS.FORBIDDEN')
      : message
  );

const useInvite = value => {
  invite.value = value;
  latestInvite.value = value;
  text.value = value?.text || '';
  pageId.value = value?.booking_page?.id ?? pageId.value;
};

const fetchInvites = async () => {
  const { data } = await BookingInvitesAPI.index(scope.value);
  pages.value = data?.pages || [];
  latestInvite.value = data?.payload?.[0] || null;
  return latestInvite.value;
};

const createInvite = async bookingPageId => {
  const { data } = await BookingInvitesAPI.create({
    bookingPageId: bookingPageId || undefined,
    cardId: cardId.value || undefined,
    conversationId: conversationId.value || undefined,
  });
  useInvite(data.payload);
};

const handleLoadError = error => {
  const code = errorCode(error);
  if (code === ERROR_DISABLED) {
    isDisabledOnServer.value = true;
    dialogRef.value?.close();
    return;
  }
  if (code === ERROR_NO_PAGE) {
    hasNoPage.value = true;
    return;
  }
  alertError(error, t('CRM_KANBAN.BOOKING_INVITE.ERRORS.LOAD'));
};

const prepareInvite = async () => {
  isLoading.value = true;
  hasNoPage.value = false;
  try {
    const latest = await fetchInvites();
    if (isActiveInvite(latest)) {
      useInvite(latest);
    } else if (!pages.value.length) {
      hasNoPage.value = true;
    } else {
      await createInvite(pages.value[0].id);
    }
  } catch (error) {
    handleLoadError(error);
  } finally {
    isLoading.value = false;
  }
};

const openPanel = () => {
  dialogRef.value?.open();
  prepareInvite();
};

const closePanel = () => dialogRef.value?.close();

const changePage = async () => {
  if (pageId.value === invite.value?.booking_page?.id) return;
  isLoading.value = true;
  try {
    await createInvite(pageId.value);
  } catch (error) {
    handleLoadError(error);
  } finally {
    isLoading.value = false;
  }
};

// Copiado = enviado por outro canal (#1194): o painel de resultados conta. Se o registro falhar, o link já
// está copiado; a pessoa não precisa fazer nada, então não há aviso de erro.
const markCopied = async () => {
  try {
    const { data } = await BookingInvitesAPI.copied(invite.value.id);
    useInvite({ ...data.payload, text: text.value });
  } catch {
    // Só a contagem fica sem este envio; o painel continua certo para o resto.
  }
};

const copyLink = async () => {
  try {
    await copyTextToClipboard(invite.value.url);
    useAlert(t('CRM_KANBAN.BOOKING_INVITE.COPIED'));
  } catch {
    useAlert(t('CRM_KANBAN.BOOKING_INVITE.ERRORS.COPY'));
    return;
  }
  await markCopied();
};

const sendInConversation = async () => {
  isSending.value = true;
  try {
    const { data } = await BookingInvitesAPI.deliver(invite.value.id, {
      conversationId: conversationId.value,
      text: text.value,
    });
    useInvite({ ...data.payload, text: text.value });
    useAlert(t('CRM_KANBAN.BOOKING_INVITE.SENT'));
    closePanel();
  } catch (error) {
    alertError(
      error,
      errorCode(error) === ERROR_CANNOT_REPLY
        ? t('CRM_KANBAN.BOOKING_INVITE.ERRORS.CANNOT_REPLY')
        : t('CRM_KANBAN.BOOKING_INVITE.ERRORS.SEND')
    );
  } finally {
    isSending.value = false;
  }
};

// Cancelar é definitivo: pede confirmação num diálogo por cima (foco nele; Esc ou "Voltar" desistem).
const askCancel = () => cancelConfirmRef.value?.open();

const cancelLink = async () => {
  isCanceling.value = true;
  try {
    await BookingInvitesAPI.cancel(invite.value.id);
    useInvite({ ...invite.value, state: 'canceled' });
    useAlert(t('CRM_KANBAN.BOOKING_INVITE.CANCELED'));
  } catch (error) {
    alertError(error, t('CRM_KANBAN.BOOKING_INVITE.ERRORS.CANCEL'));
  } finally {
    isCanceling.value = false;
    cancelConfirmRef.value?.close();
  }
};

const newLink = async () => {
  isLoading.value = true;
  try {
    await createInvite(pageId.value || pages.value[0]?.id);
  } catch (error) {
    handleLoadError(error);
  } finally {
    isLoading.value = false;
  }
};

const openSettings = () => {
  closePanel();
  router.push({
    name: SETTINGS_ROUTE,
    params: { accountId: accountId.value },
  });
};

// O selo do card mostra o último link sem abrir o painel.
watch(
  () => [props.showStatus, isEnabled.value, cardId.value],
  async ([showStatus, enabled, id]) => {
    if (!showStatus || !enabled || !id) return;
    try {
      await fetchInvites();
    } catch (error) {
      if (errorCode(error) === ERROR_DISABLED) isDisabledOnServer.value = true;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div v-if="isEnabled && hasScope" class="flex items-center gap-2">
    <NextButton
      type="button"
      icon="i-lucide-calendar-plus"
      :label="t('CRM_KANBAN.BOOKING_INVITE.BUTTON')"
      :title="t('CRM_KANBAN.BOOKING_INVITE.BUTTON_HINT')"
      aria-haspopup="dialog"
      slate
      faded
      sm
      class="relative before:absolute before:inset-x-0 before:-inset-y-1.5"
      data-booking-invite-trigger
      @click="openPanel"
    />
    <span
      v-if="showStatus && badgeState"
      class="rounded-full px-2 py-0.5 text-xs font-medium"
      :class="stateToneClass(badgeState)"
      data-booking-invite-badge
    >
      {{ t(stateLabelKey(badgeState)) }}
    </span>

    <Dialog
      ref="dialogRef"
      :title="title"
      :show-cancel-button="false"
      :show-confirm-button="false"
      width="md"
    >
      <div
        v-if="isLoading && !invite"
        role="status"
        class="py-6 text-center text-sm text-n-slate-11"
      >
        {{ t('CRM_KANBAN.BOOKING_INVITE.LOADING') }}
      </div>

      <div v-else-if="hasNoPage" class="flex flex-col gap-4" data-booking-empty>
        <p class="mb-0 text-sm text-n-slate-12">
          {{
            canOpenSettings
              ? t('CRM_KANBAN.BOOKING_INVITE.EMPTY.ADMIN')
              : t('CRM_KANBAN.BOOKING_INVITE.EMPTY.AGENT')
          }}
        </p>
        <NextButton
          v-if="showSettingsShortcut"
          type="button"
          lg
          icon="i-lucide-settings"
          :label="t('CRM_KANBAN.BOOKING_INVITE.EMPTY.OPEN_SETTINGS')"
          data-booking-open-settings
          @click="openSettings"
        />
      </div>

      <div v-else-if="invite" class="flex flex-col gap-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="mb-0 text-sm text-n-slate-11">
            <template v-if="pageOptions.length <= 1">
              {{ t('CRM_KANBAN.BOOKING_INVITE.PAGE', { title: pageTitle }) }}
              ·
            </template>
            {{
              t('CRM_KANBAN.BOOKING_INVITE.VALID_UNTIL', { date: validUntil })
            }}
          </p>
          <span
            role="status"
            class="rounded-full px-2 py-0.5 text-xs font-medium"
            :class="stateToneClass(shownState)"
            data-booking-invite-state
          >
            {{ t(stateLabelKey(shownState)) }}
          </span>
        </div>

        <ChoiceSelect
          v-if="pageOptions.length > 1"
          v-model="pageId"
          :options="pageOptions"
          :aria-label="t('CRM_KANBAN.BOOKING_INVITE.PAGE_LABEL')"
          :disabled="isLoading"
          @change="changePage"
        />

        <template v-if="isInviteActive">
          <div class="flex flex-col gap-1">
            <label :for="textId" class="text-sm font-medium text-n-slate-12">
              {{ t('CRM_KANBAN.BOOKING_INVITE.TEXT_LABEL') }}
            </label>
            <textarea
              :id="textId"
              v-model="text"
              rows="4"
              class="w-full resize-y rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 focus:outline-2 focus:outline-n-brand"
              :aria-describedby="textHasLink ? undefined : `${textId}-hint`"
              data-booking-invite-text
            />
            <p
              v-if="!textHasLink"
              :id="`${textId}-hint`"
              class="mb-0 text-xs text-n-ruby-11"
            >
              {{ t('CRM_KANBAN.BOOKING_INVITE.TEXT_NEEDS_LINK') }}
            </p>
          </div>

          <div class="flex flex-col gap-2 sm:flex-row">
            <NextButton
              v-if="conversationId"
              type="button"
              lg
              class="w-full sm:flex-1"
              icon="i-lucide-send"
              :label="t('CRM_KANBAN.BOOKING_INVITE.SEND')"
              :is-loading="isSending"
              :disabled="!textHasLink || isSending"
              data-booking-send
              @click="sendInConversation"
            />
            <NextButton
              type="button"
              lg
              class="w-full sm:flex-1"
              :variant="conversationId ? 'outline' : 'solid'"
              :color="conversationId ? 'slate' : 'blue'"
              icon="i-lucide-copy"
              :label="t('CRM_KANBAN.BOOKING_INVITE.COPY')"
              data-booking-copy
              @click="copyLink"
            />
          </div>
        </template>

        <NextButton
          v-else
          type="button"
          lg
          icon="i-lucide-refresh-cw"
          :label="t('CRM_KANBAN.BOOKING_INVITE.NEW_LINK')"
          :is-loading="isLoading"
          data-booking-new
          @click="newLink"
        />
      </div>

      <div class="flex items-center justify-between gap-2">
        <NextButton
          v-if="invite && isInviteActive && !hasNoPage"
          type="button"
          ghost
          ruby
          class="min-h-11"
          :label="t('CRM_KANBAN.BOOKING_INVITE.CANCEL_LINK')"
          :is-loading="isCanceling"
          data-booking-cancel
          @click="askCancel"
        />
        <span v-else />
        <NextButton
          type="button"
          ghost
          slate
          class="min-h-11"
          :label="t('CRM_KANBAN.BOOKING_INVITE.CLOSE')"
          data-booking-close
          @click="closePanel"
        />
      </div>
    </Dialog>

    <Dialog
      ref="cancelConfirmRef"
      type="alert"
      :title="t('CRM_KANBAN.BOOKING_INVITE.CANCEL_CONFIRM.TITLE')"
      :description="t('CRM_KANBAN.BOOKING_INVITE.CANCEL_CONFIRM.DESCRIPTION')"
      :cancel-button-label="t('CRM_KANBAN.BOOKING_INVITE.CANCEL_CONFIRM.BACK')"
      :confirm-button-label="t('CRM_KANBAN.BOOKING_INVITE.CANCEL_CONFIRM.YES')"
      :is-loading="isCanceling"
      width="sm"
      @confirm="cancelLink"
    />
  </div>
</template>
