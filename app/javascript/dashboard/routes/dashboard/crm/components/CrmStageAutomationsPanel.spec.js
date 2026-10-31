import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import CrmStageAutomationsPanel from './CrmStageAutomationsPanel.vue';
import FunilEtapaAcoes from './funil/FunilEtapaAcoes.vue';

// #2414 F1.3: mexer em automação de etapa pede também a chave das regras automáticas (a API recusa sem ela). Sem a
// chave, a pessoa vê as automações, mas sem criar, editar ou apagar; no resumo da etapa, "Ver" no lugar de "Alterar".
const podeMontar = ref(true);
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: () => podeMontar,
}));

const automacao = {
  id: 7,
  name: 'Entrou',
  trigger_event: 'on_enter',
  enabled: true,
  steps: [],
};
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: { 'crmKanban/getUIFlags': {} },
    dispatch: vi.fn().mockResolvedValue([automacao]),
  }),
}));

const montarPainel = async () => {
  const wrapper = mount(CrmStageAutomationsPanel, {
    props: { stage: { id: 3, name: 'Novo' }, expanded: true },
  });
  await flushPromises();
  return wrapper;
};

const montarResumo = async () => {
  const wrapper = mount(FunilEtapaAcoes, {
    props: { etapaId: 3 },
  });
  await flushPromises();
  return wrapper;
};

describe('automação de etapa e a chave das regras automáticas', () => {
  it('com a chave, mostra criar, editar e apagar', async () => {
    podeMontar.value = true;
    const wrapper = await montarPainel();

    expect(wrapper.text()).toContain('Entrou');
    expect(wrapper.find('button .i-lucide-plus').exists()).toBe(true);
    expect(wrapper.find('button .i-lucide-pencil').exists()).toBe(true);
    expect(wrapper.find('button .i-lucide-trash-2').exists()).toBe(true);
  });

  it('sem a chave, lista as automações sem criar, editar ou apagar', async () => {
    podeMontar.value = false;
    const wrapper = await montarPainel();

    expect(wrapper.text()).toContain('Entrou');
    expect(wrapper.find('button .i-lucide-plus').exists()).toBe(false);
    expect(wrapper.find('button .i-lucide-pencil').exists()).toBe(false);
    expect(wrapper.find('button .i-lucide-trash-2').exists()).toBe(false);
  });

  it('no resumo da etapa, sem a chave o botão é "Ver"', async () => {
    podeMontar.value = false;
    const wrapper = await montarResumo();

    expect(wrapper.find('button .i-lucide-eye').exists()).toBe(true);
    expect(wrapper.find('button .i-lucide-pencil').exists()).toBe(false);
  });
});
