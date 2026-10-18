import TelaInicialAPI from 'dashboard/api/telaInicial';
import { buscarResumo, lerResumo } from '../resumoDoServidor';

vi.mock('dashboard/api/telaInicial', () => ({
  default: { resumo: vi.fn() },
}));

const doServidor = {
  esperam: 4,
  sem_responsavel: 2,
  fora_do_prazo: 3,
  proxima: {
    id: 40,
    display_id: 4,
    nome_do_contato: 'Ana Lima',
    waiting_since: 1000,
  },
  equipe: { esperam: 12, sem_responsavel: 2, fora_do_prazo: 5 },
};

describe('resumoDoServidor', () => {
  beforeEach(() => vi.clearAllMocks());

  it('chama a rota do resumo e traduz os campos', async () => {
    TelaInicialAPI.resumo.mockResolvedValue({ data: doServidor });
    expect(await buscarResumo()).toEqual({
      esperamVoce: 4,
      semResponsavel: 2,
      foraDoPrazo: 3,
      proxima: { displayId: 4, nome: 'Ana Lima', desde: 1000 },
      equipe: { esperam: 12, semResponsavel: 2, foraDoPrazo: 5 },
    });
    expect(TelaInicialAPI.resumo).toHaveBeenCalledTimes(1);
  });

  it('agente sem equipe e conta sem prazos', () => {
    expect(
      lerResumo({
        esperam: 0,
        sem_responsavel: 1,
        fora_do_prazo: null,
        proxima: null,
      })
    ).toEqual({
      esperamVoce: 0,
      semResponsavel: 1,
      foraDoPrazo: null,
      proxima: null,
      equipe: null,
    });
  });

  it('erro da api sobe para quem chamou', async () => {
    TelaInicialAPI.resumo.mockRejectedValue(new Error('rede'));
    await expect(buscarResumo()).rejects.toThrow('rede');
  });
});
