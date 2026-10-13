import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import BookingInvitesAPI from 'dashboard/api/crmBookingInvites';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import { useBookingInviteAvailable } from './useBookingInviteAvailable';
import {
  BADGE_STATES,
  formatValidUntil,
  inviteState,
  isActiveInvite,
} from './bookingInvite';

// Link de agenda por cliente (#1190): gerar (ou reaproveitar) o link, trocar a
// página, enviar na conversa, copiar, cancelar e gerar outro. O botão do
// cabeçalho da conversa (BookingInviteButton, numa janela) e a tela "Mandar o
// link" do card do funil (#1423, dentro da gaveta) usam esta mesma lógica; cada
// um só decide onde mostrar.
const MANAGE_KEY = 'agendamento_manage';
const SETTINGS_ROUTE = 'settings_booking';
const ERROR_DISABLED = 'crm.booking_v2.disabled';
const ERROR_NO_PAGE = 'crm.booking_v2.no_page';
const ERROR_CANNOT_REPLY = 'crm.booking_v2.cannot_reply';
const HTTP_UNAUTHORIZED = 401;

export const useBookingInvite = ({ conversation, card, withStatus }) => {
  const store = useStore();
  const router = useRouter();
  const { t, locale } = useI18n();

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
  const isAvailable = useBookingInviteAvailable();
  const isEnabled = computed(
    () => isAvailable.value && !isDisabledOnServer.value
  );

  // A API recebe o número da conversa no painel (display_id): no cabeçalho é o
  // `id` da conversa; no card, `conversation_id` é o id do banco, então vale o
  // `display_id` da conversa principal.
  const conversationId = computed(
    () => conversation.value?.id || card.value?.conversation?.display_id || null
  );
  const cardId = computed(() => card.value?.id || null);
  const scope = computed(() =>
    cardId.value
      ? { card_id: cardId.value }
      : { conversation_id: conversationId.value }
  );
  const hasScope = computed(() =>
    Boolean(cardId.value || conversationId.value)
  );

  const contactName = computed(
    () =>
      invite.value?.contact?.name ||
      card.value?.contact?.name ||
      conversation.value?.meta?.sender?.name ||
      ''
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

  // Admin ou função com `agendamento_manage` vê o atalho para CRM › Agendamento.
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

  // Resposta de outro card ou conversa (troca rápida) não vale para este:
  // volta `undefined` (diferente de `null`, que é "nenhum link ainda").
  const fetchInvites = async () => {
    const pedido = JSON.stringify(scope.value);
    const { data } = await BookingInvitesAPI.index(scope.value);
    if (pedido !== JSON.stringify(scope.value)) return undefined;
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
      return;
    }
    if (code === ERROR_NO_PAGE) {
      hasNoPage.value = true;
      return;
    }
    alertError(error, t('CRM_KANBAN.BOOKING_INVITE.ERRORS.LOAD'));
  };

  const withLoading = async action => {
    isLoading.value = true;
    try {
      await action();
    } catch (error) {
      handleLoadError(error);
    } finally {
      isLoading.value = false;
    }
  };

  const prepareInvite = () => {
    hasNoPage.value = false;
    return withLoading(async () => {
      const latest = await fetchInvites();
      if (latest === undefined) return;
      if (isActiveInvite(latest)) useInvite(latest);
      else if (!pages.value.length) hasNoPage.value = true;
      else await createInvite(pages.value[0].id);
    });
  };

  const changePage = () => {
    if (pageId.value === invite.value?.booking_page?.id) return undefined;
    return withLoading(() => createInvite(pageId.value));
  };

  const newLink = () =>
    withLoading(() => createInvite(pageId.value || pages.value[0]?.id));

  // Copiado = enviado por outro canal (#1194): o painel de resultados conta. Se
  // o registro falhar, o link já está copiado; a pessoa não precisa fazer nada,
  // então não há aviso de erro.
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

  // Devolve true quando a mensagem saiu, para quem chamou fechar a tela.
  const sendInConversation = async () => {
    isSending.value = true;
    try {
      const { data } = await BookingInvitesAPI.deliver(invite.value.id, {
        conversationId: conversationId.value,
        text: text.value,
      });
      useInvite({ ...data.payload, text: text.value });
      useAlert(t('CRM_KANBAN.BOOKING_INVITE.SENT'));
      return true;
    } catch (error) {
      alertError(
        error,
        errorCode(error) === ERROR_CANNOT_REPLY
          ? t('CRM_KANBAN.BOOKING_INVITE.ERRORS.CANNOT_REPLY')
          : t('CRM_KANBAN.BOOKING_INVITE.ERRORS.SEND')
      );
      return false;
    } finally {
      isSending.value = false;
    }
  };

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
    }
  };

  const openSettings = () =>
    router.push({
      name: SETTINGS_ROUTE,
      params: { accountId: accountId.value },
    });

  // O selo do card mostra o último link sem abrir nada.
  watch(
    () => [withStatus.value, isEnabled.value, cardId.value],
    async ([status, enabled, id]) => {
      if (!status || !enabled || !id) return;
      try {
        await fetchInvites();
      } catch (error) {
        if (errorCode(error) === ERROR_DISABLED)
          isDisabledOnServer.value = true;
      }
    },
    { immediate: true }
  );

  return {
    isLoading,
    isSending,
    isCanceling,
    isDisabledOnServer,
    isEnabled,
    hasNoPage,
    hasScope,
    invite,
    pageId,
    text,
    conversationId,
    contactName,
    pageOptions,
    pageTitle,
    validUntil,
    isInviteActive,
    shownState,
    textHasLink,
    badgeState,
    canOpenSettings,
    showSettingsShortcut,
    prepareInvite,
    changePage,
    newLink,
    copyLink,
    sendInConversation,
    cancelLink,
    openSettings,
  };
};
