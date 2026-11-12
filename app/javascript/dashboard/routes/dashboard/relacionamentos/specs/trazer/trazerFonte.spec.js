import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import {
  DURACAO_DA_TRAZIDA_MS,
  DURACAO_DO_DESFAZER_MS,
} from '../../demo/trazer';
import { agendaComRecuo } from '../../trazer/consultaComRecuo';

// A fonte de "Trazer minha lista" (#2894): a demonstração. A fonte real (#2896)
// está em trazerFonteReal.spec.js. O que a demonstração faz como o servidor
// está em demonstracaoLinhas.spec.js e
// demonstracaoColunas.spec.js; a forma do que ela devolve, em
// paridadeDaDemonstracao.spec.js.
const DIA = 24 * 60 * 60 * 1000;
const AGORA = Date.UTC(2026, 10, 11, 15);
const carregarDemo = () => import('../../demo/trazer.js');
// As colunas da planilha de exemplo, pelo índice.
const COLUNA = { CEL: 1, SITUACAO: 5, ANIVERSARIO: 6 };

const fonteDoRelogio = (relogio, estado = 'cheio') =>
  trazerFonte({
    demo: estado,
    carregarDemo,
    atraso: 0,
    atrasoDaLeitura: 0,
    agora: () => relogio.agora,
  });

const fonteComRelogio = (estado = 'cheio') => {
  const relogio = { agora: AGORA };
  return { fonte: fonteDoRelogio(relogio, estado), relogio };
};

beforeEach(() => esquecerMemoriaDaDemo());

describe('qual fonte', () => {
  it('sem módulo de demonstração (produção) volta à fonte real', () => {
    const fonte = trazerFonte({ demo: 'cheio', carregarDemo: null });
    expect(fonte.usaDemo).toBe(false);
    expect(fonte.temDesfazer).toBe(true);
  });
});

describe('ler', () => {
  it('qualquer planilha devolve a leitura de 203 pessoas com 8 problemas', async () => {
    const { fonte } = fonteComRelogio();
    const leitura = await fonte.ler({ name: 'minha-lista.csv' });
    expect(leitura.arquivo).toBe('minha-lista.csv');
    expect(leitura.resumo).toEqual({
      total: 203,
      novas: 180,
      completadas: 15,
      comProblema: 8,
      juntadas: 3,
      // A conta de quantas entram, que na demonstração a própria demo faz.
      entram: 195,
      // Ninguém é cliente até a pessoa dizer quem é (E3).
      clientes: 0,
    });
    expect(leitura.problemasTotal).toBe(8);
    expect(leitura.problemas).toHaveLength(8);
    expect(leitura.problemas.map(p => p.tipo)).toEqual([
      'telefone',
      'email',
      'nome',
      'telefone',
      'formula',
      'duplicada',
      'duplicada',
      'sem_contato',
    ]);
    expect(leitura.exemplos).toHaveLength(3);
    expect(leitura.perguntas.map(p => p.id)).toEqual(['clientes', 'telefone']);
    expect(leitura.colunas.find(c => c.duvidosa).nome).toBe('Cel');
  });

  it('a planilha de exemplo (sem arquivo) tem nome próprio', async () => {
    const { fonte } = fonteComRelogio();
    expect((await fonte.ler(null)).arquivo).toBe('Clientes 2025.xlsx');
  });

  it('é sempre a mesma leitura', async () => {
    const { fonte } = fonteComRelogio();
    const primeira = await fonte.ler(null);
    const segunda = await fonte.ler(null);
    expect({ ...primeira, id: 0 }).toEqual({ ...segunda, id: 0 });
    expect(primeira.id).not.toBe(segunda.id);
  });

  it('usa só dados fictícios', async () => {
    const { fonte } = fonteComRelogio();
    const { exemplos } = await fonte.ler(null);
    exemplos.forEach(({ telefone, email }) => {
      expect(telefone.startsWith('+55 11 9')).toBe(true);
      expect(email.endsWith('@exemplo.com.br')).toBe(true);
    });
  });
});

