import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { usePermissoesDaFicha } from '../../ficha/usePermissoesDaFicha';

// Quem vê os botões de escrita da ficha (#2895): "Alterar", "Marcar como
// cliente", "Liberar" e a caixa de nota são de quem edita contato; "Novo card"
// segue a regra do CRM, a mesma de "Criar cards" na lista.
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
}));

const assento = ({
  papel = 'agent',
  funcao = null,
  chaves = [papel],
  crmLigado = true,
} = {}) => {
  const getters = {
    getCurrentUser: {
      accounts: [
        { id: 7, role: papel, custom_role_id: funcao, permissions: chaves },
      ],
    },
    getCurrentAccountId: 7,
    getCurrentRole: papel,
    getCurrentCustomRoleId: funcao,
    'globalConfig/get': { crmKanbanEnabled: crmLigado },
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
    editar: permissoes.podeEditar.value,
    criarCards: permissoes.podeCriarCards.value,
  };
};

describe('Alterar, Marcar como cliente, Liberar e nota: quem edita contato', () => {
  it('administrador e agente sem função editam', () => {
    expect(assento({ papel: 'administrator' }).editar).toBe(true);
    expect(assento().editar).toBe(true);
  });

  it('função personalizada só com contact_manage', () => {
    const comFuncao = chaves => assento({ funcao: 3, chaves }).editar;
    expect(comFuncao(['custom_role', 'contact_view'])).toBe(false);
    expect(comFuncao(['custom_role', 'contact_manage'])).toBe(true);
  });
});

describe('Novo card: quem vê o CRM e pode criar card', () => {
  it('administrador e agente sem função veem', () => {
    expect(assento({ papel: 'administrator' }).criarCards).toBe(true);
    expect(assento().criarCards).toBe(true);
  });

  it('função personalizada precisa ver o CRM e poder criar card', () => {
    const comFuncao = chaves => assento({ funcao: 3, chaves }).criarCards;
    expect(comFuncao(['custom_role', 'contact_manage'])).toBe(false);
    expect(comFuncao(['custom_role', 'crm_view'])).toBe(false);
    expect(comFuncao(['custom_role', 'crm_view', 'crm_manage_cards'])).toBe(
      true
    );
  });

  it('com o CRM desligado ninguém vê', () => {
    expect(
      assento({ papel: 'administrator', crmLigado: false }).criarCards
    ).toBe(false);
  });
});
