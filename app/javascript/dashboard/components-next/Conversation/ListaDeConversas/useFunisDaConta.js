// #2202 — a conta tem funil? Uma leitura por conta, dividida por todos os cards. Sem
// funil (contas 17 e 47), o lugar da etapa mostra o nome da caixa.
import { computed, reactive, watch } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const porConta = reactive({});

const ler = async contaId => {
  if (porConta[contaId]) return;
  porConta[contaId] = { carregado: false, quantos: 0 };
  try {
    const { data } = await CrmKanbanAPI.getPipelines();
    porConta[contaId] = {
      carregado: true,
      quantos: (data?.payload || []).length,
    };
  } catch {
    // Sem a resposta, a conta conta como "com funil": o card não troca a etapa pela caixa.
    porConta[contaId] = { carregado: false, quantos: 0 };
  }
};

export function useFunisDaConta(contaId, ligado) {
  watch(
    () => [contaId.value, ligado.value],
    ([id, sim]) => {
      if (id && sim) ler(id);
    },
    { immediate: true }
  );
  return computed(() => {
    const estado = porConta[contaId.value] || {};
    return { semFunil: Boolean(estado.carregado && estado.quantos === 0) };
  });
}
