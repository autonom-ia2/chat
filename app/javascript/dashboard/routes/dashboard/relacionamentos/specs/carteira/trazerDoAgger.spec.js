import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaInsuranceAPI from 'dashboard/api/autonomiaInsurance';
import {
  ETAPAS_DO_AGGER,
  LOGIN,
  PEDIR_LOGIN,
  useBuscaNoAgger,
} from '../../carteira/useBuscaNoAgger';
import {
  caminhosDeTrazer,
  SEM_CAMINHOS,
} from '../../carteira/caminhosDeTrazer';
import { chaveDaRecusaDoAgger } from '../../carteira/recusas';
import { trazerAggerFonte } from '../../fonte/trazerAggerFonte';
import SeguradorasDaBusca from '../../components/carteira/trazer/agger/SeguradorasDaBusca.vue';
import AndamentoDaBusca from '../../components/carteira/trazer/agger/AndamentoDaBusca.vue';
import { todasComAviso } from '../../carteira/avisosDasSeguradoras';
import { recusa } from './apoio';

// #2900 (E7.3, E7.5) — "Trazer do Agger" na tela: o caminho do botão ao
// pronto, o "mês X de Y" da busca, a linha calma das seguradoras com o detalhe
// atrás de "Ver quais" e quem diz os caminhos da conta. As fontes são de
// mentira: nada aqui fala com o servidor nem com IA.
withFullI18n('pt_BR');
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));
vi.mock('dashboard/api/relacionamentosTrazerPdfs', () => ({ default: {} }));
vi.mock('dashboard/api/relacionamentosTrazerAgger', () => ({ default: {} }));
vi.mock('dashboard/api/autonomiaInsurance', () => ({ default: {} }));

const lendo = (extra = {}) => ({
  id: 5,
  estado: 'lendo',
  porSeguradora: [],
  recebidos: 0,
  ...extra,
});
const lida = { id: 5, estado: 'lida', seguros: 3, pessoas: 3 };

