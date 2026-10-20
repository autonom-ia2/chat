import { mount } from '@vue/test-utils';
import { defineComponent, ref } from 'vue';
import { useQuemVeNumeros } from './useQuemVeNumeros';

// Quem vê o quê em CRM › Números (#1897): a mesma matriz da Crm::NumerosPolicy.
const estado = {
  papel: 'agent',
  funcao: null,
  chaves: [],
  porPapel: true,
  contaCarregada: true,
};

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: chave =>
    ({
      getCurrentAccountId: ref(1),
      getCurrentUser: ref({
        accounts: [{ id: 1, permissions: estado.chaves }],
      }),
      getCurrentRole: ref(estado.papel),
      getCurrentCustomRoleId: ref(estado.funcao),
      'accounts/isFeatureEnabledonAccount': ref(() => estado.porPapel),
      'accounts/getAccount': ref(() =>
        estado.contaCarregada ? { id: 1, features: {} } : {}
      ),
    })[chave],
}));

const montar = () => {
  let api;
  mount(
    defineComponent({
      setup() {
        api = useQuemVeNumeros();
        return () => null;
      },
    })
  );
  return api;
};
const quemVe = () => {
  const api = montar();
  return [api.veSoEu.value, api.veEquipe.value];
};

describe('useQuemVeNumeros', () => {
  const pessoas = {
    administrador: { papel: 'administrator', funcao: null, chaves: [] },
    agente: { papel: 'agent', funcao: null, chaves: [] },
    gestor: {
      papel: 'agent',
      funcao: 3,
      chaves: ['crm_view', 'crm_view_reports'],
    },
    crm: { papel: 'agent', funcao: 3, chaves: ['crm_view'] },
    socio: { papel: 'agent', funcao: 3, chaves: ['crm_view_reports'] },
    semCrm: { papel: 'agent', funcao: 3, chaves: ['conversation_manage'] },
    // A rota de Números não aceita crm_admin: sem a chave da rota, nada abre.
    crmAdmin: { papel: 'agent', funcao: 3, chaves: ['crm_admin'] },
  };

  it('com a flag: "Só eu" para quem trabalha no CRM e a equipe só com a chave', () => {
    const esperado = {
      administrador: [true, true],
      agente: [true, false],
      gestor: [true, true],
      crm: [true, false],
      socio: [false, true],
      semCrm: [false, false],
      crmAdmin: [false, false],
    };
    Object.entries(pessoas).forEach(([quem, pessoa]) => {
      Object.assign(estado, pessoa, { porPapel: true });
      expect([quem, ...quemVe()]).toEqual([quem, ...esperado[quem]]);
    });
  });

  it('sem a flag: ninguém tem "Só eu" e o agente sem função segue vendo a equipe', () => {
    Object.assign(estado, pessoas.agente, { porPapel: false });
    expect(quemVe()).toEqual([false, true]);
    Object.assign(estado, pessoas.crm, { porPapel: false });
    expect(quemVe()).toEqual([false, false]);
  });
});

describe('useQuemVeNumeros antes da conta carregar', () => {
  // Na carga direta da página as flags da conta ainda não chegaram: sem esperar,
  // o agente sem função parece "sem a flag", monta o painel da equipe e leva 401.
  it('agente sem função: não escolhe visão, mas o item de Números não some do menu', () => {
    Object.assign(estado, { papel: 'agent', funcao: null, chaves: [] });
    Object.assign(estado, { porPapel: false, contaCarregada: false });
    const api = montar();
    expect(api.pronto.value).toBe(false);
    expect([api.veSoEu.value, api.veEquipe.value]).toEqual([false, false]);
    expect(api.abreNumeros.value).toBe(true);
  });

  it('quem vê a equipe sem depender da flag já a vê; a função só com crm_view espera', () => {
    Object.assign(estado, { porPapel: false, contaCarregada: false });
    Object.assign(estado, { papel: 'administrator', funcao: null, chaves: [] });
    expect(montar().veEquipe.value).toBe(true);
    Object.assign(estado, { papel: 'agent', funcao: 3 });
    estado.chaves = ['crm_view_reports'];
    expect(montar().veEquipe.value).toBe(true);
    estado.chaves = ['crm_view'];
    expect(montar().abreNumeros.value).toBe(false);
  });

  it('fica pronto quando a conta chega', () => {
    Object.assign(estado, { porPapel: true, contaCarregada: true });
    expect(montar().pronto.value).toBe(true);
  });
});
