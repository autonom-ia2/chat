import { mount } from '@vue/test-utils';
import { defineComponent, ref } from 'vue';
import { useQuemVeNumeros } from './useQuemVeNumeros';

// Quem vê o quê em CRM › Números (#1897): a mesma matriz da Crm::NumerosPolicy.
const estado = { papel: 'agent', funcao: null, chaves: [], porPapel: true };

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
    })[chave],
}));

const quemVe = () => {
  let api;
  mount(
    defineComponent({
      setup() {
        api = useQuemVeNumeros();
        return () => null;
      },
    })
  );
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
  };

  it('com a flag: "Só eu" para quem trabalha no CRM e a equipe só com a chave', () => {
    const esperado = {
      administrador: [true, true],
      agente: [true, false],
      gestor: [true, true],
      crm: [true, false],
      socio: [false, true],
      semCrm: [false, false],
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
