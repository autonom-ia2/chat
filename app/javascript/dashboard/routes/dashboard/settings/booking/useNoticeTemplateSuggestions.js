import { ref, watch, onBeforeUnmount } from 'vue';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import { templateChoice } from './bookingNotices';
import { NOTICE_KINDS } from './constants';

// Modelos de aviso do WhatsApp oficial (#1272). Ao escolher a caixa oficial, a
// IA sugere a mensagem aprovada de cada aviso e ela entra só nos avisos ainda
// vazios, uma vez por caixa: escolha da pessoa (inclusive "nenhuma") não é
// trocada. Sem IA, a tela segue com a escolha à mão.
//
// O botão "Criar os modelos na Meta" (v1) saiu em #1612: os modelos dos avisos
// agora são os v2, que o sistema cria sozinho com a autorização do dono.
export const useNoticeTemplateSuggestions = ({
  pageId,
  form,
  inbox,
  kinds,
  onChange,
}) => {
  const suggestions = ref({});
  const loading = ref(false);
  // Avisos já preenchidos por aqui ou mexidos pela pessoa: não se preenche de novo.
  let applied = new Set();
  let lastRequest = 0;

  const current = () => form().noticeTemplates || {};

  // Preenche com a sugestão da IA os avisos vazios do jogo.
  const fillEmpty = () => {
    const filled = current();
    const additions = kinds.value
      .filter(kind => !filled[kind] && !applied.has(kind))
      .map(kind => [kind, suggestions.value[kind]])
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

  // Cada troca de caixa é um pedido novo: resposta de pedido antigo não vale
  // (A → B → A não aplica a resposta da primeira ida a A).
  const load = async chosen => {
    lastRequest += 1;
    const request = lastRequest;
    suggestions.value = {};
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
      suggestions.value = data?.payload?.suggestions || {};
      fillEmpty();
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
  });

  const isSuggested = kind => {
    const suggestion = suggestions.value[kind];
    return Boolean(
      suggestion &&
        templateChoice(suggestion) === templateChoice(current()[kind])
    );
  };

  return {
    suggestions,
    loading,
    isSuggested,
    markTouched: kind => applied.add(kind),
  };
};
