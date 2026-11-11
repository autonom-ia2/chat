import { carteiraFonte } from '../../fonte/carteiraFonte';
import { renovacoesFonte } from '../../fonte/renovacoesFonte';
import { AJUSTES_PADRAO, PALAVRAS } from '../../carteira/ajustesDaRenovacao';
import { periodoEscolhido } from '../../carteira/resultados';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { FUNIS_DA_DEMO, salvarAjustesNaDemo } from '../../demo/carteiraAjustes';
import { carregarDemonstracao } from './apoio';

// A fonte de "Ajustar renovações" e "Resultados" (#2897, telas 13 e 14) e o que
// os ajustes mudam na carteira fictícia.
vi.setConfig({ testTimeout: 30000 });

const fonte = (demo = 'cheio', opcoes = {}) =>
  renovacoesFonte({ demo, atraso: 0, ...opcoes });
const nome = erro => erro.name;
const APOLICE_NOVA = 109;

beforeAll(carregarDemonstracao, 60000);
afterEach(esquecerEscritasDaCarteira);

describe('os ajustes', () => {
  it('chegam respondidos com o padrão, com o que a tela precisa para mostrá-los', async () => {
    const dados = await fonte().ajustes();

    expect(dados.ajustes).toEqual(AJUSTES_PADRAO);
    expect(dados.funis).toEqual(FUNIS_DA_DEMO);
    expect(dados).toMatchObject({
      aggerLigado: true,
      cotaSozinha: true,
      agente: 'Lia',
      semPermissao: false,
    });
    expect(dados.exemplo).toMatchObject({ nome: 'Fábio', tipo: 'auto' });
    // Em quantos dias cada seguro termina: 22 entram com 60 dias; 17, com 30.
    const ate = dias => dados.vencimentos.filter(falta => falta <= dias).length;
    expect([ate(60), ate(30)]).toEqual([22, 17]);
  });

  it('conta sem Agger não cota sozinha; com a chave desligada também não', async () => {
    expect(await fonte('sem-seguros').ajustes()).toMatchObject({
      aggerLigado: false,
      cotaSozinha: false,
      vencimentos: [],
    });
    expect(
      await fonte('cheio', { cotacaoDesligada: true }).ajustes()
    ).toMatchObject({ aggerLigado: true, cotaSozinha: false });
    expect(
      (await fonte('cheio', { caso: 'sem_permissao_de_funil' }).ajustes())
        .semPermissao
    ).toBe(true);
    expect(
      (await fonte('cheio', { caso: 'cotacao_sem_agente' }).ajustes()).agente
    ).toBeNull();
  });

  it('salvar guarda o que mudou; `ajustes_nao_salvou` falha uma vez e depois passa', async () => {
    const f = fonte();
    expect(await f.salvar({ dias: 45 })).toEqual({
      ...AJUSTES_PADRAO,
      dias: 45,
    });
    expect((await f.ajustes()).ajustes.dias).toBe(45);

    const falha = fonte('cheio', { caso: 'ajustes_nao_salvou' });
    await expect(falha.salvar({ dias: 30 }).catch(nome)).resolves.toBe(
      'ERRO_DA_DEMO'
    );
    expect((await falha.salvar({ dias: 30 })).dias).toBe(30);
  });

  it('carregando nunca responde; erro falha; sem demonstração, a fonte real está pendente', async () => {
    const resposta = vi.fn();
    fonte('carregando').ajustes().then(resposta);
    fonte('cheio', { peca: 'carregando' }).resultados().then(resposta);
    await new Promise(resolve => {
      setTimeout(resolve, 20);
    });
    expect(resposta).not.toHaveBeenCalled();

    await expect(
      fonte('cheio', { peca: 'erro' }).ajustes().catch(nome)
    ).resolves.toBe('ERRO_DA_DEMO');
    const real = renovacoesFonte({ demo: null });
    expect(real.usaDemo).toBe(false);
    await expect(real.ajustes().catch(nome)).resolves.toBe(
      'FONTE_REAL_PENDENTE'
    );
    await expect(real.resultados().catch(nome)).resolves.toBe(
      'FONTE_REAL_PENDENTE'
    );
    await expect(real.salvar({}).catch(nome)).resolves.toBe(
      'FONTE_REAL_PENDENTE'
    );
  });
});

