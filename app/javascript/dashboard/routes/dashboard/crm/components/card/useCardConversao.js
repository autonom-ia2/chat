import { ref, watch } from 'vue';
import MetaConversionsAPI from 'dashboard/api/metaConversions';

// #1423 — o aviso ao Facebook e ao Instagram (MT-01): só a linha deste card,
// buscada ao abrir. Resposta de outro card (troca rápida) é descartada.
export const useCardConversao = ({ mostrar, cardId }) => {
  const conversao = ref(null);
  const buscar = async () => {
    conversao.value = null;
    if (!mostrar.value || !cardId.value) return;
    const pedido = cardId.value;
    try {
      const { data } = await MetaConversionsAPI.getForCards([pedido]);
      if (pedido !== cardId.value) return;
      conversao.value =
        (data?.payload || []).find(
          linha => Number(linha.card_id) === Number(pedido)
        ) || null;
    } catch {
      if (pedido === cardId.value) conversao.value = null;
    }
  };
  watch(() => [mostrar.value, cardId.value], buscar, { immediate: true });
  return conversao;
};
