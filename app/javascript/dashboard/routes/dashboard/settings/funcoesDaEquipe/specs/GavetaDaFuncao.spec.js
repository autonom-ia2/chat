import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { PRESETS } from '../../customRoles/permissionMatrix';
import GavetaDaFuncao from '../pessoas/GavetaDaFuncao.vue';
import PessoaDaFuncao from '../pessoas/PessoaDaFuncao.vue';
import { espiarDialogo, global, loja } from './montar';
import { CARLA } from './quemMonta';

// #2308, especificação 5.D e 14: a gaveta de quem usa uma função e a de quem está sem função, com a Carla.
const { validityCheck, clearCookiesOnLogout } = vi.hoisted(() => ({
  validityCheck: vi.fn(),
  clearCookiesOnLogout: vi.fn(),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/auth', () => ({ default: { validityCheck } }));
vi.mock('dashboard/store/utils/api', async importOriginal => ({
  ...(await importOriginal()),
  clearCookiesOnLogout,
}));

// #2317: a Carla não alcança as chaves do "Sem função" (sales_value_view é de delegação), então "Tirar desta função"
// fica travado para ela. Os testes do salvar usam o tirar só para deixar uma mudança pendente: neles, o alcance do
// "Sem função" fica liberado. O bloco do #2317 liga a régua de verdade (`alcance.real`).
const alcance = vi.hoisted(() => ({ real: false, estaLigada: null }));
vi.mock('../semFuncao', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    alcancaSemFuncao: (giver, estaLigada, ...resto) => {
      alcance.estaLigada = estaLigada;
      return (
        !alcance.real || original.alcancaSemFuncao(giver, estaLigada, ...resto)
      );
    },
  };
});

// O corpo de verdade do 401 do agents/update quando a recusa não é do GrantGuard (administrador, o próprio acesso, quem
// perdeu Pessoas): cai no handler genérico (request_exception_handler.rb), sem código; a store põe a frase em `code`.
// A recusa do GrantGuard leva o código (out_of_reach), como no /custom_roles (#2317).
const CORPO_DO_401 = 'You are not authorized to do this action';

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

// As pessoas como a store de verdade as guarda: reativas, para a gaveta ver uma recarga que muda alguém (rodada 9).
const pessoas = (extras = []) =>
  reactive([...AGENTES, ...extras].map(item => ({ ...item })));

// O servidor de mentira: o update grava a função na lista que o agents/get "recarrega", como o de verdade.
const gravarNa =
  agentes =>
  (_, { id, custom_role_id: funcao }) => {
    agentes.find(item => item.id === id).custom_role_id = funcao;
  };

const montar = ({
  funcao = VENDEDOR,
  giver = CARLA,
  flags = [],
  agentes = pessoas(),
  funcoes = [ATENDENTE, VENDEDOR, FINANCEIRO],
  atualizar = vi.fn(gravarNa(agentes)),
  recarregar = vi.fn(),
  funcoesDeNovo = vi.fn(),
  config = {},
} = {}) => {
  const quemMontaPelaStore = vi.fn();
  const porNaStore = vi.fn(({ commit }, usuario) =>
    commit('SET_CURRENT_USER', usuario)
  );
  const store = loja({
    giver,
    flags,
    funcoes,
    agentes,
    actions: {
      'agents/update': atualizar,
      'agents/get': recarregar,
      'customRole/getCustomRole': funcoesDeNovo,
      validityCheck: quemMontaPelaStore,
      setCurrentUser: porNaStore,
    },
  });
  const wrapper = mount(GavetaDaFuncao, {
    attachTo: document.body,
    props: { funcao },
    global: {
      ...global(store),
      stubs: { ...global(store).stubs, Avatar: true },
      config,
    },
  });
  return {
    wrapper,
    atualizar,
    recarregar,
    funcoesDeNovo,
    quemMontaPelaStore,
    porNaStore,
  };
};

// A resposta do /auth/validate_token: quem monta como o servidor o vê agora.
const sessaoDe = permissions => ({
  data: {
    payload: {
      data: { id: CARLA.userId, accounts: [{ id: 1, permissions }] },
    },
  },
});
const SEM_PESSOAS = CARLA.permissions.filter(
  chave => chave !== 'people_manage'
);

// A recusa como a store de agentes a lança (agents.js: Error com status e code da resposta).
const recusa = (status, code) =>
  Object.assign(new Error('Request failed'), { status, code });
const acoesDasPessoas = wrapper => wrapper.findAll('[data-pessoa] [data-acao]');

const linha = (wrapper, id) => wrapper.find(`[data-pessoa="${id}"]`);
// O aviso do salvar como a pessoa lê: "foi salva" (linha neutra) e cada problema (vermelho), na ordem da tela.
const aviso = wrapper =>
  wrapper
    .findAll('[data-salva-gaveta], [data-erro-gaveta]')
    .map(paragrafo => paragrafo.text())
    .join(' ');
const nomes = lista => lista.findAll('[data-pessoa]').map(item => item.text());

beforeEach(() => {
  validityCheck.mockResolvedValue({});
});

afterEach(() => {
  document.body.innerHTML = '';
  validityCheck.mockReset();
  clearCookiesOnLogout.mockReset();
  useAlert.mockReset();
});

const salvar = async wrapper => {
  await wrapper.find('[data-salvar]').trigger('click');
  await flushPromises();
};

describe('GavetaDaFuncao', () => {
  it('quem já é, em ordem alfabética, e as outras pessoas com a trava escrita', () => {
    const { wrapper } = montar();

    expect(wrapper.find('h2').text()).toBe('Quem vai ser Vendedor?');
    expect(wrapper.text()).toContain('Já são Vendedor (2)');
    expect(nomes(wrapper.find('[data-ja-sao]'))[0]).toContain('Eduarda Pires');
    expect(
      linha(wrapper, 21).find('[data-acao]').attributes('aria-label')
    ).toBe('Tirar desta função: Gabriel Souza');
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
    ).toBe('Pôr como Vendedor: Kauã Moreira');
  });

  // Rodada 4: a pessoa numa função acima do alcance (Financeiro) e a própria Carla não têm ação nenhuma.
  it('quem está numa função acima do alcance e a própria Carla ficam sem ação, com o motivo', () => {
    const agentes = pessoas([
      { id: 26, name: 'Nina Alves', role: 'agent', custom_role_id: 3 },
    ]);
    const { wrapper } = montar({ agentes });

    expect(linha(wrapper, 26).find('[data-acao]').exists()).toBe(false);
    expect(linha(wrapper, 26).text()).toContain(
      'Só o administrador muda a função desta pessoa'
    );
    expect(linha(wrapper, CARLA.userId).find('[data-acao]').exists()).toBe(
      false
    );
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
      // Rodada 4: a mesma frase da linha, com a perda que mais pesa.
      'Gabriel Souza vai ficar sem função e passa a ler e atender as conversas dos colegas. Deixa de procurar clientes novos. Também passa a ver os valores das vendas em R$.',
      'Íris Lopes passa a ser Vendedor.',
    ]);

    await salvar(wrapper);
    // Só a função vai no pedido: o nome lido da lista desfaria uma troca de nome feita em paralelo.
    expect(atualizar.mock.calls.map(([, dados]) => dados)).toEqual([
      { id: 21, custom_role_id: null },
      { id: 23, custom_role_id: 2 },
    ]);
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('o servidor responde 200 sem gravar (conta sem custom_roles): a gaveta confere e diz que não mudou', async () => {
    const { wrapper, recarregar } = montar({ atualizar: vi.fn() });

    await linha(wrapper, 24).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(recarregar).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(aviso(wrapper)).toBe(
      'A função de Kauã Moreira não mudou. Tente de novo; se continuar, fale com o administrador.'
    );
  });

  it('ao tirar alguém, "Pôr em outra função" leva a pessoa para a função escolhida', async () => {
    const { wrapper, atualizar } = montar();

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    const escolha = linha(wrapper, 21).findComponent(ChoiceSelect);
    expect(escolha.props('options').map(opcao => opcao.label)).toEqual([
      'Atendente',
    ]);
    escolha.vm.$emit('update:modelValue', 1);
    await flushPromises();
    expect(wrapper.find('[data-frase-rodape]').text()).toBe(
      'Gabriel Souza passa a ser Atendente.'
    );

    await salvar(wrapper);
    expect(atualizar.mock.calls.map(([, dados]) => dados)).toEqual([
      { id: 21, custom_role_id: 1 },
    ]);
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('função sem ninguém: "Ninguém tem esta função ainda." em vez de "Já são … (0)"', () => {
    const vazia = { id: 9, name: 'Marketing', permissions: ['campaign_view'] };
    const { wrapper } = montar({
      funcao: vazia,
      funcoes: [ATENDENTE, VENDEDOR, FINANCEIRO, vazia],
    });

    expect(wrapper.find('[data-ninguem-ainda]').text()).toBe(
      'Ninguém tem esta função ainda.'
    );
    expect(wrapper.text()).not.toContain('Já são Marketing');
    expect(wrapper.find('[data-so-leitura]').exists()).toBe(false);
  });

  it('no celular, "Cancelar" vem antes de "Salvar", como nos diálogos', async () => {
    const { wrapper } = montar();
    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    const botoes = wrapper.find('[data-salvar]').element.parentElement;

    expect(botoes.classList.contains('flex-col')).toBe(true);
    expect(botoes.classList.contains('flex-col-reverse')).toBe(false);
    expect(botoes.firstElementChild.hasAttribute('data-cancelar')).toBe(true);
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

    expect(wrapper.find('[data-so-leitura]').text()).toBe(
      'Só quem pode pôr e tirar pessoas da equipe muda quem tem esta função.'
    );
    expect(acoesDasPessoas(wrapper)).toHaveLength(0);
    expect(wrapper.find('[data-salvar]').exists()).toBe(false);
    // Rodada 9 (M1): a gaveta que já abre só leitura não tem botão embaixo (só o X).
    expect(wrapper.find('[data-fechar-gaveta]').exists()).toBe(false);
    expect(wrapper.find('[data-outras]').exists()).toBe(false);
    expect(nomes(wrapper.find('[data-ja-sao]'))).toHaveLength(2);
  });

  it.each([
    [
      'acima do alcance (ABOVE)',
      FINANCEIRO,
      'Só o administrador põe e tira pessoas desta função.',
    ],
    [
      'a própria função (MINE)',
      GERENTE,
      'Ninguém muda a própria função: esta é a sua.',
    ],
  ])(
    'função %s: só leitura, mesmo com Pessoas, com o motivo certo',
    (_, funcao, motivo) => {
      // A gaveta lê a função da lista pelo id (rodada 8): a de quem monta também está lá, como na conta.
      const { wrapper } = montar({
        funcao,
        funcoes: [ATENDENTE, VENDEDOR, FINANCEIRO, GERENTE],
      });

      expect(wrapper.find('[data-so-leitura]').text()).toBe(motivo);
      expect(acoesDasPessoas(wrapper)).toHaveLength(0);
      expect(wrapper.find('[data-salvar]').exists()).toBe(false);
      expect(wrapper.find('[data-outras]').exists()).toBe(false);
    }
  );

  // Rodada 4: o 401 sem código do agents/update também vem de quem perdeu Pessoas (UserPolicy#update?). Rodada 5: quem
  // monta vem da própria conferência da sessão (authAPI.validityCheck), não do validityCheck da store, que engole a
  // falha de rede e deixaria Pessoas velho.
  it('401 sem código de quem perdeu Pessoas: a conferência da sessão diz que não pode mais', async () => {
    validityCheck.mockResolvedValue(sessaoDe(SEM_PESSOAS));
    const atualizar = vi.fn(() => Promise.reject(recusa(401, CORPO_DO_401)));
    const { wrapper, quemMontaPelaStore, porNaStore } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(validityCheck).toHaveBeenCalledTimes(1);
    expect(quemMontaPelaStore).not.toHaveBeenCalled();
    // Rodada 6: quem monta entra na store pela ação do auth (com o setUser), não por um commit solto.
    expect(porNaStore).toHaveBeenCalledWith(
      expect.anything(),
      sessaoDe(SEM_PESSOAS).data.payload.data
    );
    expect(wrapper.find('[data-erro-gaveta]').attributes('role')).toBe('alert');
    // Rodada 8 (L1): quem não gravou é citado junto.
    expect(aviso(wrapper)).toBe(
      'Você não pode mais pôr e tirar pessoas das funções. Fale com o administrador. A função de Gabriel Souza continua como era.'
    );
    expect(aviso(wrapper)).not.toContain('fora do que você pode dar');
    expect(wrapper.find('[data-so-leitura]').exists()).toBe(true);
    expect(acoesDasPessoas(wrapper)).toHaveLength(0);
    expect(wrapper.emitted('fechar')).toBeUndefined();
    await wrapper.find('[data-fechar]').trigger('click');
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('401 sem código e a conferência da sessão cai por rede: tente de novo, nunca "fora do alcance"', async () => {
    validityCheck.mockRejectedValue(new Error('Network Error'));
    const atualizar = vi.fn(() => Promise.reject(recusa(401, CORPO_DO_401)));
    const { wrapper, quemMontaPelaStore } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(quemMontaPelaStore).not.toHaveBeenCalled();
    expect(aviso(wrapper)).toBe(
      'A função de Gabriel Souza não foi salva. Confira a internet e tente de novo.'
    );
  });

  // Rodada 5: sem Pessoas, nada fica pendente, nem quem caiu por rede: a gaveta fecha sem perguntar.
  it('sem Pessoas, com uma pessoa recusada e outra caída por rede: nada pendente, e o X fecha direto', async () => {
    validityCheck.mockResolvedValue(sessaoDe(SEM_PESSOAS));
    const { mostrar, soltar } = espiarDialogo();
    const atualizar = vi.fn((_, { id }) =>
      Promise.reject(
        id === 23 ? recusa(401, CORPO_DO_401) : recusa(undefined, undefined)
      )
    );
    const { wrapper } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await linha(wrapper, 23).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    // Rodada 8 (L1): a recusada e a caída por rede não mudaram, e a gaveta diz isso.
    expect(aviso(wrapper)).toBe(
      'Você não pode mais pôr e tirar pessoas das funções. Fale com o administrador. A função destas pessoas continua como era: Gabriel Souza e Íris Lopes.'
    );
    expect(wrapper.find('[data-frase-rodape]').exists()).toBe(false);
    await wrapper.find('[data-fechar]').trigger('click');
    expect(mostrar).not.toHaveBeenCalled();
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    soltar();
  });

  // Rodada 5: o 401 sem código com Pessoas ainda ali, e a recarga mostra a pessoa travada (numa função acima do
  // alcance, ou administradora). Ela sai do que falta salvar, com a frase da trava: nada de "Salvar" em laço.
  it.each([
    [
      'numa função acima do alcance',
      pessoa => {
        pessoa.custom_role_id = 3;
      },
      'A função de Íris Lopes não mudou: só o administrador muda.',
    ],
    [
      'administradora',
      pessoa => {
        pessoa.role = 'administrator';
        pessoa.custom_role_id = null;
      },
      'A função de Íris Lopes não mudou: já tem acesso de administrador e pode tudo.',
    ],
  ])(
    '401 sem código e a recarga traz a pessoa %s: sai do pendente, com a frase da trava',
    async (_, mudar, frase) => {
      const agentes = pessoas();
      const atualizar = vi.fn(() => Promise.reject(recusa(401, CORPO_DO_401)));
      const recarregar = vi.fn(() =>
        mudar(agentes.find(item => item.id === 23))
      );
      const { wrapper } = montar({ agentes, atualizar, recarregar });

      await linha(wrapper, 23).find('[data-acao]').trigger('click');
      await salvar(wrapper);

      expect(recarregar).toHaveBeenCalledTimes(1);
      expect(aviso(wrapper)).toBe(frase);
      expect(aviso(wrapper)).not.toContain('fora do que você pode dar');
      expect(wrapper.find('[data-frase-rodape]').exists()).toBe(false);
      expect(
        wrapper.find('[data-salvar]').attributes('disabled')
      ).toBeDefined();
      // Rodada 6: nada gravou, então a gaveta não diz "salvas" nem fecha; sem pendentes, o X fecha direto.
      expect(useAlert).not.toHaveBeenCalled();
      expect(wrapper.emitted('fechar')).toBeUndefined();
      await wrapper.find('[data-fechar]').trigger('click');
      expect(wrapper.emitted('fechar')).toHaveLength(1);
    }
  );

  // Rodada 6: uma pessoa gravou e outra ficou travada. Nem tudo o que estava pendente gravou: a gaveta fica aberta,
  // com a frase da trava, sem o "salvas".
  it('uma pessoa gravada e outra travada: fica aberta com a frase da trava, sem dizer "salvas"', async () => {
    const agentes = pessoas();
    const gravar = gravarNa(agentes);
    const atualizar = vi.fn((contexto, dados) =>
      dados.id === 23
        ? Promise.reject(recusa(401, CORPO_DO_401))
        : gravar(contexto, dados)
    );
    const recarregar = vi.fn(() => {
      agentes.find(item => item.id === 23).custom_role_id = 3;
    });
    const { wrapper } = montar({ agentes, atualizar, recarregar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await linha(wrapper, 23).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(aviso(wrapper)).toBe(
      'A função de Gabriel Souza foi salva. A função de Íris Lopes não mudou: só o administrador muda.'
    );
    expect(useAlert).not.toHaveBeenCalled();
    expect(wrapper.emitted('fechar')).toBeUndefined();
  });

  // Rodada 6: o "salvas" só vem quando tudo gravou de fato.
  it('tudo gravou: diz "salvas" e fecha', async () => {
    const { wrapper } = montar();

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. As funções das pessoas foram salvas.'
    );
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('401 do agents/update com sessão boa e Pessoas ainda ali (corpo real, sem código): diz que está fora do alcance e recarrega pessoas e funções', async () => {
    const agentes = pessoas();
    const gravar = gravarNa(agentes);
    const atualizar = vi.fn((contexto, dados) =>
      dados.id === 23
        ? Promise.reject(recusa(401, CORPO_DO_401))
        : gravar(contexto, dados)
    );
    const { wrapper, recarregar, funcoesDeNovo } = montar({
      agentes,
      atualizar,
    });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await linha(wrapper, 23).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(validityCheck).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(wrapper.find('[data-erro-gaveta]').attributes('role')).toBe('alert');
    expect(aviso(wrapper)).toBe(
      'A função de Gabriel Souza foi salva. Não deu para mudar a função de Íris Lopes: está fora do que você pode dar.'
    );
    expect(wrapper.findAll('[data-frase-rodape]').map(f => f.text())).toEqual([
      'Íris Lopes passa a ser Vendedor.',
    ]);
    expect(recarregar).toHaveBeenCalledTimes(1);
    expect(funcoesDeNovo).toHaveBeenCalledTimes(1);
    expect(clearCookiesOnLogout).not.toHaveBeenCalled();
  });

  it('401 com a sessão vencida: vai para o login, sem mensagem e sem fechar', async () => {
    validityCheck.mockRejectedValue({ response: { status: 401 } });
    const atualizar = vi.fn(() => Promise.reject(recusa(401, CORPO_DO_401)));
    const { wrapper } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(clearCookiesOnLogout).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-erro-gaveta]').exists()).toBe(false);
    expect(wrapper.emitted('fechar')).toBeUndefined();
  });

  it('falha mista (um 401 e uma queda de rede): cada nome com o seu motivo', async () => {
    const atualizar = vi.fn((_, { id }) =>
      Promise.reject(
        id === 23 ? recusa(401, CORPO_DO_401) : recusa(undefined, undefined)
      )
    );
    const { wrapper } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await linha(wrapper, 23).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(aviso(wrapper)).toBe(
      'Não deu para mudar a função de Íris Lopes: está fora do que você pode dar. A função de Gabriel Souza não foi salva. Confira a internet e tente de novo.'
    );
    expect(wrapper.findAll('[data-frase-rodape]')).toHaveLength(2);
  });

  it('falha de rede ao salvar: pede para conferir a internet', async () => {
    const atualizar = vi.fn(() => Promise.reject(recusa(undefined, undefined)));
    const { wrapper } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await wrapper.find('[data-salvar]').trigger('click');
    await flushPromises();

    expect(aviso(wrapper)).toBe(
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

  // Rodada 3: o X passa pela mesma guarda do Esc e do fundo (guardaNoX do AgenteGaveta).
  it('o X com mudança pendente pergunta "Sair sem salvar?"; sem mudança, fecha', async () => {
    const { mostrar, soltar } = espiarDialogo();
    const { wrapper } = montar();
    await linha(wrapper, 21).find('[data-acao]').trigger('click');

    await wrapper.find('[data-fechar]').trigger('click');
    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(mostrar).toHaveBeenCalledTimes(1);
    soltar();

    const limpo = montar().wrapper;
    await limpo.find('[data-fechar]').trigger('click');
    expect(limpo.emitted('fechar')).toHaveLength(1);
  });

  it('enquanto salva: "Salvando…", nada fecha (Cancelar, X, fundo) e o segundo clique não manda de novo', async () => {
    const { mostrar, soltar } = espiarDialogo();
    let soltarPedido;
    const atualizar = vi.fn(
      () =>
        new Promise(resolve => {
          soltarPedido = resolve;
        })
    );
    const { wrapper } = montar({ atualizar });
    await linha(wrapper, 21).find('[data-acao]').trigger('click');

    await wrapper.find('[data-salvar]').trigger('click');
    await wrapper.find('[data-salvar]').trigger('click');
    expect(atualizar).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-salvar]').text()).toBe('Salvando…');
    expect(wrapper.find('[data-salvar]').attributes('disabled')).toBeDefined();
    expect(
      wrapper.find('[data-cancelar]').attributes('disabled')
    ).toBeDefined();
    await wrapper.find('[data-fechar]').trigger('click');
    await wrapper.find('[data-fundo]').trigger('click');
    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(mostrar).not.toHaveBeenCalled();
    soltar();

    soltarPedido();
    await flushPromises();
    expect(wrapper.find('[data-salvar]').text()).toBe('Salvar');
  });

  // Rodada 4: o fim do salvar troca as mudanças pelo que não gravou; mexer numa linha no meio se perderia, e a gaveta
  // fecharia "Salvo". Enquanto salva, as linhas não mudam.
  it('enquanto salva, as linhas ficam travadas: nem a ação nem a escolha mudam nada', async () => {
    let soltarPedido;
    const atualizar = vi.fn(
      () =>
        new Promise(resolve => {
          soltarPedido = resolve;
        })
    );
    const { wrapper } = montar({ atualizar });
    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await wrapper.find('[data-salvar]').trigger('click');

    const acoes = acoesDasPessoas(wrapper);
    expect(acoes.length).toBeGreaterThan(0);
    acoes.forEach(acao => expect(acao.attributes('disabled')).toBeDefined());
    await linha(wrapper, 23).find('[data-acao]').trigger('click');
    expect(linha(wrapper, 23).find('[data-estado]').text()).toBe('Atendente');
    wrapper
      .findAllComponents(ChoiceSelect)
      .forEach(escolha => expect(escolha.props('disabled')).toBe(true));

    soltarPedido();
    await flushPromises();
  });

  it('quem está sem função, enquanto salva: a escolha fica travada', async () => {
    let soltarPedido;
    const atualizar = vi.fn(
      () =>
        new Promise(resolve => {
          soltarPedido = resolve;
        })
    );
    const { wrapper } = montar({ funcao: null, atualizar });
    const escolha = wrapper.findComponent(ChoiceSelect);
    escolha.vm.$emit('update:modelValue', 1);
    await flushPromises();
    await wrapper.find('[data-salvar]').trigger('click');

    expect(wrapper.findComponent(ChoiceSelect).props('disabled')).toBe(true);
    expect(
      linha(wrapper, 24).find('[data-acao]').attributes('disabled')
    ).toBeDefined();

    soltarPedido();
    await flushPromises();
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
    // Rodada 4: o nome acessível começa pelo texto visível ("Escolher função").
    expect(escolha.props('ariaLabel')).toBe('Escolher função: Kauã Moreira');
    expect(wrapper.find('[data-escondidas]').text()).toBe(
      'A função Financeiro não aparece na escolha: só o administrador dá.'
    );

    // Lia é administradora e Carla tem função: só o Kauã está sem função.
    expect(nomes(wrapper.find('[data-sem-funcao]'))).toHaveLength(1);
    expect(nomes(wrapper.find('[data-sem-funcao]'))[0]).toContain(
      'Kauã Moreira'
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

  it('quem está sem função, sem Pessoas: só a lista, sem escolha', () => {
    const giver = {
      ...CARLA,
      permissions: CARLA.permissions.filter(chave => chave !== 'people_manage'),
    };
    const { wrapper } = montar({ funcao: null, giver });

    expect(wrapper.findComponent(ChoiceSelect).exists()).toBe(false);
    expect(wrapper.find('[data-salvar]').exists()).toBe(false);
    expect(nomes(wrapper.find('[data-sem-funcao]'))).toHaveLength(1);
  });
});

// Rodadas 7 e 8: a tabela de desfechos do salvar (useSalvarGaveta.js), pessoa por pessoa e misturada. Por padrão,
// Gabriel (21) sai do Vendedor e Íris (23) passa a ser Vendedor; `agir` troca isso. Em toda linha, `salvando` volta a
// false. As funções são reativas como na store de verdade: a gaveta lê a função dela da lista, pelo id (rodada 8).
describe('GavetaDaFuncao: tirar da função segue a régua de dar uma função (#2317)', () => {
  beforeEach(() => {
    alcance.real = true;
  });
  afterEach(() => {
    alcance.real = false;
  });

  it('para quem não alcança o "Sem função", "Tirar desta função" aparece travado, com o motivo', async () => {
    const { wrapper } = montar();
    const gabriel = linha(wrapper, 21);
    const tirar = gabriel.find('[data-acao="TIRAR"]');
    const estado = gabriel.find('[data-estado]');

    expect(estado.text()).toBe('Só o administrador tira esta pessoa da função');
    expect(estado.find('.i-lucide-lock').exists()).toBe(true);
    expect(tirar.attributes('disabled')).toBeDefined();
    expect(tirar.attributes('aria-describedby')).toBe(estado.attributes('id'));

    await tirar.trigger('click');
    expect(gabriel.find('[data-estado]').text()).toBe(
      'Só o administrador tira esta pessoa da função'
    );
    expect(wrapper.findAll('[data-frase-rodape]')).toHaveLength(0);
  });

  it('pôr outra pessoa nesta função continua livre', async () => {
    const { wrapper } = montar();

    const porComo = linha(wrapper, 23).find('[data-acao="POR_COMO"]');
    expect(porComo.attributes('disabled')).toBeUndefined();
    await porComo.trigger('click');
    expect(linha(wrapper, 23).find('[data-estado]').text()).toBe(
      'Hoje é Atendente. Vai passar a ser Vendedor.'
    );
  });

  const CARLA_ACIMA = {
    ...CARLA,
    permissions: [...CARLA.permissions, 'grant_above_own'],
  };
  const FORA_GABRIEL =
    'Não deu para mudar a função de Gabriel Souza: está fora do que você pode dar.';

  it('o servidor recusa a saída com out_of_reach: a linha fica pendente e a gaveta diz por quê', async () => {
    const atualizar = vi.fn(() =>
      Promise.reject(
        Object.assign(new Error('Request failed'), {
          status: 401,
          code: 'out_of_reach',
        })
      )
    );
    const { wrapper } = montar({ giver: CARLA_ACIMA, atualizar });

    await linha(wrapper, 21).find('[data-acao="TIRAR"]').trigger('click');
    await salvar(wrapper);

    expect(atualizar).toHaveBeenCalledTimes(1);
    expect(aviso(wrapper)).toBe(FORA_GABRIEL);
    expect(linha(wrapper, 21).find('[data-estado]').text()).toBe(
      'Vai ficar sem função'
    );
    expect(linha(wrapper, 21).find('[data-acao]').attributes('data-acao')).toBe(
      'DESFAZER'
    );
  });

  it('o alcance cai com a saída pendente: a linha mostra a trava, o Desfazer fica livre e o salvar nem manda', async () => {
    const atualizar = vi.fn();
    const { wrapper } = montar({ giver: CARLA_ACIMA, atualizar });

    await linha(wrapper, 21).find('[data-acao="TIRAR"]').trigger('click');
    wrapper.vm.$store.commit('SET_CURRENT_USER', {
      id: CARLA.userId,
      accounts: [{ id: 1, permissions: CARLA.permissions }],
    });
    await flushPromises();

    const gabriel = linha(wrapper, 21);
    expect(gabriel.find('[data-estado]').text()).toBe(
      'Só o administrador tira esta pessoa da função'
    );
    expect(gabriel.find('.i-lucide-lock').exists()).toBe(true);
    const desfazer = gabriel.find('[data-acao="DESFAZER"]');
    expect(desfazer.attributes('disabled')).toBeUndefined();

    await salvar(wrapper);
    expect(atualizar).not.toHaveBeenCalled();
    expect(aviso(wrapper)).toBe(FORA_GABRIEL);
    expect(
      linha(wrapper, 21).find('[data-acao="TIRAR"]').attributes('disabled')
    ).toBeDefined();
  });

  it('lê crm_numeros_lentes da conta para o alcance do "Sem função"', () => {
    const { wrapper } = montar({ flags: ['crm_numeros_lentes'] });

    expect(alcance.estaLigada('crm_numeros_lentes')).toBe(true);
    expect(linha(wrapper, 21).find('[data-estado]').text()).toBe(
      'Só o administrador tira esta pessoa da função'
    );

    montar();
    expect(alcance.estaLigada('crm_numeros_lentes')).toBe(false);
  });

  it('com grant_above_own, tira sem trava', async () => {
    const giver = {
      ...CARLA,
      permissions: [...CARLA.permissions, 'grant_above_own'],
    };
    const { wrapper } = montar({ giver });
    const tirar = linha(wrapper, 21).find('[data-acao="TIRAR"]');

    expect(linha(wrapper, 21).text()).not.toContain(
      'Só o administrador tira esta pessoa da função'
    );
    expect(tirar.attributes('disabled')).toBeUndefined();
    expect(tirar.attributes('aria-describedby')).toBeUndefined();
    await tirar.trigger('click');
    expect(linha(wrapper, 21).find('[data-estado]').text()).toBe(
      'Vai ficar sem função'
    );
  });
});

describe('GavetaDaFuncao: desfechos do salvar', () => {
  const SALVA_GABRIEL = 'A função de Gabriel Souza foi salva.';
  const SALVA_IRIS = 'A função de Íris Lopes foi salva.';
  const CONTINUA_IRIS = 'A função de Íris Lopes continua como era.';
  const TENTE_ADMIN = 'Tente de novo; se continuar, fale com o administrador.';
  const FORA_GABRIEL =
    'Não deu para mudar a função de Gabriel Souza: está fora do que você pode dar.';
  const remover = id => agentes =>
    agentes.splice(
      agentes.findIndex(item => item.id === id),
      1
    );
  const mudarPessoas =
    (mudanca, ids = [23]) =>
    agentes =>
      ids.forEach(id =>
        Object.assign(
          agentes.find(item => item.id === id),
          mudanca
        )
      );
  const mudarIris = mudanca => mudarPessoas(mudanca);
  // A função passa a pedir o financeiro, que a Carla não tem: sai do alcance dela.
  const acimaDoAlcance = (funcoes, indice) => {
    const funcao = funcoes[indice];
    funcoes.splice(indice, 1, {
      ...funcao,
      permissions: [...funcao.permissions, 'financial_view'],
    });
  };
  const ATENDENTE_ACIMA = funcoes => acimaDoAlcance(funcoes, 0);
  const escolher = async (wrapper, id, funcao) => {
    linha(wrapper, id)
      .findComponent(ChoiceSelect)
      .vm.$emit('update:modelValue', funcao);
    await flushPromises();
  };
  const tirarGabrielEPorIris = async wrapper => {
    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await linha(wrapper, 23).find('[data-acao]').trigger('click');
  };
  // Gabriel sai do Vendedor e vai para Atendente (a escolha da própria linha).
  const gabrielParaAtendente = async wrapper => {
    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await escolher(wrapper, 21, ATENDENTE.id);
  };

  // A resposta de cada pessoa: 'gravou', 'nada' (200 sem gravar), 'rede' ou o status da recusa ([status, código]).
  const responder = (respostas, agentes) => {
    const gravar = gravarNa(agentes);
    return vi.fn((contexto, dados) => {
      const resposta = respostas[dados.id];
      if (resposta === 'gravou') return gravar(contexto, dados);
      if (resposta === 'nada') return Promise.resolve();
      if (resposta === 'rede') return Promise.reject(recusa(undefined));
      const [status, codigo = CORPO_DO_401] = [resposta].flat();
      return Promise.reject(recusa(status, codigo));
    });
  };
  const SESSOES = {
    boa: () => validityCheck.mockResolvedValue({}),
    semPessoas: () => validityCheck.mockResolvedValue(sessaoDe(SEM_PESSOAS)),
    vencida: () =>
      validityCheck.mockRejectedValue({ response: { status: 401 } }),
    rede: () => validityCheck.mockRejectedValue(new Error('Network Error')),
  };

  const abrir = ({
    funcao = VENDEDOR,
    respostas = {},
    recarga = () => {},
    recargaDasFuncoes = () => {},
    quebra = false,
  } = {}) => {
    const agentes = pessoas();
    const funcoes = reactive([ATENDENTE, VENDEDOR, FINANCEIRO]);
    const erroDoVue = vi.fn();
    const montado = montar({
      funcao,
      agentes,
      funcoes,
      atualizar: responder(respostas, agentes),
      recarregar: vi.fn(() =>
        quebra ? Promise.reject(new Error('quebrou')) : recarga(agentes)
      ),
      funcoesDeNovo: vi.fn(() => recargaDasFuncoes(funcoes)),
      config: { errorHandler: erroDoVue },
    });
    return { ...montado, funcoes, agentes, erroDoVue };
  };

  it.each([
    {
      nome: 'todos gravaram: diz "salvas" e fecha',
      respostas: { 21: 'gravou', 23: 'gravou' },
      frase: '',
      fecha: true,
    },
    {
      nome: 'um gravou e outro ficou travado acima do alcance',
      respostas: { 21: 'gravou', 23: 401 },
      recarga: mudarIris({ custom_role_id: 3 }),
      frase: `${SALVA_GABRIEL} A função de Íris Lopes não mudou: só o administrador muda.`,
      sair: 'Fechar',
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'um gravou e outro virou administrador',
      respostas: { 21: 'gravou', 23: 401 },
      recarga: mudarIris({ role: 'administrator', custom_role_id: null }),
      frase: `${SALVA_GABRIEL} A função de Íris Lopes não mudou: já tem acesso de administrador e pode tudo.`,
      sair: 'Fechar',
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'os dois viraram administradores (plural da trava)',
      respostas: { 21: 401, 23: 401 },
      recarga: mudarPessoas(
        { role: 'administrator', custom_role_id: null },
        [21, 23]
      ),
      frase:
        'A função destas pessoas não mudou: Gabriel Souza e Íris Lopes. Já têm acesso de administrador e podem tudo.',
      sair: 'Fechar',
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'um gravou e quem monta perdeu Pessoas (401 sem código): cita quem não mudou',
      respostas: { 21: 'gravou', 23: 401 },
      sessao: 'semPessoas',
      frase: `${SALVA_GABRIEL} Você não pode mais pôr e tirar pessoas das funções. Fale com o administrador. ${CONTINUA_IRIS}`,
      soLeitura:
        'Só quem pode pôr e tirar pessoas da equipe muda quem tem esta função.',
      sair: null,
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'a função da gaveta foi apagada no meio (404 no "Pôr como", M1): só leitura, sem "Escolha outra"',
      respostas: { 21: 'gravou', 23: 404 },
      recargaDasFuncoes: funcoes => funcoes.splice(1, 1),
      frase: `${SALVA_GABRIEL} ${CONTINUA_IRIS}`,
      soLeitura: 'A função Vendedor foi apagada.',
      sair: null,
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'a função da gaveta saiu do alcance no meio (401, M1): só leitura ABOVE, sem laço',
      respostas: { 21: 'gravou', 23: 401 },
      recargaDasFuncoes: funcoes => acimaDoAlcance(funcoes, 1),
      frase: `${SALVA_GABRIEL} ${CONTINUA_IRIS}`,
      soLeitura: 'Só o administrador põe e tira pessoas desta função.',
      sair: null,
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'um gravou e outro ficou fora do alcance (401 sem código, com Pessoas)',
      respostas: { 21: 'gravou', 23: 401 },
      frase: `${SALVA_GABRIEL} Não deu para mudar a função de Íris Lopes: está fora do que você pode dar.`,
      sair: 'Cancelar',
      pendentes: 1,
      funcoes: true,
    },
    {
      nome: '401 com código (out_of_reach)',
      respostas: { 21: 'gravou', 23: [401, 'out_of_reach'] },
      frase: `${SALVA_GABRIEL} Não deu para mudar a função de Íris Lopes: está fora do que você pode dar.`,
      sair: 'Cancelar',
      pendentes: 1,
      funcoes: true,
    },
    {
      nome: '401 e o destino escolhido na linha saiu do alcance: não fica pendente',
      agir: gabrielParaAtendente,
      respostas: { 21: 401 },
      recargaDasFuncoes: ATENDENTE_ACIMA,
      frase: FORA_GABRIEL,
      sair: 'Fechar',
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'destino já fora do alcance antes do pedido: nem manda',
      agir: gabrielParaAtendente,
      antes: ATENDENTE_ACIMA,
      frase: FORA_GABRIEL,
      enviados: [],
      sair: 'Fechar',
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'sessão vencida: vai para o login, sem frase, tudo pendente',
      respostas: { 21: 401, 23: 401 },
      sessao: 'vencida',
      frase: '',
      sair: 'Cancelar',
      pendentes: 2,
      login: true,
    },
    {
      nome: '401 e a conferência da sessão cai por rede',
      respostas: { 21: 401, 23: 401 },
      sessao: 'rede',
      frase:
        'A função destas pessoas não foi salva: Gabriel Souza e Íris Lopes. Confira a internet e tente de novo.',
      sair: 'Cancelar',
      pendentes: 2,
      funcoes: true,
    },
    {
      nome: 'um gravou e o outro saiu da conta no meio (404, H1)',
      respostas: { 21: 404, 23: 'gravou' },
      recarga: remover(21),
      frase: `${SALVA_IRIS} Gabriel Souza não está mais na conta.`,
      sair: 'Fechar',
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: '200 sem mudar, e um saiu da conta no meio (H1, ramo "não mudou")',
      respostas: { 21: 'nada', 23: 'nada' },
      recarga: remover(21),
      frase: `Gabriel Souza não está mais na conta. A função de Íris Lopes não mudou. ${TENTE_ADMIN}`,
      sair: 'Cancelar',
      pendentes: 1,
    },
    {
      nome: 'a função escolhida na linha foi apagada no meio (404): "Escolha outra", com a escolha ali',
      funcao: null,
      agir: wrapper => escolher(wrapper, 24, ATENDENTE.id),
      respostas: { 24: 404 },
      recargaDasFuncoes: funcoes => funcoes.splice(0, 1),
      frase:
        'A função escolhida para Kauã Moreira não existe mais. Escolha outra.',
      escolhaNa: 24,
      sair: 'Fechar',
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'outro 4xx com a pessoa e a função ainda lá (M1)',
      respostas: { 21: 'gravou', 23: 422 },
      frase: `${SALVA_GABRIEL} A função de Íris Lopes não mudou. ${TENTE_ADMIN}`,
      sair: 'Cancelar',
      pendentes: 1,
      funcoes: true,
    },
    {
      nome: '429 (muitos pedidos seguidos): espere e tente de novo, fica pendente',
      respostas: { 21: 'gravou', 23: 429 },
      frase: `${SALVA_GABRIEL} A função de Íris Lopes não foi salva. Foram muitas tentativas seguidas: espere um pouco e tente de novo.`,
      sair: 'Cancelar',
      pendentes: 1,
    },
    {
      nome: 'um gravou e o outro caiu por rede',
      respostas: { 21: 'gravou', 23: 'rede' },
      frase: `${SALVA_GABRIEL} A função de Íris Lopes não foi salva. Confira a internet e tente de novo.`,
      sair: 'Cancelar',
      pendentes: 1,
    },
    {
      nome: 'os dois caíram por rede (5xx também é rede)',
      respostas: { 21: 'rede', 23: 503 },
      frase:
        'A função destas pessoas não foi salva: Gabriel Souza e Íris Lopes. Confira a internet e tente de novo.',
      sair: 'Cancelar',
      pendentes: 2,
    },
    {
      nome: '200 sem mudar nos dois',
      respostas: { 21: 'nada', 23: 'nada' },
      frase: `A função destas pessoas não mudou: Gabriel Souza e Íris Lopes. ${TENTE_ADMIN}`,
      sair: 'Cancelar',
      pendentes: 2,
    },
    {
      nome: '200 sem gravar e a recarga mostra a pessoa numa função acima do alcance: frase da trava, nada pendente (L1)',
      respostas: { 21: 'gravou', 23: 'nada' },
      recarga: mudarIris({ custom_role_id: 3 }),
      frase: `${SALVA_GABRIEL} A função de Íris Lopes não mudou: só o administrador muda.`,
      sair: 'Fechar',
      pendentes: 0,
    },
    {
      nome: 'a pessoa ficou travada antes do salvar (outra recarga): nem manda, frase da trava (L1)',
      respostas: { 21: 'gravou' },
      antes: (_, agentes) => mudarIris({ custom_role_id: 3 })(agentes),
      frase: `${SALVA_GABRIEL} A função de Íris Lopes não mudou: só o administrador muda.`,
      enviados: [21],
      sair: 'Fechar',
      pendentes: 0,
      funcoes: true,
    },
    {
      nome: 'gaveta sem função, 429, e a recarga mostra que a pessoa já tem função: saiu da lista, nada pendente (L1)',
      funcao: null,
      agir: wrapper => escolher(wrapper, 24, ATENDENTE.id),
      respostas: { 24: 429 },
      recarga: mudarPessoas({ custom_role_id: VENDEDOR.id }, [24]),
      frase: 'Kauã Moreira já tem uma função e saiu desta lista.',
      sair: 'Fechar',
      pendentes: 0,
    },
    {
      nome: 'algo lança no meio do salvar: diz tente de novo, tudo pendente, e o erro chega ao Vue',
      respostas: { 21: 'gravou', 23: 'gravou' },
      quebra: true,
      // Rodada 9 (L2): o catch quase sempre é defeito, não rede, e o servidor pode ter gravado.
      frase: 'Não deu para confirmar o que foi salvo. Tente de novo.',
      sair: 'Cancelar',
      pendentes: 2,
    },
  ])(
    '$nome',
    async ({
      funcao = VENDEDOR,
      agir = tirarGabrielEPorIris,
      antes = () => {},
      respostas = {},
      sessao = 'boa',
      recarga,
      recargaDasFuncoes,
      quebra = false,
      frase,
      fecha = false,
      soLeitura = null,
      enviados,
      escolhaNa,
      sair,
      pendentes,
      funcoes: recarregaFuncoes = false,
      login = false,
    }) => {
      SESSOES[sessao]();
      const { wrapper, atualizar, funcoesDeNovo, funcoes, agentes, erroDoVue } =
        abrir({
          funcao,
          respostas,
          recarga,
          recargaDasFuncoes,
          quebra,
        });

      await agir(wrapper);
      antes(funcoes, agentes);
      await flushPromises();
      await salvar(wrapper);

      expect(aviso(wrapper)).toBe(frase);
      expect(useAlert.mock.calls.length > 0).toBe(fecha);
      expect(Boolean(wrapper.emitted('fechar'))).toBe(fecha);
      expect(clearCookiesOnLogout.mock.calls.length > 0).toBe(login);
      expect(funcoesDeNovo.mock.calls.length > 0).toBe(recarregaFuncoes);
      expect(erroDoVue.mock.calls.length > 0).toBe(quebra);
      if (enviados)
        expect(atualizar.mock.calls.map(([, dados]) => dados.id)).toEqual(
          enviados
        );
      wrapper
        .findAllComponents(PessoaDaFuncao)
        .forEach(item => expect(item.props('salvando')).toBe(false));
      if (fecha) return;
      const motivo = wrapper.find('[data-so-leitura]');
      expect(motivo.exists() ? motivo.text() : null).toBe(soLeitura);
      if (soLeitura) expect(acoesDasPessoas(wrapper)).toHaveLength(0);
      if (escolhaNa)
        expect(
          linha(wrapper, escolhaNa).findComponent(ChoiceSelect).exists()
        ).toBe(true);
      expect(wrapper.findAll('[data-frase-rodape]')).toHaveLength(pendentes);
      const cancelar = wrapper.find('[data-cancelar]');
      expect(cancelar.exists() ? cancelar.text() : null).toBe(sair);
      // Rodada 9 (M1): virou só leitura com aviso: um só "Fechar", com o foco.
      const fechar = wrapper.find('[data-fechar-gaveta]');
      expect(fechar.exists()).toBe(Boolean(soLeitura));
      if (soLeitura) expect(document.activeElement).toBe(fechar.element);
      if (cancelar.exists())
        expect(wrapper.find('[data-salvar]').text()).toBe('Salvar');
    }
  );

  it('sem nada pendente, o X fecha direto; com pendente, pergunta antes', async () => {
    const { mostrar, soltar } = espiarDialogo();
    const { wrapper } = abrir({
      respostas: { 21: 404, 23: 'gravou' },
      recarga: remover(21),
    });
    await tirarGabrielEPorIris(wrapper);
    await salvar(wrapper);

    await wrapper.find('[data-fechar]').trigger('click');
    expect(mostrar).not.toHaveBeenCalled();
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    soltar();
  });

  // Rodada 8 (M2): vermelho só para destruir ou tirar (especificação, seção 9). "Foi salva" é uma linha neutra, com o
  // check, anunciada como status; cada problema vem no seu parágrafo vermelho, como alerta.
  it('"foi salva" numa linha neutra; cada problema no seu parágrafo vermelho', async () => {
    const { wrapper } = abrir({
      respostas: { 21: 'gravou', 23: 'rede', 24: 404 },
      recarga: remover(24),
    });
    await tirarGabrielEPorIris(wrapper);
    await linha(wrapper, 24).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    const salva = wrapper.find('[data-salva-gaveta]');
    expect(salva.text()).toBe(SALVA_GABRIEL);
    expect(wrapper.find('[data-status-gaveta]').attributes('role')).toBe(
      'status'
    );
    expect(salva.classes()).toContain('text-n-slate-12');
    expect(salva.classes()).not.toContain('text-n-ruby-11');
    expect(salva.find('.i-lucide-check').exists()).toBe(true);
    const problemas = wrapper.findAll('[data-erro-gaveta]');
    expect(problemas.map(item => item.text())).toEqual([
      'Kauã Moreira não está mais na conta.',
      'A função de Íris Lopes não foi salva. Confira a internet e tente de novo.',
    ]);
    problemas.forEach(item => {
      expect(item.attributes('role')).toBe('alert');
      expect(item.classes()).toContain('text-n-ruby-11');
    });
  });

  // Rodada 8 (L3): o aviso de um salvar antigo não fica na tela depois de uma mudança nova.
  it.each([
    ['desfazer', wrapper => linha(wrapper, 21).find('[data-acao]')],
    ['mudar outra pessoa', wrapper => linha(wrapper, 23).find('[data-acao]')],
  ])('%s apaga o aviso do salvar anterior', async (_, botao) => {
    const { wrapper } = abrir({ respostas: { 21: 'rede' } });
    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await salvar(wrapper);
    expect(aviso(wrapper)).toBe(
      'A função de Gabriel Souza não foi salva. Confira a internet e tente de novo.'
    );

    await botao(wrapper).trigger('click');

    expect(aviso(wrapper)).toBe('');
    expect(wrapper.find('[data-cancelar]').text()).toBe('Cancelar');
  });

  // Rodada 8 (L4): a gaveta recém-aberta, sem aviso e sem mudança, oferece "Cancelar" (o "Fechar" é só depois de um
  // salvar com problema e nada pendente).
  it('recém-aberta, o botão de baixo diz "Cancelar"', () => {
    const { wrapper } = abrir();

    expect(wrapper.find('[data-cancelar]').text()).toBe('Cancelar');
  });

  // Rodada 9 (M1): depois do 404 do "Pôr como" (função apagada), Cancelar e Salvar somem; fica um "Fechar" largo, perto
  // do polegar, com o foco.
  it('virou só leitura depois de salvar: um "Fechar" largo, com o foco, que fecha', async () => {
    const { wrapper } = abrir({
      respostas: { 21: 'gravou', 23: 404 },
      recargaDasFuncoes: funcoes => funcoes.splice(1, 1),
    });
    await tirarGabrielEPorIris(wrapper);
    await salvar(wrapper);

    const fechar = wrapper.find('[data-fechar-gaveta]');
    expect(fechar.text()).toBe('Fechar');
    expect(fechar.classes()).toEqual(
      expect.arrayContaining(['min-h-11', 'max-sm:w-full'])
    );
    expect(document.activeElement).toBe(fechar.element);
    expect(wrapper.find('[data-salvar]').exists()).toBe(false);
    await fechar.trigger('click');
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  // Rodada 9 (L3): função apagada não pergunta "Quem vai ser…?" nem diz "Ninguém tem esta função ainda".
  it('função apagada: título só com o nome, sem "Ninguém tem" nem "Já são"', async () => {
    const { wrapper } = abrir({
      respostas: { 21: 'gravou', 23: 404 },
      recarga: mudarPessoas({ custom_role_id: null }, [22]),
      recargaDasFuncoes: funcoes => funcoes.splice(1, 1),
    });
    await tirarGabrielEPorIris(wrapper);
    await salvar(wrapper);

    expect(wrapper.find('h2').text()).toBe('Vendedor');
    expect(wrapper.find('[data-so-leitura]').text()).toBe(
      'A função Vendedor foi apagada.'
    );
    expect(wrapper.find('[data-ninguem-ainda]').exists()).toBe(false);
    expect(wrapper.find('[data-ja-sao]').exists()).toBe(false);
  });

  // Rodada 9 (L4): o "foi salva" entra num role=status que já estava na tela (o leitor só anuncia o que muda nele),
  // até quando a gaveta vira só leitura no meio do salvar.
  it.each([
    ['com a gaveta editável', { respostas: { 21: 'gravou', 23: 'rede' } }],
    [
      'quando ela vira só leitura no salvar',
      {
        respostas: { 21: 'gravou', 23: 404 },
        recargaDasFuncoes: funcoes => funcoes.splice(1, 1),
      },
    ],
  ])('"foi salva" entra no status que já existia, %s', async (_, opcoes) => {
    const { wrapper } = abrir(opcoes);
    await tirarGabrielEPorIris(wrapper);
    const status = wrapper.find('[data-status-gaveta]');
    expect(status.attributes('role')).toBe('status');
    expect(status.text()).toBe('');

    await salvar(wrapper);

    expect(wrapper.find('[data-status-gaveta]').element).toBe(status.element);
    expect(status.text()).toBe(SALVA_GABRIEL);
  });

  // Rodada 9 (L5): a gaveta lê a função de agora na lista, pelo id; renomeada em paralelo, título e "Pôr como" seguem.
  it('a função renomeada em paralelo: título e "Pôr como" com o nome novo', async () => {
    const { wrapper, funcoes } = abrir();

    funcoes.splice(1, 1, { ...VENDEDOR, name: 'Vendedor Sênior' });
    await flushPromises();

    expect(wrapper.find('h2').text()).toBe('Quem vai ser Vendedor Sênior?');
    expect(
      linha(wrapper, 24).find('[data-acao]').attributes('aria-label')
    ).toBe('Pôr como Vendedor Sênior: Kauã Moreira');
    await linha(wrapper, 24).find('[data-acao]').trigger('click');
    expect(wrapper.find('[data-frase-rodape]').text()).toBe(
      'Kauã Moreira passa a ser Vendedor Sênior.'
    );
  });

  // Rodada 9 (L5): a gaveta vira só leitura sem salvar (a lista muda por fora): o pendente some, e o X fecha direto.
  it('virou só leitura por fora, sem salvar: o pendente some e o X fecha sem perguntar', async () => {
    const { mostrar, soltar } = espiarDialogo();
    const { wrapper, funcoes } = abrir();
    await tirarGabrielEPorIris(wrapper);

    acimaDoAlcance(funcoes, 1);
    await flushPromises();

    expect(wrapper.find('[data-so-leitura]').text()).toBe(
      'Só o administrador põe e tira pessoas desta função.'
    );
    expect(wrapper.find('[data-frase-rodape]').exists()).toBe(false);
    await wrapper.find('[data-fechar]').trigger('click');
    expect(mostrar).not.toHaveBeenCalled();
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    soltar();
  });
});
