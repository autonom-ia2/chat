import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import comentarioDaConversaAPI from 'dashboard/api/comentarioDaConversa';
import { apiDemo } from './comentarioDemo';

// Comentários na caixa (#2215): o comentário do Instagram de onde a conversa nasceu, lido ao vivo na Meta (o texto é
// de terceiro e não fica gravado), e as três ações sobre ele. `ocupado` segura os botões enquanto uma ação vai à Meta;
// uma falha deixa tudo como estava e avisa.
//
// conversationId: computed com o display_id da conversa aberta.
export const useComentarioDaConversa = ({ conversationId, api } = {}) => {
  const { t } = useI18n();
  // PROTÓTIPO: a demo usa o adaptador falso.
  const fonte = api || apiDemo || comentarioDaConversaAPI;

  const estado = ref('carregando');
  const comentario = ref(null);
  const pode = ref({});
  const podeLiberar = ref(false);
  const ocupado = ref(false);

  const carregar = async () => {
    const id = conversationId.value;
    if (!id) return;
    estado.value = 'carregando';
    try {
      const { data } = await fonte.get(id);
      if (id !== conversationId.value) return;
      estado.value = data.status;
      comentario.value = data.comentario || null;
      pode.value = data.pode || {};
      podeLiberar.value = Boolean(data.pode_liberar);
    } catch {
      if (id === conversationId.value) estado.value = 'meta_unavailable';
    }
  };

  const agir = async (chamada, aviso) => {
    ocupado.value = true;
    try {
      const { data } = await chamada();
      useAlert(t(`CONVERSA_CANAL.COMENTARIO.FEITO.${aviso}`));
      return data;
    } catch (error) {
      const codigo = error?.response?.data?.error;
      useAlert(
        t(
          codigo === 'needs_permission'
            ? 'CONVERSA_CANAL.COMENTARIO.ERRO.PERMISSAO'
            : 'CONVERSA_CANAL.COMENTARIO.ERRO.GERAL'
        )
      );
      return null;
    } finally {
      ocupado.value = false;
    }
  };

  const responder = async texto => {
    const data = await agir(
      () => fonte.responder(conversationId.value, texto),
      'RESPONDIDO'
    );
    if (!data) return false;
    comentario.value = {
      ...comentario.value,
      respostas: [...(comentario.value.respostas || []), data.resposta],
    };
    return true;
  };

  const esconder = async hidden => {
    const data = await agir(
      () => fonte.esconder(conversationId.value, hidden),
      hidden ? 'ESCONDIDO' : 'MOSTRADO'
    );
    if (data) comentario.value = { ...comentario.value, escondido: hidden };
  };

  const apagar = async () => {
    const data = await agir(
      () => fonte.apagar(conversationId.value),
      'APAGADO'
    );
    if (data) estado.value = 'apagado';
  };

  watch(conversationId, carregar, { immediate: true });

  return {
    estado,
    comentario,
    pode,
    podeLiberar,
    ocupado,
    carregar,
    responder,
    esconder,
    apagar,
  };
};
