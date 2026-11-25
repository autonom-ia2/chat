import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgenteEscreverPage from '../../pages/AgenteEscreverPage.vue';
import { MAX_INSTRUCAO } from '../../utils/pagina';
import agentesEn from 'dashboard/i18n/locale/en/agents.json';
import agentesPtBR from 'dashboard/i18n/locale/pt_BR/agents.json';

// #3214 — "Escrever as instruções com as minhas palavras": o agente nasce manual, parado, com o texto como escrito,
// sem o Construtor. Vazio não envia; falha mostra o aviso e não perde o texto; um clique só. Sair com algo escrito e
// sem ter criado pergunta antes; depois de criar, não.
const estado = vi.hoisted(() => ({ podeGerenciar: true }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => estado.podeGerenciar) };
});
const store = vi.hoisted(() => ({ dispatch: vi.fn() }));
// O diálogo de sair (TeleportWithDirection) lê a direção do texto da conta.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: () => computed(() => false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

// O roteador falso passa pelas guardas como o vue-router: sair da rota pela de saída, trocar a consulta da mesma rota
// (a criação conversando, `?modelo=custom`) pela de troca. `navegou` só recebe o destino que as guardas deixaram; a
// navegação barrada devolve uma falha, como o vue-router.
const FALHA = { falhaDeNavegacao: true };
const guardas = vi.hoisted(() => ({ saida: null, troca: null }));
const navegou = vi.hoisted(() => vi.fn());
const router = vi.hoisted(() => ({
  push: vi.fn(),
  replace: vi.fn(),
  resolve: vi.fn(rota => ({
    href: `/app/${rota.name}/${rota.params?.agentId}`,
  })),
}));
vi.mock('vue-router', () => ({
  useRouter: () => router,
  isNavigationFailure: valor => Boolean(valor?.falhaDeNavegacao),
  onBeforeRouteLeave: guarda => {
    guardas.saida = guarda;
  },
  onBeforeRouteUpdate: guarda => {
    guardas.troca = guarda;
  },
}));
const navegar = async destino => {
  const guarda =
    destino.name === 'autonomia_agents_builder' ? guardas.troca : guardas.saida;
  if (guarda?.(destino) === false) return FALHA;
  navegou(destino);
  return undefined;
};

const no = seletor => document.querySelector(seletor);
const digitar = async (seletor, valor) => {
  const campo = no(seletor);
  campo.value = valor;
  campo.dispatchEvent(new Event('input'));
  await nextTick();
};
const clicar = async seletor => {
  no(seletor).click();
  await flushPromises();
};
const criar = () => clicar('[data-criar]');
const dialogo = () => no('dialog');

const TEXTO = 'Atenda com frases curtas.\nNunca prometa prazo de entrega.';
const LISTA = { name: 'autonomia_agents_index' };
const CONTAR = {
  name: 'autonomia_agents_builder',
  query: { modelo: 'custom' },
};

const montar = (props = {}) =>
  mount(AgenteEscreverPage, { props, attachTo: document.body });

