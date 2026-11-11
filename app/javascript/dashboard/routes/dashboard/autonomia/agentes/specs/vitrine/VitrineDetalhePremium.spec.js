import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';

// #2858 F7 — o detalhe do card Premium troca o "Experimente" (cada consulta é paga) pelo quadro "Quanto custa". O card
// grátis continua com o "Experimente".
const vitrine = vi.hoisted(() => ({
  premiumDe: vi.fn(),
  tem: vi.fn(() => false),
  incluir: vi.fn(),
  experimentar: vi.fn(),
}));
vi.mock('../../vitrine/useVitrine', () => ({ useVitrine: () => vitrine }));

withFullI18n('pt_BR');

const { default: VitrineDetalhe } = await import(
  '../../vitrine/components/VitrineDetalhe.vue'
);
const { ferramentaPorId } = await import('../../vitrine/catalogo');

const montar = id =>
  mount(VitrineDetalhe, {
    props: {
      ferramenta: ferramentaPorId(id),
      agentes: [{ id: 1, name: 'Ana' }],
    },
    global: {
      stubs: {
        AgenteGaveta: { template: '<div><slot /><slot name="rodape" /></div>' },
        VitrineExperimente: { template: '<div data-stub-experimente />' },
      },
    },
  });

describe('VitrineDetalhe · Premium', () => {
  it('the Premium card shows how much it costs and no "Try it"', () => {
    vitrine.premiumDe.mockReturnValue({
      gratis: 20,
      restantes: 3,
      precos: ['0.06', '0.15'],
    });
    const wrapper = montar('certidoes_empresa');
    expect(wrapper.find('[data-vitrine-detalhe-premium]').text()).toContain(
      'Quanto custa'
    );
    expect(wrapper.find('[data-vitrine-detalhe-premium]').text()).toContain(
      'Restam 3 grátis'
    );
    expect(wrapper.find('[data-stub-experimente]').exists()).toBe(false);
  });

  it('the free card keeps "Try it"', () => {
    vitrine.premiumDe.mockReturnValue(null);
    const wrapper = montar('cep');
    expect(wrapper.find('[data-vitrine-detalhe-premium]').exists()).toBe(false);
    expect(wrapper.find('[data-stub-experimente]').exists()).toBe(true);
  });
});
