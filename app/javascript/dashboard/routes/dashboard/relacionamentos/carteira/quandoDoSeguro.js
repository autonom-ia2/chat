// #2897 — "vence em 18 dias", "venceu há 12 dias", "cancelado em 02/10": qual
// frase de tempo um seguro mostra. Função pura: devolve o nome da frase, o
// número de dias e a data (em segundos); quem desenha escolhe o catálogo (lista
// ou ficha) e formata a data.
// "Vence em N dias" só até 90 dias: mais longe que isso ninguém conta em dias,
// e a frase mostra só a data ("vence em 13/06/2027"). A regra mora só aqui.
import { SELOS, diasParaTerminar, seloDoSeguro } from '../fonte/selosDoSeguro';

const AMANHA = 1;
export const CONTA_EM_DIAS_ATE = 90;

export const quandoDoSeguro = (seguro, agora = Date.now()) => {
  const selo = seloDoSeguro(seguro, agora);
  const dias = diasParaTerminar(seguro, agora);
  if (selo === SELOS.CANCELADO) {
    return { id: 'CANCELADO_EM', data: seguro.canceladoEm };
  }
  // #2898 — o renovado diz quando renovou: a data em que ele termina já não é
  // o que importa.
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
  if (dias > CONTA_EM_DIAS_ATE) {
    return { id: 'VENCE_NA_DATA', data: seguro.termina };
  }
  return { id: 'VENCE_EM', count: dias, data: seguro.termina };
};
