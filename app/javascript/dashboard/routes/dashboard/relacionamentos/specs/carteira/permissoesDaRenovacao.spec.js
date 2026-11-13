import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { usePermissoesDaFicha } from '../../ficha/usePermissoesDaFicha';

// Quem vê o que é da renovação (#2898). "Exportar" o histórico de um seguro
// segue a regra de exportar contatos. "Ajustar renovações" e o convite para
// escolher o funil são de quem o servidor deixa mudar os ajustes: o
// administrador, ou a função que tem as duas chaves, `contact_manage` e
// `crm_manage_pipelines` (o agente sem função não).
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
}));

const assento = ({ papel = 'agent', funcao = null, chaves = [papel] } = {}) => {
  const getters = {
    getCurrentUser: {
      accounts: [
        { id: 7, role: papel, custom_role_id: funcao, permissions: chaves },
      ],
    },
    getCurrentAccountId: 7,
    getCurrentRole: papel,
    getCurrentCustomRoleId: funcao,
    'globalConfig/get': { crmKanbanEnabled: true },
    'globalConfig/isOnChatwootCloud': false,
    'globalConfig/isACustomBrandedInstance': false,
    'globalConfig/isMetaInboxCreationDisabled': false,
    'globalConfig/isMetaMessageSendingDisabled': false,
    'accounts/getAccount': () => ({}),
    'accounts/isFeatureEnabledonAccount': () => true,
  };
  let permissoes;
  const Peca = defineComponent({
    setup() {
      permissoes = usePermissoesDaFicha();
      return () => h('div');
    },
  });
  // `mocks` do test-utils só chega depois do setup(); o composable lê antes.
  mount(Peca, {
    global: { config: { globalProperties: { $store: { getters } } } },
  });
  return {
    exportar: permissoes.podeExportar.value,
    ajustar: permissoes.podeAjustarRenovacoes.value,
  };
};
const comFuncao = chaves => assento({ funcao: 3, chaves });

describe('Exportar o histórico do seguro: quem exporta contatos', () => {
  it('o administrador exporta, e o agente sem função não', () => {
    expect(assento({ papel: 'administrator' }).exportar).toBe(true);
    expect(assento().exportar).toBe(false);
  });

  it('função personalizada só com contact_export', () => {
    expect(comFuncao(['custom_role', 'contact_manage']).exportar).toBe(false);
    expect(comFuncao(['custom_role', 'contact_export']).exportar).toBe(true);
  });
});

describe('Ajustar renovações: o administrador ou a função com as duas chaves', () => {
  it('o administrador muda, e o agente sem função não', () => {
    expect(assento({ papel: 'administrator' }).ajustar).toBe(true);
    expect(assento().ajustar).toBe(false);
  });

  it('função personalizada só com contact_manage e crm_manage_pipelines juntas', () => {
    expect(comFuncao(['custom_role', 'contact_view']).ajustar).toBe(false);
    expect(
      comFuncao(['custom_role', 'contact_manage', 'crm_manage_pipelines'])
        .ajustar
    ).toBe(true);
  });

  it.each(['contact_manage', 'crm_manage_pipelines'])(
    'só com %s não muda',
    chave => {
      expect(comFuncao(['custom_role', chave]).ajustar).toBe(false);
    }
  );
});
