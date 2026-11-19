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
    editar: permissoes.podeEditar.value,
    exportar: permissoes.podeExportar.value,
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

// #2896 — a mesma regra da rota e do servidor (ContactPolicy#import?).
describe('Trazer minha lista: administrador ou a chave contact_manage', () => {
  it('administrador traz', () => {
    expect(assento({ papel: 'administrator' }).trazer).toBe(true);
  });

  it('agente sem função não traz', () => {
    expect(assento().trazer).toBe(false);
  });

  it('função personalizada só com contact_manage', () => {
    const comFuncao = chaves => assento({ funcao: 3, chaves }).trazer;
    expect(comFuncao(['custom_role', 'contact_view'])).toBe(false);
    expect(comFuncao(['custom_role', 'contact_manage'])).toBe(true);
  });
});

// #3062 — "Nova pessoa" e o lápis da linha seguem a regra de criar e editar
// contato; "Baixar planilha", a de exportar contato (ContactPolicy#export?).
describe('Nova pessoa, editar e baixar planilha', () => {
  it('administrador faz os três', () => {
    expect(assento({ papel: 'administrator' })).toMatchObject({
      editar: true,
      exportar: true,
    });
  });

  it('agente sem função edita, mas não baixa', () => {
    expect(assento()).toMatchObject({ editar: true, exportar: false });
  });

  // Achado do revisor do #3062: a função personalizada também tem papel
  // `agent` na conta, mas as permissões que o servidor manda para ela são as
  // chaves da função mais `custom_role`, sem `agent`
  // (enterprise/app/models/enterprise/account_user.rb). Sem contact_manage o
  // servidor responde 403 (Relationships::RecordPermissions): a tela esconde.
  it('função personalizada sem contact_manage não vê Nova pessoa, lápis nem Etiquetas', () => {
    const semManage = assento({
      papel: 'agent',
      funcao: 3,
      chaves: ['custom_role', 'contact_view', 'conversation_manage'],
    });
    expect(semManage).toMatchObject({ editar: false, etiquetar: false });
  });

  it('função personalizada: editar pede contact_manage; baixar, contact_export', () => {
    expect(
      assento({ funcao: 3, chaves: ['custom_role', 'contact_manage'] })
    ).toMatchObject({ editar: true, exportar: false });
    expect(
      assento({ funcao: 3, chaves: ['custom_role', 'contact_export'] })
    ).toMatchObject({ editar: false, exportar: true });
  });
});
