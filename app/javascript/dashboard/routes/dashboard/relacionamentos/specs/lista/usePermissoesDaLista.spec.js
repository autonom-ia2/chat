import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { usePermissoesDaLista } from '../../lista/usePermissoesDaLista';

// Quem vê "Criar cards", "Etiqueta" e "Apagar" na barra da lista (#2894), com as
// regras que o painel já tem: a do CRM (ver e criar card) e as de editar e de
// apagar da lista de contatos.
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
      permissoes = usePermissoesDaLista();
      return () => h('div');
    },
  });
  // `mocks` do test-utils só chega depois do setup(); o composable lê antes.
  mount(Peca, {
    global: { config: { globalProperties: { $store: { getters } } } },
  });
  return {
    criarCards: permissoes.podeCriarCards.value,
    etiquetar: permissoes.podeEtiquetar.value,
    apagar: permissoes.podeApagar.value,
    trazer: permissoes.podeTrazer.value,
  };
};

describe('Criar cards: quem vê o CRM e pode criar card', () => {
  it('administrador e agente sem função veem', () => {
    expect(assento({ papel: 'administrator' }).criarCards).toBe(true);
    expect(assento().criarCards).toBe(true);
  });

  it('função personalizada precisa ver o CRM e poder criar card', () => {
    const comFuncao = chaves => assento({ funcao: 3, chaves }).criarCards;
    expect(comFuncao(['custom_role', 'contact_manage'])).toBe(false);
    expect(comFuncao(['custom_role', 'crm_view', 'crm_manage_cards'])).toBe(
      true
    );
    expect(comFuncao(['custom_role', 'crm_admin'])).toBe(true);
  });

  it('função só com crm_view não vê: o servidor recusaria a escrita', () => {
    expect(
      assento({ funcao: 3, chaves: ['custom_role', 'crm_view'] }).criarCards
    ).toBe(false);
  });

  it('função que cria card mas não vê o CRM não vê', () => {
    expect(
      assento({ funcao: 3, chaves: ['custom_role', 'crm_manage_cards'] })
        .criarCards
    ).toBe(false);
  });

  it('com o CRM desligado ninguém vê, como o menu', () => {
    expect(
      assento({ papel: 'administrator', crmLigado: false }).criarCards
    ).toBe(false);
  });
});

describe('Etiqueta: quem pode editar contato', () => {
  it('administrador e agente sem função etiquetam', () => {
    expect(assento({ papel: 'administrator' }).etiquetar).toBe(true);
    expect(assento().etiquetar).toBe(true);
  });

  it('função personalizada só com contact_manage', () => {
    const comFuncao = chaves => assento({ funcao: 3, chaves }).etiquetar;
    expect(comFuncao(['custom_role', 'contact_view'])).toBe(false);
    expect(comFuncao(['custom_role', 'contact_manage'])).toBe(true);
  });
});

describe('Apagar: administrador ou a chave contact_delete', () => {
  it('administrador apaga', () => {
    expect(assento({ papel: 'administrator' }).apagar).toBe(true);
  });

  it('agente sem função não apaga', () => {
    expect(assento().apagar).toBe(false);
  });

  it('função personalizada só com contact_delete', () => {
    const comFuncao = chaves => assento({ funcao: 3, chaves }).apagar;
    expect(comFuncao(['custom_role', 'contact_manage'])).toBe(false);
    expect(comFuncao(['custom_role', 'contact_delete'])).toBe(true);
  });
});

describe('Trazer minha lista: quem pode importar contatos', () => {
  it('administrador vê; agente sem função não', () => {
    expect(assento({ papel: 'administrator' }).trazer).toBe(true);
    expect(assento().trazer).toBe(false);
  });

  it('função personalizada precisa de `contact_manage`', () => {
    const comFuncao = chaves => assento({ funcao: 3, chaves }).trazer;
    expect(comFuncao(['contact_manage'])).toBe(true);
    expect(comFuncao(['contact_view'])).toBe(false);
  });
});
