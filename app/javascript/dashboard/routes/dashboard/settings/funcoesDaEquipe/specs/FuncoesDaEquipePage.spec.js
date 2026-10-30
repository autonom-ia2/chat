import { reactive } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { ATENDENTE, AGENTES, montar } from './montarLista';

// #2308, especificação 5.A: a lista nova. Faixa só com Pessoas, erro nunca vira lista vazia, função travada sem ações,
// as fixas e a gaveta de pessoas. O apagar mora em ApagarFuncao.spec.js.
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

afterEach(() => {
  document.body.innerHTML = '';
  vi.clearAllMocks();
});

describe('Funções da equipe: lista', () => {
  it('mostra título, contagem, cartões com a frase curta e as fixas', async () => {
    const wrapper = await montar();

    expect(wrapper.find('h1').text()).toBe('Funções da equipe');
    expect(wrapper.find('[data-contagem]').text()).toBe(
      '2 funções criadas · 1 pessoa com função'
    );
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');
    expect(atendente.find('[data-frase]').text()).toBe(
      'Atende as próprias conversas e pega as novas que estão sem ninguém. Cria e move as vendas em andamento. Só olha os contatos.'
    );
    expect(atendente.text()).toContain('1 pessoa');
    expect(wrapper.find('[data-fixa-admin]').text()).toContain(
      '1 pessoa · não muda'
    );
    expect(wrapper.find('[data-fixa-sem-funcao]').text()).toContain(
      'Mexe em todos os contatos e nas respostas prontas.'
    );
    expect(wrapper.find('[data-fixa-sem-funcao]').text()).toContain(
      '2 pessoas · não muda'
    );
  });

  it('a faixa de quem está sem função só aparece com Pessoas', async () => {
    const admin = await montar();
    const faixa = admin.find('[data-faixa-sem-funcao]');
    expect(faixa.attributes('role')).toBe('status');
    expect(faixa.text()).toContain('2 pessoas estão sem função.');
    expect(faixa.text()).toContain('2 pessoas sem função.');

    const comPessoas = await montar({ admin: false, pessoas: true });
    expect(comPessoas.find('[data-faixa-sem-funcao]').exists()).toBe(true);

    const soMontaFuncoes = await montar({ admin: false });
    expect(soMontaFuncoes.find('[data-faixa-sem-funcao]').exists()).toBe(false);
  });

  it('erro de rede mostra o erro e "Tentar de novo", nunca a lista vazia', async () => {
    const wrapper = await montar({ funcoes: [], falha: true });

    expect(wrapper.find('[data-erro]').text()).toContain(
      'Não deu para abrir as funções agora.'
    );
    expect(wrapper.find('[data-tentar-de-novo]').exists()).toBe(true);
    expect(wrapper.find('[data-vazio]').exists()).toBe(false);
    expect(wrapper.find('[data-cartao-funcao]').exists()).toBe(false);
  });

  it('sem nenhuma função, o herói e as 3 prontas em destaque', async () => {
    const wrapper = await montar({ funcoes: [] });

    expect(wrapper.find('[data-vazio]').exists()).toBe(true);
    expect(wrapper.findAll('[data-pronta]')).toHaveLength(3);
    expect(wrapper.find('[data-erro]').exists()).toBe(false);

    await wrapper.find('[data-pronta="AGENT"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'funcoes_equipe_new',
      query: { pronta: 'AGENT' },
    });
  });

  it('função acima do alcance fica travada, sem Alterar nem Mais', async () => {
    const wrapper = await montar({ admin: false, pessoas: true });
    const [atendente, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    expect(financeiro.find('[data-travada]').text()).toBe(
      'Só o administrador muda esta função.'
    );
    expect(financeiro.find('[data-alterar]').exists()).toBe(false);
    await financeiro.find('[data-mais]').trigger('click');
    expect(
      financeiro.findAll('[role="menuitem"]').map(item => item.text())
    ).toEqual(['Duplicar']);
    await financeiro.find('[data-acao="duplicar"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'funcoes_equipe_duplicate',
      params: { roleId: 2 },
    });
    expect(atendente.find('[data-alterar]').exists()).toBe(true);
  });

  it('a própria função diz que ninguém muda a própria e ainda oferece Duplicar', async () => {
    const minha = { ...ATENDENTE, id: 99, name: 'Gerente da loja' };
    const wrapper = await montar({ funcoes: [minha], admin: false });
    const cartao = wrapper.find('[data-cartao-funcao]');

    expect(cartao.find('[data-travada]').text()).toBe(
      'Ninguém muda a própria função.'
    );
    expect(cartao.find('[data-alterar]').exists()).toBe(false);
    await cartao.find('[data-mais]').trigger('click');
    expect(
      cartao.findAll('[role="menuitem"]').map(item => item.text())
    ).toEqual(['Duplicar']);
  });

  it('enquanto as pessoas carregam: esqueleto, nunca "nenhuma pessoa" nem "Ninguém usa ainda"', async () => {
    let soltar;
    const pessoasDaConta = vi.fn(
      () =>
        new Promise(resolve => {
          soltar = resolve;
        })
    );
    const wrapper = await montar({ pessoasDaConta });

    expect(
      wrapper.find('[data-contagem] [data-pessoas-carregando]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-contagem]').text()).not.toContain('nenhuma');
    expect(
      wrapper.find('[data-cartao-funcao] [data-pessoas-carregando]').exists()
    ).toBe(true);
    expect(wrapper.text()).not.toContain('Ninguém usa ainda');
    expect(wrapper.find('[data-faixa-sem-funcao]').exists()).toBe(false);

    soltar(true);
    await flushPromises();
    expect(wrapper.find('[data-pessoas-carregando]').exists()).toBe(false);
    expect(wrapper.find('[data-contagem]').text()).toBe(
      '2 funções criadas · 1 pessoa com função'
    );
  });

  it('"Escolher pessoas" só com Pessoas e numa função ao alcance', async () => {
    const vazia = { ...ATENDENTE, id: 3, name: 'Nova' };
    const comPessoas = await montar({
      funcoes: [vazia],
      admin: false,
      pessoas: true,
    });
    expect(comPessoas.find('[data-escolher-pessoas]').exists()).toBe(true);

    const semPessoas = await montar({ funcoes: [vazia], admin: false });
    expect(semPessoas.find('[data-ninguem]').text()).toBe('Ninguém usa ainda');
    expect(semPessoas.find('[data-escolher-pessoas]').exists()).toBe(false);
  });

  it('Criar, Alterar e Duplicar abrem a conversa guiada (PR 3)', async () => {
    const wrapper = await montar();
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');

    await wrapper.find('[data-criar]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({ name: 'funcoes_equipe_new' });

    await atendente.find('[data-alterar]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'funcoes_equipe_edit',
      params: { roleId: 1 },
    });

    await atendente.find('[data-mais]').trigger('click');
    await atendente.find('[data-acao="duplicar"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'funcoes_equipe_duplicate',
      params: { roleId: 1 },
    });
  });

  it('fora do plano, o bloqueio de plano no lugar da lista', async () => {
    const wrapper = await montar({ plano: false });

    expect(wrapper.find('[data-paywall]').exists()).toBe(true);
    expect(wrapper.find('[data-cartao-funcao]').exists()).toBe(false);
  });

  it('"Ver quem são" abre a gaveta de quem está sem função; a pilha abre quem usa', async () => {
    const wrapper = await montar();
    const gaveta = () => wrapper.findComponent({ name: 'GavetaDaFuncao' });

    await wrapper.find('[data-ver-quem-sao]').trigger('click');
    expect(gaveta().props('funcao')).toBeNull();

    gaveta().vm.$emit('fechar');
    await flushPromises();
    expect(gaveta().exists()).toBe(false);

    await wrapper.find('[data-pessoas]').trigger('click');
    expect(gaveta().props('funcao')).toEqual(ATENDENTE);
    expect(wrapper.find('[data-pessoas]').attributes('aria-label')).toBe(
      'Ver a pessoa que é Atendente'
    );
  });

  it('"Ver tudo o que pode" do Sem função segue a flag crm_numeros_lentes', async () => {
    const itens = async lentes => {
      const wrapper = await montar({ lentes });
      await wrapper.find('[data-ver-tudo-sem-funcao]').trigger('click');
      return wrapper
        .findAll('[data-grupo="NAO_PODE"] [data-item]')
        .map(item => item.text());
    };

    expect(await itens(false)).toEqual([
      'Procurar clientes novos',
      'Levar a lista de clientes para uma planilha',
      'Montar as colunas das vendas',
      'Pedir ajuda à IA nas vendas',
      'Cuidar de tudo nas vendas',
      'Definir as metas do mês de cada pessoa',
    ]);
    expect(await itens(true)).toContain('Ver os relatórios das vendas');
  });

  it('falha ao buscar as pessoas não vira "nenhuma pessoa": diz que não deu e oferece tentar', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(false)
      .mockResolvedValue(true);
    const wrapper = await montar({ pessoasDaConta });

    expect(wrapper.find('[data-contagem]').text()).toContain(
      'Não deu para ver quem tem cada função.'
    );
    expect(wrapper.find('[data-contagem]').text()).not.toContain('nenhuma');
    expect(wrapper.find('[data-faixa-sem-funcao]').exists()).toBe(false);
    expect(wrapper.find('[data-cartao-funcao]').text()).not.toContain(
      'Ninguém usa'
    );

    await wrapper.find('[data-tentar-pessoas]').trigger('click');
    await flushPromises();
    expect(pessoasDaConta).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-contagem]').text()).toBe(
      '2 funções criadas · 1 pessoa com função'
    );
  });

  it('fechada a gaveta, se "Ver quem são" sumiu (todos ganharam função), o foco cai no título da lista', async () => {
    const agentes = reactive(AGENTES.map(item => ({ ...item })));
    const wrapper = await montar({ pessoas: true, agentes });
    await wrapper.find('[data-faixa-sem-funcao] button').trigger('click');
    const gaveta = wrapper.findComponent({ name: 'GavetaDaFuncao' });
    expect(gaveta.exists()).toBe(true);

    agentes.forEach(item => {
      item.custom_role_id = 1;
    });
    gaveta.vm.$emit('fechar');
    await flushPromises();
    expect(wrapper.find('[data-faixa-sem-funcao]').exists()).toBe(false);
    expect(document.activeElement).toBe(
      wrapper.find('[data-titulo-da-lista]').element
    );
  });
});