describe('useBuscaNoAgger', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('sem o login aceito, pede o login antes; aceito, busca, confere e traz', async () => {
    const fonte = {
      conectar: vi.fn().mockResolvedValue(LOGIN.ACEITO),
      buscar: vi.fn().mockResolvedValue({ leituraId: 5 }),
      busca: vi.fn().mockResolvedValueOnce(lendo()).mockResolvedValue(lida),
      trazer: vi.fn().mockResolvedValue({ estado: 'trazendo', porcentagem: 0 }),
      andamento: vi.fn().mockResolvedValue({
        estado: 'trazida',
        seguros: 3,
        pessoas: 3,
        pessoasNovas: 3,
      }),
    };
    const aoMudarBusca = vi.fn();
    const busca = useBuscaNoAgger(fonte, { aoMudarBusca });

    expect(await busca.comecar()).toBe(PEDIR_LOGIN);
    expect(fonte.buscar).not.toHaveBeenCalled();

    expect(await busca.conectar({ login: 'exemplo', senha: 'x' })).toBe(
      LOGIN.ACEITO
    );
    expect(aoMudarBusca).toHaveBeenCalledWith(5);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.BUSCANDO);

    await vi.advanceTimersByTimeAsync(2000);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.CONFERIR);

    await busca.trazer();
    expect(fonte.trazer).toHaveBeenCalledWith(5);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.PRONTO);
  });

  it.each([LOGIN.RECUSADO, LOGIN.FORA_DO_AR])(
    'o login %s não busca e deixa a janela dizer',
    async resposta => {
      const fonte = {
        conectar: vi.fn().mockResolvedValue(resposta),
        buscar: vi.fn(),
      };
      const busca = useBuscaNoAgger(fonte);

      expect(await busca.conectar({ login: 'exemplo', senha: 'x' })).toBe(
        resposta
      );
      expect(fonte.buscar).not.toHaveBeenCalled();
      expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.INICIO);
    }
  );

  it('a busca parada pelo login: o login aceito de novo busca de novo a mesma', async () => {
    const parou = lendo({ estado: 'parou', motivo: 'agger_pede_login' });
    const fonte = {
      busca: vi.fn().mockResolvedValueOnce(parou).mockResolvedValue(lida),
      conectar: vi.fn().mockResolvedValue(LOGIN.ACEITO),
      deNovo: vi.fn().mockResolvedValue(lendo()),
    };
    const busca = useBuscaNoAgger(fonte, { ligado: true });

    await busca.abrir(5);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.BUSCANDO);
    expect(busca.busca.value.motivo).toBe('agger_pede_login');

    await busca.conectar({ login: 'exemplo', senha: 'x' });
    expect(fonte.deNovo).toHaveBeenCalledWith(5);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.CONFERIR);
  });

  it('"Buscar de novo" volta direto ao "Buscando", sem os avisos da busca anterior', async () => {
    const comAvisos = {
      ...lida,
      porSeguradora: [{ nome: 'Seguradora Sol (exemplo)', situacao: 'falhou' }],
    };
    let responder;
    const fonte = {
      busca: vi
        .fn()
        .mockResolvedValueOnce(comAvisos)
        .mockReturnValue(
          new Promise(resolver => {
            responder = resolver;
          })
        ),
      deNovo: vi.fn().mockResolvedValue(lendo()),
    };
    const busca = useBuscaNoAgger(fonte, { ligado: true });

    await busca.abrir(5);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.CONFERIR);

    const pedido = busca.deNovo();
    await vi.waitFor(() => expect(fonte.busca).toHaveBeenCalledTimes(2));
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.BUSCANDO);
    expect(busca.busca.value).toEqual({
      id: 5,
      estado: 'lendo',
      porSeguradora: [],
    });
    responder(lendo({ fatias: { pedidas: 1, total: 37 } }));
    await pedido;
    expect(busca.busca.value.fatias).toEqual({ pedidas: 1, total: 37 });
    busca.parar();
  });

  it('o acompanhamento que falha e a busca que não anda têm "Tentar de novo"', async () => {
    const fonte = {
      busca: vi
        .fn()
        .mockResolvedValueOnce(lendo())
        .mockRejectedValueOnce(new Error('rede'))
        .mockResolvedValue(lendo()),
      deNovo: vi.fn().mockResolvedValue(lendo()),
    };
    const busca = useBuscaNoAgger(fonte, { ligado: true });

    await busca.abrir(5);
    await vi.advanceTimersByTimeAsync(2000);
    expect(busca.semAcompanhar.value).toBe(true);
    expect(busca.erro.value).toBe('RELACIONAMENTOS_CARTEIRA.AGGER.NAO_DEU');

    await busca.tentarDeNovo();
    expect(busca.semAcompanhar.value).toBe(false);
    await vi.advanceTimersByTimeAsync(11 * 60 * 1000);
    expect(busca.parado.value).toBe(true);

    await busca.tentarDeNovo();
    expect(fonte.deNovo).toHaveBeenCalledWith(5);
    busca.parar();
  });

  it('a recusa do servidor vira a frase do código', async () => {
    const fonte = {
      buscar: vi.fn().mockRejectedValue(recusa('agger_desligado')),
    };
    const busca = useBuscaNoAgger(fonte, { ligado: true });

    await busca.comecar();
    expect(busca.erro.value).toBe(
      'RELACIONAMENTOS_CARTEIRA.RECUSAS.AGGER_DESLIGADO'
    );
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.INICIO);
  });

  it('as recusas da leitura falam da busca, não do PDF; as outras seguem as de sempre', () => {
    expect(chaveDaRecusaDoAgger('nao_pode_desfazer', 'PADRAO')).toBe(
      'RELACIONAMENTOS_CARTEIRA.AGGER.RECUSAS.NAO_PODE_DESFAZER'
    );
    expect(chaveDaRecusaDoAgger('agger_desligado', 'PADRAO')).toBe(
      'RELACIONAMENTOS_CARTEIRA.RECUSAS.AGGER_DESLIGADO'
    );
    expect(chaveDaRecusaDoAgger('', 'PADRAO')).toBe('PADRAO');
  });
});

