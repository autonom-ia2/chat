import { flushPromises, mount } from '@vue/test-utils';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { PRESETS } from '../../customRoles/permissionMatrix';
import GavetaDaFuncao from '../pessoas/GavetaDaFuncao.vue';
import { espiarDialogo, global, loja } from './montar';
import { CARLA } from './quemMonta';

// #2308, especificação 5.D e 14: a gaveta de quem usa uma função e a de quem está sem função, com a Carla.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/auth', () => ({
  default: { validityCheck: vi.fn().mockResolvedValue({}) },
}));

const ATENDENTE = { id: 1, name: 'Atendente', permissions: PRESETS.AGENT() };
const VENDEDOR = { id: 2, name: 'Vendedor', permissions: PRESETS.SDR() };
const FINANCEIRO = {
  id: 3,
  name: 'Financeiro',
  permissions: ['financial_view'],
};
const AGENTES = [
  { id: 21, name: 'Gabriel Souza', role: 'agent', custom_role_id: 2 },
  { id: 22, name: 'Eduarda Pires', role: 'agent', custom_role_id: 2 },
  { id: 23, name: 'Íris Lopes', role: 'agent', custom_role_id: 1 },
  { id: 24, name: 'Kauã Moreira', role: 'agent', custom_role_id: null },
  { id: 25, name: 'Lia Rocha', role: 'administrator', custom_role_id: null },
  { id: CARLA.userId, name: 'Carla Dias', role: 'agent', custom_role_id: 7 },
];

const GERENTE = { id: 7, name: 'Gerente da loja', permissions: ['crm_view'] };

const montar = ({
  funcao = VENDEDOR,
  giver = CARLA,
  flags = [],
  atualizar = vi.fn(),
} = {}) => {
  const recarregar = vi.fn();
  const store = loja({
    giver,
    flags,
    funcoes: [ATENDENTE, VENDEDOR, FINANCEIRO],
    agentes: AGENTES,
    actions: { 'agents/update': atualizar, 'agents/get': recarregar },
  });
  const wrapper = mount(GavetaDaFuncao, {
    attachTo: document.body,
    props: { funcao },
    global: {
      ...global(store),
      stubs: { ...global(store).stubs, Avatar: true },
    },
  });
  return { wrapper, atualizar, recarregar };
};

// A recusa como a store de agentes a lança (agents.js: Error com status e code da resposta).
const recusa = (status, code) =>
  Object.assign(new Error('Request failed'), { status, code });
const acoesDasPessoas = wrapper => wrapper.findAll('[data-pessoa] [data-acao]');

const linha = (wrapper, id) => wrapper.find(`[data-pessoa="${id}"]`);
const nomes = lista => lista.findAll('[data-pessoa]').map(item => item.text());

afterEach(() => {
  document.body.innerHTML = '';
});