describe('escritas na leitura', () => {
  it('responder tira a dúvida da coluna e marca os exemplos', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    const nova = await fonte.responder(id, {
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
    });
    const cel = nova.colunas.find(c => c.nome === 'Cel');
    expect(cel.destino).toBe('telefone');
    expect(cel).not.toHaveProperty('duvidosa');
    expect(nova.exemplos.every(e => e.cliente)).toBe(true);
  });

  // E3 — a coluna não diz sozinha quem é cliente: marcar a coluna faz a
  // planilha ser lida de novo, e o selo só aparece em quem tem um valor que a
  // pessoa marcou.
  it('"Algumas" deixa o selo só em quem tem o valor que a pessoa marcou', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    const respostas = {
      clientes: 'algumas',
      colunaCliente: COLUNA.SITUACAO,
      telefone: 'da_pessoa',
    };
    const lida = await fonte.responder(id, respostas);
    expect(lida.colunas.find(c => c.nome === 'Situação').destino).toBe(
      'cliente'
    );
    expect(lida.exemplos.some(e => e.cliente)).toBe(false);
    const dosValores = lida.perguntas.find(p => p.id === 'valores_cliente');
    const { chave } = dosValores.valores.find(v => v.valor === 'Cliente');
    const nova = await fonte.responder(id, {
      ...respostas,
      valores_cliente: { modo: 'valores', chaves: [chave] },
    });
    expect(nova.exemplos.map(e => e.cliente)).toEqual([true, false, true]);
  });

  it('"Ainda não" não marca ninguém', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    const nova = await fonte.responder(id, {
      clientes: 'ainda_nao',
      telefone: 'da_pessoa',
    });
    expect(nova.exemplos.some(e => e.cliente)).toBe(false);
  });

  it('consertar guarda a linha e deixarDeFora tira a linha', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    await fonte.consertar(id, 14, '(11) 97380-0014');
    const nova = await fonte.deixarDeFora(id, 62);
    const por = linha => nova.problemas.find(p => p.linha === linha);
    expect(por(14)).toMatchObject({
      estado: 'guardado',
      corrigido: '+5511973800014',
    });
    expect(por(62).estado).toBe('deixado');
    expect(por(37).estado).toBe('aberto');
  });

  it('trocarDestino muda só a coluna pedida', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    const nova = await fonte.trocarDestino(
      id,
      COLUNA.ANIVERSARIO,
      'nao_guardar'
    );
    expect(nova.colunas.find(c => c.nome === 'Aniversário').destino).toBe(
      'nao_guardar'
    );
    expect(nova.colunas.find(c => c.nome === 'Cel').destino).toBe('telefone');
  });

  // #2896, Fatia 2 — a informação nova guarda o nome do campo e o "para que
  // serve", no mesmo formato do servidor.
  it('trocarDestino para informação nova guarda o campo; outro destino o tira', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    const campo = { nome: 'Nascimento', para_que_serve: 'dia do aniversário' };
    const nova = await fonte.trocarDestino(
      id,
      COLUNA.ANIVERSARIO,
      'informacao',
      campo
    );
    expect(nova.colunas.find(c => c.nome === 'Aniversário')).toMatchObject({
      destino: 'informacao',
      campo,
    });
    const fora = await fonte.trocarDestino(
      id,
      COLUNA.ANIVERSARIO,
      'nao_guardar'
    );
    expect(
      fora.colunas.find(c => c.nome === 'Aniversário').campo
    ).toBeUndefined();
  });

  it('devolve cópia: mexer no resultado não muda a próxima leitura', async () => {
    const { fonte } = fonteComRelogio();
    const lida = await fonte.ler(null);
    lida.problemas[0].estado = 'guardado';
    const nova = await fonte.trocarDestino(lida.id, COLUNA.CEL, 'telefone');
    expect(nova.problemas[0].estado).toBe('aberto');
  });

  it('leitura que não existe dá erro nomeado', async () => {
    const { fonte } = fonteComRelogio();
    await expect(fonte.consertar('nada', 1, 'x')).rejects.toMatchObject({
      name: 'LEITURA_NAO_ENCONTRADA',
    });
  });
});