describe('a resposta do Agger ao login', () => {
  it.each([
    ['ready', LOGIN.ACEITO],
    ['discovering', LOGIN.ACEITO],
    ['offline', LOGIN.FORA_DO_AR],
    ['degraded', LOGIN.FORA_DO_AR],
    ['human_required', LOGIN.FORA_DO_AR],
    ['auth_required', LOGIN.RECUSADO],
  ])('a conexão em %s é %s', async (status, resposta) => {
    const conexao = { data: { payload: { status } } };
    AutonomiaInsuranceAPI.connect = vi.fn().mockResolvedValue(conexao);

    expect(
      await trazerAggerFonte().conectar({ login: 'exemplo', senha: 'x' })
    ).toBe(resposta);
  });
});

describe('as seguradoras que não buscaram seguros novos', () => {
  const avisos = (seguradoras, props = {}) =>
    mount(SeguradorasDaBusca, { props: { seguradoras, ...props } });
  const variadas = [
    { nome: 'Seguradora Azul (exemplo)', situacao: 'pronta' },
    { nome: 'Seguradora Sol (exemplo)', situacao: 'pede_login' },
    { nome: 'Seguradora Lua (exemplo)', situacao: 'sem_login' },
    { nome: 'Seguradora Mar (exemplo)', situacao: 'falhou' },
    { nome: null, situacao: 'falhou' },
    { nome: 'Seguradora Rio (exemplo)', situacao: 'falhou' },
  ];

  it('nenhum aviso quando tudo foi bem', () => {
    const w = avisos([
      { nome: 'Seguradora Azul (exemplo)', situacao: 'pronta' },
      { nome: 'Seguradora Verde (exemplo)', situacao: 'buscando' },
    ]);

    expect(w.find('[data-carteira="seguradoras-da-busca"]').exists()).toBe(
      false
    );
  });

  it('é uma linha calma só, com "Ver quais" fechado; os grupos ficam escondidos até abrir', async () => {
    const w = avisos(variadas);

    expect(w.get('[data-carteira="frase-das-seguradoras"]').text()).toBe(
      'O Agger não buscou seguros novos em 5 seguradoras agora. Os que já estavam no Agger vieram.'
    );
    const ver = w.get('[data-carteira="ver-quais"]');
    expect(ver.element.tagName).toBe('BUTTON');
    expect(ver.text()).toBe('Ver quais');
    expect(ver.attributes('aria-expanded')).toBe('false');
    const grupos = w.get('[data-carteira="grupos-das-seguradoras"]');
    expect(ver.attributes('aria-controls')).toBe(grupos.attributes('id'));
    expect(grupos.isVisible()).toBe(false);

    await ver.trigger('click');
    expect(grupos.isVisible()).toBe(true);
    expect(ver.attributes('aria-expanded')).toBe('true');
    expect(ver.text()).toBe('Esconder');
  });

  it('dentro, um grupo por situação, com os nomes e uma frase do que fazer', async () => {
    const w = avisos(variadas);
    await w.get('[data-carteira="ver-quais"]').trigger('click');
    const grupos = w.findAll('[data-situacao]');

    expect(grupos.map(grupo => grupo.attributes('data-situacao'))).toEqual([
      'pede_login',
      'sem_login',
      'falhou',
    ]);
    expect(
      grupos.map(grupo => grupo.get('[data-carteira="nomes-do-grupo"]').text())
    ).toEqual([
      'Seguradora Sol (exemplo)',
      'Seguradora Lua (exemplo)',
      'Seguradora Mar (exemplo), Seguradora Rio (exemplo) e mais uma seguradora',
    ]);
    expect(grupos[0].text()).toContain(
      'Entre de novo nessa seguradora, no Agger.'
    );
    expect(grupos[1].text()).toContain(
      'Guarde no Agger o login dessa seguradora.'
    );
    expect(grupos[2].text()).toContain(
      'O Agger não conseguiu buscar nessas seguradoras agora. Tente de novo mais tarde.'
    );
    const tentar = w.findAll('[data-carteira="tentar-seguradora"]');
    expect(tentar).toHaveLength(1);
    expect(tentar[0].text()).toBe('Tentar de novo');
    expect(tentar[0].attributes('disabled')).toBeUndefined();
    await tentar[0].trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });

  it('a seguradora sem nome é "uma seguradora"', async () => {
    const w = avisos([
      { nome: null, situacao: 'sem_login' },
      { nome: null, situacao: 'sem_login' },
    ]);
    await w.get('[data-carteira="ver-quais"]').trigger('click');

    expect(w.get('[data-carteira="nomes-do-grupo"]').text()).toBe(
      '2 seguradoras'
    );
    expect(w.get('[data-situacao="sem_login"]').text()).toContain(
      'Guarde no Agger o login dessas seguradoras.'
    );
  });

  it('nada veio e todas com aviso: a linha é a frase do que fazer, sem culpar ninguém', () => {
    const todas = variadas.filter(({ situacao }) => situacao !== 'pronta');
    const w = avisos(todas, { nadaVeio: true });

    expect(todasComAviso(todas)).toBe(true);
    expect(todasComAviso(variadas)).toBe(false);
    expect(todasComAviso([])).toBe(false);
    expect(w.get('[data-carteira="frase-das-seguradoras"]').text()).toBe(
      'Nenhum seguro veio desta vez: o Agger não conseguiu buscar nas seguradoras agora. Veja o que fazer em cada uma e busque de novo mais tarde.'
    );
  });
});

