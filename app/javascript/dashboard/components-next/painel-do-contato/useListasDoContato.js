// #2138 — o que alimenta as linhas que abrem: conversas anteriores, arquivos desta
// conversa, outras informações (só atributos com definição e valor) e quem acompanha.
// Tudo de getters e ações que o painel antigo já usa; nenhum pedido novo.
import { computed, unref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { NON_FILE_TYPES } from 'dashboard/components-next/message/constants';

const temValor = valor =>
  valor !== null && valor !== undefined && String(valor).trim() !== '';

export function useListasDoContato({ contact, conversationId }) {
  const store = useStore();
  const conversasDoContato = useMapGetter(
    'contactConversations/getContactConversation'
  );
  const anexos = useMapGetter('getSelectedChatAttachments');
  const definicoes = useMapGetter('attributes/getAttributesByModel');
  const acompanhantes = useMapGetter(
    'conversationWatchers/getByConversationId'
  );

  const contatoId = computed(() => unref(contact)?.id);
  const conversaId = computed(() => Number(unref(conversationId)));

  watch(
    contatoId,
    id => {
      if (id) store.dispatch('contactConversations/get', id);
    },
    { immediate: true }
  );
  watch(
    conversaId,
    id => {
      if (id)
        store.dispatch('conversationWatchers/show', { conversationId: id });
    },
    { immediate: true }
  );

  const conversas = computed(() =>
    (conversasDoContato.value(contatoId.value) || []).filter(
      c => c.id !== conversaId.value
    )
  );

  const arquivos = computed(() =>
    (anexos.value || [])
      .filter(a => a.data_url && !NON_FILE_TYPES.includes(a.file_type))
      .sort((a, b) => (b.created_at || 0) - (a.created_at || 0))
  );

  const informacoes = computed(() => {
    const valores = unref(contact)?.custom_attributes || {};
    return (definicoes.value('contact_attribute') || [])
      .filter(d => temValor(valores[d.attribute_key]))
      .map(d => ({
        chave: d.attribute_key,
        rotulo: d.attribute_display_name,
        valor: valores[d.attribute_key],
        tipo: d.attribute_display_type,
      }));
  });

  const quemAcompanha = computed(
    () => acompanhantes.value(conversaId.value) || []
  );

  return { conversas, arquivos, informacoes, quemAcompanha };
}
