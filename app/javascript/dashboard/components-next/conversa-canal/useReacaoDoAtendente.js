// O atendente reage à mensagem (#1702), só com a pele do WhatsApp. O selo se
// atualiza pelo `message.updated` que o servidor emite ao gravar a reação.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import { PELES, usePele } from './pele';
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
  const conversa = useMapGetter('getSelectedChat');
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const enviando = ref(false);

  const estado = computed(() => {
    if (pele.value !== PELES.WHATSAPP) return { visivel: false };
    const dados = mensagem.value;
    return estadoDaReacao({
      caixa: caixaPorId.value(dados.inboxId),
      conversa: conversa.value,
      mensagem: { ...dados, deleted: dados.contentAttributes?.deleted },
    });
  });

  const atual = computed(() =>
    reacaoDaEquipe(reacoesDaMensagem(mensagem.value.contentAttributes))
  );

  const reagir = async escolhido => {
    if (enviando.value || estado.value.bloqueado) return;
    enviando.value = true;
    const { conversationId, id } = mensagem.value;
    try {
      await ConversaCanalAPI.reagir(
        conversationId,
        id,
        emojiParaEnviar(atual.value, escolhido)
      );
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
