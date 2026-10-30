import { actions } from 'dashboard/store/modules/customRole';
import { PRESETS } from '../../customRoles/permissionMatrix';
import { salvarFuncao } from '../salvarFuncao';
import { ADMIN, CARLA } from './quemMonta';

// #2308, especificação 14 › Salvar: trava antes de enviar, 401 pelo /auth/validate_token e 422 de nome.
const { validityCheck, clearCookiesOnLogout } = vi.hoisted(() => ({
  validityCheck: vi.fn(),
  clearCookiesOnLogout: vi.fn(),
}));
vi.mock('dashboard/api/auth', () => ({ default: { validityCheck } }));
vi.mock('dashboard/store/utils/api', async importOriginal => ({
  ...(await importOriginal()),
  clearCookiesOnLogout,
}));

const recusa = (status, data = {}) =>
  Object.assign(new Error('recusa'), {
    status,
    code: data.error,
    attributes: data.attributes || [],
  });

const loja = ({ falha, funcoes = [] } = {}) => ({
  dispatch: vi.fn(async acao => {
    if (acao === 'customRole/getCustomRole') return undefined;
    if (falha) throw falha;
    return { id: 9, name: 'Atendente 2' };
  }),
  getters: { 'customRole/getCustomRoles': funcoes },
});

const dados = (permissions = PRESETS.AGENT()) => ({
  name: 'Atendente 2',
  description: '',
  permissions,
});

beforeEach(() => {
  validityCheck.mockReset();
  clearCookiesOnLogout.mockReset();
});

describe('salvarFuncao', () => {
  it('cria e devolve a função', async () => {
    const store = loja();
    expect(await salvarFuncao({ store, giver: CARLA, dados: dados() })).toEqual(
      {
        funcao: { id: 9, name: 'Atendente 2' },
      }
    );
    expect(store.dispatch).toHaveBeenCalledWith(
      'customRole/createCustomRole',
      dados()
    );
  });

  it('alterar usa o update com o id', async () => {
    const store = loja();
    await salvarFuncao({ store, giver: ADMIN, id: 4, dados: dados() });
    expect(store.dispatch).toHaveBeenCalledWith('customRole/updateCustomRole', {
      id: 4,
      ...dados(),
    });
  });

  it('fora do alcance (com as implicadas), trava e não envia', async () => {
    const store = loja();
    const resultado = await salvarFuncao({
      store,
      giver: CARLA,
      dados: dados([...PRESETS.AGENT(), 'crm_export']),
    });
    expect(resultado).toEqual({ erro: 'TRAVA' });
    expect(store.dispatch).not.toHaveBeenCalled();
  });

  it('401 com sessão vencida: vai para o login, sem mensagem', async () => {
    validityCheck.mockRejectedValue({ response: { status: 401 } });
    const store = loja({ falha: recusa(401, { error: 'out_of_reach' }) });

    expect(await salvarFuncao({ store, giver: CARLA, dados: dados() })).toEqual(
      {
        erro: null,
      }
    );
    expect(clearCookiesOnLogout).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['out_of_reach', 'FORA_DO_ALCANCE'],
    ['feature_off', 'INDISPONIVEL'],
    ['own_role', 'PROPRIA_FUNCAO'],
    // O corpo real do check_authorization (request_exception_handler.rb): sem código, a frase de acesso.
    ['You are not authorized to do this action', 'SEM_ACESSO'],
    [undefined, 'SEM_ACESSO'],
  ])('401 com sessão boa e código %s: %s', async (codigo, frase) => {
    validityCheck.mockResolvedValue({ status: 200 });
    const store = loja({ falha: recusa(401, { error: codigo }) });

    expect(await salvarFuncao({ store, giver: CARLA, dados: dados() })).toEqual(
      {
        erro: frase,
      }
    );
    expect(clearCookiesOnLogout).not.toHaveBeenCalled();
  });

  // O contrato de ponta a ponta: o erro que a store de verdade lança (status e código da resposta) chega aqui.
  it('401 que a store de verdade lança vira a frase certa', async () => {
    validityCheck.mockResolvedValue({ status: 200 });
    window.axios = {
      patch: vi.fn().mockRejectedValue({
        response: { status: 401, data: { error: 'own_role' } },
      }),
    };
    const store = {
      dispatch: (_acao, dadosDoPedido) =>
        actions.updateCustomRole({ commit: vi.fn() }, dadosDoPedido),
    };

    expect(
      await salvarFuncao({ store, giver: ADMIN, id: 4, dados: dados() })
    ).toEqual({ erro: 'PROPRIA_FUNCAO' });
    expect(window.axios.patch).toHaveBeenCalledTimes(1);
    delete window.axios;
  });

  it('401 e a conferência da sessão sem rede: erro de rede, sessão intacta', async () => {
    validityCheck.mockRejectedValue(new Error('Network Error'));
    const store = loja({ falha: recusa(401) });

    expect(await salvarFuncao({ store, giver: CARLA, dados: dados() })).toEqual(
      {
        erro: 'REDE',
      }
    );
    expect(clearCookiesOnLogout).not.toHaveBeenCalled();
  });

  it('422 de nome que a lista mostra: "Já existe"', async () => {
    const store = loja({
      falha: recusa(422, { attributes: ['name'] }),
      funcoes: [{ id: 1, name: 'atendente 2' }],
    });
    expect(await salvarFuncao({ store, giver: CARLA, dados: dados() })).toEqual(
      {
        erroDoNome: 'NOME_REPETIDO',
      }
    );
    expect(store.dispatch).toHaveBeenCalledWith('customRole/getCustomRole');
  });

  it('422 de nome de integração: sugere o primeiro livre e não reenvia', async () => {
    const store = loja({
      falha: recusa(422, { attributes: ['name'] }),
      funcoes: [{ id: 1, name: 'Atendente' }],
    });
    expect(await salvarFuncao({ store, giver: CARLA, dados: dados() })).toEqual(
      {
        erroDoNome: 'NOME_DE_INTEGRACAO',
        sugestao: 'Atendente 3',
      }
    );
    const criacoes = store.dispatch.mock.calls.filter(
      ([acao]) => acao === 'customRole/createCustomRole'
    );
    expect(criacoes).toHaveLength(1);
  });

  // Sem vai-e-volta: "Atendente 3" também recusado não pode sugerir "Atendente 2" de novo.
  it('422 de novo, com a sugestão: pula todos os nomes já recusados', async () => {
    const store = loja({
      falha: recusa(422, { attributes: ['name'] }),
      funcoes: [{ id: 1, name: 'Atendente' }],
    });
    const segunda = await salvarFuncao({
      store,
      giver: CARLA,
      dados: { ...dados(), name: 'Atendente 3' },
      recusados: ['Atendente 2'],
    });
    expect(segunda).toEqual({
      erroDoNome: 'NOME_DE_INTEGRACAO',
      sugestao: 'Atendente 4',
    });
  });

  it('outra falha: erro de rede', async () => {
    const store = loja({ falha: recusa(500) });
    expect(await salvarFuncao({ store, giver: CARLA, dados: dados() })).toEqual(
      {
        erro: 'REDE',
      }
    );
  });
});
