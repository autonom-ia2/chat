import LabelsAPI from 'dashboard/api/labels';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { acoesDaListaFonte } from '../../fonte/acoesDaListaFonte';
import { PESSOAS_POR_FATIA } from '../../fonte/emFatias';

// A fonte real das ações em grupo (#2894): fala com o servidor pelo cliente de
// API, manda as pessoas em fatias, uma depois da outra, e devolve o que a tela
// lê. O contrato do servidor está em
// spec/requests/api/v1/accounts/relacionamentos_acoes_spec.rb.
vi.mock('dashboard/api/relacionamentos', () => ({
  default: {
    funis: vi.fn(),
    criarCards: vi.fn(),
    aplicarEtiqueta: vi.fn(),
    apagar: vi.fn(),
  },
}));
vi.mock('dashboard/api/labels', () => ({ default: { get: vi.fn() } }));

const real = () => acoesDaListaFonte({ demo: null });
const pessoas = quantas =>
  Array.from({ length: quantas }, (_, i) => ({
    id: i + 1,
    name: `Pessoa ${i + 1}`,
  }));
const ids = (de, ate) => Array.from({ length: ate - de + 1 }, (_, i) => de + i);
const erroHttp = status =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error: 'pedido recusado' } },
  });
// O servidor responde quantas deram certo na fatia que recebeu.
const respondeAFatia = (metodo, contagem, deFora = () => []) =>
  RelacionamentosAPI[metodo].mockImplementation(async corpo => {
    const fora = deFora(corpo.pessoa_ids);
    return {
      data: {
        [contagem]: corpo.pessoa_ids.length - fora.length,
        de_fora: fora,
      },
    };
  });
const adiada = () => {
  let resolver;
  const promessa = new Promise(resolve => {
    resolver = resolve;
  });
  return { promessa, resolver };
};

afterEach(() => {
  vi.resetAllMocks();
});

describe('leituras', () => {
  it('não é a demonstração', () => {
    expect(real().usaDemo).toBe(false);
  });

  it('funis devolve os funis com as etapas como o servidor mandou', async () => {
    const funis = [
      { id: 3, nome: 'Vendas', etapas: [{ id: 4, nome: 'Novo' }] },
    ];
    RelacionamentosAPI.funis.mockResolvedValue({ data: funis });
    expect(await real().funis()).toEqual(funis);
  });

  it('funis repassa o 401 de quem não pode ver o CRM', async () => {
    const recusado = erroHttp(401);
    RelacionamentosAPI.funis.mockRejectedValue(recusado);
    await expect(real().funis()).rejects.toBe(recusado);
  });

  it('etiquetas lê as da conta pelo cliente que o painel já usa, em ordem alfabética', async () => {
    LabelsAPI.get.mockResolvedValue({
      data: { payload: [{ title: 'site' }, { title: 'feira' }] },
    });
    expect(await real().etiquetas()).toEqual(['feira', 'site']);
    expect(LabelsAPI.get).toHaveBeenCalledWith(true);
  });
});