describe('os resultados', () => {
  it('por período: quantos venceram, quantos renovaram e por que os outros não', async () => {
    const { periodos, vencem30 } = await fonte().resultados();
    const resumo = dias => {
      const p = periodoEscolhido(periodos, dias);
      return [
        p.venceram,
        p.renovou,
        p.naoRenovou,
        p.motivos.map(m => m.quantos),
      ];
    };

    expect(resumo(30)).toEqual([19, 14, 5, [2, 1, 1, 1]]);
    expect(resumo(90)).toEqual([52, 41, 11, [5, 3, 1, 2]]);
    expect(resumo(365)).toEqual([190, 151, 39, [17, 10, 5, 7]]);
    expect(periodoEscolhido(periodos, 30).motivos.map(m => m.motivo)).toEqual([
      'achou_caro',
      'outra_corretora',
      'vendeu_o_bem',
      'nao_respondeu',
    ]);
    expect(vencem30).toBe(17);
  });

  it('quem não renovou na tela é quem a lista "Não renovaram" mostra', async () => {
    const { periodos } = await fonte().resultados();
    const carteira = carteiraFonte({
      demo: 'cheio',
      atraso: 0,
      temporario: 'nao_renovaram_30',
    });

    const contagens = await carteira.contagens({});
    const lista = await carteira.listarTodos({ grupo: 'nao_renovaram_30' });

    expect(contagens.nao_renovaram_30).toBe(
      periodoEscolhido(periodos, 30).naoRenovou
    );
    expect(lista.total).toBe(5);
    expect(lista.itens.every(seguro => Boolean(seguro.motivo))).toBe(true);
  });

  it('os recortes somam o total do período', async () => {
    const { periodos } = await fonte().resultados();
    const { recortes, venceram, renovou } = periodoEscolhido(periodos, 30);

    Object.values(recortes).forEach(linhas => {
      expect(linhas.reduce((soma, l) => soma + l.venceram, 0)).toBe(venceram);
      expect(linhas.reduce((soma, l) => soma + l.renovou, 0)).toBe(renovou);
    });
    expect(recortes.tipo[0]).toEqual({ tipo: 'auto', venceram: 9, renovou: 7 });
  });

  it('conta sem seguro: tudo zerado', async () => {
    const { periodos, vencem30 } = await fonte('sem-seguros').resultados();

    expect(periodos.map(p => p.venceram)).toEqual([0, 0, 0]);
    expect(vencem30).toBe(0);
  });
});

describe('seu seguro em palavras simples, conforme o ajuste', () => {
  const daCarteira = () => carteiraFonte({ demo: 'cheio', atraso: 0 });

  it('"eu confiro antes" (padrão): o texto espera; salvar e enviar ficam guardados', async () => {
    const carteira = daCarteira();
    expect((await carteira.seguro(APOLICE_NOVA)).palavras).toMatchObject({
      cobre: 'batida, roubo e furto, vidros e guincho',
      texto: '',
      enviadoEm: null,
      sozinho: false,
    });
    // Só a apólice nova tem o texto.
    expect((await carteira.seguro(1)).palavras).toBeUndefined();

    await carteira.salvarPalavras(APOLICE_NOVA, {
      texto: 'Oi! Está tudo certo.',
    });
    const enviado = await carteira.enviarPalavras(APOLICE_NOVA);

    expect(enviado.palavras.texto).toBe('Oi! Está tudo certo.');
    expect(enviado.palavras.enviadoEm).toBeGreaterThan(0);
    expect((await carteira.historia(APOLICE_NOVA))[0].tipo).toBe(
      'palavras_enviadas'
    );
  });

  it('"sai sozinho": já foi no dia em que a apólice começou; "não mandar": não existe', async () => {
    salvarAjustesNaDemo({ palavras: PALAVRAS.SOZINHO });
    const sozinho = (await daCarteira().seguro(APOLICE_NOVA)).palavras;
    expect(sozinho.sozinho).toBe(true);
    expect(sozinho.enviadoEm).toBeGreaterThan(0);

    salvarAjustesNaDemo({ palavras: PALAVRAS.NAO_MANDAR });
    expect((await daCarteira().seguro(APOLICE_NOVA)).palavras).toBeNull();
  });

  it('`palavras_lendo` e `palavras_erro` mostram a leitura andando e a que falhou', async () => {
    const com = caso =>
      carteiraFonte({ demo: 'cheio', atraso: 0, caso }).seguro(APOLICE_NOVA);

    expect((await com('palavras_lendo')).palavras.estado).toBe('lendo');
    expect((await com('palavras_erro')).palavras.estado).toBe('erro');
  });
});
