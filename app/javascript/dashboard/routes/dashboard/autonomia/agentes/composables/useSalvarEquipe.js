import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';
import { PAPEL_AREA_NA_QUERY } from '../constants/criacao';

// #1433 (tema 13) — grava onde o agente da equipe fica: entra nas caixas novas (POST channels com papel
// area, que já liga o agente) e depois sai das que foram tiradas (DELETE). Entrar antes de sair: o
// agente nunca fica, no meio do caminho, sem onde trabalhar (o servidor o pararia).
// Uma caixa por chamada. Se uma falha, para ali; as que já deram certo ficam guardadas e não são
// repetidas na próxima tentativa. O erro traz a explicação do servidor (422) quando há.
export function useSalvarEquipe() {
  const { t } = useI18n();
  const salvando = ref(false);
  const erro = ref(null);
  const feitos = new Set();

  const umaVez = async (chave, acao) => {
    if (feitos.has(chave)) return;
    await acao();
    feitos.add(chave);
  };

  const salvar = async ({ agenteId, nome, entram = [], saem = [] }) => {
    if (salvando.value) return false;
    salvando.value = true;
    erro.value = null;
    try {
      // eslint-disable-next-line no-restricted-syntax
      for (const inboxId of entram) {
        // Em série de propósito: a ordem importa (ver acima) e o servidor trava agente e caixa.
        // eslint-disable-next-line no-await-in-loop
        await umaVez(`entra:${inboxId}`, () =>
          AutonomiaChannelsAPI.connect(agenteId, inboxId, {
            papel: PAPEL_AREA_NA_QUERY,
          })
        );
      }
      // eslint-disable-next-line no-restricted-syntax
      for (const inboxId of saem) {
        // eslint-disable-next-line no-await-in-loop
        await umaVez(`sai:${inboxId}`, () =>
          AutonomiaChannelsAPI.disconnect(agenteId, inboxId)
        );
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
