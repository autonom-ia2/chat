import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { ETAPAS } from '../../trazer/etapas';
import { ERROS } from '../../trazer/useTrazerLista';
import {
  MARCADOR,
  PERGUNTAS,
  erroDeNome,
  fonteDeMentira,
  lida,
  montarTela,
  noConferir,
} from './apoioDaTela';
import {
  LENDO,
  PLANILHA,
  erroHttp,
  fonteComLeitura,
  montarFonteReal,
  pronta,
  responder,
} from './apoioDoServidor';

// #2896, Fatia 2 — a conferência vencida: a planilha enviada há mais de 7 dias
// e ainda não trazida já foi apagada do servidor. Quem pergunta pela leitura
// recebe `200 { id, situacao: 'vencida' }`; toda escrita nela, e o trazer,
// `422 { error: 'conferencia_vencida' }`. A fonte dá o mesmo nome aos dois
// casos (`CONFERENCIA_VENCIDA`) e a tela volta ao Enviar com a frase fixa
// (a frase na tela está em paginaDaLeitura.spec.js).
vi.mock('dashboard/api/relacionamentosTrazer', async () => ({
  default: (await import('./apiDeMentira')).apiDeMentira(),
}));

const responde = responder(TrazerAPI);
const VENCIDA = { id: 812, situacao: 'vencida' };
const RECUSA = () => erroHttp(422, 'conferencia_vencida');
const NOME = 'CONFERENCIA_VENCIDA';

afterEach(() => {
  vi.resetAllMocks();
});

describe('fonte real: quem pergunta pela leitura vencida', () => {
  it('retomar: o erro tem o nome da conferência vencida, sem perguntar de novo', async () => {
    const { fonte, espera } = montarFonteReal();
    responde('leitura', VENCIDA);
    const falha = await fonte.retomar('812').catch(erro => erro);
    expect(falha.name).toBe(NOME);
    // Não é "ainda não terminou": a tela não guarda o id para tentar de novo.
    expect(falha.leituraId).toBeUndefined();
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(1);
    expect(espera).not.toHaveBeenCalled();
  });

  it('retomar: vencida depois de "lendo" também', async () => {
    const { fonte } = montarFonteReal();
    responde('leitura', LENDO, VENCIDA);
    await expect(fonte.retomar(812)).rejects.toMatchObject({ name: NOME });
  });

  it('ler: o mesmo nome', async () => {
    const { fonte } = montarFonteReal();
    responde('enviar', LENDO);
    responde('leitura', VENCIDA);
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({ name: NOME });
  });

  it('a página seguinte dos problemas: o mesmo nome, não "tela desatualizada"', async () => {
    const { fonte } = await fonteComLeitura(
      TrazerAPI,
      pronta({ problemas_total: 3 })
    );
    responde('leitura', VENCIDA);
    await expect(fonte.maisProblemas(812)).rejects.toMatchObject({
      name: NOME,
    });
  });
});

describe('fonte real: a escrita na leitura vencida', () => {
  it.each([
    ['responder', 'responder', fonte => fonte.responder(812, {})],
    [
      'consertar',
      'consertar',
      fonte => fonte.consertar(812, 14, '11987650014'),
    ],
    ['deixar de fora', 'deixarDeFora', fonte => fonte.deixarDeFora(812, 14)],
    ['voltar atrás', 'reabrir', fonte => fonte.reabrir(812, 14)],
    [
      'trocar a coluna',
      'trocarColuna',
      fonte => fonte.trocarDestino(812, 6, 'nao_guardar'),
    ],
    ['trazer', 'trazer', fonte => fonte.trazer(812)],
  ])(
    '%s: 422 conferencia_vencida ganha o nome',
    async (_, pedido, escrever) => {
      const { fonte } = await fonteComLeitura(TrazerAPI);
      TrazerAPI[pedido].mockRejectedValueOnce(RECUSA());
      const falha = await escrever(fonte).catch(erro => erro);
      expect(falha.name).toBe(NOME);
      expect(falha.cause.response.status).toBe(422);
    }
  );
});

