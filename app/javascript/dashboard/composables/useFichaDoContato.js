import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #3130 — o caminho único para a ficha de uma pessoa ou de uma empresa. Com o
// menu novo de Relacionamentos (`relationships_navigation`, ligado em todas as
// contas desde a E9, #2902) é a ficha nova; sem ele, a antiga. Montar
// `contacts_edit` ou `/contacts/:id` à mão levava de volta à tela antiga: o
// "Novo card" da ficha nova voltava do CRM para ela.
export const rotaDaPessoa = (accountId, contactId, fichaNova) => ({
  name: fichaNova ? 'relacionamentos_pessoa' : 'contacts_edit',
  params: { accountId, contactId },
});

export const rotaDaEmpresa = (accountId, companyId, fichaNova) => ({
  name: fichaNova ? 'relacionamentos_empresa' : 'companies_dashboard_show',
  params: { accountId, companyId },
});

// Lê a conta e a flag do store, não do endereço: serve também fora das telas
// da conta (a busca, o painel da conversa) e não prende quem usa ao roteador.
export const useFichaDoContato = () => {
  const accountId = useMapGetter('getCurrentAccountId');
  const flagLigada = useMapGetter('accounts/isFeatureEnabledonAccount');
  const fichaNova = computed(() =>
    Boolean(
      accountId.value &&
        flagLigada.value?.(
          accountId.value,
          FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION
        )
    )
  );
  return {
    fichaNova,
    pessoa: contactId =>
      rotaDaPessoa(accountId.value, contactId, fichaNova.value),
    empresa: companyId =>
      rotaDaEmpresa(accountId.value, companyId, fichaNova.value),
  };
};