describe('fatias', () => {
  it('a fatia tem 50 pessoas', () => {
    expect(PESSOAS_POR_FATIA).toBe(50);
  });

  it('manda os ids de 50 em 50, uma fatia depois da outra', async () => {
    const esperas = [adiada(), adiada(), adiada()];
    RelacionamentosAPI.apagar
      .mockReturnValueOnce(esperas[0].promessa)
      .mockReturnValueOnce(esperas[1].promessa)
      .mockReturnValueOnce(esperas[2].promessa);
    const pronto = real().apagar({ pessoas: pessoas(120) });
    await Promise.resolve();
    expect(RelacionamentosAPI.apagar).toHaveBeenCalledTimes(1);
    esperas[0].resolver({ data: { apagadas: 50, de_fora: [] } });
    await vi.waitFor(() =>
      expect(RelacionamentosAPI.apagar).toHaveBeenCalledTimes(2)
    );
    esperas[1].resolver({ data: { apagadas: 50, de_fora: [] } });
    await vi.waitFor(() =>
      expect(RelacionamentosAPI.apagar).toHaveBeenCalledTimes(3)
    );
    esperas[2].resolver({ data: { apagadas: 20, de_fora: [] } });
    await pronto;
    expect(
      RelacionamentosAPI.apagar.mock.calls.map(([corpo]) => corpo)
    ).toEqual([
      { pessoa_ids: ids(1, 50) },
      { pessoa_ids: ids(51, 100) },
      { pessoa_ids: ids(101, 120) },
    ]);
  });

  it('soma o que cada fatia fez e junta quem ficou de fora, traduzindo `de_fora`', async () => {
    const fora = lote =>
      lote
        .filter(id => id === 7 || id === 60)
        .map(id => ({ id, nome: `Pessoa ${id}`, motivo: 'nao_apagada' }));
    respondeAFatia('apagar', 'apagadas', fora);
    expect(await real().apagar({ pessoas: pessoas(120) })).toEqual({
      apagadas: 118,
      deFora: [
        { id: 7, nome: 'Pessoa 7', motivo: 'nao_apagada' },
        { id: 60, nome: 'Pessoa 60', motivo: 'nao_apagada' },
      ],
      faltam: [],
      erro: null,
    });
  });

  it('avisa o andamento a cada fatia: feitas de total', async () => {
    respondeAFatia('apagar', 'apagadas');
    const aoAndar = vi.fn();
    await real().apagar({ pessoas: pessoas(120), aoAndar });
    expect(aoAndar.mock.calls.map(([passo]) => passo)).toEqual([
      { feitas: 50, total: 120 },
      { feitas: 100, total: 120 },
      { feitas: 120, total: 120 },
    ]);
  });

  it.each([
    ['rede', new Error('Network Error')],
    ['500', erroHttp(500)],
    ['422', erroHttp(422)],
  ])(
    'falha de %s na 2ª fatia: para ali e devolve o parcial com o erro',
    async (_qual, falha) => {
      respondeAFatia('apagar', 'apagadas');
      RelacionamentosAPI.apagar.mockImplementationOnce(async () => ({
        data: {
          apagadas: 49,
          de_fora: [{ id: 3, nome: null, motivo: 'nao_existe_mais' }],
        },
      }));
      RelacionamentosAPI.apagar.mockRejectedValueOnce(falha);
      const todas = pessoas(120);
      const resultado = await real().apagar({ pessoas: todas });
      expect(RelacionamentosAPI.apagar).toHaveBeenCalledTimes(2);
      expect(resultado).toEqual({
        apagadas: 49,
        deFora: [{ id: 3, nome: null, motivo: 'nao_existe_mais' }],
        faltam: todas.slice(50),
        erro: falha,
      });
    }
  );

  it('falha já na 1ª fatia: nada feito, todas faltam e o erro vem junto', async () => {
    const falha = erroHttp(500);
    RelacionamentosAPI.apagar.mockRejectedValue(falha);
    const todas = pessoas(3);
    expect(await real().apagar({ pessoas: todas })).toEqual({
      apagadas: 0,
      deFora: [],
      faltam: todas,
      erro: falha,
    });
  });

  it('tentar de novo só com as que faltam manda só elas', async () => {
    respondeAFatia('apagar', 'apagadas');
    RelacionamentosAPI.apagar.mockImplementationOnce(async () => ({
      data: { apagadas: 50, de_fora: [] },
    }));
    RelacionamentosAPI.apagar.mockRejectedValueOnce(erroHttp(500));
    const primeira = await real().apagar({ pessoas: pessoas(120) });
    RelacionamentosAPI.apagar.mockClear();
    const segunda = await real().apagar({ pessoas: primeira.faltam });
    expect(
      RelacionamentosAPI.apagar.mock.calls.map(([corpo]) => corpo)
    ).toEqual([{ pessoa_ids: ids(51, 100) }, { pessoa_ids: ids(101, 120) }]);
    expect(segunda).toEqual({
      apagadas: 70,
      deFora: [],
      faltam: [],
      erro: null,
    });
  });

  it('para antes da próxima fatia quando pedem para parar, sem erro', async () => {
    respondeAFatia('apagar', 'apagadas');
    const todas = pessoas(120);
    const deveParar = () => RelacionamentosAPI.apagar.mock.calls.length >= 1;
    expect(await real().apagar({ pessoas: todas, deveParar })).toEqual({
      apagadas: 50,
      deFora: [],
      faltam: todas.slice(50),
      erro: null,
    });
  });
});

describe('cada escrita manda o corpo que o servidor espera', () => {
  it('criarCards: pessoa_ids, funil_id e etapa_id, e devolve `criados`', async () => {
    respondeAFatia('criarCards', 'criados', lote =>
      lote
        .filter(id => id === 2)
        .map(id => ({ id, nome: 'Bia', motivo: 'ja_tem_card' }))
    );
    expect(
      await real().criarCards({ pessoas: pessoas(3), funilId: 3, etapaId: 4 })
    ).toEqual({
      criados: 2,
      deFora: [{ id: 2, nome: 'Bia', motivo: 'ja_tem_card' }],
      faltam: [],
      erro: null,
    });
    expect(RelacionamentosAPI.criarCards).toHaveBeenCalledWith({
      pessoa_ids: [1, 2, 3],
      funil_id: 3,
      etapa_id: 4,
    });
  });

  it('aplicarEtiqueta: pessoa_ids e etiqueta, e devolve `aplicadas`', async () => {
    respondeAFatia('aplicarEtiqueta', 'aplicadas');
    expect(
      await real().aplicarEtiqueta({ pessoas: pessoas(2), etiqueta: 'feira' })
    ).toEqual({ aplicadas: 2, deFora: [], faltam: [], erro: null });
    expect(RelacionamentosAPI.aplicarEtiqueta).toHaveBeenCalledWith({
      pessoa_ids: [1, 2],
      etiqueta: 'feira',
    });
  });

  it('apagar: só pessoa_ids, e devolve `apagadas`', async () => {
    respondeAFatia('apagar', 'apagadas');
    expect(await real().apagar({ pessoas: pessoas(2) })).toEqual({
      apagadas: 2,
      deFora: [],
      faltam: [],
      erro: null,
    });
    expect(RelacionamentosAPI.apagar).toHaveBeenCalledWith({
      pessoa_ids: [1, 2],
    });
  });
});
