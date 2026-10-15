import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';
import { PAPEL_AREA_NA_QUERY } from '../constants/criacao';

// #1433 (tema 13) — grava onde o agente da equipe fica: entra nas caixas novas (POST channels com papel
// area, que já liga o agente) e depois sai das que foram tiradas (DELETE). Entrar antes de sair: o
// agente nunca fica, no meio do caminho, sem onde trabalhar (o servidor o pararia).
// Uma caixa por chamada. Se uma falha, para ali. Nada é lembrado entre tentativas: quem chama relê
// onde ele está (a leitura de canais) e manda de novo o que falta. Entrar numa caixa em que ele já
// está na equipe é sucesso no servidor (idempotente). O erro traz a explicação do servidor (422).
export function useSalvarEquipe() {
  const { t } = useI18n();
  const salvando = ref(false);
  const erro = ref(null);
  const salvar = async ({ agenteId, nome, entram = [], saem = [] }) => {
    if (salvando.value) return false;
    salvando.value = true;
    erro.value = null;
    try {
      // eslint-disable-next-line no-restricted-syntax
      for (const inboxId of entram) {
        // Em série de propósito: a ordem importa (ver acima) e o servidor trava agente e caixa.
        // eslint-disable-next-line no-await-in-loop
        await AutonomiaChannelsAPI.connect(agenteId, inboxId, {
          papel: PAPEL_AREA_NA_QUERY,
        });
      }
      // eslint-disable-next-line no-restricted-syntax
      for (const inboxId of saem) {
        // eslint-disable-next-line no-await-in-loop
        await AutonomiaChannelsAPI.disconnect(agenteId, inboxId);
      }
      return true;
    } catch (falha) {
      erro.value = {
        titulo:
          falha?.response?.data?.error ||
          t('AGENTS.JORNADA.EQUIPE.ERRO', { nome }),
        garantia: t('AGENTS.JORNADA.EQUIPE.ERRO_GARANTIA'),
      };
      return false;
    } finally {
      salvando.value = false;
    }
  };

  return { salvando, erro, salvar };
}
