import { computed, ref } from 'vue';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import { pad } from './meetingDates';

// AI (S5) no formulário do Google/Microsoft: sugerir horários e redigir o
// convite, com a chave da própria conta. Só aparece com CRM_AI_ENABLED; o
// servidor ainda confere e degrada sozinho (a sugestão cai em horários livres).
// Resposta que chega depois de a pessoa mudar caixa, dia, duração, card ou
// texto é descartada.
const mesmo = (a, b) => JSON.stringify(a) === JSON.stringify(b);

export const useMeetingAi = ({
  t,
  accountId,
  cardId,
  inboxId,
  date,
  duration,
  timezone,
  title,
  description,
  podeSugerir,
}) => {
  const enabled = computed(
    () => window.globalConfig?.CRM_AI_ENABLED === 'true'
  );
  const suggestions = ref([]);
  const suggesting = ref(false);
  const loaded = ref(false);
  const drafting = ref(false);
  const fromAi = ref(false);
  let suggestId = 0;
  let draftId = 0;

  const invalidate = () => {
    suggestId += 1;
    draftId += 1;
    suggesting.value = false;
    drafting.value = false;
  };
  const clear = () => {
    suggestions.value = [];
    loaded.value = false;
    fromAi.value = false;
  };
  const clearSuggestions = () => {
    suggestions.value = [];
    loaded.value = false;
  };

  const contextoSugestao = () => ({
    accountId: accountId.value,
    cardId: cardId.value,
    inboxId: inboxId.value,
    date: date.value,
    duration: Number(duration.value),
    timezone: timezone.value,
  });

  const suggest = async () => {
    if (suggesting.value || !enabled.value || !podeSugerir.value) return;
    if (!accountId.value || !cardId.value) return;
    suggestId += 1;
    const pedido = suggestId;
    const contexto = contextoSugestao();
    suggesting.value = true;
    loaded.value = false;
    const valeAinda = () =>
      pedido === suggestId && mesmo(contexto, contextoSugestao());
    try {
      const { data } = await crmMeetingsAPI.suggestTimes(contexto.accountId, {
        cardId: contexto.cardId,
        inboxId: contexto.inboxId,
        date: contexto.date,
        durationMinutes: contexto.duration,
        timezone: contexto.timezone,
      });
      if (!valeAinda()) return;
      suggestions.value = (data?.suggestions || []).filter(
        item => item?.starts_at
      );
    } catch {
      if (valeAinda()) suggestions.value = [];
    } finally {
      if (pedido === suggestId) {
        loaded.value = true;
        suggesting.value = false;
      }
    }
  };

  const contextoConvite = () => ({
    accountId: accountId.value,
    cardId: cardId.value,
    title: title.value.trim(),
    description: description.value,
  });

  const draft = async () => {
    if (drafting.value || !enabled.value) return;
    if (!accountId.value || !cardId.value) return;
    draftId += 1;
    const pedido = draftId;
    const contexto = contextoConvite();
    drafting.value = true;
    try {
      const { data } = await crmMeetingsAPI.draftInvite(contexto.accountId, {
        cardId: contexto.cardId,
        title: contexto.title,
      });
      if (pedido !== draftId || !mesmo(contexto, contextoConvite())) return;
      if (data?.description) {
        description.value = data.description;
        fromAi.value = true;
      }
    } catch {
      // Fail-safe: leave the description untouched; backend never 500s.
    } finally {
      if (pedido === draftId) drafting.value = false;
    }
  };

  // Chip "HH:mm" da sugestão e o motivo (ou "livre na agenda") na dica.
  const timeLabel = iso => {
    const quando = new Date(iso);
    if (Number.isNaN(quando.getTime())) return '';
    return `${pad(quando.getHours())}:${pad(quando.getMinutes())}`;
  };
  const reason = motivo =>
    motivo || t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AI_SUGGESTION_REASON');

  return {
    enabled,
    suggestions,
    suggesting,
    loaded,
    drafting,
    fromAi,
    invalidate,
    clear,
    clearSuggestions,
    suggest,
    draft,
    timeLabel,
    reason,
  };
};