describe('AgenteEscreverPage', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = function abrir() {
      this.open = true;
    };
    HTMLDialogElement.prototype.close = function fechar() {
      this.open = false;
    };
  });

  beforeEach(() => {
    vi.clearAllMocks();
    guardas.saida = null;
    guardas.troca = null;
    estado.podeGerenciar = true;
    store.dispatch.mockResolvedValue({ id: 42, name: 'Duda' });
    router.push.mockImplementation(navegar);
    router.replace.mockImplementation(navegar);
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('opens with the focus on the title, the explanation and the big field of the instructions drawer', async () => {
    const wrapper = montar();
    await nextTick();
    const titulo = wrapper.get('h1');
    expect(titulo.text()).toBe('AGENTS.JORNADA.ESCREVER.TITULO');
    expect(titulo.attributes('tabindex')).toBe('-1');
    expect(document.activeElement).toBe(titulo.element);
    expect(wrapper.text()).toContain('AGENTS.JORNADA.ESCREVER.TEXTO');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.ESCREVER.NOME_DICA');
    const nome = no('[data-nome]');
    expect(nome.getAttribute('maxlength')).toBe('40');
    const dicaDoNome = [...document.querySelectorAll('p')].find(p =>
      p.textContent.includes('AGENTS.JORNADA.ESCREVER.NOME_DICA')
    );
    expect(nome.getAttribute('aria-describedby')).toBe(dicaDoNome.id);
    const campo = no('[data-instrucao]');
    expect(campo.getAttribute('maxlength')).toBe(String(MAX_INSTRUCAO));
    expect(campo.getAttribute('placeholder')).toBe(
      'AGENTS.JORNADA.ESCREVER.EXEMPLO'
    );
    // Mais baixa no celular, a altura da gaveta a partir do md.
    expect(campo.className).toContain('h-64');
    expect(campo.className).toContain('min-h-[16rem]');
    expect(campo.className).toContain('md:h-auto');
    expect(campo.className).toContain('md:min-h-[22rem]');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.ESCREVER.DICA');
    expect(wrapper.text()).toContain(
      'AGENTS.JORNADA.PAGINA.INSTRUCOES.CONTADOR'
    );
    expect(wrapper.get('[data-criar]').text()).toBe(
      'AGENTS.JORNADA.ESCREVER.CRIAR'
    );
    expect(wrapper.find('select').exists()).toBe(false);
    wrapper.unmount();
  });

  it('keeps the create button clear of the Guide bubble on the phone', () => {
    const wrapper = montar();
    const conteiner = wrapper.get('[data-escrever-agente]').classes();
    expect(conteiner).toContain('pb-24');
    expect(conteiner).toContain('md:pb-6');
    wrapper.unmount();
  });

  it('sends nothing with both fields empty, shows both messages under the fields with a ruby ring, and focuses the name', async () => {
    const wrapper = montar();
    await criar();
    expect(store.dispatch).not.toHaveBeenCalled();
    const nome = no('[data-nome]');
    const campo = no('[data-instrucao]');
    expect(no('[data-nome-vazio]').textContent).toContain(
      'AGENTS.JORNADA.ESCREVER.NOME_VAZIO'
    );
    expect(no('[data-vazio]').textContent).toContain(
      'AGENTS.JORNADA.PAGINA.INSTRUCOES.VAZIO'
    );
    expect(nome.getAttribute('aria-invalid')).toBe('true');
    expect(nome.getAttribute('aria-describedby')).toContain(
      no('[data-nome-vazio]').id
    );
    expect(nome.classList).toContain('ring-n-ruby-9');
    expect(campo.classList).toContain('ring-n-ruby-9');
    expect(campo.getAttribute('aria-describedby')).toContain(
      no('[data-vazio]').id
    );
    // A mensagem fica logo abaixo da caixa, antes do contador.
    expect(campo.nextElementSibling).toBe(no('[data-vazio]'));
    expect(document.activeElement).toBe(nome);
    wrapper.unmount();
  });

  it('sends nothing with only spaces in the instructions, focuses that field and clears the error when typing', async () => {
    const wrapper = montar();
    await digitar('[data-nome]', 'Duda');
    await digitar('[data-instrucao]', '   \n  ');
    await criar();
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(no('[data-nome-vazio]')).toBeNull();
    expect(no('[data-nome]').classList).toContain('ring-n-slate-7');
    const campo = no('[data-instrucao]');
    expect(campo.getAttribute('aria-invalid')).toBe('true');
    expect(document.activeElement).toBe(campo);

    await digitar('[data-instrucao]', 'Atenda bem.');
    expect(no('[data-vazio]')).toBeNull();
    expect(campo.getAttribute('aria-invalid')).toBeNull();
    expect(campo.classList).toContain('ring-n-slate-7');
    wrapper.unmount();
  });

  it('creates the manual agent, stopped, with the text as written, opens its page without asking and says it was created', async () => {
    const wrapper = montar();
    await digitar('[data-nome]', '  Duda  ');
    await digitar('[data-instrucao]', TEXTO);
    await criar();
    expect(store.dispatch.mock.calls).toEqual([
      [
        'autonomiaAgents/create',
        {
          name: 'Duda',
          agent_type: 'custom',
          mode: 'manual',
          instruction: TEXTO,
          status: 'paused',
          enabled: false,
        },
      ],
    ]);
    const pagina = { name: 'autonomia_agent_panel', params: { agentId: 42 } };
    expect(router.replace).toHaveBeenCalledWith(pagina);
    expect(navegou).toHaveBeenCalledWith(pagina);
    expect(dialogo().open).toBeFalsy();
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.ESCREVER.CRIADO');
    wrapper.unmount();
  });

  it('creates only once, even with a second click or Enter while it is creating', async () => {
    let terminar;
    store.dispatch.mockImplementation(
      () =>
        new Promise(resolve => {
          terminar = resolve;
        })
    );
    const wrapper = montar();
    await digitar('[data-nome]', 'Duda');
    await digitar('[data-instrucao]', TEXTO);
    await criar();
    const botao = wrapper.get('[data-criar]');
    expect(botao.text()).toBe('AGENTS.JORNADA.ESCREVER.CRIANDO');
    expect(botao.attributes('aria-busy')).toBe('true');
    expect(no('[data-instrucao]').readOnly).toBe(true);
    await criar();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledTimes(1);

    terminar({ id: 42 });
    await flushPromises();
    expect(router.replace).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('shows the failure, keeps what was written and tries again', async () => {
    store.dispatch.mockRejectedValueOnce(new Error('500'));
    const wrapper = montar();
    await digitar('[data-nome]', 'Duda');
    await digitar('[data-instrucao]', TEXTO);
    await criar();

    const erro = wrapper.get('[data-erro]');
    expect(erro.attributes('role')).toBe('alert');
    expect(erro.text()).toContain('AGENTS.JORNADA.ESCREVER.ERRO');
    expect(erro.text()).toContain('AGENTS.JORNADA.ESCREVER.ERRO_GARANTIA');
    expect(no('[data-nome]').value).toBe('Duda');
    expect(no('[data-instrucao]').value).toBe(TEXTO);
    expect(no('[data-instrucao]').readOnly).toBe(false);
    expect(router.replace).not.toHaveBeenCalled();
    expect(alerta).not.toHaveBeenCalled();
    // Uma saída só: o "Tentar de novo" do aviso.
    expect(wrapper.find('[data-criar]').exists()).toBe(false);

    await erro.get('button').trigger('click');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledTimes(2);
    expect(store.dispatch.mock.calls[1][1].instruction).toBe(TEXTO);
    expect(router.replace).toHaveBeenCalledWith({
      name: 'autonomia_agent_panel',
      params: { agentId: 42 },
    });
    wrapper.unmount();
  });

  describe('a página do agente não abriu depois de criar', () => {
    const criarSemAbrir = async falhaDaNavegacao => {
      router.replace.mockImplementationOnce(falhaDaNavegacao);
      const wrapper = montar();
      await digitar('[data-nome]', 'Duda');
      await digitar('[data-instrucao]', TEXTO);
      await criar();
      return wrapper;
    };

    it.each([
      ['an aborted navigation', async () => FALHA],
      ['a navigation error', async () => Promise.reject(new Error('chunk'))],
    ])(
      'after %s, swaps the button for "Abrir {nome}", without "Tentar de novo" nor the created notice',
      async (_caso, falhaDaNavegacao) => {
        const wrapper = await criarSemAbrir(falhaDaNavegacao);
        const abrir = wrapper.get('[data-abrir-criado]');
        expect(abrir.text()).toBe('AGENTS.JORNADA.ESCREVER.ABRIR');
        expect(abrir.attributes('href')).toBe('/app/autonomia_agent_panel/42');
        expect(abrir.classes()).toContain('min-h-12');
        expect(wrapper.find('[data-criar]').exists()).toBe(false);
        expect(wrapper.find('[data-erro]').exists()).toBe(false);
        expect(alerta).not.toHaveBeenCalled();
        expect(no('[data-instrucao]').readOnly).toBe(true);

        // Um Enter no nome não cria outro.
        await wrapper.get('form').trigger('submit');
        await flushPromises();
        expect(store.dispatch).toHaveBeenCalledTimes(1);
        wrapper.unmount();
      }
    );

    it('opens the page with the link and only then says it was created', async () => {
      const wrapper = await criarSemAbrir(async () => FALHA);
      await clicar('[data-abrir-criado]');
      const pagina = { name: 'autonomia_agent_panel', params: { agentId: 42 } };
      expect(router.replace).toHaveBeenLastCalledWith(pagina);
      expect(navegou).toHaveBeenCalledWith(pagina);
      expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.ESCREVER.CRIADO');
      expect(store.dispatch).toHaveBeenCalledTimes(1);
      wrapper.unmount();
    });

    it('leaves without asking once created', async () => {
      const wrapper = await criarSemAbrir(async () => FALHA);
      await clicar('[data-voltar-lista]');
      expect(navegou).toHaveBeenCalledWith(LISTA);
      expect(dialogo().open).toBeFalsy();
      wrapper.unmount();
    });
  });

  describe('sair sem criar', () => {
    it('goes back to the list at once when nothing was written', async () => {
      const wrapper = montar();
      await clicar('[data-voltar-lista]');
      expect(router.push).toHaveBeenCalledWith(LISTA);
      expect(navegou).toHaveBeenCalledWith(LISTA);
      expect(dialogo().open).toBeFalsy();
      wrapper.unmount();
    });

    it('asks before going back with something written, with "Continuar aqui" as the main button', async () => {
      const wrapper = montar();
      await digitar('[data-instrucao]', TEXTO);
      await clicar('[data-voltar-lista]');
      expect(navegou).not.toHaveBeenCalled();
      expect(dialogo().open).toBe(true);
      expect(dialogo().textContent).toContain(
        'AGENTS.JORNADA.ESCREVER.SAIR.TITULO'
      );
      expect(dialogo().textContent).toContain(
        'AGENTS.JORNADA.ESCREVER.SAIR.TEXTO'
      );
      const ficar = dialogo().querySelector('[data-ficar]');
      const sair = dialogo().querySelector('[data-confirmar]');
      expect(ficar.textContent).toContain('AGENTS.JORNADA.ESCREVER.SAIR.FICAR');
      expect(ficar.className).toContain('bg-n-blue-11');
      expect(ficar.className).toContain('order-last');
      expect(sair.textContent).toContain('AGENTS.JORNADA.ESCREVER.SAIR.SAIR');
      expect(sair.className).toContain('ring-n-blue-9');
      wrapper.unmount();
    });

    it('stays with the text when "Continuar aqui" is chosen, and asks again on the next try', async () => {
      const wrapper = montar();
      await digitar('[data-nome]', 'Duda');
      await clicar('[data-voltar-lista]');
      await clicar('dialog [data-ficar]');
      expect(dialogo().open).toBe(false);
      expect(navegou).not.toHaveBeenCalled();
      expect(no('[data-nome]').value).toBe('Duda');

      await clicar('[data-voltar-lista]');
      expect(dialogo().open).toBe(true);
      expect(navegou).not.toHaveBeenCalled();
      wrapper.unmount();
    });

    it('leaves to where it was going when "Sair" is chosen, replacing the page in the history', async () => {
      const wrapper = montar();
      await digitar('[data-instrucao]', TEXTO);
      await clicar('[data-voltar-lista]');
      await clicar('dialog [data-confirmar]');
      expect(router.replace).toHaveBeenCalledWith(LISTA);
      expect(navegou).toHaveBeenCalledTimes(1);
      expect(navegou).toHaveBeenCalledWith(LISTA);
      expect(dialogo().open).toBe(false);
      wrapper.unmount();
    });

    it('offers to tell it in my own words, going to the chat creation, under the same question', async () => {
      const wrapper = montar();
      const link = wrapper.get('[data-contar-com-minhas-palavras]');
      expect(link.text()).toBe('AGENTS.JORNADA.ESCREVER.SEM_TEXTO');
      expect(link.classes()).toContain('min-h-11');

      await digitar('[data-nome]', 'Duda');
      await clicar('[data-contar-com-minhas-palavras]');
      expect(navegou).not.toHaveBeenCalled();
      expect(dialogo().open).toBe(true);
      await clicar('dialog [data-confirmar]');
      expect(navegou).toHaveBeenCalledWith(CONTAR);
      wrapper.unmount();
    });

    it('does not leave nor ask while it is creating', async () => {
      store.dispatch.mockImplementation(() => new Promise(() => {}));
      const wrapper = montar();
      await digitar('[data-nome]', 'Duda');
      await digitar('[data-instrucao]', TEXTO);
      await criar();
      expect(no('[data-voltar-lista]').disabled).toBe(true);
      expect(no('[data-contar-com-minhas-palavras]').disabled).toBe(true);
      // O voltar do navegador (ou outro link do painel) passa pela guarda.
      await router.push(LISTA);
      await router.push(CONTAR);
      await flushPromises();
      expect(navegou).not.toHaveBeenCalled();
      expect(dialogo().open).toBeFalsy();
      wrapper.unmount();
    });

    it('does not ask when only the query of the writing page changes', async () => {
      const wrapper = montar();
      await digitar('[data-instrucao]', TEXTO);
      expect(guardas.troca({ query: { escrever: '1', x: '2' } })).toBe(true);
      expect(dialogo().open).toBeFalsy();
      wrapper.unmount();
    });

    it('goes to the chat creation at once when nothing was written', async () => {
      const wrapper = montar();
      await clicar('[data-contar-com-minhas-palavras]');
      expect(navegou).toHaveBeenCalledWith(CONTAR);
      expect(dialogo().open).toBeFalsy();
      wrapper.unmount();
    });
  });

  it('offers no form nor button to a view only seat', () => {
    estado.podeGerenciar = false;
    const wrapper = montar();
    expect(wrapper.text()).toContain('AGENTS.JORNADA.HEROI.SO_VER');
    expect(wrapper.find('[data-criar]').exists()).toBe(false);
    expect(wrapper.find('[data-nome]').exists()).toBe(false);
    expect(wrapper.find('[data-instrucao]').exists()).toBe(false);
    expect(wrapper.find('[data-contar-com-minhas-palavras]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });

  it('keeps every action at least 44 px tall', () => {
    const wrapper = montar();
    expect(wrapper.get('[data-voltar-lista]').classes()).toContain('min-h-11');
    expect(wrapper.get('[data-criar]').classes()).toContain('min-h-12');
    expect(wrapper.get('[data-nome]').classes()).toContain('min-h-11');
    wrapper.unmount();
  });

  it('has every new text in en and pt_BR', () => {
    [agentesEn, agentesPtBR].forEach(catalogo => {
      const jornada = catalogo.AGENTS.JORNADA;
      ['TITULO', 'TEXTO', 'EXEMPLO'].forEach(chave =>
        expect(jornada.CRIAR_EM_PASSOS.ESCREVER.COPILOTO[chave]).toBeTruthy()
      );
      ['ESCOLHIDO', 'TROCAR', 'TROCAR_ARIA', 'VOLTAR'].forEach(chave =>
        expect(jornada.CRIAR_EM_PASSOS.COMO[chave]).toBeTruthy()
      );
      [
        'TITULO',
        'TEXTO',
        'NOME',
        'NOME_DICA',
        'NOME_VAZIO',
        'INSTRUCOES',
        'DICA',
        'SEM_TEXTO',
        'EXEMPLO',
        'CRIAR',
        'CRIANDO',
        'CRIADO',
        'ABRIR',
        'ERRO',
        'ERRO_GARANTIA',
      ].forEach(chave => expect(jornada.ESCREVER[chave]).toBeTruthy());
      ['TITULO', 'TEXTO', 'FICAR', 'SAIR'].forEach(chave =>
        expect(jornada.ESCREVER.SAIR[chave]).toBeTruthy()
      );
      expect(jornada.ESCREVER.CRIADO).toContain('{nome}');
      expect(jornada.ESCREVER.ABRIR).toContain('{nome}');
    });
    expect(
      agentesPtBR.AGENTS.JORNADA.CRIAR_EM_PASSOS.COMO.ESCREVER.TITULO
    ).toBe('Escrever eu mesmo');
  });

  // #3219 — escrever com papel (`?papel=atender|copiloto`, que a entrada passa como prop).
  describe('with a role (#3219)', () => {
    const PASSO_1 = { name: 'autonomia_agents_builder', query: {} };

    it('creates the Team copilot as an internal manual agent, stopped and without a channel', async () => {
      const wrapper = montar({ papel: 'copiloto' });
      await digitar('[data-nome]', 'Duda');
      await digitar('[data-instrucao]', TEXTO);
      await criar();
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/create', {
        name: 'Duda',
        agent_type: 'custom',
        mode: 'manual',
        instruction: TEXTO,
        status: 'paused',
        enabled: false,
        actuation: 'internal',
      });
      wrapper.unmount();
    });

    it('creates the customer agent without actuation, as before', async () => {
      const wrapper = montar({ papel: 'atender' });
      await digitar('[data-nome]', 'Duda');
      await digitar('[data-instrucao]', TEXTO);
      await criar();
      expect(store.dispatch.mock.calls[0][1]).not.toHaveProperty('actuation');
      wrapper.unmount();
    });

    it('shows the Team copilot texts and the chosen role with "Trocar"', () => {
      const wrapper = montar({ papel: 'copiloto' });
      expect(wrapper.get('h1').text()).toBe(
        'AGENTS.JORNADA.CRIAR_EM_PASSOS.ESCREVER.COPILOTO.TITULO'
      );
      expect(wrapper.text()).toContain(
        'AGENTS.JORNADA.CRIAR_EM_PASSOS.ESCREVER.COPILOTO.TEXTO'
      );
      expect(no('[data-instrucao]').getAttribute('placeholder')).toBe(
        'AGENTS.JORNADA.CRIAR_EM_PASSOS.ESCREVER.COPILOTO.EXEMPLO'
      );
      expect(wrapper.get('[data-papel-escolhido]').text()).toContain(
        'AGENTS.JORNADA.CRIAR_EM_PASSOS.PAPEIS.COPILOTO.TITULO'
      );
      expect(wrapper.get('[data-voltar-lista]').text()).toBe(
        'AGENTS.JORNADA.CRIAR_EM_PASSOS.COMO.VOLTAR'
      );
      wrapper.unmount();
    });

    it('keeps the page of always without a role (no band, back to Agents)', async () => {
      const wrapper = montar();
      expect(wrapper.find('[data-papel-escolhido]').exists()).toBe(false);
      expect(wrapper.get('[data-voltar-lista]').text()).toBe(
        'AGENTS.JORNADA.CRIAR.VOLTAR'
      );
      await clicar('[data-voltar-lista]');
      expect(navegou).toHaveBeenCalledWith(LISTA);
      wrapper.unmount();
    });

    it.each([
      ['atender', { papel: 'atender' }],
      ['copiloto', { papel: 'copiloto' }],
    ])('goes back to step 2 of %s with "Voltar"', async (papel, query) => {
      const wrapper = montar({ papel });
      await clicar('[data-voltar-lista]');
      expect(navegou).toHaveBeenCalledWith({
        name: 'autonomia_agents_builder',
        query,
      });
      wrapper.unmount();
    });

    it('goes back to step 1 with "Trocar"', async () => {
      const wrapper = montar({ papel: 'copiloto' });
      await clicar('[data-trocar-papel]');
      expect(navegou).toHaveBeenCalledWith(PASSO_1);
      wrapper.unmount();
    });

    it.each([
      ['atender', { modelo: 'custom' }],
      ['copiloto', { atuacao: 'interno' }],
    ])(
      'opens the conversation of the same role (%s) from "Não tem um texto pronto?"',
      async (papel, query) => {
        const wrapper = montar({ papel });
        await clicar('[data-contar-com-minhas-palavras]');
        expect(navegou).toHaveBeenCalledWith({
          name: 'autonomia_agents_builder',
          query,
        });
        wrapper.unmount();
      }
    );

    it('still asks before leaving with something written, also on "Voltar" and "Trocar"', async () => {
      const wrapper = montar({ papel: 'copiloto' });
      await digitar('[data-instrucao]', TEXTO);
      await clicar('[data-voltar-lista]');
      expect(navegou).not.toHaveBeenCalled();
      expect(dialogo().open).toBe(true);

      dialogo().open = false;
      await clicar('[data-trocar-papel]');
      expect(navegou).not.toHaveBeenCalled();
      expect(dialogo().open).toBe(true);
      wrapper.unmount();
    });
  });
});
