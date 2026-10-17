import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

// Tema 14 (#1434) — quem o ajudante ajuda e "quando chamar" (`GET/PUT agents/:id/ajuda`, atrás da Fase 2).
// - `carregar`: lê o "quando chamar" (o agente só traz os nomes, em `ajuda`). Falhando, a página mostra só os
//   nomes e o "Mudar" continua.
// - `salvar`: troca o conjunto inteiro, num PUT só (o servidor recusa tudo ou grava tudo). Recusado (422), a
//   explicação do servidor vai para o erro, junto da garantia de que nada mudou.
export function useAjudaDoAgente() {
  const { t } = useI18n();
  const quando = ref('');
  const leitura = ref('pronto');
  const salvando = ref(false);
  const erro = ref(null);

  const carregar = async agenteId => {
    leitura.value = 'carregando';
    try {
      const { data } = await AutonomiaAgentsAPI.getAjuda(agenteId);
      quando.value = data?.quando || '';
      leitura.value = 'pronto';
    } catch {
      leitura.value = 'erro';
    }
  };

  const salvar = async ({ agenteId, nome, principalIds, quando: frase }) => {
    if (salvando.value) return false;
    salvando.value = true;
    erro.value = null;
    try {
      const { data } = await AutonomiaAgentsAPI.updateAjuda(agenteId, {
        principalIds,
        quando: frase,
      });
      quando.value = data?.quando ?? frase;
      return true;
    } catch (falha) {
      erro.value = {
        titulo:
          falha?.response?.data?.error ||
          t('AGENTS.JORNADA.AJUDANTE.ERRO', { nome }),
        garantia: t('AGENTS.JORNADA.AJUDANTE.ERRO_GARANTIA', { nome }),
      };
      return false;
    } finally {
      salvando.value = false;
    }
  };

  return { quando, leitura, salvando, erro, carregar, salvar };
}
