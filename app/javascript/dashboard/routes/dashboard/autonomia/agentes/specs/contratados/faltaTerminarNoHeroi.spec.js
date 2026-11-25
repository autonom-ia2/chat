import { mount } from '@vue/test-utils';
import PaginaHeroi from '../../components/pagina/PaginaHeroi.vue';
import AgenteStatus from '../../components/AgenteStatus.vue';
import { ESTADO } from '../../utils/estadoDoAgente';

// #3211 — "Falta terminar" no topo da página, para quem gerencia: só no rascunho do agente contratado (que nasce
// assim, sem o interruptor). O rascunho dos outros agentes segue como sempre, sem a pílula.
vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: rota => ({ href: `/app/${rota.name}` }) }),
}));

const montar = props =>
  mount(PaginaHeroi, {
    props: {
      nome: 'Bia',
      estado: ESTADO.FALTA_TERMINAR,
      hrefLista: '/app/agentes',
      podeGerenciar: true,
      ...props,
    },
  });

const pilula = wrapper => wrapper.findComponent(AgenteStatus);

describe('PaginaHeroi: "Falta terminar" (#3211)', () => {
  it('shows the draft pill to whoever manages a hired agent', () => {
    const wrapper = montar({ contratado: true });
    expect(pilula(wrapper).exists()).toBe(true);
    expect(pilula(wrapper).text()).toContain(
      'AGENTS.JORNADA.STATUS.FALTA_TERMINAR'
    );
  });

  it('does not show it on the draft of an agent that is not hired', () => {
    expect(pilula(montar()).exists()).toBe(false);
  });

  it('keeps the pill for whoever only views, hired or not', () => {
    expect(pilula(montar({ podeGerenciar: false })).exists()).toBe(true);
  });

  it('shows no pill to whoever manages a hired agent that already works', () => {
    const wrapper = montar({ contratado: true, estado: ESTADO.PARADO });
    expect(pilula(wrapper).exists()).toBe(false);
  });
});
