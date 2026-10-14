import { ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';

// #1181 — "Começar a atender": pôr o agente no canal escolhido e ligá-lo, trocando quem já estava
// lá quando a pessoa escolheu um canal ocupado.
// #1366 — agente sem canal não pode ficar atendendo: o servidor recusa ativar antes (422). Ligar e
// entrar no canal é um passo só no servidor (POST do canal com `ativar`). Ordem:
//   1. PATCH do "quando", só se mudou (o agente continua como está);
//   2. DELETE do canal no agente antigo, se for troca;
//   3. POST do canal no agente novo com `ativar` (vínculo e ligar na mesma transação);
//   4. relê o agente, para a tela mostrar o estado que o servidor gravou.
// Falha no POST: nada foi ligado. Desfaz o "quando", se mudou, para o "Nada mudou" ser verdade.
// Se a falha vier depois que o antigo já saiu (DECISOES.md item 16, opção a), também tenta pôr o
// antigo de volta na caixa, ligado de novo se ele atendia (sair da última caixa o parou); não
// conseguindo, a caixa ficou sem agente (motivo próprio, para a tela dizer que as conversas vão
// para a equipe). Os canais vão direto pela API (sem a store autonomiaChannels, que relê a lista do
// agente a cada passo e guarda o estado de um agente só).
export const MOTIVO = {
  COMECAR: 'comecar',
  CANAL: 'canal',
  TROCA_SEM_AGENTE: 'troca_sem_agente',
  OFFLINE: 'offline',
  OCUPADO: 'ocupado',
};

const navegadorSemRede = () =>
  typeof navigator !== 'undefined' && navigator.onLine === false;

// O PATCH do "quando" passa pela store (updateRecord → throwErrorMessage), que devolve um Error só
// com a mensagem, sem `response`: ali só o navegador diz se falta rede. Os canais vão direto pelo
// axios, e aí erro sem `response` é pedido que não chegou ao servidor.
const semRede = (error, { nosCanais }) =>
  navegadorSemRede() || (nosCanais && !error?.response);

const motivoDaFalha = (error, passo) => {
  if (semRede(error, passo)) return MOTIVO.OFFLINE;
  // 422 no POST = o canal recusou este agente (já ocupado, bot externo, agente interno).
  if (passo.conectando && error.response.status === 422) return MOTIVO.CANAL;
  return MOTIVO.COMECAR;
};

// A explicação do servidor quando ele recusou (422), para a tela mostrar no lugar do texto geral.
export const mensagemDaRecusa = error => {
  if (error?.response?.status !== 422) return null;
  const dados = error.response.data || {};
  return dados.message || dados.error || null;
};

export function useComecarAAtender() {
  const store = useStore();
  const comecando = ref(false);
  const erro = ref(null);

  const atualizar = dados => store.dispatch('autonomiaAgents/update', dados);

  const desfazerJanela = async agente => {
    try {
      await atualizar({
        id: agente.id,
        config: { response_window: agente.config?.response_window || 'always' },
      });
      return true;
    } catch {
      return false;
    }
  };

  const devolverAoAntigo = async (troca, inboxId) => {
    try {
      await AutonomiaChannelsAPI.connect(troca.agenteId, inboxId, {
        ativar: troca.atendia === true,
      });
      return true;
    } catch {
      return false;
    }
  };

  const relerAgente = async id => {
    try {
      await store.dispatch('autonomiaAgents/show', id);
    } catch {
      // O agente já está no canal e ligado; a próxima leitura da tela mostra o estado certo.
    }
  };

  const comecar = async ({ agente, inboxId, troca = null, janela = null }) => {
    if (comecando.value) return { ok: false, motivo: MOTIVO.OCUPADO };
    comecando.value = true;
    erro.value = null;

    const janelaMudou =
      Boolean(janela) && janela !== agente.config?.response_window;

    const passo = {
      janela: false,
      nosCanais: false,
      trocou: false,
      conectando: false,
    };
    try {
      if (janelaMudou) {
        await atualizar({ id: agente.id, config: { response_window: janela } });
        passo.janela = true;
      }
      passo.nosCanais = true;
      if (troca) {
        await AutonomiaChannelsAPI.disconnect(troca.agenteId, inboxId);
        passo.trocou = true;
      }
      passo.conectando = true;
      await AutonomiaChannelsAPI.connect(agente.id, inboxId, { ativar: true });
      await relerAgente(agente.id);
      return { ok: true };
    } catch (error) {
      const desfeito = passo.janela ? await desfazerJanela(agente) : true;
      const semAgente =
        passo.trocou && !(await devolverAoAntigo(troca, inboxId));
      erro.value = semAgente
        ? { motivo: MOTIVO.TROCA_SEM_AGENTE, desfeito, troca }
        : {
            motivo: motivoDaFalha(error, passo),
            desfeito,
            mensagem: mensagemDaRecusa(error),
          };
      return { ok: false, ...erro.value };
    } finally {
      comecando.value = false;
    }
  };

  return { comecar, comecando, erro };
}
