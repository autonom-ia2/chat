import {
  alternarPergunta,
  blocosDe,
  contar,
  mudarBloco,
  soltas,
  temBlocos,
} from '../utils/perguntasEmBlocos';

// #3020 — as perguntas do agente pronto por ramo, em blocos. A lista é a do servidor; nada aqui a muda no lugar.
const ITENS = [
  { id: 'p1', texto: 'Qual o CEP?', tirada: false, bloco: 'Endereço' },
  {
    id: 'p2',
    texto: 'Qual o endereço?',
    tirada: false,
    bloco: 'Endereço',
    se: 'não souber o CEP',
    segue: true,
  },
  { id: 'p3', texto: 'Quantos elevadores?', tirada: true, bloco: 'O prédio' },
  {
    id: 'p4',
    texto: 'Qual a marca deles?',
    tirada: true,
    bloco: 'O prédio',
    se: 'houver elevadores',
    segue: true,
  },
  { id: 'p5', texto: 'Quantas vagas?', tirada: true, bloco: 'O prédio' },
  { id: 'p6', texto: 'Tem portaria 24 horas?', tirada: false },
];
const ligadas = itens => itens.filter(item => !item.tirada).map(i => i.id);

describe('perguntasEmBlocos', () => {
  it('groups the model questions by block, in order, and keeps the owner questions apart', () => {
    expect(temBlocos(ITENS)).toBe(true);
    expect(
      temBlocos([{ id: 'p1', texto: 'Qual o CNPJ?', tirada: false }])
    ).toBe(false);
    expect(
      blocosDe(ITENS).map(bloco => [bloco.nome, bloco.perguntas.map(p => p.id)])
    ).toEqual([
      ['Endereço', ['p1', 'p2']],
      ['O prédio', ['p3', 'p4', 'p5']],
    ]);
    expect(soltas(ITENS).map(item => item.id)).toEqual(['p6']);
  });

  it('counts what is on: what every customer answers and what depends on the answer', () => {
    expect(contar(ITENS)).toEqual({
      ligadas: 3,
      todos: 2,
      conforme: 1,
      total: 6,
    });
  });

  it('turning off a question turns off the ones that follow it', () => {
    const nova = alternarPergunta(ITENS, 'p1');

    expect(ligadas(nova)).toEqual(['p6']);
    expect(ligadas(ITENS)).toEqual(['p1', 'p2', 'p6']);
  });

  it('turning on a question that follows another turns on the one above too', () => {
    expect(ligadas(alternarPergunta(ITENS, 'p4'))).toEqual([
      'p1',
      'p2',
      'p3',
      'p4',
      'p6',
    ]);
  });

  it('turning a question on or off leaves the others of the block alone', () => {
    expect(ligadas(alternarPergunta(ITENS, 'p3'))).toEqual([
      'p1',
      'p2',
      'p3',
      'p6',
    ]);
    expect(ligadas(alternarPergunta(ITENS, 'p2'))).toEqual(['p1', 'p6']);
    expect(alternarPergunta(ITENS, 'nao_existe')).toBe(ITENS);
  });

  it('turns a whole block on or off, and only that block', () => {
    expect(ligadas(mudarBloco(ITENS, 'O prédio', true))).toEqual([
      'p1',
      'p2',
      'p3',
      'p4',
      'p5',
      'p6',
    ]);
    expect(ligadas(mudarBloco(ITENS, 'Endereço', false))).toEqual(['p6']);
  });
});
