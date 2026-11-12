import { mount } from '@vue/test-utils';
import CompanyCustomAttributes from '../CompanyCustomAttributes.vue';

// #2435 — na empresa, o atributo com "Mostrar na tela" desligado não aparece,
// com ou sem valor. A lista passa pelo getter de verdade
// (attributes/getCompanyAttributes), que só converte para camelCase.
const state = vi.hoisted(() => ({ records: [] }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', async () => {
  const { getters } = await import('dashboard/store/modules/attributes');
  return {
    useStore: () => ({ dispatch: vi.fn() }),
    useMapGetter: () => ({
      get value() {
        return getters.getCompanyAttributes({ records: state.records });
      },
    }),
  };
});

const definicao = (id, chave, extra = {}) => ({
  id,
  attribute_key: chave,
  attribute_display_name: chave,
  attribute_display_type: 'text',
  attribute_model: 'company_attribute',
  ...extra,
});

const montar = customAttributes =>
  mount(CompanyCustomAttributes, {
    props: { company: { id: 5, customAttributes } },
    global: {
      stubs: {
        CompanyCustomAttributeItem: {
          props: ['attribute'],
          template: '<div data-campo>{{ attribute.attributeKey }}</div>',
        },
      },
    },
  });
const campos = wrapper => wrapper.findAll('[data-campo]').map(c => c.text());

describe('CompanyCustomAttributes — atributo fora da tela', () => {
  beforeEach(() => {
    state.records = [
      definicao(1, 'segmento'),
      definicao(2, 'codigo_erp', { oculto_na_tela: true }),
    ];
  });

  it('com valor ou sem valor, o atributo fora da tela não aparece', () => {
    expect(campos(montar({ segmento: 'Varejo', codigo_erp: 'X1' }))).toEqual([
      'segmento',
    ]);
    expect(campos(montar({}))).toEqual(['segmento']);
  });

  it('só com atributos fora da tela, a empresa mostra o estado vazio', () => {
    state.records = [definicao(2, 'codigo_erp', { oculto_na_tela: true })];
    const wrapper = montar({ codigo_erp: 'X1' });
    expect(campos(wrapper)).toEqual([]);
    expect(wrapper.text()).toContain('COMPANIES.DETAIL.ATTRIBUTES.EMPTY_STATE');
  });
});
