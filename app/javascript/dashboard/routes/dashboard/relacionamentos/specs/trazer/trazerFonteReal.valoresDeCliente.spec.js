import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { corpoDasRespostas, erroDaEscrita } from '../../fonte/trazerTraducao';
import { resumoDaTela } from '../../trazer/contagem';
import {
  erroHttp,
  fonteComLeitura,
  problema,
  pronta,
  responder,
} from './apoioDoServidor';

// #2896, E3 — a fonte real (fonte/trazerFonte.js) e a pergunta "Quais destes
// querem dizer cliente?", com o cliente de API simulado e os corpos do
// contrato: a pergunta vem na leitura com as contagens, a resposta vai e volta
// como `valores_cliente` (só `modo` e `chaves`, nunca o texto da célula), e as
// duas recusas novas ganham nome.
vi.mock('dashboard/api/relacionamentosTrazer', async () => ({
  default: (await import('./apiDeMentira')).apiDeMentira(),
}));

const responde = responder(TrazerAPI);

const DOS_VALORES = {
  id: 'valores_cliente',
  coluna: 'Já é cliente?',
  indice: 4,
  preenchidas: 35,
  valores: [
    { chave: '9f2c', valor: 'Sim', linhas: 12 },
    { chave: 'a01b', valor: 'Não', linhas: 20 },
  ],
  outros: { valores: 7, linhas: 9 },
};
const PERGUNTAS = [{ id: 'clientes' }, DOS_VALORES];
const MARCADAS = { modo: 'valores', chaves: ['9f2c'] };

afterEach(() => {
  vi.resetAllMocks();
});

describe('fonte real: a pergunta dos valores na leitura', () => {
  it('chega como o servidor manda, com as contagens e o `outros`', async () => {
    const { leitura } = await fonteComLeitura(
      TrazerAPI,
      pronta({
        perguntas: PERGUNTAS,
        respostas: { clientes: 'algumas', coluna_cliente: 4 },
      })
    );
    expect(leitura.perguntas).toEqual(PERGUNTAS);
    expect(leitura.respostas).toEqual({
      clientes: 'algumas',
      colunaCliente: 4,
    });
  });

  it('a resposta que já vale vem em `valores_cliente`, nas duas formas', async () => {
    const comValores = await fonteComLeitura(
      TrazerAPI,
      pronta({
        perguntas: PERGUNTAS,
        respostas: {
          clientes: 'algumas',
          coluna_cliente: 4,
          valores_cliente: MARCADAS,
        },
      })
    );
    expect(comValores.leitura.respostas.valores_cliente).toEqual(MARCADAS);

    const comPreenchidas = await fonteComLeitura(
      TrazerAPI,
      pronta({
        perguntas: PERGUNTAS,
        respostas: {
          clientes: 'algumas',
          coluna_cliente: 4,
          valores_cliente: { modo: 'preenchidas' },
        },
      })
    );
    expect(comPreenchidas.leitura.respostas.valores_cliente).toEqual({
      modo: 'preenchidas',
    });
  });

  it('quantas entram como cliente vem no resumo, e a tela não refaz a conta', async () => {
    const { leitura } = await fonteComLeitura(
      TrazerAPI,
      pronta({ resumo: { ...pronta().resumo, clientes: 12 } })
    );
    expect(resumoDaTela(leitura).clientes).toBe(12);
    expect(resumoDaTela(pronta()).clientes).toBe(0);
  });

  it('a escrita numa linha que devolve `clientes` atualiza o resumo; a que não devolve mantém', async () => {
    const { fonte } = await fonteComLeitura(
      TrazerAPI,
      pronta({ resumo: { ...pronta().resumo, clientes: 12 } })
    );
    responde('deixarDeFora', {
      problema: problema(14, { estado: 'deixado' }),
      entram: 194,
    });
    expect((await fonte.deixarDeFora(812, 14)).resumo.clientes).toBe(12);
    responde('reabrir', { problema: problema(14), entram: 195, clientes: 13 });
    expect((await fonte.reabrir(812, 14)).resumo.clientes).toBe(13);
    responde('consertar', {
      problema: problema(14, { estado: 'guardado' }),
      entram: 196,
      clientes: 14,
    });
    const consertada = await fonte.consertar(812, 14, '(11) 97380-0014');
    expect(consertada.resumo).toMatchObject({ entram: 196, clientes: 14 });
  });
});

