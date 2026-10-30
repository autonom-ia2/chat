import { reactive } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { PRESETS } from '../../customRoles/permissionMatrix';
import { espiarDialogo } from './montar';
import {
  AGENTES,
  ATENDENTE,
  FINANCEIRO,
  dialogo,
  montar,
  pedirApagar,
  recarregar,
} from './montarLista';

// #2308, especificação 5.E: apagar uma função da lista, sem ninguém ou com destino, e cada recusa do servidor.
const { routerPush, validityCheck, clearCookiesOnLogout } = vi.hoisted(() => ({
  routerPush: vi.fn(),
  validityCheck: vi.fn(),
  clearCookiesOnLogout: vi.fn(),
}));
vi.mock('dashboard/api/auth', () => ({ default: { validityCheck } }));
// O logout de verdade limparia o storage e redirecionaria dentro do jsdom: o teste só confere que foi pedido.
vi.mock('dashboard/store/utils/api', async importOriginal => ({
  ...(await importOriginal()),
  clearCookiesOnLogout,
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// Especificação 5.E (Vendedor → Sem função), com o que o contrato gerado diz a mais com crm_numeros_lentes desligada.
const PASSAM_DO_VENDEDOR = [
  'Ler e atender as conversas dos colegas, nos canais em que estão',
  'Criar e mudar as respostas prontas',
  'Apagar mensagens',
  'Arquivar vendas',
  'Ver os relatórios das vendas',
  'Ver os valores das vendas em R$',
  'Ver de que anúncio veio cada cliente',
];
const DEIXAM_DO_VENDEDOR = ['Procurar clientes novos'];
const DEIXAM_DO_SUPERVISOR = [
  'Ver os relatórios',
  'Ver os robôs de IA',
  'Ver os canais',
  'Ver as regras automáticas',
  'Mudar as etiquetas',
  'Mudar os atalhos de mensagens',
];

let espiao = null;
const espiar = opcoes => {
  espiao = espiarDialogo(opcoes);
  return espiao;
};

afterEach(() => {
  espiao?.soltar();
  espiao = null;
  document.body.innerHTML = '';
  vi.clearAllMocks();
});

describe('Funções da equipe: apagar', () => {
  it('apagar sem ninguém: "Apagar a função …?" e apaga sem destino', async () => {
    const apagar = vi.fn();
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    expect(dialogo(wrapper).find('h2').text()).toBe(
      'Apagar a função Financeiro?'
    );
    expect(dialogo(wrapper).text()).toContain(
      'Ninguém usa esta função. A função some da lista.'
    );
    expect(dialogo(wrapper).find('[data-seguro]').text()).toBe('Manter');
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(apagar).toHaveBeenCalledWith(expect.anything(), {
      id: 2,
      destinationRoleId: undefined,
    });
    expect(useAlert).toHaveBeenCalledWith('Função Financeiro apagada.');
  });

  it('apagar com gente: destino obrigatório, e "Sem função" mostra o que muda', async () => {
    const apagar = vi.fn();
    const wrapper = await montar({ apagar });
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(atendente);
    expect(dialogo(wrapper).find('h2').text()).toBe('Para onde vai a pessoa?');
    const mover = dialogo(wrapper).find('[data-acao]');
    expect(mover.text()).toBe('Mover as pessoas e apagar');
    expect(mover.attributes('disabled')).toBeDefined();

    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    const diff = dialogo(wrapper).find('[data-diff]');
    expect(diff.text()).toContain(
      'Essa pessoa vai passar a poder mais coisas.'
    );
    expect(diff.find('[data-grupo="PASSAM"]').text()).toContain(
      'Ler e atender as conversas dos colegas, nos canais em que estão'
    );
    expect(mover.attributes('disabled')).toBeUndefined();

    await mover.trigger('click');
    await flushPromises();
    expect(apagar).toHaveBeenCalledWith(expect.anything(), {
      id: 1,
      destinationRoleId: 'none',
    });
  });

  it('409: avisa que alguém mudou a função e recarrega', async () => {
    const apagar = vi.fn().mockRejectedValue(
      Object.assign(new Error('conflito'), {
        code: 'changed_meanwhile',
        status: 409,
      })
    );
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');
    recarregar.mockClear();

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Alguém mudou esta função agora. Confira de novo.'
    );
    expect(recarregar).toHaveBeenCalled();
  });

  it('destination_invalid: reabre a pergunta com o motivo', async () => {
    const apagar = vi
      .fn()
      .mockRejectedValue(
        Object.assign(new Error('recusado'), { code: 'destination_invalid' })
      );
    const wrapper = await montar({ apagar });
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(atendente);
    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(dialogo(wrapper).find('[data-erro-destino]').text()).toBe(
      'Essa função não está mais disponível. Escolha outra.'
    );
    expect(
      dialogo(wrapper).find('[data-acao]').attributes('disabled')
    ).toBeDefined();
    expect(recarregar).toHaveBeenCalledTimes(2);
  });

  const recusa = (code, status) =>
    Object.assign(new Error('Has people'), { code, status });

  // Rodada 6: a recarga mostra a função sem ninguém (esvaziou no meio). Nada de "ainda tem pessoas" com a lista em 0:
  // o diálogo volta, sem destino, dizendo que a função mudou.
  it('destination_required e a recarga mostra a função vazia: volta sem destino, dizendo que mudou', async () => {
    espiar({ marcarAberto: true });
    const apagar = vi.fn().mockRejectedValue(recusa('destination_required'));
    const pessoasDaConta = vi.fn();
    const wrapper = await montar({ apagar, pessoasDaConta });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(pessoasDaConta).toHaveBeenCalledTimes(2);
    expect(useAlert).not.toHaveBeenCalled();
    expect(dialogo(wrapper).find('h2').text()).toBe(
      'Apagar a função Financeiro?'
    );
    expect(dialogo(wrapper).find('[data-destino]').exists()).toBe(false);
    expect(dialogo(wrapper).find('[data-erro-apagar]').text()).toBe(
      'Alguém mudou esta função agora. Confira de novo.'
    );
    expect(dialogo(wrapper).text()).not.toContain('ainda tem pessoas');
    expect(dialogo(wrapper).text()).not.toContain('Has people');
  });

  // Rodada 4: com o diálogo aberto, a pergunta volta com o motivo (role=alert) e o foco no campo do destino, e não
  // num conteúdo que trocou em silêncio.
  it('destination_required achando gente: o diálogo diz por que voltou e põe o foco no destino', async () => {
    espiar({ marcarAberto: true });
    const agentes = reactive(AGENTES.map(item => ({ ...item })));
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(true)
      .mockImplementation(async () => {
        agentes[1].custom_role_id = 2;
        return true;
      });
    const apagar = vi.fn().mockRejectedValue(recusa('destination_required'));
    const wrapper = await montar({ apagar, pessoasDaConta, agentes });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(dialogo(wrapper).find('h2').text()).toBe('Para onde vai a pessoa?');
    const motivo = dialogo(wrapper).find('[data-erro-destino]');
    expect(motivo.attributes('role')).toBe('alert');
    expect(motivo.text()).toBe(
      'Esta função ainda tem pessoas. Escolha para onde vão.'
    );
    expect(document.activeElement?.id).toBe(
      dialogo(wrapper).find('label').attributes('for')
    );
  });

  // Rodada 4: a recarga das pessoas depois da recusa passa pela da página. Falhou: o próximo "Apagar" diz que não deu
  // para ver quem usa, e não "Ninguém usa".
  it('destination_required com a recarga das pessoas falhando: o próximo apagar não diz "Ninguém usa"', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(true)
      .mockResolvedValue(false);
    const apagar = vi.fn().mockRejectedValue(recusa('destination_required'));
    const wrapper = await montar({ apagar, pessoasDaConta });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();
    await pedirApagar(financeiro);
    await flushPromises();

    expect(dialogo(wrapper).text()).not.toContain('Ninguém usa');
    expect(dialogo(wrapper).find('[data-apagar-erro]').exists()).toBe(true);
  });

  // Rodada 5: a recusa volta com a recarga das pessoas falhando, e o diálogo diz por que voltou. Rodada 6: num alerta
  // só, que diz as duas coisas, sem mandar escolher um destino que não aparece; "Tentar de novo" continua ali.
  it('destination_required com a recarga falhando: um alerta só, com o porquê e sem mandar escolher', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(true)
      .mockResolvedValue(false);
    const apagar = vi.fn().mockRejectedValue(recusa('destination_required'));
    const wrapper = await montar({ apagar, pessoasDaConta });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    const alertas = dialogo(wrapper).findAll('[role="alert"]');
    expect(alertas).toHaveLength(1);
    expect(alertas[0].text()).toBe(
      'Esta função ainda tem pessoas, mas não deu para ver quem.'
    );
    expect(dialogo(wrapper).text()).not.toContain('Escolha para onde vão');
    expect(dialogo(wrapper).find('[data-apagar-tentar]').exists()).toBe(true);
    // Rodada 7: o botão já diz "Tentar de novo"; a frase não repete.
    expect(dialogo(wrapper).text()).not.toContain('Tente de novo');
  });

  // Rodada 6: "Tentar de novo" que traz as pessoas tira o aviso de antes: o destino não abre com um erro velho.
  it('destination_required com a recarga falhando e o "Tentar de novo" dando certo: o destino abre sem erro velho', async () => {
    espiar({ marcarAberto: true });
    const agentes = reactive(AGENTES.map(item => ({ ...item })));
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(true)
      .mockResolvedValueOnce(false)
      .mockImplementation(async () => {
        agentes[1].custom_role_id = 2;
        return true;
      });
    const apagar = vi.fn().mockRejectedValue(recusa('destination_required'));
    const wrapper = await montar({ apagar, pessoasDaConta, agentes });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();
    await dialogo(wrapper).find('[data-apagar-tentar]').trigger('click');
    await flushPromises();

    expect(dialogo(wrapper).find('[data-destino]').exists()).toBe(true);
    expect(dialogo(wrapper).find('[data-erro-destino]').exists()).toBe(false);
  });

  // Rodada 5: depois de apagar com destino, a página recarrega as pessoas (quem tinha a função mudou). A recarga que
  // falha diz que não deu para ver quem tem cada função, como as outras.
  it('apagar com destino recarrega as pessoas; a recarga falhando diz que não deu para ver', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(true)
      .mockResolvedValue(false);
    const apagar = vi.fn();
    const wrapper = await montar({ apagar, pessoasDaConta });
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(atendente);
    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(pessoasDaConta).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-contagem]').text()).toContain(
      'Não deu para ver quem tem cada função.'
    );
  });

  it('409 com a recarga das pessoas falhando: a lista diz que não deu para ver quem tem cada função', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(true)
      .mockResolvedValue(false);
    const apagar = vi.fn().mockRejectedValue(recusa('changed_meanwhile', 409));
    const wrapper = await montar({ apagar, pessoasDaConta });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-contagem]').text()).toContain(
      'Não deu para ver quem tem cada função.'
    );
  });

  it('apagando com gente: a escolha do destino fica travada', async () => {
    let terminar;
    const apagar = vi.fn(
      () =>
        new Promise(resolve => {
          terminar = resolve;
        })
    );
    const wrapper = await montar({ apagar });
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(atendente);
    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    await dialogo(wrapper).find('[data-acao]').trigger('click');

    expect(wrapper.findComponent(ChoiceSelect).props('disabled')).toBe(true);
    terminar();
    await flushPromises();
  });

  // Rodada 4: "Tentar de novo" some quando as pessoas voltam a carregar; o foco vai para o título do diálogo.
  it('"Tentar de novo" no apagar devolve o foco ao título do diálogo', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(false)
      .mockResolvedValue(true);
    const wrapper = await montar({ pessoasDaConta });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    const tentar = dialogo(wrapper).find('[data-apagar-tentar]');
    tentar.element.focus();
    await tentar.trigger('click');
    await flushPromises();

    expect(document.activeElement).toBe(dialogo(wrapper).find('h2').element);
  });

  // A recusa sem código é o corpo real do check_authorization (request_exception_handler.rb).
  it.each([
    [
      'sessão boa e fora do alcance: frase de apagar',
      {},
      'out_of_reach',
      'Você não pode apagar esta função. Peça ao administrador.',
    ],
    [
      'sessão boa e sem código: perdeu o acesso',
      {},
      'You are not authorized to do this action',
      'Você não pode mais mudar as funções. Fale com o administrador.',
    ],
    [
      'sessão boa e flag desligada: indisponível',
      {},
      'feature_off',
      'Funções da equipe não estão disponíveis agora. Fale com o administrador.',
    ],
    [
      'sessão boa e a própria função: ninguém apaga a própria',
      {},
      'own_role',
      'Ninguém apaga a própria função.',
    ],
    [
      'sem conferir a sessão (rede): tente de novo',
      'rede',
      'out_of_reach',
      'Não deu para apagar agora. Confira a internet e tente de novo.',
    ],
    [
      'sessão vencida: nenhum aviso e vai para o login',
      null,
      'out_of_reach',
      null,
    ],
  ])('apagar com 401, %s', async (_, sessao, codigo, frase) => {
    if (sessao === 'rede') validityCheck.mockRejectedValue(new Error('rede'));
    else if (sessao) validityCheck.mockResolvedValue(sessao);
    else validityCheck.mockRejectedValue({ response: { status: 401 } });
    const apagar = vi.fn().mockRejectedValue(recusa(codigo, 401));
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(validityCheck).toHaveBeenCalledTimes(1);
    if (frase) expect(useAlert).toHaveBeenCalledWith(frase);
    else expect(useAlert).not.toHaveBeenCalled();
    expect(clearCookiesOnLogout).toHaveBeenCalledTimes(frase ? 0 : 1);
  });

  it('apagar um Vendedor com gente para "Sem função" desenha o que se ganha e o que se perde', async () => {
    const vendedor = { id: 4, name: 'Vendedor', permissions: PRESETS.SDR() };
    const wrapper = await montar({
      funcoes: [vendedor],
      agentes: [{ id: 10, name: 'Ana', role: 'agent', custom_role_id: 4 }],
    });

    await pedirApagar(wrapper.find('[data-cartao-funcao]'));
    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    const diff = dialogo(wrapper).find('[data-diff]');
    const itens = grupo =>
      diff.findAll(`[data-grupo="${grupo}"] [data-item]`).map(i => i.text());

    expect(diff.find('p').text()).toBe(
      'Essa pessoa vai ganhar umas coisas e perder outras.'
    );
    expect(diff.find('[data-grupo="DEIXAM"] p').text()).toBe('Vai deixar de');
    expect(itens('PASSAM')).toEqual(PASSAM_DO_VENDEDOR);
    expect(itens('DEIXAM')).toEqual(DEIXAM_DO_VENDEDOR);
  });

  it('apagar um Supervisor para "Sem função": as áreas que somem aparecem com o texto da área, sem chave crua', async () => {
    const supervisor = {
      id: 5,
      name: 'Supervisor',
      permissions: PRESETS.SUPERVISOR(),
    };
    const wrapper = await montar({
      funcoes: [supervisor],
      agentes: [{ id: 10, name: 'Ana', role: 'agent', custom_role_id: 5 }],
    });

    await pedirApagar(wrapper.find('[data-cartao-funcao]'));
    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    const deixam = dialogo(wrapper)
      .findAll('[data-grupo="DEIXAM"] [data-item]')
      .map(i => i.text());
    expect(deixam).toEqual(DEIXAM_DO_SUPERVISOR);
  });

  // Rodada 3: o apagar nunca diz "Ninguém usa" sem a contagem das pessoas.
  it('apagar enquanto as pessoas carregam: diz que está vendo e não deixa apagar', async () => {
    const wrapper = await montar({
      pessoasDaConta: vi.fn(() => new Promise(() => {})),
    });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    expect(dialogo(wrapper).text()).not.toContain('Ninguém usa');
    expect(dialogo(wrapper).find('[data-apagar-carregando]').text()).toBe(
      'Vendo quem usa esta função…'
    );
    expect(
      dialogo(wrapper).find('[data-acao]').attributes('disabled')
    ).toBeDefined();
  });

  it('apagar com as pessoas em erro: diz que não deu, oferece tentar e não deixa apagar', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(false)
      .mockResolvedValue(true);
    const wrapper = await montar({ pessoasDaConta });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    expect(dialogo(wrapper).text()).not.toContain('Ninguém usa');
    expect(dialogo(wrapper).find('[data-apagar-erro]').text()).toContain(
      'Não deu para ver quem usa esta função.'
    );
    expect(
      dialogo(wrapper).find('[data-acao]').attributes('disabled')
    ).toBeDefined();

    await dialogo(wrapper).find('[data-apagar-tentar]').trigger('click');
    await flushPromises();
    expect(pessoasDaConta).toHaveBeenCalledTimes(2);
    expect(dialogo(wrapper).text()).toContain('Ninguém usa esta função.');
  });

  it('apagando: o diálogo fica aberto em "Apagando…", com Manter, Esc e o segundo clique travados', async () => {
    let terminar;
    const apagar = vi.fn(
      () =>
        new Promise(resolve => {
          terminar = resolve;
        })
    );
    const { fechar } = espiar();
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    const acao = dialogo(wrapper).find('[data-acao]');
    await acao.trigger('click');
    await acao.trigger('click');
    expect(apagar).toHaveBeenCalledTimes(1);
    expect(acao.text()).toBe('Apagando…');
    expect(
      dialogo(wrapper).find('[data-seguro]').attributes('disabled')
    ).toBeDefined();
    await dialogo(wrapper).trigger('cancel');
    expect(fechar).not.toHaveBeenCalled();

    terminar();
    await flushPromises();
    expect(fechar).toHaveBeenCalledTimes(1);
  });

  it('apagada a função, o foco cai no título da lista (o "Mais" do cartão sumiu)', async () => {
    const lista = reactive([ATENDENTE, FINANCEIRO]);
    const apagar = vi.fn(() => {
      lista.splice(1, 1);
    });
    const wrapper = await montar({ apagar, funcoes: lista });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-cartao-funcao]')).toHaveLength(1);
    expect(document.activeElement).toBe(
      wrapper.find('[data-titulo-da-lista]').element
    );
  });

  // Quem apaga sem ser administrador vê como destino só as funções que alcança (reachesRole, especificação 5.D/5.E);
  // a própria função entra, como na gaveta: o servidor só pede o alcance (custom_roles_controller#destination_role_id).
  it('apagar como não administrador: o destino lista só as funções ao alcance, inclusive a própria', async () => {
    const minha = {
      id: 99,
      name: 'Gerente da loja',
      permissions: ['contact_view'],
    };
    const alvo = { id: 3, name: 'Alvo', permissions: ['contact_view'] };
    const wrapper = await montar({
      admin: false,
      funcoes: [ATENDENTE, FINANCEIRO, minha, alvo],
      agentes: [{ id: 10, name: 'Ana', role: 'agent', custom_role_id: 3 }],
    });
    const cartoes = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(cartoes[3]);
    expect(wrapper.findComponent(ChoiceSelect).props('options')).toEqual([
      { value: 1, label: 'Atendente' },
      { value: 99, label: 'Gerente da loja' },
      {
        value: 'none',
        label: 'Sem função',
        disabled: true,
        hint: 'Só o administrador tira esta pessoa da função',
      },
    ]);
  });

  // #2317: deixar alguém sem função segue a régua de dar uma função. Quem não alcança as chaves do "Sem função" vê a
  // opção travada, com o motivo, e não consegue escolhê-la; quem tem grant_above_own (ou é administrador) escolhe.
  describe('"Sem função" como destino (#2317)', () => {
    const alvo = { id: 3, name: 'Alvo', permissions: ['contact_view'] };
    const doisNoAlvo = [
      { id: 10, name: 'Ana', role: 'agent', custom_role_id: 3 },
      { id: 11, name: 'Bia', role: 'agent', custom_role_id: 3 },
    ];
    const opcaoSemFuncao = wrapper =>
      wrapper
        .findComponent(ChoiceSelect)
        .props('options')
        .find(opcao => opcao.value === 'none');
    // A lista aberta rola até a opção ativa; o jsdom não tem scrollIntoView.
    beforeAll(() => {
      Element.prototype.scrollIntoView = vi.fn();
    });
    afterAll(() => {
      delete Element.prototype.scrollIntoView;
    });

    it('travada para quem não alcança, com o motivo no plural, e não deixa apagar', async () => {
      const apagar = vi.fn();
      const wrapper = await montar({
        admin: false,
        funcoes: [ATENDENTE, alvo],
        agentes: doisNoAlvo,
        apagar,
      });

      await pedirApagar(wrapper.findAll('[data-cartao-funcao]')[1]);
      expect(opcaoSemFuncao(wrapper)).toEqual({
        value: 'none',
        label: 'Sem função',
        disabled: true,
        hint: 'Só o administrador tira estas pessoas da função',
      });
      await wrapper.find('[role="combobox"]').trigger('click');
      const opcao = wrapper
        .findAll('[role="option"]')
        .find(item => item.text().includes('Sem função'));
      expect(opcao.attributes('aria-disabled')).toBe('true');
      expect(opcao.text()).toContain(
        'Só o administrador tira estas pessoas da função'
      );
      await opcao.trigger('click');
      expect(
        dialogo(wrapper).find('[data-acao]').attributes('disabled')
      ).toBeDefined();
      expect(apagar).not.toHaveBeenCalled();
    });

    it('livre para quem tem grant_above_own e para o administrador', async () => {
      const comAlcance = await montar({
        admin: false,
        extras: ['grant_above_own'],
        funcoes: [ATENDENTE, alvo],
        agentes: doisNoAlvo,
      });
      await pedirApagar(comAlcance.findAll('[data-cartao-funcao]')[1]);
      expect(opcaoSemFuncao(comAlcance)).toEqual({
        value: 'none',
        label: 'Sem função',
      });
      comAlcance.unmount();
      document.body.innerHTML = '';

      const admin = await montar({
        funcoes: [ATENDENTE, alvo],
        agentes: doisNoAlvo,
      });
      await pedirApagar(admin.findAll('[data-cartao-funcao]')[1]);
      expect(opcaoSemFuncao(admin)).toEqual({
        value: 'none',
        label: 'Sem função',
      });
    });
  });
});
