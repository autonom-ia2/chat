// O lado da mensagem no encaminhar (#1702), só com a pele do WhatsApp: a opção
// do menu, o botão ao lado da mídia e o checkbox do modo seleção.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { PELES, usePele } from '../pele';
import {
  LIMITE_DE_MENSAGENS,
  alternarMensagem,
  comecarSelecao,
  encaminhamentoDireto,
  encaminhavel,
  estaMarcada,
  selecao,
  temBotaoAoLado,
} from './selecaoParaEncaminhar';

// mensagem: computed com { id, conversationId, messageType, contentType, status,
// private, content, contentAttributes, attachments }; ids: computed com os ids que
// vão juntos (o álbum leva todos os itens).
export const useEncaminharDaMensagem = (mensagem, ids) => {
  const { t } = useI18n();
  const pele = usePele();

  const podeEncaminhar = computed(
    () => pele.value === PELES.WHATSAPP && encaminhavel(mensagem.value)
  );
  const botaoAoLado = computed(
    () =>
      podeEncaminhar.value && !selecao.ativa && temBotaoAoLado(mensagem.value)
  );
  const emSelecao = computed(
    () =>
      pele.value === PELES.WHATSAPP &&
      selecao.ativa &&
      selecao.conversaId === mensagem.value.conversationId
  );
  const marcada = computed(() => emSelecao.value && estaMarcada(ids.value));

  const iniciarSelecao = () =>
    comecarSelecao(mensagem.value.conversationId, ids.value);

  const alternar = () => {
    if (alternarMensagem(ids.value)) return;
    useAlert(
      t('CONVERSA_CANAL.ENCAMINHAR.LIMITE_MENSAGENS', {
        limite: LIMITE_DE_MENSAGENS,
      })
    );
  };

  const encaminharDireto = () =>
    encaminhamentoDireto(mensagem.value.conversationId, ids.value);

  return {
    podeEncaminhar,
    botaoAoLado,
    emSelecao,
    marcada,
    iniciarSelecao,
    alternar,
    encaminharDireto,
  };
};