describe('fonte real: responder com os valores', () => {
  it('manda `valores_cliente` com as chaves, junto das outras respostas', async () => {
    const { fonte } = await fonteComLeitura(
      TrazerAPI,
      pronta({ perguntas: PERGUNTAS })
    );
    responde('responder', pronta({ perguntas: PERGUNTAS }));
    await fonte.responder(812, {
      clientes: 'algumas',
      colunaCliente: 4,
      valores_cliente: MARCADAS,
      telefone: 'da_pessoa',
    });
    expect(TrazerAPI.responder).toHaveBeenCalledWith(812, {
      clientes: 'algumas',
      coluna_cliente: 4,
      valores_cliente: { modo: 'valores', chaves: ['9f2c'] },
      telefone: 'da_pessoa',
    });
  });

  it('"toda linha com algo escrito" vai só com o modo', () => {
    expect(
      corpoDasRespostas({
        clientes: 'algumas',
        colunaCliente: 4,
        valores_cliente: { modo: 'preenchidas', chaves: ['9f2c'] },
      })
    ).toEqual({
      clientes: 'algumas',
      coluna_cliente: 4,
      valores_cliente: { modo: 'preenchidas' },
    });
  });

  it('sem nada marcado, `valores_cliente` não vai', () => {
    expect(
      corpoDasRespostas({ clientes: 'algumas', colunaCliente: 4 })
    ).toEqual({ clientes: 'algumas', coluna_cliente: 4 });
  });

  it('os valores só vão com a resposta "algumas"', () => {
    expect(
      corpoDasRespostas({ clientes: 'sim_todas', valores_cliente: MARCADAS })
    ).toEqual({ clientes: 'sim_todas' });
  });

  it.each(['resposta_desconhecida', 'pergunta_desconhecida'])(
    'a recusa `%s` é tela desatualizada: a tela lê a leitura de novo',
    async codigo => {
      const { fonte } = await fonteComLeitura(
        TrazerAPI,
        pronta({ perguntas: PERGUNTAS })
      );
      TrazerAPI.responder.mockRejectedValueOnce(erroHttp(422, codigo));
      await expect(
        fonte.responder(812, {
          clientes: 'algumas',
          colunaCliente: 4,
          valores_cliente: MARCADAS,
        })
      ).rejects.toMatchObject({ name: 'TELA_DESATUALIZADA' });
    }
  );
});

describe('fonte real: trazer sem ter dito quem é cliente', () => {
  it('a recusa `falta_valores_cliente` ganha nome', async () => {
    const { fonte } = await fonteComLeitura(
      TrazerAPI,
      pronta({ perguntas: PERGUNTAS })
    );
    TrazerAPI.trazer.mockRejectedValueOnce(
      erroHttp(422, 'falta_valores_cliente')
    );
    await expect(fonte.trazer(812)).rejects.toMatchObject({
      name: 'FALTA_VALORES_CLIENTE',
    });
  });

  // O contrato escreve esta recusa com a chave `erro`; as outras recusas do
  // servidor vêm em `error`. A tradução entende as duas.
  it('o código da recusa vale em `error` e em `erro`', () => {
    const comErro = Object.assign(new Error('422'), {
      response: { status: 422, data: { erro: 'falta_valores_cliente' } },
    });
    expect(erroDaEscrita(comErro).name).toBe('FALTA_VALORES_CLIENTE');
  });
});