describe('GavetaDaFuncao', () => {
  it('quem já é, em ordem alfabética, e as outras pessoas com a trava escrita', () => {
    const { wrapper } = montar();

    expect(wrapper.find('h2').text()).toBe('Quem vai ser Vendedor?');
    expect(wrapper.text()).toContain('Já são Vendedor (2)');
    expect(nomes(wrapper.find('[data-ja-sao]'))[0]).toContain('Eduarda Pires');
    expect(
      linha(wrapper, 21).find('[data-acao]').attributes('aria-label')
    ).toBe('Tirar Gabriel Souza desta função');
    expect(linha(wrapper, 25).text()).toContain(
      'Já pode tudo: tem acesso de administrador'
    );
    expect(linha(wrapper, 25).find('[data-acao]').exists()).toBe(false);
    expect(linha(wrapper, CARLA.userId).text()).toContain(
      'Ninguém muda a própria função'
    );
    expect(linha(wrapper, 24).find('[data-estado]').text()).toBe('Sem função');
    expect(
      linha(wrapper, 24).find('[data-acao]').attributes('aria-label')
    ).toBe('Pôr Kauã Moreira como Vendedor');
  });

  it('tirar e pôr marcam a linha, e o rodapé diz a frase de cada pessoa', async () => {
    const { wrapper, atualizar } = montar();

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await linha(wrapper, 23).find('[data-acao]').trigger('click');

    expect(linha(wrapper, 21).find('[data-estado]').text()).toBe(
      'Vai ficar sem função'
    );
    expect(linha(wrapper, 21).find('[data-efeito]').text()).toContain(
      'Sem função, passa a ler e atender as conversas dos colegas. Deixa de procurar clientes novos.'
    );
    expect(linha(wrapper, 23).find('[data-estado]').text()).toBe(
      'Hoje é Atendente. Vai passar a ser Vendedor.'
    );
    expect(wrapper.findAll('[data-frase-rodape]').map(f => f.text())).toEqual([
      'Gabriel Souza vai ficar sem função e passa a ler e atender as conversas dos colegas.',
      'Íris Lopes passa a ser Vendedor.',
    ]);

    await wrapper.find('[data-salvar]').trigger('click');
    await flushPromises();
    expect(atualizar.mock.calls.map(([, dados]) => dados)).toEqual([
      { id: 21, name: 'Gabriel Souza', custom_role_id: null },
      { id: 23, name: 'Íris Lopes', custom_role_id: 2 },
    ]);
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('"Desfazer" restaura a linha e o rodapé', async () => {
    const { wrapper } = montar();

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    expect(
      linha(wrapper, 21).find('[data-acao]').attributes('aria-label')
    ).toBe('Desfazer a mudança de Gabriel Souza');
    await linha(wrapper, 21).find('[data-acao]').trigger('click');

    expect(linha(wrapper, 21).find('[data-efeito]').exists()).toBe(false);
    expect(linha(wrapper, 21).find('[data-acao]').text()).toBe(
      'Tirar desta função'
    );
    expect(wrapper.find('[data-frase-rodape]').exists()).toBe(false);
    expect(wrapper.find('[data-salvar]').attributes('disabled')).toBeDefined();
  });

  it('"Ver tudo o que muda" segue a flag crm_numeros_lentes da conta', async () => {
    const itens = async flags => {
      const { wrapper } = montar({ flags });
      await linha(wrapper, 21).find('[data-acao]').trigger('click');
      await linha(wrapper, 21).find('[data-ver-tudo]').trigger('click');
      return linha(wrapper, 21)
        .findAll('[data-diff] [data-item]')
        .map(item => item.attributes('data-item'));
    };

    expect(await itens([])).toContain('relatorios_das_vendas');
    expect(await itens(['crm_numeros_lentes'])).not.toContain(
      'relatorios_das_vendas'
    );
  });

  it('sem Pessoas, a gaveta só mostra quem é, sem botões', () => {
    const giver = {
      ...CARLA,
      permissions: CARLA.permissions.filter(chave => chave !== 'people_manage'),
    };
    const { wrapper } = montar({ giver });

    expect(wrapper.find('[data-so-leitura]').exists()).toBe(true);
    expect(acoesDasPessoas(wrapper)).toHaveLength(0);
    expect(wrapper.find('[data-salvar]').exists()).toBe(false);
    expect(wrapper.find('[data-outras]').exists()).toBe(false);
    expect(nomes(wrapper.find('[data-ja-sao]'))).toHaveLength(2);
  });

  it.each([
    ['acima do alcance (ABOVE)', FINANCEIRO],
    ['a própria função (MINE)', GERENTE],
  ])('função %s: só leitura, mesmo com Pessoas', (_, funcao) => {
    const { wrapper } = montar({ funcao });

    expect(wrapper.find('[data-so-leitura]').exists()).toBe(true);
    expect(acoesDasPessoas(wrapper)).toHaveLength(0);
    expect(wrapper.find('[data-salvar]').exists()).toBe(false);
    expect(wrapper.find('[data-outras]').exists()).toBe(false);
  });

  it('falha ao salvar: a gaveta fica, diz quem não foi salvo e por quê (401 explicado), e recarrega as pessoas', async () => {
    const atualizar = vi.fn((_, { id }) =>
      id === 23 ? Promise.reject(recusa(401, 'out_of_reach')) : undefined
    );
    const { wrapper, recarregar } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await linha(wrapper, 23).find('[data-acao]').trigger('click');
    await wrapper.find('[data-salvar]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(wrapper.find('[data-erro-gaveta]').attributes('role')).toBe('alert');
    expect(wrapper.find('[data-erro-gaveta]').text()).toBe(
      'A função de Íris Lopes não foi salva. Você não pode dar parte disto. Peça ao administrador.'
    );
    expect(wrapper.findAll('[data-frase-rodape]').map(f => f.text())).toEqual([
      'Íris Lopes passa a ser Vendedor.',
    ]);
    expect(recarregar).toHaveBeenCalledTimes(1);
  });

  it('falha de rede ao salvar: pede para conferir a internet', async () => {
    const atualizar = vi.fn(() => Promise.reject(recusa(undefined, undefined)));
    const { wrapper } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await wrapper.find('[data-salvar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-erro-gaveta]').text()).toBe(
      'A função de Gabriel Souza não foi salva. Confira a internet e tente de novo.'
    );
  });

  it('clique no fundo com mudança pendente pergunta "Sair sem salvar?"; sem mudança, fecha', async () => {
    const { mostrar, soltar } = espiarDialogo();
    const { wrapper } = montar();
    await linha(wrapper, 21).find('[data-acao]').trigger('click');

    await wrapper.find('[data-fundo]').trigger('click');
    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(mostrar).toHaveBeenCalledTimes(1);
    const dialogo = wrapper.find('dialog');
    expect(dialogo.find('h2').text()).toBe('Sair sem salvar?');
    soltar();

    await dialogo.find('[data-acao]').trigger('click');
    expect(wrapper.emitted('fechar')).toHaveLength(1);

    const limpo = montar().wrapper;
    await limpo.find('[data-fundo]').trigger('click');
    expect(limpo.emitted('fechar')).toHaveLength(1);
  });

  it('quem está sem função: uma escolha por pessoa, só com as funções ao alcance', async () => {
    const { wrapper } = montar({ funcao: null });

    expect(wrapper.find('h2').text()).toBe('Quem está sem função');
    expect(wrapper.text()).toContain(
      'Essa pessoa vê as conversas dos colegas. Dê uma função para mostrar menos.'
    );
    const escolha = wrapper.findComponent(ChoiceSelect);
    expect(escolha.props('options').map(opcao => opcao.label)).toEqual([
      'Atendente',
      'Vendedor',
    ]);
    expect(wrapper.find('[data-escondidas]').text()).toBe(
      'A função Financeiro não aparece na escolha: só o administrador dá.'
    );

    escolha.vm.$emit('update:modelValue', 1);
    await flushPromises();
    expect(linha(wrapper, 24).find('[data-estado]').text()).toBe(
      'Vai ser Atendente.'
    );
    expect(wrapper.find('[data-frase-rodape]').text()).toBe(
      'Kauã Moreira passa a ser Atendente.'
    );
  });
});
