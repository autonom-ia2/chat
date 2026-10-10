import { ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';

// #1181 — "Começar a atender": ativar o agente e pôr no canal escolhido, trocando quem já estava
// lá quando a pessoa escolheu um canal ocupado. Ordem fechada no DECISOES.md item 4, porque o
// backend só conecta agente que já está ativo (InboxConnector → agent_not_active):
//   1. PATCH status active (e o "quando" no mesmo PATCH, se mudou) no agente novo;
//   2. DELETE do canal no agente antigo, se for troca;
//   3. POST do canal no agente novo.
// Falha depois do PATCH desfaz o status do novo, para o "Nada mudou" ser verdade para ele.
// Se a falha vier no POST depois que o antigo já saiu (DECISOES.md item 16, opção a), também tenta
// pôr o antigo de volta na caixa: conseguindo, é o mesmo "Nada mudou"; não conseguindo, a caixa
// ficou sem agente (motivo próprio, para a tela dizer que as conversas vão para a equipe).
// Os canais vão direto pela API (sem a store autonomiaChannels, que relê a lista do agente a cada
// passo e guarda o estado de um agente só).
export const MOTIVO = {
  COMECAR: 'comecar',
  CANAL: 'canal',
  TROCA_SEM_AGENTE: 'troca_sem_agente',
  OFFLINE: 'offline',
  OCUPADO: 'ocupado',
};

const navegadorSemRede = () =>
  typeof navigator !== 'undefined' && navigator.onLine === false;

// O PATCH passa pela store (updateRecord → throwErrorMessage), que devolve um Error só com a
// mensagem, sem `response`: ali só o navegador diz se falta rede. Os canais vão direto pelo axios,
// e aí erro sem `response` é pedido que não chegou ao servidor.
const semRede = (error, { ativou }) =>
  navegadorSemRede() || (ativou && !error?.response);

const motivoDaFalha = (error, { ativou, conectando }) => {
  if (semRede(error, { ativou })) return MOTIVO.OFFLINE;
  // 422 no POST = o canal recusou este agente (já ocupado, bot externo, agente interno).
  if (conectando && error.response.status === 422) return MOTIVO.CANAL;
  return MOTIVO.COMECAR;
};

export function useComecarAAtender() {
  const store = useStore();
  const comecando = ref(false);
  const erro = ref(null);

  const atualizar = dados => store.dispatch('autonomiaAgents/update', dados);

  const desfazer = async (agente, janelaMudou) => {
    const anterior = {
      id: agente.id,
      enabled: agente.enabled === true,
      status: agente.status || 'draft',
    };
    if (janelaMudou) {
      anterior.config = {
        response_window: agente.config?.response_window || 'always',
      };
    }
    try {
      await atualizar(anterior);
      return true;
    } catch {
      return false;
    }
  };

  const devolverAoAntigo = async (troca, inboxId) => {
    try {
      await AutonomiaChannelsAPI.connect(troca.agenteId, inboxId);
      return true;
    } catch {
      return false;
    }
  };

  const comecar = async ({ agente, inboxId, troca = null, janela = null }) => {
    if (comecando.value) return { ok: false, motivo: MOTIVO.OCUPADO };
    comecando.value = true;
    erro.value = null;

    const janelaMudou =
      Boolean(janela) && janela !== agente.config?.response_window;
    const ativar = { id: agente.id, enabled: true, status: 'active' };
    if (janelaMudou) ativar.config = { response_window: janela };

    const passo = { ativou: false, trocou: false, conectando: false };
    try {
      await atualizar(ativar);
      passo.ativou = true;
      if (troca) {
        await AutonomiaChannelsAPI.disconnect(troca.agenteId, inboxId);
        passo.trocou = true;
      }
      passo.conectando = true;
      await AutonomiaChannelsAPI.connect(agente.id, inboxId);
      return { ok: true };
    } catch (error) {
      const desfeito = passo.ativou
        ? await desfazer(agente, janelaMudou)
        : true;
      const semAgente =
        passo.trocou && !(await devolverAoAntigo(troca, inboxId));
      erro.value = semAgente
        ? { motivo: MOTIVO.TROCA_SEM_AGENTE, desfeito, troca }
        : { motivo: motivoDaFalha(error, passo), desfeito };
      return { ok: false, ...erro.value };
    } finally {
      comecando.value = false;
    }
  };

  return { comecar, comecando, erro };
}
