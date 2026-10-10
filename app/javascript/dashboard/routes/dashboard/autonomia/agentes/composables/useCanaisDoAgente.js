import { computed, ref } from 'vue';
import JornadaAPI from 'dashboard/api/autonomia/jornada';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';
import { canaisDoAgente } from '../utils/estadoDoAgente';

// #1181 PR3 — as caixas para a página do agente e para "Onde e quando" (T07/T10).
// Lê a L2 (todas as caixas e quem responde em cada uma). Se a L2 falha, cai nos canais do próprio
// agente (`agents/:id/channels`: os ligados a ele e as caixas livres) e marca `semLeitura`: a lista
// não mostra as caixas de outros agentes (t10-semleitura). Se as duas falham, `estado` = 'erro'.
// Quem chama decide quando ler (a página lê ao montar).
export function useCanaisDoAgente(agentId) {
  const estado = ref('carregando');
  const canais = ref([]);
  const semLeitura = ref(false);

  const daL2 = async () => {
    const { data } = await JornadaAPI.canaisOcupados();
    return data?.payload || [];
  };

  // Mesmo formato da L2 a partir de `agents/:id/channels`.
  const doAgente = async () => {
    const id = Number(agentId.value);
    const { data } = await AutonomiaChannelsAPI.get(id);
    const ligados = (data?.payload || []).map(item => ({
      inbox_id: item.inbox_id,
      name: item.inbox_name,
      channel_type: item.channel_type,
      occupied_by: { kind: 'agent', agent_id: id },
    }));
    const livres = (data?.eligible_inboxes || []).map(item => ({
      inbox_id: item.id,
      name: item.name,
      channel_type: item.channel_type,
      occupied_by: null,
    }));
    return [...ligados, ...livres];
  };

  const carregar = async () => {
    estado.value = 'carregando';
    try {
      canais.value = await daL2();
      semLeitura.value = false;
      estado.value = 'pronto';
      return;
    } catch {
      semLeitura.value = true;
    }
    try {
      canais.value = await doAgente();
      estado.value = 'pronto';
    } catch {
      canais.value = [];
      estado.value = 'erro';
    }
  };

  // Caixas em que este agente responde agora.
  const atuais = computed(() =>
    canaisDoAgente(Number(agentId.value), canais.value)
  );

  return { estado, canais, semLeitura, atuais, carregar };
}