describe('historico', () => {
  it('cheio traz quatro listas antigas: duas prontas, uma desfeita e uma que parou no meio', async () => {
    const { fonte } = fonteComRelogio('cheio');
    const listas = await fonte.historico();
    expect(listas.map(l => l.situacao)).toEqual([
      'pronto',
      'desfeito',
      'pronto',
      'falhou',
    ]);
    // Só a que parou no meio tem como continuar.
    expect(listas.map(l => l.podeTentar)).toEqual([false, false, false, true]);
    // Dá para desfazer a pronta e a que parou no meio (ela chegou a pôr gente).
    expect(listas.map(l => l.podeDesfazer)).toEqual([true, false, true, true]);
    // Da mais nova para a mais antiga, como o servidor entrega.
    expect(listas.map(l => l.quando)).toEqual(
      [...listas.map(l => l.quando)].sort((a, b) => b - a)
    );
    expect(listas[0]).toMatchObject({
      arquivo: 'Clientes de setembro.xlsx',
      total: 132,
    });
    expect(listas.map(l => l.arquivo)).not.toContain('Clientes 2025.xlsx');
    expect(listas[0].quando).toBe(AGORA - 3 * DIA);
  });

  it('vazio não traz nenhuma', async () => {
    const { fonte } = fonteComRelogio('vazio');
    expect(await fonte.historico()).toEqual([]);
  });

  it('a lista antiga pronta sabe quantos saem, quantos ficam aqui e quantos voltam ao que eram', async () => {
    const { fonte } = fonteComRelogio();
    const [pronta] = await fonte.historico();
    const previa = await fonte.previaDoDesfazer(pronta.id);
    expect(previa).toEqual({ tira: 104, ficam: 16, devolve: 12 });
    expect(previa.tira + previa.ficam + previa.devolve).toBe(pronta.total);
    expect(previa.receberamCampanha).toBeUndefined();
  });
});

describe('trazer e andamento', () => {
  const trazerUma = async fonte => {
    const { id } = await fonte.ler(null);
    return fonte.trazer(id);
  };

  it('a lista recém-trazida entra no topo e, depois de trazida, tem a prévia da planilha de exemplo', async () => {
    const { fonte, relogio } = fonteComRelogio();
    const { trazidaId } = await trazerUma(fonte);
    const [nova] = await fonte.historico();
    expect(nova).toMatchObject({
      id: trazidaId,
      arquivo: 'Clientes 2025.xlsx',
      total: 195,
    });
    relogio.agora += DURACAO_DA_TRAZIDA_MS;
    expect(await fonte.previaDoDesfazer(trazidaId)).toEqual({
      tira: 162,
      ficam: 18,
      devolve: 15,
    });
  });

  it('sobe de 0 a 100 em 17 segundos e termina pronto', async () => {
    const { fonte, relogio } = fonteComRelogio();
    const { trazidaId } = await trazerUma(fonte);
    expect(await fonte.andamento(trazidaId)).toMatchObject({
      porcentagem: 0,
      situacao: 'trazendo',
      total: 195,
      novas: 180,
      completadas: 15,
    });
    relogio.agora = AGORA + DURACAO_DA_TRAZIDA_MS * 0.4;
    expect(await fonte.andamento(trazidaId)).toMatchObject({
      porcentagem: 40,
      situacao: 'trazendo',
    });
    relogio.agora = AGORA + DURACAO_DA_TRAZIDA_MS;
    expect(await fonte.andamento(trazidaId)).toMatchObject({
      porcentagem: 100,
      situacao: 'pronto',
    });
  });

  // A tela pergunta pelo andamento com a espera crescendo
  // (trazer/consultaComRecuo.js). A demonstração dura o bastante para a barra
  // andar aos poucos nessas consultas, e não em dois saltos.
  describe('nas consultas que a tela faz', () => {
    const CONSULTAS = 6;
    // Quanto tempo depois do começo cai cada consulta, pela agenda da tela.
    const temposDasConsultas = () => {
      vi.useFakeTimers();
      const inicio = Date.now();
      const agenda = agendaComRecuo();
      const tempos = [0];
      const consultar = () => {
        tempos.push(Date.now() - inicio);
        if (tempos.length < CONSULTAS) agenda.agendar(consultar);
      };
      agenda.agendar(consultar);
      vi.runAllTimers();
      vi.useRealTimers();
      return tempos;
    };

    it('a barra passa por 0, 8, 22, 41 e 71 e termina na sexta consulta', async () => {
      const tempos = temposDasConsultas();
      expect(tempos).toEqual([0, 1500, 3750, 7125, 12125, 17125]);
      const { fonte, relogio } = fonteComRelogio();
      const { trazidaId } = await trazerUma(fonte);
      const vistos = await tempos.reduce(async (anteriores, tempo) => {
        const ate = await anteriores;
        relogio.agora = AGORA + tempo;
        return [...ate, await fonte.andamento(trazidaId)];
      }, Promise.resolve([]));
      expect(vistos.map(visto => visto.porcentagem)).toEqual([
        0, 8, 22, 41, 71, 100,
      ]);
      expect(vistos.map(visto => visto.situacao)).toEqual([
        'trazendo',
        'trazendo',
        'trazendo',
        'trazendo',
        'trazendo',
        'pronto',
      ]);
    });
  });

  it('o total conta as linhas consertadas e tira as deixadas de fora', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    await fonte.consertar(id, 14, '(11) 97380-0014');
    await fonte.consertar(id, 37, 'rita@exemplo.com.br');
    await fonte.deixarDeFora(id, 62);
    const { trazidaId } = await fonte.trazer(id);
    expect((await fonte.andamento(trazidaId)).total).toBe(197);
  });

  it('a lista trazida aparece no histórico com a porcentagem, mesmo depois de sair e voltar', async () => {
    const { fonte, relogio } = fonteComRelogio();
    await trazerUma(fonte);
    relogio.agora = AGORA + DURACAO_DA_TRAZIDA_MS * 0.4;
    const voltou = fonteDoRelogio(relogio);
    const [nova] = await voltou.historico();
    expect(nova).toMatchObject({ situacao: 'trazendo', porcentagem: 40 });
  });

  it('lista que não existe dá erro nomeado', async () => {
    const { fonte } = fonteComRelogio();
    await expect(fonte.andamento('nada')).rejects.toMatchObject({
      name: 'LISTA_NAO_ENCONTRADA',
    });
  });
});

