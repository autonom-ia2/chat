import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  ETAPAS_DO_AGGER,
  PEDIR_LOGIN,
  useBuscaNoAgger,
} from '../../carteira/useBuscaNoAgger';
import { caminhosDeTrazer } from '../../carteira/caminhosDeTrazer';
import SeguradorasDaBusca from '../../components/carteira/trazer/agger/SeguradorasDaBusca.vue';
import { recusa } from './apoio';

// #2900 (E7.3) — "Trazer do Agger" na tela: o caminho do botão ao pronto, os
// avisos de cada seguradora com as frases do produto e quem diz os caminhos da
// conta. As fontes são de mentira: nada aqui fala com o servidor nem com IA.
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
      conectar: vi.fn().mockResolvedValue(true),
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

    expect(await busca.conectar({ login: 'exemplo', senha: 'x' })).toBe(true);
    expect(aoMudarBusca).toHaveBeenCalledWith(5);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.BUSCANDO);

    await vi.advanceTimersByTimeAsync(2000);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.CONFERIR);

    await busca.trazer();
    expect(fonte.trazer).toHaveBeenCalledWith(5);
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.PRONTO);
  });

  it('o login recusado não busca e deixa a janela dizer', async () => {
    const fonte = {
      conectar: vi.fn().mockResolvedValue(false),
      buscar: vi.fn(),
    };
    const busca = useBuscaNoAgger(fonte);

    expect(await busca.conectar({ login: 'exemplo', senha: 'x' })).toBe(false);
    expect(fonte.buscar).not.toHaveBeenCalled();
    expect(busca.etapa.value).toBe(ETAPAS_DO_AGGER.INICIO);
  });

  it('a busca parada pelo login: o login aceito de novo busca de novo a mesma', async () => {
    const parou = lendo({ estado: 'parou', motivo: 'agger_pede_login' });
    const fonte = {
      busca: vi.fn().mockResolvedValueOnce(parou).mockResolvedValue(lida),
      conectar: vi.fn().mockResolvedValue(true),
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
});

describe('os avisos das seguradoras', () => {
  const avisos = seguradoras =>
    mount(SeguradorasDaBusca, { props: { seguradoras } });

  it('diz o que houve com cada seguradora, em palavras simples, e só onde há o que fazer', () => {
    const w = avisos([
      { nome: 'Seguradora Azul (exemplo)', situacao: 'pronta' },
      { nome: 'Seguradora Sol (exemplo)', situacao: 'pede_login' },
      { nome: 'Seguradora Lua (exemplo)', situacao: 'sem_login' },
      { nome: 'Seguradora Mar (exemplo)', situacao: 'falhou' },
    ]);
    const frases = w.findAll('li').map(li => li.find('span').text());

    expect(frases).toEqual([
      'A Seguradora Sol (exemplo) pediu para você entrar de novo no Agger',
      'Seu login da Seguradora Lua (exemplo) não está guardado no Agger',
      'Não deu para buscar na Seguradora Mar (exemplo) agora',
    ]);
    const tentar = w.findAll('[data-carteira="tentar-seguradora"]');
    expect(tentar).toHaveLength(1);
    expect(tentar[0].text()).toBe('Tentar de novo');
    expect(tentar[0].attributes('disabled')).toBeUndefined();
  });

  it('a seguradora sem nome é "uma seguradora", e "Tentar de novo" pede a busca de novo', async () => {
    const w = avisos([
      { nome: null, situacao: 'sem_login' },
      { nome: null, situacao: 'falhou' },
    ]);

    expect(w.findAll('li').map(li => li.find('span').text())).toEqual([
      'Seu login de uma seguradora não está guardado no Agger',
      'Não deu para buscar em uma seguradora agora',
    ]);
    await w.get('[data-carteira="tentar-seguradora"]').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });
});

describe('caminhosDeTrazer', () => {
  const resumo = dados => ({ resumo: vi.fn().mockResolvedValue(dados) });

  it('o Agger aparece só com aggerDisponivel, e o login só conta junto', async () => {
    expect(
      await caminhosDeTrazer({
        fonte: resumo({ aggerDisponivel: true, aggerLigado: true }),
      })
    ).toEqual({ pdfs: false, agger: true, aggerLigado: true });
    expect(
      await caminhosDeTrazer({
        fonte: resumo({ aggerDisponivel: false, aggerLigado: true }),
      })
    ).toEqual({ pdfs: false, agger: false, aggerLigado: false });
  });

  it('a demonstração e o resumo que falhou ficam só com a planilha', async () => {
    const falhou = { resumo: vi.fn().mockRejectedValue(new Error('rede')) };

    expect(await caminhosDeTrazer({ fonte: falhou })).toEqual({
      pdfs: false,
      agger: false,
      aggerLigado: false,
    });
    expect(
      await caminhosDeTrazer({
        demo: true,
        fonte: resumo({ aggerDisponivel: true, leituraDePdf: true }),
      })
    ).toEqual({ pdfs: false, agger: false, aggerLigado: false });
  });
});