describe('a tela: a leitura vencida volta ao Enviar', () => {
  const vencida = () => vi.fn().mockRejectedValue(erroDeNome(NOME));
  const noEnviarComAFrase = ({ tela, avisar }) => {
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.erro.value).toBe(ERROS.VENCIDA);
    expect(tela.leitura.value).toBeNull();
    // Não há o que tentar de novo, nem leitura para guardar na rota.
    expect(tela.leituraEmAberto.value).toBeNull();
    expect(tela.ocupado.value).toBe(false);
    expect(tela.lendo.value).toBe(false);
    expect(tela.relendo.value).toBe(false);
    // A frase fixa já diz tudo: sem aviso solto.
    expect(avisar).not.toHaveBeenCalled();
  };

  it('ao retomar a leitura que a rota guardava', async () => {
    const montada = montarTela(fonteDeMentira({ retomar: vencida() }));
    await montada.tela.retomar('812');
    noEnviarComAFrase(montada);
    // "Tentar de novo" não pergunta por ela outra vez.
    await montada.tela.tentarDeNovo();
    expect(montada.fonte.retomar).toHaveBeenCalledTimes(1);
    montada.parar();
  });

  it('ao enviar a planilha', async () => {
    const montada = montarTela(fonteDeMentira({ ler: vencida() }));
    await montada.tela.escolherArquivo({ name: 'a.csv' });
    noEnviarComAFrase(montada);
    montada.parar();
  });

  it.each([
    ['consertar', 'consertar', tela => tela.guardar(14, '11987650014')],
    ['deixar de fora', 'deixarDeFora', tela => tela.deixarDeFora(14)],
    ['voltar atrás', 'reabrir', tela => tela.reabrir(14)],
    [
      'trocar a coluna',
      'trocarDestino',
      tela => tela.trocarDestino(6, 'nao_guardar'),
    ],
    ['mostrar mais', 'maisProblemas', tela => tela.mostrarMais()],
    ['trazer', 'trazer', tela => tela.trazer()],
  ])('ao %s no Conferir', async (_, metodo, agir) => {
    const montada = await noConferir(lida({ problemasTotal: 3 }), {
      [metodo]: vencida(),
    });
    expect(montada.tela.etapa.value).toBe(ETAPAS.CONFERIR);
    await agir(montada.tela);
    expect(montada.fonte[metodo]).toHaveBeenCalledTimes(1);
    noEnviarComAFrase(montada);
    // A recusa não fica presa em lugar nenhum da tela que saiu.
    expect(montada.tela.recusaDoConserto.value).toBeNull();
    expect(montada.tela.recusaDaColuna.value).toBeNull();
    expect(montada.tela.erroDoMais.value).toBe(false);
    montada.parar();
  });

  it('ao responder a última pergunta', async () => {
    const montada = await noConferir(lida({ perguntas: PERGUNTAS }), {
      responder: vencida(),
    });
    const { tela } = montada;
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    tela.responder('clientes', 'sim_todas');
    await tela.continuar();
    tela.responder('telefone', 'da_pessoa');
    await tela.continuar();
    expect(montada.fonte.responder).toHaveBeenCalledTimes(1);
    noEnviarComAFrase(montada);
    expect(tela.recusaDaPergunta.value).toBeNull();
    montada.parar();
  });

  it('ao ler a planilha de novo depois de uma mudança', async () => {
    const montada = await noConferir(lida(), {
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR),
      retomar: vencida(),
    });
    await montada.tela.trocarDestino(1, 'nao_guardar');
    noEnviarComAFrase(montada);
    expect(montada.tela.releituraParada.value).toBe(false);
    montada.parar();
  });

  it('ao ler de novo a lista que mudou por fora', async () => {
    const montada = await noConferir(lida(), {
      deixarDeFora: vi.fn().mockRejectedValue(erroDeNome('TELA_DESATUALIZADA')),
      retomar: vencida(),
    });
    await montada.tela.deixarDeFora(14);
    noEnviarComAFrase(montada);
    expect(montada.tela.mudou.value).toBe(false);
    montada.parar();
  });
});
