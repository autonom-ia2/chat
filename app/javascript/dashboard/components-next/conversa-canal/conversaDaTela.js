// A conversa que a tela mostra (#3165). Na tela da conversa é a aberta no painel
// (`getSelectedChat`). Outra tela que mostra uma conversa só para ler (o card do CRM)
// fornece a dela, com as mensagens já carregadas, e a lista, os balões e as peles
// (WhatsApp, e-mail, Instagram) passam a ler essa — sem trocar a conversa aberta.
// Quem fornece também liga o "só leitura": nada que escreve aparece.
import { computed, inject, provide } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const CHAVE = Symbol('conversaDaTela');

// conversa: computed com o objeto da conversa no formato do painel (inclui `messages`).
// anexos: computed com os anexos das mensagens carregadas (galeria de fotos e vídeos).
export const fornecerConversaDaTela = ({ conversa, anexos }) =>
  provide(CHAVE, { conversa, anexos });

const useFornecida = () => inject(CHAVE, null);

export const useConversaDaTela = () => {
  const fornecida = useFornecida();
  const aberta = useMapGetter('getSelectedChat');
  return fornecida ? fornecida.conversa : aberta;
};

export const useAnexosDaTela = () => {
  const fornecida = useFornecida();
  const daAberta = useMapGetter('getSelectedChatAttachments');
  return fornecida ? fornecida.anexos : daAberta;
};

export const useSoLeitura = () => {
  const fornecida = useFornecida();
  return computed(() => fornecida !== null);
};
