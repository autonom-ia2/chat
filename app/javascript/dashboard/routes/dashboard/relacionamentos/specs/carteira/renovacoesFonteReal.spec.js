import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { FUNIL_PAROU } from '../../carteira/funilDasRenovacoes';
import { RECUSADO } from '../../carteira/recusas';
import { NAO_ACHEI, SEM_ACESSO } from '../../ficha/falhas';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { renovacoesFonte } from '../../fonte/renovacoesFonte';
import { aoMeioDia, erroHttp } from './apoio';

// A renovação no servidor (#2898): os ajustes, os resultados e como a
// renovação de um seguro termina. O cliente de API é de mentira: o que importa
// aqui é o que a fonte pede e o que ela devolve às telas. Tudo inventado.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: {
    renovacoes: vi.fn(),
    salvarRenovacoes: vi.fn(),
    resultados: vi.fn(),
    renovou: vi.fn(),
    naoRenovou: vi.fn(),
    desfazerDesfecho: vi.fn(),
    criar: vi.fn(),
  },
}));

const dasRenovacoes = () => renovacoesFonte({ demo: null });
const daCarteira = () => carteiraFonte({ demo: null });
const responde = (metodo, data) =>
  SegurosAPI[metodo].mockResolvedValue({ data });

const ESCOLHAS = { funilId: 3, etapaId: 31, dias: 45, mensagens: 'nao_mandar' };
const FUNIS = [
  { id: 3, nome: 'Renovação', etapas: [{ id: 31, nome: 'A vencer' }] },
];
// O que o servidor manda em `GET seguros/renovacoes`.
const DO_SERVIDOR = {
  ajustes: ESCOLHAS,
  escolha: 'feita',
  funis: FUNIS,
  vencimentos: [3, 20, 61],
  semPermissao: false,
  exemplo: null,
  aggerLigado: false,
  cotaSozinha: false,
  cotaSemConversa: false,
  agente: null,
};
// Um seguro como o servidor manda: datas sem hora, selo e dias prontos.
const SEGURO = {
  id: 7,
  pessoaId: 23,
  tipo: 'auto',
  seguradora: 'Seguradora Atlântica',
  numero: 'AT-000451',
  comeca: '2025-11-29',
  termina: '2026-11-29',
  selo: 'renovado',
  dias: 17,
  canceladoEm: null,
  renovadoEm: 1790000000,
  renovacao: {
    cardId: 88,
    funil: 'Renovação',
    etapa: 'A vencer',
    desfecho: 'renovou',
    cuida: 'Bruna Teixeirão',
  },
};
const NA_TELA = {
  ...SEGURO,
  comeca: aoMeioDia(2025, 11, 29),
  termina: aoMeioDia(2026, 11, 29),
};

