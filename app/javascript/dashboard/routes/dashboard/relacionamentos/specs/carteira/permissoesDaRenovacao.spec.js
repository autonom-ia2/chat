import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { usePermissoesDaFicha } from '../../ficha/usePermissoesDaFicha';

// Quem vê o que é da renovação (#2898). "Exportar" o histórico de um seguro
// segue a regra de exportar contatos. "Ajustar renovações" e o convite para
// escolher o funil são de quem o servidor deixa mudar os ajustes: o
// administrador, ou a função que tem `contact_manage` e uma chave de funil,
// `crm_manage_pipelines` ou `crm_admin` (o agente sem função não).
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

describe('Ajustar renovações: o administrador ou a função com as chaves', () => {
  it('o administrador muda, e o agente sem função não', () => {
    expect(assento({ papel: 'administrator' }).ajustar).toBe(true);
    expect(assento().ajustar).toBe(false);
  });

  it.each(['crm_manage_pipelines', 'crm_admin'])(
    'função personalizada com contact_manage e %s muda',
    deFunil => {
      expect(
        comFuncao(['custom_role', 'contact_manage', deFunil]).ajustar
      ).toBe(true);
    }
  );

  it('função personalizada com as duas chaves de funil e sem contact_manage não muda', () => {
    expect(
      comFuncao(['custom_role', 'crm_manage_pipelines', 'crm_admin']).ajustar
    ).toBe(false);
  });

  it.each([
    'contact_view',
    'contact_manage',
    'crm_manage_pipelines',
    'crm_admin',
  ])('só com %s não muda', chave => {
    expect(comFuncao(['custom_role', chave]).ajustar).toBe(false);
  });
});
