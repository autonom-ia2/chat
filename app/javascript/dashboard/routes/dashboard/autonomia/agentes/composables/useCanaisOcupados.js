import { onMounted, ref } from 'vue';
import JornadaAPI from 'dashboard/api/autonomia/jornada';

// #1181 L2 — as caixas da conta e quem responde em cada uma:
// `occupied_by` null (livre), {kind:'agent', agent_id, agent_name, operating} ou {kind:'external'}.
// Busca ao montar quem usa. Se a leitura falha, a tela cai no texto sem o nome do canal
// ("Responde em 1 canal", protótipo t02-semnomecanal).
export function useCanaisOcupados() {
  const estado = ref('carregando');
  const canais = ref([]);

  const carregar = async () => {
    estado.value = 'carregando';
    try {
      const { data } = await JornadaAPI.canaisOcupados();
      canais.value = data?.payload || [];
      estado.value = 'pronto';
    } catch {
      canais.value = [];
      estado.value = 'erro';
    }
  };

  onMounted(carregar);

  return { estado, canais, carregar };
}