describe('ajustar renovações', () => {
  it('fora da demonstração é a fonte real', () => {
    expect(dasRenovacoes().usaDemo).toBe(false);
    expect(renovacoesFonte({ demo: 'cheio', carregarDemo: null }).usaDemo).toBe(
      false
    );
  });

  it('lê as escolhas, os funis e os vencimentos como o servidor manda', async () => {
    responde('renovacoes', DO_SERVIDOR);

    const lido = await dasRenovacoes().ajustes();

    expect(SegurosAPI.renovacoes).toHaveBeenCalledWith();
    // `funilParou` é da fonte: com a escolha feita, o funil serve.
    expect(lido).toEqual({ ...DO_SERVIDOR, funilParou: '' });
  });

  // O funil que parou de servir não vem em `ajustes`: quem diz por que é
  // `escolha` (Carteira::RenovacaoConfig#escolha).
  it.each([
    ['funil_arquivado', FUNIL_PAROU.ARQUIVADO],
    ['sumiu', FUNIL_PAROU.APAGADO],
  ])(
    'a escolha %s do servidor chega à tela como funil parado',
    async (escolha, estado) => {
      responde('renovacoes', {
        ...DO_SERVIDOR,
        escolha,
        ajustes: { funilId: null, etapaId: null, dias: 45 },
      });

      const lido = await dasRenovacoes().ajustes();

      expect(lido.funilParou).toBe(estado);
      expect(lido.ajustes).toEqual({ funilId: null, etapaId: null, dias: 45 });
    }
  );

  it('a conta que nunca escolheu não é funil parado', async () => {
    responde('renovacoes', {
      ...DO_SERVIDOR,
      escolha: 'nunca_feita',
      ajustes: { funilId: null, etapaId: null, dias: 60 },
    });

    expect((await dasRenovacoes().ajustes()).funilParou).toBe('');
  });

  it('das escolhas, a tela fica só com as quatro que ela mostra', async () => {
    responde('renovacoes', {
      ...DO_SERVIDOR,
      ajustes: { ...ESCOLHAS, guardadoPor: 9 },
    });

    expect((await dasRenovacoes().ajustes()).ajustes).toEqual(ESCOLHAS);
  });

  it('a conta que ainda não escolheu vem sem funil e sem etapa', async () => {
    responde('renovacoes', {
      ...DO_SERVIDOR,
      ajustes: { dias: 60, mensagens: 'mandar' },
    });

    expect((await dasRenovacoes().ajustes()).ajustes).toEqual({
      funilId: null,
      etapaId: null,
      dias: 60,
      mensagens: 'mandar',
    });
  });

  it('sem a escolha das mensagens na resposta, a tela fica sem ela', async () => {
    responde('renovacoes', {
      ...DO_SERVIDOR,
      ajustes: { funilId: 3, etapaId: 31, dias: 45 },
    });

    expect((await dasRenovacoes().ajustes()).ajustes).toEqual({
      funilId: 3,
      etapaId: 31,
      dias: 45,
    });
  });

  it('quem não tem a escolha das mensagens não a manda nem a recebe de volta', async () => {
    responde('salvarRenovacoes', { ...ESCOLHAS, dias: 30 });

    const guardados = await dasRenovacoes().salvar({
      funilId: 3,
      etapaId: 31,
      dias: 30,
    });

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      funilId: 3,
      etapaId: 31,
      dias: 30,
    });
    expect(guardados).toEqual({ funilId: 3, etapaId: 31, dias: 30 });
  });

  it('salvar manda só as quatro escolhas e devolve o que ficou guardado', async () => {
    responde('salvarRenovacoes', { ...ESCOLHAS, dias: 30 });

    const guardados = await dasRenovacoes().salvar({
      ...ESCOLHAS,
      dias: 30,
      rascunho: true,
    });

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      ...ESCOLHAS,
      dias: 30,
    });
    expect(guardados).toEqual({ ...ESCOLHAS, dias: 30 });
  });

  it.each(['funil_desconhecido', 'etapa_de_outro_funil', 'dias_invalidos'])(
    'a recusa %s chega com o código, sem repetir o que foi mandado',
    async codigo => {
      SegurosAPI.salvarRenovacoes.mockRejectedValue(
        erroHttp(422, { error: codigo })
      );

      await expect(dasRenovacoes().salvar(ESCOLHAS)).rejects.toMatchObject({
        name: RECUSADO,
        codigo,
      });
    }
  );

  it('quem não pode mudar recebe o nome de sem acesso', async () => {
    SegurosAPI.salvarRenovacoes.mockRejectedValue(erroHttp(403));

    await expect(dasRenovacoes().salvar(ESCOLHAS)).rejects.toMatchObject({
      name: SEM_ACESSO,
    });
  });

  it('conta sem a carteira (404) ganha o nome de não achei', async () => {
    SegurosAPI.renovacoes.mockRejectedValue(erroHttp(404));

    await expect(dasRenovacoes().ajustes()).rejects.toMatchObject({
      name: NAO_ACHEI,
    });
  });
});

