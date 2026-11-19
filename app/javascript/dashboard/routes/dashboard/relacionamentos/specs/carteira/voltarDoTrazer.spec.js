import { RouterLinkStub, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import ComoTrazer from '../../components/carteira/trazer/pdfs/ComoTrazer.vue';
import TrazerPdfs from '../../components/carteira/trazer/pdfs/TrazerPdfs.vue';
import TrazerDoAgger from '../../components/carteira/trazer/agger/TrazerDoAgger.vue';
import DialogoDoLoginNoAgger from '../../components/carteira/trazer/agger/DialogoDoLoginNoAgger.vue';
import { LOGIN } from '../../carteira/useBuscaNoAgger';
import { DialogoFalso } from './apoio';

// #3057 — "Como trazer", "Trazer por PDFs" e "Do Agger" têm o caminho de volta
// no topo (sem ele, no celular a única saída era o ☰). "Como trazer" volta à
// aba de onde a pessoa veio (`?aba=`); PDFs e Agger voltam a "Como trazer". As
// fontes ficam esperando para sempre: aqui só importa o topo das telas. Junto,
// o redesenho: os caminhos do mais fácil para o mais trabalhoso, as etapas da
// jornada, o começo do Agger em 3 passos e a janela do login.
vi.mock('dashboard/api/relacionamentosTrazerPdfs', () => ({ default: {} }));
vi.mock('dashboard/api/relacionamentosTrazerAgger', () => ({ default: {} }));
vi.mock('dashboard/api/autonomiaInsurance', () => ({ default: {} }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { usePermissionGranted: () => computed(() => true) };
});
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {} });
  const roteador = { push: vi.fn(), replace: vi.fn() };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const roteador = useRouter();
const rota = useRoute();
// Uma fonte que nunca responde.
const fonteParada = () =>
  new Proxy(
    {},
    {
      get: (_, nome) =>
        nome === 'then' ? undefined : () => new Promise(() => {}),
    }
  );

let aberta;
afterEach(() => {
  aberta?.unmount();
  aberta = null;
  roteador.push.mockClear();
  rota.query = {};
});
const montar = async (Tela, props) => {
  aberta = mount(Tela, {
    attachTo: document.body,
    props,
    global: {
      stubs: { RouterLink: RouterLinkStub, Dialog: DialogoFalso },
    },
  });
  await flushPromises();
  return aberta;
};
const volta = w => w.get('[data-relacionamentos="voltar"]');

const COMO = {
  rotas: {
    planilha: { q: 'planilha' },
    pdfs: { q: 'pdfs' },
    agger: { q: 'agger' },
  },
  caminhos: ['planilha', 'pdfs'],
};

describe('a volta de "Como trazer": à aba de onde a pessoa veio', () => {
  it.each([
    [{}, 'Voltar para Pessoas', {}],
    [{ aba: 'empresas' }, 'Voltar para Empresas', { aba: 'empresas' }],
    [{ aba: 'seguros' }, 'Voltar para Seguros', { aba: 'seguros' }],
    [{ aba: 'outra' }, 'Voltar para Pessoas', {}],
  ])('com %o, diz "%s" e volta para a aba', async (query, texto, destino) => {
    rota.query = query;
    const w = await montar(ComoTrazer, COMO);

    expect(volta(w).text()).toBe(texto);
    expect(volta(w).element.compareDocumentPosition(w.get('h1').element)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING
    );
    await volta(w).trigger('click');

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relationships_home',
      query: destino,
    });
  });
});

describe.each([
  ['Trazer por PDFs', TrazerPdfs],
  ['Do Agger', TrazerDoAgger],
])('a volta de %s: a "Como trazer"', (_, Tela) => {
  it('fica no topo e volta a "Como trazer", na mesma aba de origem, sem o lote', async () => {
    rota.query = { como: 'pdfs', aba: 'seguros' };
    const w = await montar(Tela, { fonte: fonteParada() });

    expect(volta(w).text()).toBe('Voltar e escolher outro jeito');
    expect(volta(w).element.compareDocumentPosition(w.get('h1').element)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING
    );
    await volta(w).trigger('click');

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_trazer',
      query: { aba: 'seguros' },
    });
  });

  it('mostra as etapas da jornada, com a primeira marcada como a de agora', async () => {
    const w = await montar(Tela, { fonte: fonteParada() });
    const etapas = w.findAll('[data-carteira="etapas"] li');

    expect(etapas.map(e => e.text())).toEqual([
      expect.stringMatching(/^1(Enviar|Buscar)$/),
      '2Conferir',
      '3Pronto',
    ]);
    expect(etapas[0].attributes('aria-current')).toBe('step');
    expect(etapas[1].attributes('aria-current')).toBeUndefined();
  });
});