// #2896 — a lista que parou no meio, em demonstração: "Tentar de novo" faz ela
// voltar a ser trazida e terminar, como no servidor.
describe('tentar de novo (lista que parou no meio)', () => {
  const aQueFalhou = async fonte =>
    (await fonte.historico()).find(l => l.situacao === 'falhou');

  it('a lista volta a ser trazida, do começo da barra, e termina pronta', async () => {
    const { fonte, relogio } = fonteComRelogio();
    const falhou = await aQueFalhou(fonte);
    expect(await fonte.tentarDeNovo(falhou.id)).toEqual({
      trazidaId: falhou.id,
    });
    const logoDepois = (await fonte.historico()).find(l => l.id === falhou.id);
    expect(logoDepois).toMatchObject({
      situacao: 'trazendo',
      porcentagem: 0,
      podeTentar: false,
    });
    // O dia em que a lista foi enviada não muda por tentar de novo.
    expect(logoDepois.quando).toBe(falhou.quando);
    relogio.agora += DURACAO_DA_TRAZIDA_MS / 2;
    expect((await fonte.andamento(falhou.id)).porcentagem).toBe(50);
    relogio.agora += DURACAO_DA_TRAZIDA_MS;
    const noFim = (await fonte.historico()).find(l => l.id === falhou.id);
    expect(noFim).toMatchObject({ situacao: 'pronto', porcentagem: 100 });
  });

  it('só continua lista que parou no meio', async () => {
    const { fonte } = fonteComRelogio();
    const [pronta] = await fonte.historico();
    await expect(fonte.tentarDeNovo(pronta.id)).rejects.toMatchObject({
      name: 'NAO_PODE_TENTAR',
    });
    await expect(fonte.tentarDeNovo('nada')).rejects.toMatchObject({
      name: 'LISTA_NAO_ENCONTRADA',
    });
  });

  // Como o servidor: as pessoas que a lista chegou a pôr não ficam presas
  // numa lista que não dá para apagar. A pessoa escolhe continuar ou desfazer.
  it('a lista que parou no meio pode ser desfeita: tem prévia, fica "desfazendo" e depois "desfeito"', async () => {
    const { fonte, relogio } = fonteComRelogio();
    const falhou = await aQueFalhou(fonte);
    expect(falhou).toMatchObject({ podeTentar: true, podeDesfazer: true });
    expect(await fonte.previaDoDesfazer(falhou.id)).toEqual({
      tira: 63,
      ficam: 7,
      devolve: 10,
    });
    expect(await fonte.desfazer(falhou.id)).toEqual({
      id: falhou.id,
      situacao: 'desfazendo',
    });
    const durante = (await fonte.historico()).find(l => l.id === falhou.id);
    // Sendo desfeita, não há o que continuar nem o que desfazer de novo.
    expect(durante).toMatchObject({
      situacao: 'desfazendo',
      podeTentar: false,
      podeDesfazer: false,
    });
    await expect(fonte.tentarDeNovo(falhou.id)).rejects.toMatchObject({
      name: 'NAO_PODE_TENTAR',
    });
    relogio.agora += DURACAO_DO_DESFAZER_MS;
    const depois = (await fonte.historico()).find(l => l.id === falhou.id);
    expect(depois).toMatchObject({
      situacao: 'desfeito',
      podeTentar: false,
      podeDesfazer: false,
    });
  });
});

