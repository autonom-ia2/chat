import { onMounted, ref } from 'vue';
import JornadaAPI from 'dashboard/api/autonomia/jornada';

// #1181 L1 — conversas respondidas e passadas para a equipe nos últimos 7 dias. Busca ao montar quem
// usa (nunca no seletor da rota nem no menu). Se a leitura falha, a tela esconde a linha inteira:
// nada de "—" nem zero (protótipo t02-semnumeros).
export function useNumerosDaSemana({ agentId } = {}) {
  const estado = ref('carregando');
  const porAgente = ref({});

  const carregar = async () => {
    estado.value = 'carregando';
    try {
      const { data } = await JornadaAPI.semana(agentId ? { agentId } : {});
      porAgente.value = Object.fromEntries(
        (data?.payload || []).map(item => [
          item.agent_id,
          { respondidas: item.answered || 0, passadas: item.handed || 0 },
        ])
      );
      estado.value = 'pronto';
    } catch {
      porAgente.value = {};
      estado.value = 'erro';
    }
  };

  // O backend devolve todo agente da conta, com 0 quando não há evento; quem não veio é um agente
  // novo que ainda não tem conversa.
  const numerosDe = id => {
    if (estado.value !== 'pronto') return null;
    return porAgente.value[id] || { respondidas: 0, passadas: 0 };
  };

  onMounted(carregar);

  return { estado, numerosDe, carregar };
}
