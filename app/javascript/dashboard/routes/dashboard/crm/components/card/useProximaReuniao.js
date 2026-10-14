import { ref, watch } from 'vue';
import { startOfDay } from 'date-fns';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';

// #1423 — a próxima reunião do card, de hoje em diante (RS-01), com o mesmo
// pedido da gaveta antiga: a lista traz a primeira e o detalhe traz o
// cliente, o local e os avisos. Carrega em silêncio; erro esconde a reunião.
export const useProximaReuniao = ({ accountId, cardId, ligada }) => {
  const reuniao = ref(null);
  const carregada = ref(false);
  let pedido = 0;

  const carregar = async () => {
    pedido += 1;
    const meu = pedido;
    reuniao.value = null;
    carregada.value = false;
    if (!ligada.value || !accountId.value || !cardId.value) {
      carregada.value = true;
      return;
    }
    try {
      const { data } = await crmMeetingsAPI.index(accountId.value, {
        card_id: cardId.value,
        status: 'scheduled',
        from: startOfDay(new Date()).toISOString(),
        per_page: 1,
      });
      const proxima = data?.payload?.[0];
      if (proxima && meu === pedido) {
        const detalhe = await crmMeetingsAPI.show(accountId.value, proxima.id);
        if (meu === pedido) reuniao.value = detalhe.data?.payload || null;
      }
    } catch {
      if (meu === pedido) reuniao.value = null;
    } finally {
      if (meu === pedido) carregada.value = true;
    }
  };

  watch(() => [cardId.value, ligada.value], carregar, { immediate: true });

  return { reuniao, carregada, recarregar: carregar };
};
