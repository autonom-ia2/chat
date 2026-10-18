// As reações do balão (#1702), só com a pele do WhatsApp. Sem pele, lista vazia e o
// balão fica como sempre.
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useMessageContext } from '../message/provider.js';
import { reacoesDaMensagem } from './reacoes';

export const useReacoesDoBalao = ativa => {
  const { contentAttributes, orientation } = useMessageContext();
  const conversa = useMapGetter('getSelectedChat');

  const reacoes = computed(() =>
    ativa.value ? reacoesDaMensagem(contentAttributes?.value) : []
  );

  return {
    reacoes,
    temReacoes: computed(() => reacoes.value.length > 0),
    lado: orientation,
    nomeDoCliente: computed(() => conversa.value?.meta?.sender?.name || ''),
  };
};
