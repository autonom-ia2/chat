import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import {
  rotaDaEmpresa,
  rotaDaPessoa,
  useFichaDoContato,
} from '../useFichaDoContato';
import { useRoteadorDasFichas } from './fixtures/roteadorDasFichas';

// #3130 — com o menu novo de Relacionamentos, todo link leva à ficha nova.
describe('rotaDaPessoa e rotaDaEmpresa', () => {
  it('levam à ficha nova quando a conta tem o menu novo', () => {
    expect(rotaDaPessoa(1, 42, true)).toEqual({
      name: 'relacionamentos_pessoa',
      params: { accountId: 1, contactId: 42 },
    });
    expect(rotaDaEmpresa(1, 7, true)).toEqual({
      name: 'relacionamentos_empresa',
      params: { accountId: 1, companyId: 7 },
    });
  });

  it('levam à tela antiga só quando a conta não tem o menu novo', () => {
    expect(rotaDaPessoa(1, 42, false).name).toBe('contacts_edit');
    expect(rotaDaEmpresa(1, 7, false).name).toBe('companies_dashboard_show');
  });
});

describe('useFichaDoContato', () => {
  const montar = flagLigada => {
    let ficha;
    const flags = [];
    mount(
      defineComponent({
        setup() {
          ficha = useFichaDoContato();
          return () => h('div');
        },
      }),
      {
        global: {
          plugins: [
            createStore({
              getters: {
                getCurrentAccountId: () => 3,
                'accounts/isFeatureEnabledonAccount': () => (conta, flag) => {
                  flags.push([conta, flag]);
                  return flagLigada;
                },
              },
            }),
          ],
        },
      }
    );
    return { ficha, flags };
  };
  const endereco = rota => useRoteadorDasFichas().resolve(rota).href;

  it('com o menu novo, leva ao endereço da ficha nova da conta atual', () => {
    const { ficha, flags } = montar(true);
    expect(endereco(ficha.pessoa(42))).toBe(
      '/app/accounts/3/relacionamentos/pessoas/42'
    );
    expect(flags).toContainEqual([3, 'relationships_navigation']);
  });

  it('sem o menu novo, leva ao endereço da ficha antiga', () => {
    const { ficha } = montar(false);
    expect(endereco(ficha.pessoa(42))).toBe('/app/accounts/3/contacts/42');
  });
});
