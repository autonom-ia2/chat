import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  CRM_VIEW_PERMISSION,
  CRM_VIEW_REPORTS_PERMISSION,
} from 'dashboard/constants/permissions';

// Quem vê o quê em CRM › Números (#1897), a régua da Crm::NumerosPolicy e da
// Crm::ReportPolicy no servidor limitada às chaves que a rota aceita (o servidor
// também aceita crm_admin, a rota não):
// - equipe: administrador e função com crm_view_reports; sem a flag
//   `crm_numeros_lentes`, também o agente sem função (como antes);
// - "Só eu" (só com a flag): administrador, agente sem função e função com crm_view.
export function useQuemVeNumeros() {
  const accountId = useMapGetter('getCurrentAccountId');
  const currentUser = useMapGetter('getCurrentUser');
  const currentRole = useMapGetter('getCurrentRole');
  const currentCustomRoleId = useMapGetter('getCurrentCustomRoleId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  const getAccount = useMapGetter('accounts/getAccount');

  // Na carga direta da página as flags da conta chegam depois: até lá ninguém vê
  // nada (sem isso o agente sem função parece "sem a flag" e abre a equipe).
  const pronto = computed(() =>
    Boolean(getAccount.value(accountId.value)?.features)
  );

  const ligado = computed(() =>
    Boolean(
      isFeatureEnabledonAccount.value(
        accountId.value,
        FEATURE_FLAGS.CRM_NUMEROS_LENTES
      )
    )
  );
  // A visão "Equipe" nova (#1992, F5): só junto da "Só eu" (as duas flags).
  const equipeNova = computed(
    () =>
      ligado.value &&
      Boolean(
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.CRM_NUMEROS_EQUIPE
        )
      )
  );
  const administrador = computed(() => currentRole.value === 'administrator');
  const semFuncao = computed(() => !currentCustomRoleId.value);
  // Só a chave que a rota de Números aceita (crm.routes.js numerosMeta): crm_admin
  // sozinho não abre a rota, então também não mostra o caminho para ela.
  const temChave = chave =>
    getUserPermissions(currentUser.value, accountId.value).includes(chave);

  // Só o agente sem função depende da flag para ver a equipe: para ele, espera a conta.
  const veEquipe = computed(() => {
    if (administrador.value) return true;
    if (semFuncao.value) return pronto.value && !ligado.value;
    return temChave(CRM_VIEW_REPORTS_PERMISSION);
  });
  const veSoEu = computed(
    () =>
      pronto.value &&
      ligado.value &&
      (administrador.value || semFuncao.value || temChave(CRM_VIEW_PERMISSION))
  );
  // O agente sem função abre Números com ou sem a flag (equipe ou "Só eu"): o item
  // do menu não some enquanto a conta carrega. Só a função com crm_view espera a flag.
  const abreNumeros = computed(
    () => semFuncao.value || veEquipe.value || veSoEu.value
  );

  return {
    pronto,
    ligado,
    equipeNova,
    administrador,
    veEquipe,
    veSoEu,
    abreNumeros,
  };
}
