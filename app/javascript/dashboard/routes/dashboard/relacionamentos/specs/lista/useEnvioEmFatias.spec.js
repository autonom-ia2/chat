import { effectScope } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useEnvioEmFatias } from '../../lista/useEnvioEmFatias';

// O envio de uma ação em grupo que a fonte manda em fatias (#2894): o andamento
// enquanto roda, o resultado somado, o "tentar de novo" só com quem falta e a
// entrega ao fechar o diálogo.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const PESSOAS = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }];
const FALHA = new Error('Network Error');

const montar = () => {
  const aoConcluir = vi.fn();
  let envio;
  effectScope().run(() => {
    envio = useEnvioEmFatias({
      contagem: 'apagadas',
      mensagemDeErro: () => 'Não consegui apagar. Tente de novo.',
      aoConcluir,
    });
  });
  return { envio, aoConcluir };
};
const adiada = () => {
  let resolver;
  const promessa = new Promise(resolve => {
    resolver = resolve;
  });
  return { promessa, resolver };
};
const inteiro = (apagadas, deFora = []) => ({
  apagadas,
  deFora,
  faltam: [],
  erro: null,
});

afterEach(() => {
  vi.clearAllMocks();
});

describe('enviar', () => {
  it('entrega as pessoas à ação e guarda o resultado com a contagem em `feitas`', async () => {
    const { envio } = montar();
    const acao = vi.fn().mockResolvedValue(inteiro(4));
    const feito = await envio.enviarOQueFalta(PESSOAS, acao);
    expect(acao.mock.calls[0][0].pessoas).toEqual(PESSOAS);
    expect(feito).toEqual({ feitas: 4, deFora: [], faltam: [], erro: null });
    expect(envio.resultado.value).toEqual(feito);
    expect(envio.terminou.value).toBe(true);
  });

  it('mostra o andamento enquanto roda e apaga quando termina', async () => {
    const { envio } = montar();
    const espera = adiada();
    let andar;
    const acao = ({ aoAndar }) => {
      andar = aoAndar;
      return espera.promessa;
    };
    const pronto = envio.enviarOQueFalta(PESSOAS, acao);
    expect(envio.enviando.value).toBe(true);
    expect(envio.andamento.value).toEqual({ feitas: 0, total: 4 });
    andar({ feitas: 2, total: 4 });
    expect(envio.andamento.value).toEqual({ feitas: 2, total: 4 });
    espera.resolver(inteiro(4));
    await pronto;
    expect(envio.enviando.value).toBe(false);
    expect(envio.andamento.value).toBeNull();
  });

  it('se a ação estoura, avisa, não inventa resultado e devolve null', async () => {
    const { envio } = montar();
    const feito = await envio.enviarOQueFalta(
      PESSOAS,
      vi.fn().mockRejectedValue(FALHA)
    );
    expect(feito).toBeNull();
    expect(envio.resultado.value).toBeNull();
    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui apagar. Tente de novo.'
    );
  });
});

describe('resultado parcial', () => {
  const parcial = {
    apagadas: 2,
    deFora: [{ id: 1, nome: null, motivo: 'nao_existe_mais' }],
    faltam: PESSOAS.slice(2),
    erro: FALHA,
  };

  it('guarda o que foi feito, quem falta e o erro; não terminou', async () => {
    const { envio } = montar();
    await envio.enviarOQueFalta(PESSOAS, vi.fn().mockResolvedValue(parcial));
    expect(envio.resultado.value).toEqual({
      feitas: 2,
      deFora: parcial.deFora,
      faltam: PESSOAS.slice(2),
      erro: FALHA,
    });
    expect(envio.terminou.value).toBe(false);
  });

  it('tentar de novo manda só quem falta e soma ao que já estava feito', async () => {
    const { envio } = montar();
    const acao = vi
      .fn()
      .mockResolvedValueOnce(parcial)
      .mockResolvedValueOnce(
        inteiro(1, [{ id: 4, nome: 'Dani', motivo: 'nao_apagada' }])
      );
    await envio.enviarOQueFalta(PESSOAS, acao);
    await envio.enviarOQueFalta(PESSOAS, acao);
    expect(acao.mock.calls[1][0].pessoas).toEqual(PESSOAS.slice(2));
    expect(envio.resultado.value).toEqual({
      feitas: 3,
      deFora: [
        { id: 1, nome: null, motivo: 'nao_existe_mais' },
        { id: 4, nome: 'Dani', motivo: 'nao_apagada' },
      ],
      faltam: [],
      erro: null,
    });
    expect(envio.terminou.value).toBe(true);
  });
});

describe('fechar', () => {
  it('sem nada feito não conclui', () => {
    const { envio, aoConcluir } = montar();
    envio.fechar();
    expect(aoConcluir).not.toHaveBeenCalled();
  });

  it('com resultado conclui uma vez só, com quem falta, e recomeça do zero', async () => {
    const { envio, aoConcluir } = montar();
    await envio.enviarOQueFalta(
      PESSOAS,
      vi.fn().mockResolvedValue({
        apagadas: 2,
        deFora: [],
        faltam: PESSOAS.slice(2),
        erro: FALHA,
      })
    );
    envio.fechar();
    envio.fechar();
    expect(aoConcluir).toHaveBeenCalledTimes(1);
    expect(aoConcluir).toHaveBeenCalledWith(PESSOAS.slice(2));
    expect(envio.resultado.value).toBeNull();
  });

  it('no meio do trabalho pede para parar e conclui quando a fatia em voo volta', async () => {
    const { envio, aoConcluir } = montar();
    const espera = adiada();
    let parar;
    const acao = ({ deveParar }) => {
      parar = deveParar;
      return espera.promessa;
    };
    const pronto = envio.enviarOQueFalta(PESSOAS, acao);
    expect(parar()).toBe(false);
    envio.fechar();
    expect(parar()).toBe(true);
    expect(aoConcluir).not.toHaveBeenCalled();
    espera.resolver({
      apagadas: 2,
      deFora: [],
      faltam: PESSOAS.slice(2),
      erro: null,
    });
    await pronto;
    expect(aoConcluir).toHaveBeenCalledWith(PESSOAS.slice(2));
    expect(envio.resultado.value).toBeNull();
  });
});
