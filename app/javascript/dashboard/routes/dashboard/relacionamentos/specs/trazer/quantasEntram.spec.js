import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import { resumoDaTela } from '../../trazer/contagem';
import {
  REPETIDA,
  RESUMO,
  erroHttp,
  fonteComLeitura,
  problema,
  pronta,
  responder,
  semRede,
} from './apoioDoServidor';

// #2896, Fatia 2 — quantas pessoas entram quem diz é o servidor: `resumo.entram`
// na leitura e `entram` na resposta de cada escrita numa linha. A tela não
// refaz a conta, e a linha consertada não vira "nova". Na linha repetida,
// "ficar com esta" mexe em outras linhas no servidor: a fonte lê a leitura de
// novo em vez de confiar no que tinha.
vi.mock('dashboard/api/relacionamentosTrazer', async () => ({
  default: (await import('./apiDeMentira')).apiDeMentira(),
}));

const responde = responder(TrazerAPI);
const GUARDADA = problema(14, {
  estado: 'guardado',
  corrigido: '+55 11 97380-0014',
});

afterEach(() => {
  vi.resetAllMocks();
});

describe('fonte real: o `entram` do servidor', () => {
  it('a leitura traz `resumo.entram` como o servidor mandou', async () => {
    const { leitura } = await fonteComLeitura(TrazerAPI);
    expect(leitura.resumo.entram).toBe(195);
  });

  it('consertar usa o `entram` da resposta, sem ler a planilha de novo', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    responde('consertar', { problema: GUARDADA, entram: 196 });
    const nova = await fonte.consertar(812, 14, '11973800014');
    expect(nova.resumo).toEqual({ ...RESUMO, entram: 196 });
    expect(nova.problemas).toEqual([GUARDADA]);
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
  });

  it('deixar de fora e voltar atrás também usam o `entram` da resposta', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    responde('consertar', { problema: GUARDADA, entram: 196 });
    await fonte.consertar(812, 14, '11973800014');
    responde('deixarDeFora', {
      problema: problema(14, { estado: 'deixado' }),
      entram: 195,
    });
    expect((await fonte.deixarDeFora(812, 14)).resumo.entram).toBe(195);
    responde('reabrir', { problema: problema(14), entram: 195 });
    const reaberta = await fonte.reabrir(812, 14);
    expect(reaberta.resumo.entram).toBe(195);
    expect(reaberta.problemas).toEqual([problema(14)]);
  });
});

describe('fonte real: "ficar com esta" lê a leitura de novo', () => {
  const OUTRA_DO_GRUPO = { ...REPETIDA, linha: 190 };
  const comGrupo = () =>
    fonteComLeitura(
      TrazerAPI,
      pronta({ problemas: [REPETIDA, OUTRA_DO_GRUPO], problemas_total: 2 })
    );
  const FICOU = { ...REPETIDA, estado: 'guardado', ficar_com: 143 };

  it('depois do conserto que dá certo, pede a primeira página e devolve o que voltou', async () => {
    const { fonte } = await comGrupo();
    responde('consertar', { problema: FICOU, entram: 195 });
    // O servidor deixou de fora a outra linha do grupo: só o GET mostra isso.
    const relida = pronta({
      problemas: [FICOU, { ...OUTRA_DO_GRUPO, estado: 'deixado' }],
      problemas_total: 2,
      resumo: { ...RESUMO, entram: 194 },
    });
    responde('leitura', relida);
    const nova = await fonte.consertar(812, 143, 143);
    expect(TrazerAPI.consertar).toHaveBeenCalledWith(812, 143, {
      ficar_com: 143,
    });
    expect(TrazerAPI.leitura.mock.calls).toEqual([[812, 1]]);
    expect(nova.problemas.map(p => [p.linha, p.estado])).toEqual([
      [143, 'guardado'],
      [190, 'deixado'],
    ]);
    expect(nova.resumo.entram).toBe(194);
  });

  it('a escrita seguinte parte da leitura que voltou', async () => {
    const { fonte } = await comGrupo();
    responde('consertar', { problema: FICOU, entram: 195 });
    responde(
      'leitura',
      pronta({
        problemas: [FICOU, { ...OUTRA_DO_GRUPO, estado: 'deixado' }],
        problemas_total: 2,
      })
    );
    await fonte.consertar(812, 143, 143);
    responde('reabrir', { problema: REPETIDA, entram: 195 });
    const reaberta = await fonte.reabrir(812, 143);
    expect(reaberta.problemas[1].estado).toBe('deixado');
  });

  // O conserto está salvo, mas a outra linha do grupo ainda aparece aberta na
  // leitura que a fonte tem: ela não a devolve como se estivesse em dia.
  it.each([
    ['a rede cai', () => TrazerAPI.leitura.mockRejectedValueOnce(semRede())],
    [
      'o servidor falha',
      () => TrazerAPI.leitura.mockRejectedValueOnce(erroHttp(500)),
    ],
    [
      'a leitura não volta pronta',
      () => responde('leitura', { id: 812, situacao: 'lendo' }),
    ],
  ])(
    'se a leitura de novo não vem (%s), devolve o marcador `lendo`: a tela pergunta de novo',
    async (_caso, semALeitura) => {
      const { fonte } = await comGrupo();
      responde('consertar', { problema: FICOU, entram: 195 });
      semALeitura();
      expect(await fonte.consertar(812, 143, 143)).toEqual({
        situacao: 'lendo',
        id: 812,
      });
      expect(TrazerAPI.consertar).toHaveBeenCalledTimes(1);
    }
  );

  it('o conserto que o servidor recusa não lê nada de novo', async () => {
    const { fonte } = await comGrupo();
    TrazerAPI.consertar.mockRejectedValueOnce(
      erroHttp(422, 'planilha_apagada')
    );
    await expect(fonte.consertar(812, 143, 143)).rejects.toMatchObject({
      name: 'PLANILHA_APAGADA',
    });
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
  });

  it('o conserto de outro tipo de linha não lê de novo', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    responde('consertar', { problema: GUARDADA, entram: 196 });
    await fonte.consertar(812, 14, '11973800014');
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
  });
});

