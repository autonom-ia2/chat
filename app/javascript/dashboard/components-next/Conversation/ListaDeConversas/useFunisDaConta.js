// #2202 — a conta tem funil? Uma leitura por conta, dividida por todos os cards. Sem
// funil, o lugar da etapa mostra o nome da caixa. Se a leitura falhar, tenta de novo depois de 30 s.
import { computed, reactive, watch } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const porConta = reactive({});
// Depois de uma falha, a conta espera este tempo antes de tentar de novo: com a API fora do ar,
// cada card montado não vira uma requisição.
export const ESPERA_DEPOIS_DA_FALHA_MS = 30 * 1000;
const falhouEm = {};

const ler = async contaId => {
  if (porConta[contaId]) return;
  if (Date.now() - (falhouEm[contaId] || 0) < ESPERA_DEPOIS_DA_FALHA_MS) return;
  porConta[contaId] = { carregado: false, quantos: 0 };
  try {
    const { data } = await CrmKanbanAPI.getPipelines();
    delete falhouEm[contaId];
    porConta[contaId] = {
      carregado: true,
      quantos: (data?.payload || []).length,
    };
  } catch {
    // Sem a resposta, a conta conta como "com funil" (o card não troca a etapa pela caixa) e a
    // falha não fica guardada: passados 30 s, o próximo card montado lê de novo.
    falhouEm[contaId] = Date.now();
    delete porConta[contaId];
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
