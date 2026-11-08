import { mount } from '@vue/test-utils';
import AcharPortaPage from '../pages/AcharPortaPage.vue';

// Regra do lugar digitado (v4, C4) na porta de verdade, com a demonstração:
// várias sugestões não escolhem sozinhas: o botão "Achar empresas" fica
// desligado e a linha acima dele pede o toque na lista (rodada 2); uma
// sugestão só vale sozinha e o botão liga.
const { rota } = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  return {
    rota: reactive({
      name: 'autonomia_prospecting_achar',
      params: { accountId: '1' },
      query: {},
    }),
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const valores = { getCurrentAccountId: 1, getCurrentUser: { id: 1 } };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => true),
    usePermissionGranted: () => computed(() => false),
  };
});

const botao = wrapper => wrapper.find('[data-principal]');

describe('AcharPortaPage: o lugar digitado', () => {
  it('várias sugestões: nada é escolhido e a dica pede o toque na lista', async () => {
    rota.query = { demo: 'porta-sugestoes' };
    const wrapper = mount(AcharPortaPage);

    await vi.waitFor(
      () => {
        expect(wrapper.findAll('[data-sugestao]')).toHaveLength(3);
      },
      { timeout: 3000 }
    );
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(false);
    expect(wrapper.find('[data-dica]').text()).toContain('PORTA.FALTA.TOCAR');
    expect(botao(wrapper).text()).toContain('PORTA.BOTAO');
    expect(botao(wrapper).attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });

  it('uma sugestão só: ela vale sozinha, com o visto e o "Alterar"', async () => {
    rota.query = { demo: 'porta-uma-sugestao' };
    const wrapper = mount(AcharPortaPage);

    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(true);
      },
      { timeout: 3000 }
    );
    expect(wrapper.find('[data-alterar-lugar]').exists()).toBe(true);
    expect(botao(wrapper).text()).toContain('PORTA.BOTAO');
    expect(wrapper.find('[data-dica]').exists()).toBe(false);
    wrapper.unmount();
  });
});
