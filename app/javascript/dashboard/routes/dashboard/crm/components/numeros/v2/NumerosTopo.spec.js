import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptCrm from 'dashboard/i18n/locale/pt_BR/crm.json';
import NumerosTopo from './NumerosTopo.vue';

vi.mock('shared/composables/useLocale', async () => {
  const { ref } = await import('vue');
  return { useLocale: () => ({ resolvedLocale: ref('pt-BR') }) };
});

// Topo de CRM › Números (#1897): `traduzir` só põe em R$ o que é venda. Quem
// atende conta casos — nem nos dias 1 a 3 (CEDO) a contagem vira dinheiro.
const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { pt_BR: ptCrm },
});
const plugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = plugins;
});

const CEDO = { dia: 2, diasNoMes: 31, fechado: false };
const montar = topo =>
  mount(NumerosTopo, {
    props: { topo, mes: CEDO, mesNome: 'outubro', rotuloDoMes: 'Outubro' },
    global: { plugins: [i18n], stubs: { RouterLink: true } },
  });

describe('NumerosTopo', () => {
  it('quem atende, nos dias 1 a 3: conta casos, sem R$', () => {
    const texto = montar({
      medida: 'resolvidos',
      feito: 2,
      meta: null,
      frase: { tipo: 'eu_atende', noPrazo: null, falta: null, dias: 29 },
    }).text();
    expect(texto).toContain('Ainda é cedo para dizer');
    expect(texto).toContain('Casos resolvidos até agora: 2.');
    expect(texto).not.toContain('R$');
  });

  it('quem vende, nos dias 1 a 3: o feito vem em R$', () => {
    const texto = montar({
      medida: 'valor',
      feito: 600,
      meta: null,
      fechadas: 1,
      frase: { tipo: 'eu_vende', feito: 600, meta: null, dias: 29 },
    }).text();
    expect(texto).toContain('Até agora: R$ 600.');
  });

  it('quem atende, fora do CEDO: a falta da meta é contagem, não dinheiro', () => {
    const wrapper = mount(NumerosTopo, {
      props: {
        topo: {
          medida: 'resolvidos',
          feito: 6,
          meta: 10,
          esperadoPct: 50,
          frase: { tipo: 'eu_atende', noPrazo: 5, falta: 4, dias: 12 },
        },
        mes: { dia: 19, diasNoMes: 31, fechado: false },
        mesNome: 'outubro',
        rotuloDoMes: 'Outubro',
      },
      global: { plugins: [i18n], stubs: { RouterLink: true } },
    });
    expect(wrapper.text()).toContain('Faltam 4 para a sua meta.');
    expect(wrapper.text()).not.toContain('R$');
  });
});
