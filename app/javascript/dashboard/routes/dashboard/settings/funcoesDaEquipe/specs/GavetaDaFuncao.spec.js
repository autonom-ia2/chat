import { flushPromises, mount } from '@vue/test-utils';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { PRESETS } from '../../customRoles/permissionMatrix';
import GavetaDaFuncao from '../pessoas/GavetaDaFuncao.vue';
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

// O corpo de verdade do 401 do agents/update: o GrantGuard::Denied cai no handler genérico
// (request_exception_handler.rb), sem código; a store põe a frase em `code`.
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
  agentes = AGENTES.map(item => ({ ...item })),
  atualizar = vi.fn(gravarNa(agentes)),
  recarregar = vi.fn(),
} = {}) => {
  const funcoesDeNovo = vi.fn();
  const quemMontaPelaStore = vi.fn();
  const store = loja({
    giver,
    flags,
    funcoes: [ATENDENTE, VENDEDOR, FINANCEIRO],
    agentes,
    actions: {
      'agents/update': atualizar,
      'agents/get': recarregar,
      'customRole/getCustomRole': funcoesDeNovo,
      validityCheck: quemMontaPelaStore,
    },
  });
  const wrapper = mount(GavetaDaFuncao, {
    attachTo: document.body,
    props: { funcao },
    global: {
      ...global(store),
      stubs: { ...global(store).stubs, Avatar: true },
    },
  });
  return { wrapper, atualizar, recarregar, funcoesDeNovo, quemMontaPelaStore };
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
const nomes = lista => lista.findAll('[data-pessoa]').map(item => item.text());

beforeEach(() => {
  validityCheck.mockResolvedValue({});
});

afterEach(() => {
  document.body.innerHTML = '';
  validityCheck.mockReset();
  clearCookiesOnLogout.mockReset();
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
    const agentes = [
      ...AGENTES.map(item => ({ ...item })),
      { id: 26, name: 'Nina Alves', role: 'agent', custom_role_id: 3 },
    ];
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
    expect(wrapper.find('[data-erro-gaveta]').text()).toBe(
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
    const { wrapper } = montar({ funcao: vazia });

    expect(wrapper.find('[data-ninguem-ainda]').text()).toBe(
      'Ninguém tem esta função ainda.'
    );
    expect(wrapper.text()).not.toContain('Já são Marketing');
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
      const { wrapper } = montar({ funcao });

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
    const { wrapper, quemMontaPelaStore } = montar({ atualizar });

    await linha(wrapper, 21).find('[data-acao]').trigger('click');
    await salvar(wrapper);

    expect(validityCheck).toHaveBeenCalledTimes(1);
    expect(quemMontaPelaStore).not.toHaveBeenCalled();
    const erro = wrapper.find('[data-erro-gaveta]');
    expect(erro.attributes('role')).toBe('alert');
    expect(erro.text()).toBe(
      'Você não pode mais pôr e tirar pessoas das funções. Fale com o administrador.'
    );
    expect(erro.text()).not.toContain('fora do que você pode dar');
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
    expect(wrapper.find('[data-erro-gaveta]').text()).toBe(
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

    expect(wrapper.find('[data-erro-gaveta]').text()).toBe(
      'Você não pode mais pôr e tirar pessoas das funções. Fale com o administrador.'
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
      'Íris Lopes já pode tudo: tem acesso de administrador.',
    ],
  ])(
    '401 sem código e a recarga traz a pessoa %s: sai do pendente, com a frase da trava',
    async (_, mudar, frase) => {
      const agentes = AGENTES.map(item => ({ ...item }));
      const atualizar = vi.fn(() => Promise.reject(recusa(401, CORPO_DO_401)));
      const recarregar = vi.fn(() =>
        mudar(agentes.find(item => item.id === 23))
      );
      const { wrapper } = montar({ agentes, atualizar, recarregar });

      await linha(wrapper, 23).find('[data-acao]').trigger('click');
      await salvar(wrapper);

      expect(recarregar).toHaveBeenCalledTimes(1);
      expect(wrapper.find('[data-erro-gaveta]').text()).toBe(frase);
      expect(wrapper.find('[data-erro-gaveta]').text()).not.toContain(
        'fora do que você pode dar'
      );
      expect(wrapper.find('[data-frase-rodape]').exists()).toBe(false);
      expect(
        wrapper.find('[data-salvar]').attributes('disabled')
      ).toBeDefined();
    }
  );

  it('401 do agents/update com sessão boa e Pessoas ainda ali (corpo real, sem código): diz que está fora do alcance e recarrega pessoas e funções', async () => {
    const agentes = AGENTES.map(item => ({ ...item }));
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
    expect(wrapper.find('[data-erro-gaveta]').text()).toBe(
      'Não deu para mudar a função de Íris Lopes: está fora do que você pode dar.'
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

    expect(wrapper.find('[data-erro-gaveta]').text()).toBe(
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
