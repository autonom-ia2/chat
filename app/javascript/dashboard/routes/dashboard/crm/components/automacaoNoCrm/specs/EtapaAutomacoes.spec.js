import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import EtapaAutomacoes from '../EtapaAutomacoes.vue';

// #2414 F6.5 — as regras da etapa e as automações novas numa lista só, a ação
// principal "Nova automação para esta etapa" com o gatilho já escolhido, e o
// aviso da F6.4 sobre arquivar em lote.
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

const montar = async () => {
  const wrapper = mount(EtapaAutomacoes, { props: { etapaId: 12 } });
  await flushPromises();
  return wrapper;
};
const linhas = wrapper => wrapper.findAll('[data-automacao-da-etapa]');
const AVISO =
  'Arquivar vários cards de uma vez não conta como “saiu da etapa”.';

describe('EtapaAutomacoes', () => {
  beforeEach(() => {
    rota.query = {};
    permissao.montar = true;
    push.mockClear();
  });

  it('mostra as antigas e as novas numa lista só, como frases', async () => {
    const wrapper = await montar();
    expect(wrapper.text()).toContain('Automações desta etapa');
    expect(linhas(wrapper)).toHaveLength(3);
    expect(linhas(wrapper)[0].find('[data-frase]').text()).toContain(
      'Quando o card entra'
    );
    expect(linhas(wrapper)[0].text()).toContain(
      'Cria a tarefa “Ligar para o cliente”'
    );
    expect(linhas(wrapper)[2].find('[data-frase]').text()).toContain(
      'Quando o card sai'
    );
    expect(linhas(wrapper)[2].find('[data-desligada]').text()).toBe(
      'Desligada'
    );
    expect(wrapper.find('[data-aviso-arquivar]').text()).toBe(AVISO);
  });

  it('"Nova automação para esta etapa" abre o editor com o gatilho dela', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-nova-automacao]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'automacoes_livre_nova',
      params: { accountId: '1' },
      query: { gatilho: 'card.entrou_na_etapa', etapa: '12' },
    });
  });

  it('"Alterar" da regra da etapa abre a tela dela; o da nova, a automação', async () => {
    const wrapper = await montar();
    const alterar = wrapper.findAll('[data-alterar-automacao]');
    await alterar[0].trigger('click');
    expect(wrapper.emitted('antigas')).toHaveLength(1);
    expect(push).not.toHaveBeenCalled();

    await alterar[1].trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'automacoes_lista',
      params: { accountId: '1' },
    });
  });

  it('vazio: uma frase e o botão de criar; o aviso continua', async () => {
    rota.query = { demo: 'vazio' };
    const wrapper = await montar();
    expect(wrapper.find('[data-etapa-automacoes-vazio]').text()).toBe(
      'Esta etapa ainda não tem automação.'
    );
    expect(wrapper.find('[data-nova-automacao]').exists()).toBe(true);
    expect(wrapper.find('[data-aviso-arquivar]').exists()).toBe(true);
  });

  it('sem a chave das automações, só se vê', async () => {
    permissao.montar = false;
    const wrapper = await montar();
    expect(wrapper.find('[data-nova-automacao]').exists()).toBe(false);
    expect(wrapper.findAll('[data-alterar-automacao]')).toHaveLength(0);
    expect(wrapper.text()).toContain(
      'Você pode ver. Só quem cuida das automações pode mudar.'
    );
  });
});
