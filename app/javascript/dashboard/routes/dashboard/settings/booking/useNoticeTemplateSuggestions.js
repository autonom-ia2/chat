import { computed, onBeforeUnmount, ref, watch } from 'vue';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import { templateChoice } from './bookingNotices';
import { NOTICE_KINDS } from './constants';

// Modelos de aviso do WhatsApp oficial (#1272). Ao escolher a caixa oficial, a
// IA sugere a mensagem aprovada de cada aviso e ela entra só nos avisos ainda
// vazios, uma vez por caixa: escolha da pessoa (inclusive "nenhuma") não é
// trocada. Sem IA, a tela segue com a escolha à mão.
//
// Criar na Meta (administrador, WhatsApp Cloud): o clique enfileira e cada
// aviso mostra o seu estado (`requests`): sending → pending → approved, ou
// failed/rejected com o motivo. Enquanto houver "sending", a tela consulta o
// estado de tempos em tempos, sem recarregar.
export const POLL_MS = 3000;

const stateOf = entry => entry?.state || '';

export const useNoticeTemplateSuggestions = ({
  pageId,
  form,
  inbox,
  kinds,
  onChange,
}) => {
  const suggestions = ref({});
  const requests = ref({});
  const canCreate = ref(false);
  const loading = ref(false);
  const creating = ref(false);
  const createFailed = ref(false);
  // Avisos já preenchidos por aqui ou mexidos pela pessoa: não se preenche de novo.
  let applied = new Set();
  let lastRequest = 0;
  let pollTimer = null;
  let polling = false;

  const current = () => form().noticeTemplates || {};

  // Preenche os avisos vazios do jogo: com a sugestão da IA ou com o modelo
  // pronto que a Meta acabou de aprovar.
  const fillEmpty = () => {
    const filled = current();
    const additions = kinds.value
      .filter(kind => !filled[kind] && !applied.has(kind))
      .map(kind => {
        const request = requests.value[kind];
        const choice =
          stateOf(request) === 'approved' ? request : suggestions.value[kind];
        return [kind, choice];
      })
      .filter(([, choice]) => choice?.name && choice?.language);
    if (!additions.length) return;
    additions.forEach(([kind]) => applied.add(kind));
    onChange({
      noticeTemplates: {
        ...filled,
        ...Object.fromEntries(
          additions.map(([kind, choice]) => [
            kind,
            { name: choice.name, language: choice.language },
          ])
        ),
      },
    });
  };

  const stopPolling = () => {
    clearTimeout(pollTimer);
    pollTimer = null;
    polling = false;
  };

  const hasSending = () =>
    Object.values(requests.value).some(entry => stateOf(entry) === 'sending');

  const poll = async request => {
    pollTimer = null;
    polling = true;
    try {
      const { data } = await BookingPagesAPI.noticeTemplateRequests(
        pageId(),
        inbox.value.id
      );
      if (request !== lastRequest) return;
      requests.value = data?.payload?.requests || {};
      fillEmpty();
    } catch (error) {
      // Consulta que falhou: tenta de novo na próxima volta.
    }
    if (request !== lastRequest) return;
    polling = false;
    if (hasSending()) {
      pollTimer = setTimeout(() => poll(request), POLL_MS);
    }
  };

  const schedulePoll = () => {
    if (pollTimer || polling || !inbox.value || !hasSending()) return;
    const request = lastRequest;
    pollTimer = setTimeout(() => poll(request), POLL_MS);
  };

  // Cada troca de caixa é um pedido novo: resposta de pedido antigo não vale
  // (A → B → A não aplica a resposta da primeira ida a A).
  const load = async chosen => {
    lastRequest += 1;
    const request = lastRequest;
    stopPolling();
    suggestions.value = {};
    requests.value = {};
    canCreate.value = false;
    createFailed.value = false;
    applied = new Set();
    loading.value = false;
    if (!chosen?.needs_templates || !pageId()) return;
    loading.value = true;
    try {
      const { data } = await BookingPagesAPI.noticeTemplateSuggestions(
        pageId(),
        chosen.id,
        NOTICE_KINDS.filter(kind => !current()[kind])
      );
      if (request !== lastRequest) return;
      const payload = data?.payload || {};
      suggestions.value = payload.suggestions || {};
      requests.value = payload.requests || {};
      canCreate.value = Boolean(payload.can_create);
      fillEmpty();
      schedulePoll();
    } catch (error) {
      // Sem sugestão: a escolha continua à mão.
    } finally {
      if (request === lastRequest) loading.value = false;
    }
  };

  watch(inbox, load, { immediate: true });
  watch(kinds, fillEmpty);
  onBeforeUnmount(() => {
    lastRequest += 1;
    stopPolling();
  });

  const isSuggested = kind => {
    const suggestion = suggestions.value[kind];
    return Boolean(
      suggestion &&
        templateChoice(suggestion) === templateChoice(current()[kind])
    );
  };

  // Avisos sem mensagem escolhida, sem sugestão e sem pedido na Meta.
  const kindsToCreate = computed(() =>
    kinds.value.filter(
      kind =>
        !current()[kind] && !suggestions.value[kind] && !requests.value[kind]
    )
  );
  const showCreate = computed(
    () => canCreate.value && kindsToCreate.value.length > 0
  );
  // "Tentar de novo" só quando a criação falhou e para quem pode criar.
  const canRetry = kind =>
    canCreate.value && stateOf(requests.value[kind]) === 'failed';

  const send = async wanted => {
    if (creating.value || !inbox.value || !wanted.length) return;
    const request = lastRequest;
    creating.value = true;
    createFailed.value = false;
    try {
      const { data } = await BookingPagesAPI.createNoticeTemplates(
        pageId(),
        inbox.value.id,
        wanted
      );
      if (request !== lastRequest) return;
      requests.value = data?.payload?.requests || requests.value;
      schedulePoll();
    } catch (error) {
      createFailed.value = true;
    } finally {
      creating.value = false;
    }
  };

  return {
    suggestions,
    requests,
    loading,
    creating,
    createFailed,
    showCreate,
    isSuggested,
    canRetry,
    markTouched: kind => applied.add(kind),
    createOnMeta: () => send(kindsToCreate.value),
    retry: kind => send([kind]),
  };
};
