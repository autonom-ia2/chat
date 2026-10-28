import { mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import CrmVistasNumeros from './CrmVistasNumeros.vue';

// Seletor da página Números (#1617): só leva a vistas que a pessoa abre.
const estado = { abre: () => true, listaAcao: false };

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    getCurrentAccountId: () => 1,
    'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
      flag === 'crm_lista_acao' && estado.listaAcao,
  };
  return { useMapGetter: nome => computed(getters[nome]) };
});
vi.mock('./useAbaNumeros', async () => {
  const { computed } = await import('vue');
  return {
    ROTA_NUMEROS: 'crm_dashboard_index',
    useAbaNumeros: () => ({ mostrar: computed(() => true) }),
  };
});
vi.mock('dashboard/components-next/sidebar/fork/usePodeAbrir', () => ({
  usePodeAbrir: () => ({ podeAbrir: to => estado.abre(to) }),
}));

const RouterLink = defineComponent({
  props: { to: { type: Object, required: true } },
  setup(props, { slots, attrs }) {
    return () =>
      h(
        'a',
        {
          ...attrs,
          'data-rota': props.to.name,
          'data-vista': props.to.query?.view,
        },
        slots.default?.()
      );
  },
});

const montar = () =>
  mount(CrmVistasNumeros, { global: { components: { RouterLink } } });
const textos = wrapper => wrapper.findAll('a').map(link => link.text());

describe('CrmVistasNumeros', () => {
  it('quem abre o CRM vê Kanban, Lista, Calendário e Números', () => {
    estado.abre = () => true;
    expect(textos(montar())).toEqual([
      'CRM_KANBAN.VIEWS.KANBAN',
      'CRM_KANBAN.VIEWS.LIST',
      'CRM_KANBAN.VIEWS.CALENDAR',
      'FORK_SIDEBAR.CRM.ABA_NUMEROS',
    ]);
  });

  it('com a Lista nova (#2283), o Kanban se chama Quadro', () => {
    estado.abre = () => true;
    estado.listaAcao = true;
    expect(textos(montar())[0]).toBe('CRM_LISTA_ACAO.VISTAS.QUADRO');
    estado.listaAcao = false;
  });

  it('crm_view_reports sem crm_view: só Números, sem link para o quadro', () => {
    estado.abre = to => to.name !== 'crm_kanban_index';
    const wrapper = montar();
    expect(textos(wrapper)).toEqual(['FORK_SIDEBAR.CRM.ABA_NUMEROS']);
    expect(wrapper.find('a').attributes('aria-current')).toBe('page');
  });
});
