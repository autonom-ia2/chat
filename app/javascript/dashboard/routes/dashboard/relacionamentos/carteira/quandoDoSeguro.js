// #2897 — "vence em 18 dias", "venceu há 12 dias", "cancelado em 02/10": qual
// frase de tempo um seguro mostra. Função pura: devolve o nome da frase, o
// número de dias e a data (em segundos); quem desenha escolhe o catálogo (lista,
// ficha ou painel) e formata a data.
import { SELOS, diasParaTerminar, seloDoSeguro } from '../fonte/selosDoSeguro';

const AMANHA = 1;

export const quandoDoSeguro = (seguro, agora = Date.now()) => {
  const selo = seloDoSeguro(seguro, agora);
  const dias = diasParaTerminar(seguro, agora);
  if (selo === SELOS.EM_OUTRA_CORRETORA) return { id: 'EM_OUTRA_CORRETORA' };
  if (selo === SELOS.CANCELADO) {
    return { id: 'CANCELADO_EM', data: seguro.canceladoEm };
  }
  if (selo === SELOS.RENOVADO) {
    return { id: 'RENOVOU_EM', data: seguro.renovadoEm };
  }
  if (selo === SELOS.VENCIDO) {
    return dias === -AMANHA
      ? { id: 'VENCEU_ONTEM' }
      : { id: 'VENCEU_HA', count: -dias };
  }
  if (dias === 0) return { id: 'VENCE_HOJE' };
  if (dias === AMANHA) return { id: 'VENCE_AMANHA', data: seguro.termina };
  return { id: 'VENCE_EM', count: dias, data: seguro.termina };
};
