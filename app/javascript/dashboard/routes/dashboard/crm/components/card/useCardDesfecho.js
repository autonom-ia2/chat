import { computed } from 'vue';
import {
  STATUS_PILL_CLASSES,
  cardStatusLabel,
  countsAsSale,
} from '../../helpers/cardOutcome';
import { usaNomeDoDesfecho } from '../funil/funil';

// #1423 — o desfecho do card (ST-01 a ST-07): o selo de status e os rótulos de
// Ganhou/Perdeu, com o nome próprio do desfecho quando o funil tem um (#1144)
// e "Resolvido/Cancelado" quando o funil não é de venda.
export const useCardDesfecho = ({ t, card, funil }) => {
  const status = computed(() => card.value.status || 'open');
  const venda = computed(() => countsAsSale(funil.value));
  const rotulosProprios = computed(
    () => funil.value?.metadata?.outcome_labels || {}
  );
  const rotuloGanhar = computed(() =>
    venda.value && !rotulosProprios.value.success
      ? t('CRM_CARD.DESFECHO.GANHOU')
      : cardStatusLabel(t, venda.value ? 'won' : 'resolved', funil.value)
  );
  const rotuloPerder = computed(() =>
    venda.value && !rotulosProprios.value.failure
      ? t('CRM_CARD.DESFECHO.PERDEU')
      : cardStatusLabel(t, venda.value ? 'lost' : 'cancelled', funil.value)
  );
  // #1802 — o diálogo de "não deu certo" usa o nome próprio só no funil de
  // modelo da corretora; os outros ficam com o texto de sempre.
  const perdaPadrao = computed(
    () => !(usaNomeDoDesfecho(funil.value) && rotulosProprios.value.failure)
  );
  const desfecho = computed(() => ({
    aberto: status.value === 'open',
    status: cardStatusLabel(t, status.value, funil.value),
    tom: STATUS_PILL_CLASSES[status.value] || 'bg-n-blue-3 text-n-blue-11',
  }));
  return {
    status,
    venda,
    rotulosProprios,
    rotuloGanhar,
    rotuloPerder,
    perdaPadrao,
    desfecho,
  };
};
