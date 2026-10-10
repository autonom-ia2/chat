import { computed, ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

// #1181 PR3 — o agente da página (T07): lê pela API para distinguir "não existe mais" (404) de
// falha (t07-naoexiste × t07-erro) — a action `show` da store devolve só a mensagem — e guarda o
// registro na store (`upsert`), para as gavetas e as outras telas lerem o mesmo agente.
export const ESTADO_PAGINA = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  ERRO: 'erro',
  NAO_EXISTE: 'naoexiste',
};

export function useAgenteDaPagina(agentId) {
  const store = useStore();
  const estado = ref(ESTADO_PAGINA.CARREGANDO);
  const id = computed(() => Number(agentId.value));

  const agente = computed(() =>
    store.getters['autonomiaAgents/getRecord'](id.value)
  );

  const carregar = async () => {
    estado.value = ESTADO_PAGINA.CARREGANDO;
    try {
      const { data } = await AutonomiaAgentsAPI.show(id.value);
      await store.dispatch('autonomiaAgents/upsert', data);
      estado.value = ESTADO_PAGINA.PRONTO;
    } catch (error) {
      estado.value =
        error?.response?.status === 404
          ? ESTADO_PAGINA.NAO_EXISTE
          : ESTADO_PAGINA.ERRO;
    }
  };

  return { agente, estado, carregar };
}