describe('resultados das renovações', () => {
  it('entrega os números como o servidor manda', async () => {
    const numeros = {
      periodos: [
        {
          dias: 30,
          venceram: 9,
          renovou: 7,
          naoRenovou: 2,
          motivos: [{ motivo: 'achou_caro', quantos: 2 }],
          recortes: { tipo: [], seguradora: [], cuida: [] },
        },
      ],
      vencem30: 4,
    };
    responde('resultados', numeros);

    expect(await dasRenovacoes().resultados()).toEqual(numeros);
    expect(SegurosAPI.resultados).toHaveBeenCalledWith();
  });

  it('falha de rede sobe como veio', async () => {
    const falha = new Error('Network Error');
    SegurosAPI.resultados.mockRejectedValue(falha);

    await expect(dasRenovacoes().resultados()).rejects.toBe(falha);
  });
});

describe('como a renovação de um seguro termina', () => {
  it('"Renovou" pede pelo id e devolve o seguro da tela', async () => {
    responde('renovou', SEGURO);

    expect(await daCarteira().renovou(7)).toEqual(NA_TELA);
    expect(SegurosAPI.renovou).toHaveBeenCalledWith(7);
  });

  it('"Não renovou" leva o motivo de um toque', async () => {
    responde('naoRenovou', SEGURO);

    await daCarteira().naoRenovou(7, { motivo: 'achou_caro' });

    expect(SegurosAPI.naoRenovou).toHaveBeenCalledWith(7, {
      motivo: 'achou_caro',
    });
  });

  it('"Outro motivo" leva o que a pessoa escreveu', async () => {
    responde('naoRenovou', SEGURO);

    const seguro = await daCarteira().naoRenovou(7, {
      motivo: 'outro',
      texto: 'Mudou de país',
    });

    expect(SegurosAPI.naoRenovou).toHaveBeenCalledWith(7, {
      motivo: 'outro',
      texto: 'Mudou de país',
    });
    expect(seguro).toEqual(NA_TELA);
  });

  it('desfazer pede pelo id e devolve o seguro da tela', async () => {
    responde('desfazerDesfecho', SEGURO);

    expect(await daCarteira().desfazerDesfecho(7)).toEqual(NA_TELA);
    expect(SegurosAPI.desfazerDesfecho).toHaveBeenCalledWith(7);
  });

  it('a apólice nova diz de qual seguro ela vem e manda as datas sem hora', async () => {
    const nova = { ...SEGURO, id: 8, numero: 'AT-000987', renovacao: null };
    responde('criar', {
      ...nova,
      comeca: '2026-11-29',
      termina: '2027-11-29',
    });

    const guardada = await daCarteira().apoliceNova(7, {
      tipo: 'auto',
      seguradora: 'Seguradora Atlântica',
      numero: 'AT-000987',
      comeca: aoMeioDia(2026, 11, 29),
      termina: aoMeioDia(2027, 11, 29),
      bem: 'Carro hatch prata',
    });

    expect(SegurosAPI.criar).toHaveBeenCalledWith({
      anteriorId: 7,
      tipo: 'auto',
      seguradora: 'Seguradora Atlântica',
      numero: 'AT-000987',
      comeca: '2026-11-29',
      termina: '2027-11-29',
      bem: 'Carro hatch prata',
    });
    expect(guardada).toEqual({
      ...nova,
      comeca: aoMeioDia(2026, 11, 29),
      termina: aoMeioDia(2027, 11, 29),
    });
  });

  it('apólice nova repetida chega com o código da recusa', async () => {
    SegurosAPI.criar.mockRejectedValue(
      erroHttp(422, { error: 'apolice_repetida' })
    );

    await expect(
      daCarteira().apoliceNova(7, { numero: 'AT-000451' })
    ).rejects.toMatchObject({ name: RECUSADO, codigo: 'apolice_repetida' });
  });

  it.each(['renovou', 'naoRenovou', 'desfazerDesfecho'])(
    '%s também dá nome ao 403',
    async metodo => {
      SegurosAPI[metodo].mockRejectedValue(erroHttp(403));

      await expect(daCarteira()[metodo](7, {})).rejects.toMatchObject({
        name: SEM_ACESSO,
      });
    }
  );
});
