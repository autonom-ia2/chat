import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import { DURACAO_DA_TRAZIDA_MS } from '../../demo/trazer';

// A fonte de "Trazer minha lista" (#2894): demonstração e fonte real pendente.
const DIA = 24 * 60 * 60 * 1000;
const AGORA = Date.UTC(2026, 10, 11, 15);
const carregarDemo = () => import('../../demo/trazer.js');

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

describe('fonte real (pendente)', () => {
  it.each([
    'ler',
    'responder',
    'consertar',
    'deixarDeFora',
    'reabrir',
    'trocarDestino',
    'trazer',
    'andamento',
    'historico',
    'previaDoDesfazer',
    'desfazer',
  ])('%s diz FONTE_REAL_PENDENTE', async metodo => {
    const fonte = trazerFonte({ demo: null });
    expect(fonte.usaDemo).toBe(false);
    await expect(fonte[metodo]('x')).rejects.toMatchObject({
      name: 'FONTE_REAL_PENDENTE',
    });
  });

  it('sem módulo de demonstração (produção) volta à fonte real', async () => {
    const fonte = trazerFonte({ demo: 'cheio', carregarDemo: null });
    expect(fonte.usaDemo).toBe(false);
    await expect(fonte.ler()).rejects.toMatchObject({
      name: 'FONTE_REAL_PENDENTE',
    });
  });
});

describe('ler', () => {
  it('qualquer planilha devolve a leitura de 200 pessoas com 5 problemas', async () => {
    const { fonte } = fonteComRelogio();
    const leitura = await fonte.ler({ name: 'minha-lista.csv' });
    expect(leitura.arquivo).toBe('minha-lista.csv');
    expect(leitura.resumo).toEqual({
      total: 200,
      novas: 180,
      completadas: 15,
      comProblema: 5,
    });
    expect(leitura.problemas).toHaveLength(5);
    expect(leitura.problemas.map(p => p.tipo)).toEqual([
      'telefone',
      'email',
      'nome',
      'duplicada',
      'sem_contato',
    ]);
    expect(leitura.exemplos).toHaveLength(3);
    expect(leitura.perguntas.map(p => p.id)).toEqual(['clientes', 'telefone']);
    expect(leitura.colunas.find(c => c.duvidosa).nome).toBe('Fone 2');
  });

  it('a planilha de exemplo (sem arquivo) tem nome próprio', async () => {
    const { fonte } = fonteComRelogio();
    expect((await fonte.ler(null)).arquivo).toBe('Clientes 2025.xlsx');
  });

  it('é sempre a mesma leitura', async () => {
    const { fonte } = fonteComRelogio();
    const primeira = await fonte.ler(null);
    const segunda = await fonte.ler(null);
    expect({ ...primeira, id: '' }).toEqual({ ...segunda, id: '' });
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
  it('responder muda a coluna duvidosa e marca os exemplos', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    const nova = await fonte.responder(id, {
      clientes: 'sim_todas',
      telefone: 'da_empresa',
    });
    const fone2 = nova.colunas.find(c => c.nome === 'Fone 2');
    expect(fone2).toMatchObject({
      destino: 'telefone_da_empresa',
      duvidosa: false,
    });
    expect(nova.exemplos.every(e => e.cliente)).toBe(true);
  });

  it('"Algumas" deixa o selo só em quem a coluna diz que é cliente', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    const nova = await fonte.responder(id, {
      clientes: 'algumas',
      colunaCliente: 'Situação',
      telefone: 'nao_usar',
    });
    expect(nova.exemplos.map(e => e.cliente)).toEqual([true, false, true]);
    expect(nova.colunas.find(c => c.nome === 'Situação').destino).toBe(
      'cliente'
    );
    expect(nova.colunas.find(c => c.nome === 'Fone 2').destino).toBe(
      'nao_guardar'
    );
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
    await fonte.consertar(id, 14, '+5511973800014');
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
    const nova = await fonte.trocarDestino(id, 'Aniversário', 'nao_guardar');
    expect(nova.colunas.find(c => c.nome === 'Aniversário').destino).toBe(
      'nao_guardar'
    );
    expect(nova.colunas.find(c => c.nome === 'Cel').destino).toBe('telefone');
  });

  it('devolve cópia: mexer no resultado não muda a próxima leitura', async () => {
    const { fonte } = fonteComRelogio();
    const lida = await fonte.ler(null);
    lida.problemas[0].estado = 'guardado';
    const nova = await fonte.trocarDestino(lida.id, 'Cel', 'telefone');
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
  it('cheio traz três listas antigas: duas prontas (uma bem antiga) e uma desfeita', async () => {
    const { fonte } = fonteComRelogio('cheio');
    const listas = await fonte.historico();
    expect(listas.map(l => l.situacao)).toEqual([
      'pronto',
      'desfeito',
      'pronto',
    ]);
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

  it('a lista recém-trazida entra no topo, com a prévia da planilha de exemplo', async () => {
    const { fonte } = fonteComRelogio();
    const { trazidaId } = await trazerUma(fonte);
    const [nova] = await fonte.historico();
    expect(nova).toMatchObject({
      id: trazidaId,
      arquivo: 'Clientes 2025.xlsx',
      total: 195,
    });
    expect(await fonte.previaDoDesfazer(trazidaId)).toEqual({
      tira: 162,
      ficam: 18,
      devolve: 15,
    });
  });

  it('sobe de 0 a 100 em cerca de 6 segundos e termina pronto', async () => {
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

  it('o total conta as linhas consertadas e tira as deixadas de fora', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    await fonte.consertar(id, 14, '+5511973800014');
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

describe('desfazer', () => {
  it('desfaz a lista pronta', async () => {
    const { fonte } = fonteComRelogio();
    const [pronta] = await fonte.historico();
    await fonte.desfazer(pronta.id);
    const [depois] = await fonte.historico();
    expect(depois.situacao).toBe('desfeito');
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
    const depois = (await fonte.historico()).find(l => l.id === antiga.id);
    expect(depois.situacao).toBe('desfeito');
  });

  it('não desfaz lista que ainda está sendo trazida nem lista já desfeita', async () => {
    const { fonte } = fonteComRelogio();
    const { id } = await fonte.ler(null);
    const { trazidaId } = await fonte.trazer(id);
    await expect(fonte.desfazer(trazidaId)).rejects.toMatchObject({
      name: 'NAO_PODE_DESFAZER',
    });
    const antiga = (await fonte.historico()).find(
      l => l.situacao === 'desfeito'
    );
    await expect(fonte.desfazer(antiga.id)).rejects.toMatchObject({
      name: 'NAO_PODE_DESFAZER',
    });
  });
});
