import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import CardAutomacoes from '../CardAutomacoes.vue';

// #2414 F6.3 — "Automações deste card": uma frase por automação, "Parar para
// este card" com a confirmação numa frase, e o vazio com uma frase e um botão.
const { rota, push, permissao } = vi.hoisted(() => ({
  rota: { params: { accountId: '1' }, query: {} },
  push: vi.fn(),
  permissao: { montar: true },
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/usePodeMontarAutomacao', async () => {
  const { computed } = await import('vue');
  return { usePodeMontarAutomacao: () => computed(() => permissao.montar) };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmKanban', () => ({ default: {} }));

withFullI18n('pt_BR');

const card = { id: 5, stage_id: 12, status: 'open' };
const montar = async (props = {}) => {
  const wrapper = mount(CardAutomacoes, {
    props: { card, podeGerenciar: true, ...props },
    attachTo: document.body,
  });
  await flushPromises();
  return wrapper;
};
const linhas = wrapper => wrapper.findAll('[data-automacao-do-card]');

describe('CardAutomacoes', () => {
  beforeEach(() => {
    rota.query = {};
    permissao.montar = true;
    push.mockClear();
  });

  it('lista em frases o que age no card', async () => {
    const wrapper = await montar();
    expect(wrapper.text()).toContain('Automações deste card');
    expect(linhas(wrapper)).toHaveLength(3);
    expect(linhas(wrapper)[0].text()).toContain(
      'Lembrete de proposta — espera até 15/11'
    );
    expect(linhas(wrapper)[1].text()).toContain(
      'Avisar a equipe se o cliente sumir — espera o cliente responder'
    );
    expect(wrapper.findAll('[data-parar]')).toHaveLength(3);
    wrapper.unmount();
  });

  it('pede confirmação numa frase e só então para', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-parar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-confirma]').text()).toBe(
      'Parar Lembrete de proposta só neste card?'
    );
    expect(document.activeElement).toBe(
      wrapper.find('[data-parar-sim]').element
    );

    await wrapper.find('[data-parar-voltar]').trigger('click');
    expect(wrapper.find('[data-confirma]').exists()).toBe(false);
    expect(linhas(wrapper)).toHaveLength(3);

    await wrapper.find('[data-parar]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-parar-sim]').trigger('click');
    await flushPromises();
    expect(linhas(wrapper)).toHaveLength(2);
    expect(wrapper.text()).not.toContain('Lembrete de proposta —');
    expect(wrapper.find('[data-aviso-parar]').text()).toBe(
      'Lembrete de proposta parou neste card. Os outros cards continuam.'
    );
    wrapper.unmount();
  });

  it('sem poder mexer, só mostra a lista', async () => {
    const semCard = await montar({ podeGerenciar: false });
    expect(semCard.findAll('[data-parar]')).toHaveLength(0);
    semCard.unmount();

    permissao.montar = false;
    const semChave = await montar();
    expect(semChave.findAll('[data-parar]')).toHaveLength(0);
    semChave.unmount();
  });

  it('vazio: uma frase e um botão que abre o editor na etapa do card', async () => {
    rota.query = { demo: 'vazio' };
    const wrapper = await montar();
    expect(wrapper.find('[data-automacoes-vazio]').text()).toContain(
      'Nenhuma automação está cuidando deste card agora.'
    );
    await wrapper.find('[data-criar-automacao]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'automacoes_livre_nova',
      params: { accountId: '1' },
      query: { gatilho: 'card.entrou_na_etapa', etapa: '12' },
    });
    wrapper.unmount();
  });
});
