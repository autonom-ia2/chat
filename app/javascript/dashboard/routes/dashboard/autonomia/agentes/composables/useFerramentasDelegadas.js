import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  useCanManage,
  usePermissionGranted,
} from 'dashboard/composables/useCanManage';
import { AUTONOMIA_TOOLS_MANAGE_PERMISSION } from 'dashboard/constants/permissions';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { ehSuperAdmin } from '../utils/pagina';

// #1430 — com a flag agente_ferramentas_delegadas na conta, o administrador e quem tem a chave "Gerenciar ferramentas"
// abrem as ferramentas do agente. A API (Agents::ToolsController#check_tools_permission) confere a mesma regra.
export const ferramentasDelegadasLigadas = conta =>
  conta?.features?.[FEATURE_FLAGS.AGENTE_FERRAMENTAS_DELEGADAS] === true;

export function useFerramentasDelegadas() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  const temChave = usePermissionGranted(AUTONOMIA_TOOLS_MANAGE_PERMISSION);
  // Mesma leitura do usePainelDesempenho: o getter da conta é uma função.
  return computed(
    () =>
      typeof conta.value === 'function' &&
      ferramentasDelegadasLigadas(conta.value(contaId.value)) &&
      temChave.value
  );
}

// #2858 F2 — o cadastro manual de ferramentas ("Criar a minha (avançado)") vale para esta pessoa? Com a flag
// agente_ferramentas_delegadas e a chave, ou o SuperAdmin que gerencia agentes (a mesma regra de gavetasPermitidas e
// do ToolsController#check_tools_permission). Sem isso, a API das ferramentas manuais responde 401.
export function useCadastroManual() {
  const delegadas = useFerramentasDelegadas();
  const usuario = useMapGetter('getCurrentUser');
  const podeGerenciar = useCanManage('autonomia_manage');
  return computed(
    () =>
      delegadas.value || (ehSuperAdmin(usuario.value) && podeGerenciar.value)
  );
}
