import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import comentarioDaConversaAPI from 'dashboard/api/comentarioDaConversa';

// Comentários na caixa (#2215): o comentário do Instagram de onde a conversa nasceu, lido ao vivo na Meta (o texto é
// de terceiro e não fica gravado), e as três ações sobre ele. `ocupado` segura os botões enquanto uma ação vai à Meta.
// Uma falha deixa tudo como estava e avisa; comentário que sumiu do Instagram vira "apagado", e a permissão retirada
// mostra o "Liberar acesso".
//
// conversationId: computed com o display_id da conversa aberta.
export const useComentarioDaConversa = ({
  conversationId,
  api = comentarioDaConversaAPI,
}) => {
  const { t } = useI18n();

  const estado = ref('carregando');
  const comentario = ref(null);
  const pode = ref({});
  const ocupado = ref(false);

  const carregar = async () => {
    const id = conversationId.value;
    if (!id) return;
    estado.value = 'carregando';
    comentario.value = null;
    pode.value = {};
    try {
      const { data } = await api.get(id);
      if (id !== conversationId.value) return;
      estado.value = data.status;
      comentario.value = data.comentario || null;
      pode.value = data.pode || {};
    } catch (error) {
      if (id !== conversationId.value) return;
      // 404: o servidor não reconhece a conversa como nascida de um comentário (sem a prova dele): o cartão some.
      estado.value =
        error?.response?.status === 404 ? 'fora' : 'meta_unavailable';
    }
  };

  const falhou = error => {
    const codigo = error?.response?.data?.error;
    if (codigo === 'comment_not_found') {
      estado.value = 'apagado';
      useAlert(t('CONVERSA_CANAL.COMENTARIO.ERRO.SUMIU'));
    } else if (codigo === 'needs_permission') {
      estado.value = 'needs_permission';
      useAlert(t('CONVERSA_CANAL.COMENTARIO.ERRO.PERMISSAO'));
    } else {
      useAlert(t('CONVERSA_CANAL.COMENTARIO.ERRO.GERAL'));
    }
  };

  // aviso: o texto já traduzido do sucesso.
  const agir = async (chamada, aviso) => {
    const id = conversationId.value;
    ocupado.value = true;
    try {
      const { data } = await chamada(id);
      if (id !== conversationId.value) return null;
      useAlert(aviso);
      return data;
    } catch (error) {
      if (id === conversationId.value) falhou(error);
      return null;
    } finally {
      ocupado.value = false;
    }
  };

  const responder = async texto => {
    const data = await agir(
      id => api.responder(id, texto),
      t('CONVERSA_CANAL.COMENTARIO.FEITO.RESPONDIDO')
    );
    if (!data) return false;
    const respostas = comentario.value.respostas || [];
    comentario.value = {
      ...comentario.value,
      respostas: [...respostas, { id: respostas.length, ...data.resposta }],
    };
    return true;
  };

  const esconder = async hidden => {
    const data = await agir(
      id => api.esconder(id, hidden),
      hidden
        ? t('CONVERSA_CANAL.COMENTARIO.FEITO.ESCONDIDO')
        : t('CONVERSA_CANAL.COMENTARIO.FEITO.MOSTRADO')
    );
    if (data) comentario.value = { ...comentario.value, escondido: hidden };
  };

  const apagar = async () => {
    const data = await agir(
      id => api.apagar(id),
      t('CONVERSA_CANAL.COMENTARIO.FEITO.APAGADO')
    );
    if (data) estado.value = 'apagado';
    return Boolean(data);
  };

  watch(conversationId, carregar, { immediate: true });

  return {
    estado,
    comentario,
    pode,
    ocupado,
    carregar,
    responder,
    esconder,
    apagar,
  };
};
