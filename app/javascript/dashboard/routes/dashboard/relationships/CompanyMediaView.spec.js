import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import CompanyMediaView from './CompanyMediaView.vue';

// #3078 — a tela de mídias da empresa é aberta também pela ficha nova
// (Relacionamentos). Com o menu novo ligado, "Empresas" e a empresa no topo
// levam à lista nova e à ficha nova; sem ele, à lista e à ficha antigas.
const estado = vi.hoisted(() => ({ navegacao: null }));

vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => ({
    mediaEnabled: ref(true),
    navigationEnabled: estado.navegacao,
    accountId: ref(16),
  }),
}));
vi.mock('dashboard/api/relationships', () => ({
  default: { get: async () => ({ data: { payload: { name: 'Padaria' } } }) },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { companyId: '42' }, query: {} }),
}));

const montar = async navegacao => {
  estado.navegacao = ref(navegacao);
  const w = mount(CompanyMediaView, {
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        CompanyMedia: true,
        RouterLink: {
          props: ['to'],
          template: '<a :data-para="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return w;
};
const destinos = w =>
  w.findAll('a').map(a => JSON.parse(a.attributes('data-para')));

describe('CompanyMediaView: o caminho de volta', () => {
  it('com o menu novo, volta à aba Empresas e à ficha nova da empresa', async () => {
    const w = await montar(true);
    expect(destinos(w)).toEqual([
      { name: 'relationships_home', params: { accountId: 16 } },
      {
        name: 'relationships_home',
        params: { accountId: 16 },
        query: { aba: 'empresas' },
      },
      {
        name: 'relacionamentos_empresa',
        params: { accountId: 16, companyId: 42 },
      },
    ]);
  });

  it('sem o menu novo, volta à lista e à ficha antigas (com a aba Mídias)', async () => {
    const w = await montar(false);
    expect(destinos(w)).toEqual([
      { name: 'companies_dashboard_index', params: { accountId: 16 } },
      {
        name: 'companies_dashboard_show',
        params: { accountId: 16, companyId: 42 },
        query: { media: '{}' },
      },
    ]);
  });
});
