// #2138 — o que alimenta as linhas que abrem em "Mais": conversas anteriores,
// arquivos desta conversa, outras informações (só atributos com definição e valor,
// sem os internos do WhatsApp) e quem acompanha.
//
// Conversas e quem acompanha são pedidos aqui, com estado (carregando, erro, 403);
// quem acompanha vai também para o store, que o ⋯ do topo lê. Arquivos e
// definições já vêm do store (MessagesView e ContactPanel os pedem).
import { computed, unref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ContactAPI from 'dashboard/api/contacts';
import ConversationInboxApi from 'dashboard/api/inbox/conversation';
import types from 'dashboard/store/mutation-types';
import { NON_FILE_TYPES } from 'dashboard/components-next/message/constants';
import { ESTADO, useParteDoPainel } from './useParteDoPainel';

const temValor = valor =>
  valor !== null && valor !== undefined && String(valor).trim() !== '';

export function useListasDoContato({ contact, conversationId }) {
  const store = useStore();
  const anexos = useMapGetter('getSelectedChatAttachments');
  const definicoes = useMapGetter('attributes/getAttributesByModel');
  const acompanhantes = useMapGetter(
    'conversationWatchers/getByConversationId'
  );

  const contatoId = computed(() => unref(contact)?.id);
  const conversaId = computed(() => Number(unref(conversationId)));

  const parteDasConversas = useParteDoPainel(
    async () => {
      const { data } = await ContactAPI.getConversations(contatoId.value);
      return data.payload || [];
    },
    () => true
  );
  const parteDeQuemAcompanha = useParteDoPainel(
    async () => {
      const id = conversaId.value;
      const { data } = await ConversationInboxApi.fetchParticipants(id);
      store.commit(
        `conversationWatchers/${types.SET_CONVERSATION_PARTICIPANTS}`,
        { conversationId: id, data }
      );
      return data;
    },
    () => true
  );

  const lerConversas = () =>
    contatoId.value
      ? parteDasConversas.carregar()
      : parteDasConversas.esconder();
  const lerQuemAcompanha = () =>
    conversaId.value
      ? parteDeQuemAcompanha.carregar()
      : parteDeQuemAcompanha.esconder();

  watch(contatoId, lerConversas, { immediate: true });
  watch(conversaId, lerQuemAcompanha, { immediate: true });

  const conversas = computed(() =>
    (parteDasConversas.dados.value || []).filter(c => c.id !== conversaId.value)
  );

  const arquivos = computed(() =>
    (anexos.value || [])
      .filter(a => a.data_url && !NON_FILE_TYPES.includes(a.file_type))
      .sort((a, b) => (b.created_at || 0) - (a.created_at || 0))
  );

  const informacoes = computed(() => {
    const valores = unref(contact)?.custom_attributes || {};
    // O getter já deixa de fora os campos internos da WAHA (#2138).
    return (definicoes.value('contact_attribute') || []).filter(d =>
      temValor(valores[d.attribute_key])
    );
  });

  // Do store: o ⋯ do topo inclui ou tira a pessoa e a linha acompanha.
  const quemAcompanha = computed(() =>
    parteDeQuemAcompanha.estado.value === ESTADO.ESCONDIDO
      ? []
      : acompanhantes.value(conversaId.value) || []
  );

  const estados = computed(() => [
    parteDasConversas.estado.value,
    parteDeQuemAcompanha.estado.value,
  ]);
  const carregando = computed(() => estados.value.includes(ESTADO.CARREGANDO));
  const comErro = computed(() => estados.value.includes(ESTADO.ERRO));
  const tentarDeNovo = () => {
    if (parteDasConversas.estado.value === ESTADO.ERRO) lerConversas();
    if (parteDeQuemAcompanha.estado.value === ESTADO.ERRO) lerQuemAcompanha();
  };

  return {
    conversas,
    arquivos,
    informacoes,
    quemAcompanha,
    carregando,
    comErro,
    tentarDeNovo,
  };
}