describe('desfazer', () => {
  const situacaoDe = async (fonte, id) =>
    (await fonte.historico()).find(l => l.id === id).situacao;

  it('a lista pronta fica "desfazendo" e, passado o tempo do desfazer, "desfeito"', async () => {
    const { fonte, relogio } = fonteComRelogio();
    const [pronta] = await fonte.historico();
    expect(await fonte.desfazer(pronta.id)).toEqual({
      id: pronta.id,
      situacao: 'desfazendo',
    });
    const [durante] = await fonte.historico();
    expect(durante).toMatchObject({
      situacao: 'desfazendo',
      porcentagem: 100,
      podeDesfazer: false,
    });
    expect((await fonte.andamento(pronta.id)).situacao).toBe('desfazendo');
    relogio.agora += DURACAO_DO_DESFAZER_MS - 1;
    expect(await situacaoDe(fonte, pronta.id)).toBe('desfazendo');
    relogio.agora += 1;
    expect(await situacaoDe(fonte, pronta.id)).toBe('desfeito');
  });

  // Como o servidor: o pedido repetido não é erro nem recomeça o desfazer.
  it('pedir de novo responde a situação de agora, sem recomeçar', async () => {
    const { fonte, relogio } = fonteComRelogio();
    const [pronta] = await fonte.historico();
    await fonte.desfazer(pronta.id);
    relogio.agora += DURACAO_DO_DESFAZER_MS - 1;
    expect(await fonte.desfazer(pronta.id)).toEqual({
      id: pronta.id,
      situacao: 'desfazendo',
    });
    relogio.agora += 1;
    expect(await fonte.desfazer(pronta.id)).toEqual({
      id: pronta.id,
      situacao: 'desfeito',
    });
  });

  it('lista pronta antiga tem Desfazer, com prévia própria', async () => {
    const { fonte, relogio } = fonteComRelogio();
    relogio.agora = AGORA + 400 * DIA;
    const antiga = (await fonte.historico()).find(
      l => l.id === 'trazida-antiga-3'
    );
    expect(antiga.situacao).toBe('pronto');
    const previa = await fonte.previaDoDesfazer(antiga.id);
    const primeira = await fonte.previaDoDesfazer('trazida-antiga-1');
    expect(previa).toEqual({ tira: 41, ficam: 14, devolve: 7 });
    expect(previa).not.toEqual(primeira);
    expect(previa.tira + previa.ficam + previa.devolve).toBe(antiga.total);
    await fonte.desfazer(antiga.id);
    relogio.agora += DURACAO_DO_DESFAZER_MS;
    expect(await situacaoDe(fonte, antiga.id)).toBe('desfeito');
  });

  it.each(['previaDoDesfazer', 'desfazer'])(
    'a lista que ainda está sendo trazida não tem o que desfazer (%s)',
    async metodo => {
      const { fonte } = fonteComRelogio();
      const { id } = await fonte.ler(null);
      const { trazidaId } = await fonte.trazer(id);
      const [trazendo] = await fonte.historico();
      expect(trazendo).toMatchObject({ id: trazidaId, podeDesfazer: false });
      await expect(fonte[metodo](trazidaId)).rejects.toMatchObject({
        name: 'NAO_PODE_DESFAZER',
      });
    }
  );

  it('a lista já desfeita responde "desfeito" e continua como está', async () => {
    const { fonte } = fonteComRelogio();
    const antiga = (await fonte.historico()).find(
      l => l.situacao === 'desfeito'
    );
    expect(await fonte.desfazer(antiga.id)).toEqual({
      id: antiga.id,
      situacao: 'desfeito',
    });
    expect(await situacaoDe(fonte, antiga.id)).toBe('desfeito');
  });
});
