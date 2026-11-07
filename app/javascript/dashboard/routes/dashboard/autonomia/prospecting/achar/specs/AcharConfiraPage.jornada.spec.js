import { flushPromises, mount } from '@vue/test-utils';
import AcharConfiraPage from '../pages/AcharConfiraPage.vue';

// Jornadas 1 e 2 da v4 na tela de verdade, com a demonstração: a lista com 2
// tiradas, a folha com os dois cartões, a prévia do funil sem "Alterar" para o
// agente (caso B) e com "Alterar" para a gestora (caso A).
const { rota, push } = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  const estado = reactive({
    name: 'autonomia_prospecting_achar_busca',
    params: { accountId: '1', searchId: 'demo' },
    query: {},
  });
  return {
    rota: estado,
    push: vi.fn(async destino => {
      estado.query = { ...destino.query };
    }),
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const valores = { getCurrentAccountId: 1, getCurrentUser: { id: 1 } };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => true) };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../composables/useLeadLiveUpdates', () => ({
  useLeadLiveUpdates: vi.fn(),
}));

const abrir = async query => {
  rota.query = query;
  const wrapper = mount(AcharConfiraPage, { attachTo: document.body });
  // A demonstração chega por import dinâmico: espera a lista sair do esqueleto.
  await vi.waitFor(() => {
    expect(wrapper.find('[aria-busy]').exists()).toBe(false);
  });
  await flushPromises();
  return wrapper;
};

describe('AcharConfiraPage na demonstração', () => {
  beforeEach(() => {
    push.mockClear();
  });

  it('J1: lista com 2 tiradas e "Continuar" leva à folha', async () => {
    const wrapper = await abrir({ demo: 'confira-tirou' });

    // 20 achadas = 16 que podem ir + 4 de fora; "Chame primeiro" fora do grupo.
    expect(wrapper.findAll('[data-empresa]')).toHaveLength(20);
    expect(wrapper.find('[data-chame-primeiro] [data-empresa]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-principal]').text()).toContain('CONTINUAR');
    expect(
      wrapper.findAll('[role="switch"][aria-checked="false"]')
    ).toHaveLength(2);
    await wrapper.find('[data-principal]').trigger('click');
    expect(push).toHaveBeenLastCalledWith(
      expect.objectContaining({
        query: expect.objectContaining({ demo: 'folha' }),
      })
    );
    await flushPromises();

    expect(document.querySelector('[data-escolha-funil]')).not.toBeNull();
    expect(document.querySelector('[data-escolha-lista]')).not.toBeNull();
    wrapper.unmount();
  });

  it('J1: o agente (caso B) vê "Com quem fica: você" sem "Alterar"', async () => {
    const wrapper = await abrir({ demo: 'folha-funil-agente' });
    const comQuem = document.querySelector('[data-com-quem]');

    expect(document.querySelector('[data-previa-funil]')).not.toBeNull();
    expect(comQuem.querySelector('[data-alterar]')).toBeNull();
    wrapper.unmount();
  });

  it('J2: a gestora (caso A) vê o "Alterar" de quem fica', async () => {
    const wrapper = await abrir({ demo: 'folha-funil', papel: 'gestora' });
    const comQuem = document.querySelector('[data-com-quem]');

    expect(comQuem.querySelector('[data-alterar]')).not.toBeNull();
    wrapper.unmount();
  });

  it('J5: só Ver lê a lista sem interruptor e sem rodapé', async () => {
    const wrapper = await abrir({ demo: 'leitura' });

    expect(wrapper.findAll('[data-empresa]').length).toBeGreaterThan(0);
    expect(wrapper.find('[role="switch"]').exists()).toBe(false);
    expect(wrapper.find('[data-rodape]').exists()).toBe(false);
    wrapper.unmount();
  });
});
