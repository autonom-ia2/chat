import { ref } from 'vue';
import { getNextSlot, getSlots } from '../api';

// Horários livres de um dia e o próximo horário livre (J1-A13, J2-A8). Ocupados não vêm da API.
export function useSlots({ slug, duration }) {
  const slots = ref([]);
  const isLoading = ref(false);
  const hasFailed = ref(false);
  const nextSlot = ref(null);
  let slotsRequest = 0;
  let nextRequest = 0;

  const loadSlots = async date => {
    slotsRequest += 1;
    const current = slotsRequest;
    isLoading.value = true;
    hasFailed.value = false;
    slots.value = [];
    try {
      const data = await getSlots(slug.value, date, duration.value);
      if (current !== slotsRequest) return;
      slots.value = Array.isArray(data?.slots) ? data.slots : [];
    } catch (error) {
      if (current === slotsRequest) hasFailed.value = true;
    } finally {
      if (current === slotsRequest) isLoading.value = false;
    }
  };

  // Sem atalho enquanto busca ou quando a consulta falha: o atalho velho (de outra duração ou de antes de recarregar)
  // some na hora, e a lista de dias continua lá, então ninguém fica sem saída.
  const loadNextSlot = async () => {
    nextRequest += 1;
    const current = nextRequest;
    nextSlot.value = null;
    try {
      const data = await getNextSlot(slug.value, duration.value);
      if (current === nextRequest) nextSlot.value = data?.starts_at || null;
    } catch (error) {
      if (current === nextRequest) nextSlot.value = null;
    }
  };

  return {
    slots,
    isLoading,
    hasFailed,
    nextSlot,
    loadSlots,
    loadNextSlot,
  };
}
