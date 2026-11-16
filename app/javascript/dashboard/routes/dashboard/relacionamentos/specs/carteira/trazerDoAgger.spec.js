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
import { recusa } from './apoio';

// #2900 (E7.3, E7.5) — "Trazer do Agger" na tela: o caminho do botão ao
// pronto, o "Tentar de novo" que começa uma busca nova, a linha calma das
// seguradoras (só com evidência) com o detalhe atrás de "Ver quais
// seguradoras" e quem diz os caminhos da conta. As fontes são de mentira: nada
// aqui fala com o servidor nem com IA.
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
      porSeguradora: [
        { nome: 'Seguradora Sol (exemplo)', situacao: 'pede_login' },
      ],
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
    responder(lendo({ recebidos: 3 }));
    await pedido;
    expect(busca.busca.value.recebidos).toBe(3);
    busca.parar();
  });

  it('"Tentar de novo" começa uma busca nova, pelo mesmo caminho do botão grande', async () => {
    const fonte = {
      busca: vi
        .fn()
        .mockResolvedValueOnce(lendo())
        .mockRejectedValueOnce(new Error('rede'))
        .mockResolvedValue(lendo({ id: 6 })),
      buscar: vi.fn().mockResolvedValue({ leituraId: 6 }),
      deNovo: vi.fn(),
    };
    const aoMudarBusca = vi.fn();
    const busca = useBuscaNoAgger(fonte, { ligado: true, aoMudarBusca });

    await busca.abrir(5);
    await vi.advanceTimersByTimeAsync(2000);
    expect(busca.semAcompanhar.value).toBe(true);
    expect(busca.erro.value).toBe('RELACIONAMENTOS_CARTEIRA.AGGER.NAO_DEU');

    await busca.tentarDeNovo();
    expect(fonte.buscar).toHaveBeenCalledTimes(1);
    expect(fonte.deNovo).not.toHaveBeenCalled();
    expect(aoMudarBusca).toHaveBeenLastCalledWith(6);
    expect(fonte.busca).toHaveBeenLastCalledWith(6);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.BUSCANDO);
    expect(busca.semAcompanhar.value).toBe(false);
    expect(busca.erro.value).toBe('');

    await vi.advanceTimersByTimeAsync(11 * 60 * 1000);
    expect(busca.parado.value).toBe(true);
    await busca.tentarDeNovo();
    expect(fonte.buscar).toHaveBeenCalledTimes(2);
    expect(busca.parado.value).toBe(false);
    busca.parar();
  });

  it('"Tentar de novo" na busca que parou também começa uma busca nova', async () => {
    const parou = lendo({ estado: 'parou', motivo: 'agger_falhou' });
    const fonte = {
      busca: vi.fn().mockResolvedValueOnce(parou).mockResolvedValue(lida),
      buscar: vi.fn().mockResolvedValue({ leituraId: 7 }),
      deNovo: vi.fn(),
    };
    const busca = useBuscaNoAgger(fonte, { ligado: true });

    await busca.abrir(5);
    expect(busca.busca.value.estado).toBe('parou');

    await busca.tentarDeNovo();
    expect(fonte.buscar).toHaveBeenCalledTimes(1);
    expect(fonte.deNovo).not.toHaveBeenCalled();
    expect(fonte.busca).toHaveBeenLastCalledWith(7);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.CONFERIR);
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

describe('as seguradoras com o login faltando ou recusado no Agger', () => {
  const avisos = seguradoras =>
    mount(SeguradorasDaBusca, { props: { seguradoras } });
  const variadas = [
    { nome: 'Seguradora Azul (exemplo)', situacao: 'pronta' },
    { nome: 'Seguradora Sol (exemplo)', situacao: 'pede_login' },
    { nome: 'Seguradora Lua (exemplo)', situacao: 'sem_login' },
    { nome: 'Seguradora Mar (exemplo)', situacao: 'sem_login' },
    { nome: null, situacao: 'sem_login' },
    { nome: 'Seguradora Rio (exemplo)', situacao: 'falhou' },
  ];

  it('sem evidência, nenhum aviso: nem a seguradora pronta, nem a que só não respondeu', () => {
    const w = avisos([
      { nome: 'Seguradora Azul (exemplo)', situacao: 'pronta' },
      { nome: 'Seguradora Verde (exemplo)', situacao: 'buscando' },
      { nome: 'Seguradora Rio (exemplo)', situacao: 'falhou' },
    ]);

    expect(w.find('[data-carteira="seguradoras-da-busca"]').exists()).toBe(
      false
    );
  });

  it('é uma linha calma só, com "Ver quais seguradoras" fechado; os grupos ficam escondidos até abrir', async () => {
    const w = avisos(variadas);

    expect(w.get('[data-carteira="frase-das-seguradoras"]').text()).toBe(
      '4 seguradoras precisam do seu login no Agger para trazer seguros novos.'
    );
    const ver = w.get('[data-carteira="ver-quais"]');
    expect(ver.element.tagName).toBe('BUTTON');
    expect(ver.attributes('type')).toBe('button');
    expect(ver.classes()).toContain('min-h-11');
    expect(ver.text()).toBe('Ver quais seguradoras');
    expect(ver.attributes('aria-expanded')).toBe('false');
    const grupos = () => w.get('[data-carteira="grupos-das-seguradoras"]');
    expect(ver.attributes('aria-controls')).toBe(grupos().attributes('id'));
    expect(grupos().attributes('style')).toContain('display: none');

    await ver.trigger('click');
    expect(grupos().attributes('style') ?? '').not.toContain('display: none');
    expect(ver.attributes('aria-expanded')).toBe('true');
    expect(ver.text()).toBe('Esconder');
  });

  it('dentro, um grupo pelo que fazer, com os nomes e a frase do que fazer', async () => {
    const w = avisos(variadas);
    await w.get('[data-carteira="ver-quais"]').trigger('click');
    const grupos = w.findAll('[data-situacao]');

    expect(grupos.map(grupo => grupo.attributes('data-situacao'))).toEqual([
      'pede_login',
      'sem_login',
    ]);
    expect(
      grupos.map(grupo => grupo.get('[data-carteira="nomes-do-grupo"]').text())
    ).toEqual([
      'Seguradora Sol (exemplo)',
      'Seguradora Lua (exemplo), Seguradora Mar (exemplo) e mais uma seguradora',
    ]);
    expect(grupos[0].text()).toContain(
      'Entre de novo nessa seguradora, no Agger.'
    );
    expect(grupos[1].text()).toContain(
      'Guarde no Agger o login dessas seguradoras.'
    );
    expect(w.text()).not.toContain('Seguradora Rio (exemplo)');
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
