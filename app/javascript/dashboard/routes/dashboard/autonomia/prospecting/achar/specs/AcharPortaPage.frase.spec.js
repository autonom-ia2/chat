import { mount } from '@vue/test-utils';
import AcharPortaPage from '../pages/AcharPortaPage.vue';

// Pedido em uma frase (#2696) na porta de verdade, com a demonstração: a IA
// preenche "O quê?", "Onde?" e os ajustes; erro e "não entendi" deixam os
// campos como estavam e dizem o que fazer; sem a IA da conta, o campo some.
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
// Trocar o dono (#2694) é crm_manage_pipelines: aqui ninguém gere funis.
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({ canManagePipelines: computed(() => false) }),
    };
  }
);
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => true),
    usePermissionGranted: () => computed(() => false),
  };
});

const oQue = wrapper => wrapper.find('[data-campo-o-que]').element.value;

const pedir = async (wrapper, frase = 'padarias no centro com nota boa') => {
  await vi.waitFor(
    () => {
      expect(wrapper.find('[data-campo-frase]').exists()).toBe(true);
    },
    { timeout: 3000 }
  );
  await wrapper.find('[data-campo-frase]').setValue(frase);
  await wrapper.find('[data-preencher]').trigger('click');
};

describe('AcharPortaPage: o pedido em uma frase', () => {
  it('preenche o quê, o onde (com as sugestões para conferir) e os ajustes', async () => {
    rota.query = { demo: 'porta' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper);

    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-aviso-frase]').text()).toContain(
          'PORTA.FRASE.CONFIRA'
        );
      },
      { timeout: 3000 }
    );
    expect(oQue(wrapper)).toBe('Padarias');
    expect(wrapper.find('[data-ficou-de-fora]').text()).toContain(
      'horário que abre'
    );
    expect(wrapper.text()).toContain('PORTA.COMO.AJUSTES');
    await vi.waitFor(
      () => {
        expect(wrapper.findAll('[data-sugestao]')).toHaveLength(3);
      },
      { timeout: 3000 }
    );
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('erro da IA: os campos ficam como estavam e o aviso pede para preencher', async () => {
    rota.query = { demo: 'porta-frase-erro' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper);

    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-aviso-frase]').text()).toContain(
          'PORTA.FRASE.ERRO'
        );
      },
      { timeout: 3000 }
    );
    expect(oQue(wrapper)).toBe('Escritórios');
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('PORTA.COMO.AJUSTES');
    wrapper.unmount();
  });

  it('"não entendi": nada muda e o aviso pede outro jeito', async () => {
    rota.query = { demo: 'porta-frase-nao-entendeu' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper, 'bom dia');

    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-aviso-frase]').text()).toContain(
          'PORTA.FRASE.NAO_ENTENDEU'
        );
      },
      { timeout: 3000 }
    );
    expect(oQue(wrapper)).toBe('Escritórios');
    wrapper.unmount();
  });

  it('conta sem a IA: o campo da frase não aparece e os dois campos seguem', async () => {
    rota.query = { demo: 'porta-sem-ia' };
    const wrapper = mount(AcharPortaPage);

    await vi.waitFor(
      () => {
        expect(oQue(wrapper)).toBe('Escritórios');
      },
      { timeout: 3000 }
    );
    expect(wrapper.find('[data-frase]').exists()).toBe(false);
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(true);
    wrapper.unmount();
  });
});