describe('o andamento da busca no Agger', () => {
  const andamento = fatias => mount(AndamentoDaBusca, { props: { fatias } });

  it('com as fatias, uma barra simples: "Buscando mês 5 de 37"', () => {
    const w = andamento({ pedidas: 5, total: 37 });

    expect(w.text()).toContain(
      'Buscando seus seguros… Pode sair desta página: a busca continua.'
    );
    expect(w.get('[data-carteira="mes-da-busca"]').text()).toBe(
      'Buscando mês 5 de 37'
    );
    const barra = w.get('[role="progressbar"]');
    expect(barra.attributes('aria-valuenow')).toBe('5');
    expect(barra.attributes('aria-valuemax')).toBe('37');
    expect(barra.attributes('aria-valuetext')).toBe('Buscando mês 5 de 37');
  });

  it.each([null, { pedidas: 1, total: 1 }])(
    'sem fatias (ou com um mês só), só a frase, sem barra: %o',
    fatias => {
      const w = andamento(fatias);

      expect(w.find('[role="progressbar"]').exists()).toBe(false);
      expect(w.find('[data-carteira="mes-da-busca"]').exists()).toBe(false);
      expect(w.text()).toContain('Buscando seus seguros…');
    }
  );
});

describe('caminhosDeTrazer', () => {
  const resumo = dados => ({ resumo: vi.fn().mockResolvedValue(dados) });

  it('o Agger aparece só com aggerDisponivel, e o login só conta junto', async () => {
    expect(
      await caminhosDeTrazer({
        fonte: resumo({ aggerDisponivel: true, aggerLigado: true }),
      })
    ).toEqual({
      pdfs: false,
      agger: true,
      aggerLigado: true,
      aggerPedeLogin: false,
    });
    expect(
      await caminhosDeTrazer({
        fonte: resumo({ aggerDisponivel: false, aggerLigado: true }),
      })
    ).toEqual({
      pdfs: false,
      agger: false,
      aggerLigado: false,
      aggerPedeLogin: false,
    });
  });

  it('o login recusado pelo Agger chega à porta', async () => {
    const caminhos = await caminhosDeTrazer({
      fonte: resumo({
        aggerDisponivel: true,
        aggerLigado: true,
        aggerPedeLogin: true,
      }),
    });

    expect(caminhos.aggerPedeLogin).toBe(true);
  });

  it('a demonstração e o resumo que falhou ficam só com a planilha', async () => {
    const falhou = { resumo: vi.fn().mockRejectedValue(new Error('rede')) };

    expect(await caminhosDeTrazer({ fonte: falhou })).toEqual(SEM_CAMINHOS);
    expect(
      await caminhosDeTrazer({
        demo: true,
        fonte: resumo({ aggerDisponivel: true, leituraDePdf: true }),
      })
    ).toEqual(SEM_CAMINHOS);
  });
});