describe('"Como trazer"', () => {
  it('título de leigo e os caminhos do mais fácil para o mais trabalhoso', async () => {
    const w = await montar(ComoTrazer, {
      ...COMO,
      caminhos: ['planilha', 'pdfs', 'agger'],
    });

    expect(w.get('h1').text()).toBe('Escolha o que você tem em mãos');
    const caminhos = w.findAll('[data-como]');
    expect(caminhos.map(c => c.attributes('data-como'))).toEqual([
      'agger',
      'pdfs',
      'planilha',
    ]);
    expect(caminhos[0].text()).toContain('O jeito mais fácil');
    expect(caminhos[0].text()).toContain(
      'O Agger é o sistema onde a corretora guarda os seguros.'
    );
    expect(caminhos[1].text()).toContain('Os PDFs que a seguradora mandou');
    expect(caminhos[2].text()).toContain(
      'Planilha do Excel ou do Google Planilhas'
    );
    expect(w.findAll('[data-mais-facil]')).toHaveLength(1);
    expect(w.get('[data-carteira="confianca"]').text()).toBe(
      'Nada entra antes de você conferir.'
    );
  });

  it('sem o Agger, o mais fácil é o dos PDFs, e cada caminho leva à sua rota', async () => {
    const w = await montar(ComoTrazer, COMO);
    const caminhos = w.findAllComponents(RouterLinkStub);

    expect(caminhos.map(c => c.props('to'))).toEqual([
      { q: 'pdfs' },
      { q: 'planilha' },
    ]);
    expect(w.get('[data-mais-facil]').attributes('data-como')).toBe('pdfs');
  });
});

describe('"Do Agger": o começo', () => {
  it('explica em 3 passos, mostra o selo da senha e o botão grande', async () => {
    const w = await montar(TrazerDoAgger, { fonte: fonteParada() });

    expect(
      w.findAll('[data-carteira="passos-do-agger"] li').map(p => p.text())
    ).toEqual([
      '1Você entra com o login e a senha do Agger.',
      '2Eu busco no Agger os seguros dos seus clientes.',
      '3Você confere tudo antes de qualquer coisa entrar.',
    ]);
    expect(w.get('[data-carteira="selo-do-agger"]').text()).toBe(
      'Sua senha fica guardada em segredo e serve só para buscar seus seguros.'
    );
    expect(w.get('[data-carteira="buscar-no-agger"]').text()).toBe(
      'Trazer meus seguros do Agger'
    );
  });
});

describe('a janela do login do Agger', () => {
  const abrirJanela = async conectar => {
    const w = await montar(DialogoDoLoginNoAgger, { conectar });
    w.vm.abrir();
    await flushPromises();
    return w;
  };
  const senha = w => w.get('#carteira-agger-senha');

  it('tem cabeçalho com a frase de confiança e cada campo com rótulo e ajuda', async () => {
    const w = await abrirJanela(vi.fn());
    const janela = w.get('[data-carteira="login-do-agger"]');

    expect(janela.text()).toContain('Entrar no Agger');
    expect(janela.text()).toContain(
      'Eles servem só para eu buscar os seus seguros lá.'
    );
    expect(w.get('label[for="carteira-agger-login"]').text()).toBe(
      'Login do Agger'
    );
    expect(janela.text()).toContain(
      'O mesmo que você digita para entrar no Agger.'
    );
    expect(w.get('label[for="carteira-agger-senha"]').text()).toBe(
      'Senha do Agger'
    );
    expect(janela.text()).toContain('A senha fica guardada em segredo.');
    expect(w.get('[data-confirmar]').text()).toBe('Entrar e buscar');
    expect(w.get('[data-cancelar]').text()).toBe('Voltar');
  });

  it('"Mostrar a senha" mostra e esconde, e a senha volta escondida ao fechar', async () => {
    const w = await abrirJanela(vi.fn());
    const olho = () => w.get('[data-carteira="mostrar-senha"]');

    expect(senha(w).attributes('type')).toBe('password');
    expect(olho().attributes('aria-label')).toBe('Mostrar a senha');
    await olho().trigger('click');
    expect(senha(w).attributes('type')).toBe('text');
    expect(olho().attributes('aria-label')).toBe('Esconder a senha');

    await w.get('[data-cancelar]').trigger('click');
    w.vm.abrir();
    await flushPromises();
    expect(senha(w).attributes('type')).toBe('password');
  });

  it('o recado de erro é de gente, numa faixa de alerta', async () => {
    const conectar = vi.fn().mockResolvedValue(LOGIN.RECUSADO);
    const w = await abrirJanela(conectar);
    await w.get('#carteira-agger-login').setValue('exemplo');
    await senha(w).setValue('segredo-de-teste');

    await w.get('[data-confirmar]').trigger('click');
    await flushPromises();

    const alerta = w.get('[data-carteira="alerta-do-login"]');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(
      'O Agger não aceitou esse login e essa senha. Confira e tente de novo.'
    );
  });

  it('enquanto o Agger responde, o botão de entrar gira', async () => {
    const w = await abrirJanela(vi.fn(() => new Promise(() => {})));
    await w.get('#carteira-agger-login').setValue('exemplo');
    await senha(w).setValue('segredo-de-teste');

    await w.get('[data-confirmar]').trigger('click');
    await flushPromises();

    expect(w.get('[data-dialogo-falso]').attributes('data-carregando')).toBe(
      'true'
    );
  });
});