describe('os contadores do topo não refazem a conta do servidor', () => {
  const leitura = (problemas, extra = {}) => ({
    resumo: { ...RESUMO, juntadas: 3 },
    problemas,
    problemasTotal: problemas.length,
    ...extra,
  });

  it('a linha consertada não vira "nova": novas e completadas são as do servidor', () => {
    const resumo = resumoDaTela(
      leitura([GUARDADA, problema(37)], {
        resumo: { ...RESUMO, entram: 196 },
      })
    );
    expect(resumo.novas).toBe(180);
    expect(resumo.completadas).toBe(15);
    expect(resumo.entram).toBe(196);
    expect(resumo.precisamDeVoce).toBe(1);
  });

  it('as linhas deixadas de fora são as que a tela tem', () => {
    const resumo = resumoDaTela(
      leitura([problema(14, { estado: 'deixado' }), problema(37)])
    );
    expect(resumo.deixadas).toBe(1);
    expect(resumo.precisamDeVoce).toBe(1);
  });

  it('as linhas que ainda não vieram contam como abertas', () => {
    const resumo = resumoDaTela(
      leitura([GUARDADA, problema(37)], { problemasTotal: 450 })
    );
    expect(resumo.precisamDeVoce).toBe(449);
  });

  it('sem leitura, tudo é zero', () => {
    expect(resumoDaTela(null)).toEqual({
      total: 0,
      novas: 0,
      completadas: 0,
      precisamDeVoce: 0,
      deixadas: 0,
      juntadas: 0,
      entram: 0,
      clientes: 0,
    });
  });
});

describe('a demonstração faz o papel do servidor na conta', () => {
  const montar = () =>
    trazerFonte({
      demo: 'cheio',
      carregarDemo: () => import('../../demo/trazer.js'),
      atraso: 0,
      atrasoDaLeitura: 0,
    });

  beforeEach(() => esquecerMemoriaDaDemo());

  it('a leitura de exemplo já diz quantas entram: as aprovadas', async () => {
    const leitura = await montar().ler({ name: 'Clientes 2025.xlsx' });
    expect(leitura.resumo.entram).toBe(195);
  });

  it('consertar soma uma, deixar de fora não soma e voltar atrás desfaz', async () => {
    const fonte = montar();
    const { id } = await fonte.ler({ name: 'Clientes 2025.xlsx' });
    expect((await fonte.consertar(id, 14, '11973800014')).resumo.entram).toBe(
      196
    );
    expect((await fonte.deixarDeFora(id, 37)).resumo.entram).toBe(196);
    expect((await fonte.reabrir(id, 14)).resumo.entram).toBe(195);
  });

  it('ficar com a linha repetida é uma troca: não soma ninguém', async () => {
    const fonte = montar();
    const { id } = await fonte.ler({ name: 'Clientes 2025.xlsx' });
    expect((await fonte.consertar(id, 143, 143)).resumo.entram).toBe(195);
  });
});
