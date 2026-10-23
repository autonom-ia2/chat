// O atendente reage à mensagem (#1702), com a pele do WhatsApp ou na conversa do
// Instagram com a cara do Direct (#2113). O selo se
// atualiza pelo `message.updated` que o servidor emite ao gravar a reação. Até o eco
// chegar, vale a reação que acabou de sair (clicar de novo no mesmo emoji tira, em
// vez de mandar o mesmo outra vez). Na caixa WAHA cujo motor reage (`react` nas ações
// da conversa, #1709), o envio vai pelo mesmo cliente do #1709 (wahaMessageActions);
// no resto, pela de sempre.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import WahaMessageActionsAPI from 'dashboard/api/wahaMessageActions';
import { PELES, usePele } from './pele';
import { useInstagramDaConversa } from './instagram/useConversaDoInstagram';
import { reacoesDaMensagem } from './reacoes';
import {
  emojiParaEnviar,
  estadoDaReacao,
  reacaoDaEquipe,
} from './reacaoDoAtendente';

// mensagem: computed com { id, messageType, isPrivate, status, sourceId,
// contentAttributes, conversationId, inboxId }.
export const useReacaoDoAtendente = mensagem => {
  const { t } = useI18n();
  const pele = usePele();
  const instagram = useInstagramDaConversa();
  const conversa = useMapGetter('getSelectedChat');
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const enviando = ref(false);

  const estado = computed(() => {
    if (pele.value !== PELES.WHATSAPP && !instagram.ligado.value) {
      return { visivel: false };
    }
    const dados = mensagem.value;
    return estadoDaReacao({
      caixa: caixaPorId.value(dados.inboxId),
      conversa: conversa.value,
      mensagem: { ...dados, deleted: dados.contentAttributes?.deleted },
    });
  });

  const daConversa = computed(() =>
    reacaoDaEquipe(reacoesDaMensagem(mensagem.value.contentAttributes))
  );
  // null = sem envio esperando eco; '' = a reação foi tirada.
  const enviada = ref(null);
  watch(daConversa, () => {
    enviada.value = null;
  });
  const atual = computed(() =>
    enviada.value === null ? daConversa.value : enviada.value
  );

  const reagir = async escolhido => {
    if (enviando.value || estado.value.bloqueado) return;
    enviando.value = true;
    const { conversationId, id } = mensagem.value;
    const emoji = emojiParaEnviar(atual.value, escolhido);
    try {
      if (estado.value.pelaCaixa) {
        await WahaMessageActionsAPI.react(conversationId, id, emoji);
      } else {
        await ConversaCanalAPI.reagir(conversationId, id, emoji);
      }
      // O eco (message.updated) confirma; até lá, a tela já conta com esta.
      enviada.value = emoji;
    } catch (erro) {
      useAlert(
        erro?.response?.data?.error || t('CONVERSA_CANAL.REAGIR.FALHOU')
      );
    } finally {
      enviando.value = false;
    }
  };

  return {
    visivel: computed(() => Boolean(estado.value.visivel)),
    bloqueado: computed(() => Boolean(estado.value.bloqueado)),
    atual,
    enviando,
    reagir,
  };
};
