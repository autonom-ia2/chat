import { comTextosDaIa } from '../catalogo';
import { opcoesDosValores } from '../texto';
import { linhasDoEnsaio } from '../ensaio';
import { fraseDoPasso, fraseDoValor } from '../frases';

// #2679 — o texto que o "escrever" e o "resumir" produzem vira um dado que os
// passos seguintes leem (`ia.<id>`), e o "escrever" pode só guardar.
const t = (chave, valores) =>
  valores && Object.keys(valores).length
    ? `${chave}(${Object.values(valores).join(',')})`
    : chave;

const catalogo = {
  valores: [{ caminho: 'contato.nome', frase: 'NOME' }],
  passos: [],
};
const passos = [
  {
    id: 'p1',
    tipo: 'escrever',
    instrucao: 'Pergunte como ela está',
    destino: 'guardar',
  },
  {
    id: 's1',
    tipo: 'se',
    entao: [{ id: 'r1', tipo: 'resumir', destino: 'nota' }],
    senao: [],
  },
  { id: 'm1', tipo: 'mensagem', texto: ['oi'] },
];

describe('comTextosDaIa', () => {
  it('põe o texto de cada "escrever" e "resumir", inclusive os de dentro dos galhos', () => {
    const valores = comTextosDaIa(catalogo, passos, t).valores;

    expect(valores.map(item => item.caminho)).toEqual([
      'contato.nome',
      'ia.p1',
      'ia.r1',
    ]);
  });

  it('o "Pôr um dado" mostra o rótulo pronto: a instrução, ou "Resumo da IA"', () => {
    const opcoes = opcoesDosValores(
      comTextosDaIa(catalogo, passos, t),
      () => [],
      t
    );

    expect(opcoes.map(item => item.label)).toEqual([
      'NOME',
      'AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.ESCREVER(Pergunte como ela está)',
      'AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.RESUMIR',
    ]);
  });

  it('dois resumos levam o id junto, para dizer qual é qual', () => {
    const dois = [...passos, { id: 'r2', tipo: 'resumir', destino: 'nota' }];
    const opcoes = opcoesDosValores(
      comTextosDaIa(catalogo, dois, t),
      () => [],
      t
    );

    expect(opcoes.slice(-2).map(item => item.label)).toEqual([
      'AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.RESUMIR (r1)',
      'AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.RESUMIR (r2)',
    ]);
  });

  it('no "Só se" do gatilho o texto da IA não entra: nenhum passo rodou', () => {
    const opcoes = opcoesDosValores(
      comTextosDaIa(catalogo, passos, t),
      () => [],
      t,
      'conversa.resolvida'
    );

    expect(opcoes.map(item => item.value)).toEqual(['contato.nome']);
  });

  it('a instrução longa corta sem partir um emoji', () => {
    const longa = [
      { id: 'p1', tipo: 'escrever', instrucao: `${'a'.repeat(39)}😀😀` },
    ];
    const [item] = comTextosDaIa(catalogo, longa, t).valores.slice(-1);

    expect(item.rotulo).toBe(
      `AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.ESCREVER(${'a'.repeat(39)}😀…)`
    );
  });

  it('sem catálogo carregado, fica como está', () => {
    expect(comTextosDaIa(null, passos, t)).toBeNull();
  });
});

describe('o "escrever" que só guarda', () => {
  it('a linha do passo diz que o texto fica para os seguintes', () => {
    const comOEscrever = { ...catalogo, passos: [{ tipo: 'escrever' }] };

    expect(fraseDoPasso(passos[0], comOEscrever, t)).toBe(
      'AUTOMACAO_LIVRE.FRASES.ESCREVER_GUARDAR(Pergunte como ela está)'
    );
  });

  it('o ensaio diz que o texto ficaria guardado', () => {
    const [linha] = linhasDoEnsaio(
      [
        {
          id: 'p1',
          tipo: 'escrever',
          faria: 'ia_escrever',
          dados: { destino: 'guardar' },
        },
      ],
      () => 'frase',
      t
    );

    expect(linha.destaque).toBe(
      'AUTOMACAO_LIVRE.ENSAIO.FARIA.IA_ESCREVER_GUARDAR'
    );
  });
});

describe('o texto da IA na frase', () => {
  it('a frase do valor usa o rótulo, nunca o caminho cru nem uma tradução vazia', () => {
    const comTextos = comTextosDaIa(catalogo, passos, t);

    expect(fraseDoValor('ia.p1', comTextos, t)).toBe(
      'AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.ESCREVER(Pergunte como ela está)'
    );
  });

  it('a linha da mensagem mostra o rótulo do texto, não [ia.p1]', () => {
    const comTextos = {
      ...comTextosDaIa(catalogo, passos, t),
      passos: [{ tipo: 'mensagem' }],
    };
    const frase = fraseDoPasso(
      { id: 'm2', tipo: 'mensagem', texto: ['Oi! ', { $valor: 'ia.p1' }] },
      comTextos,
      t
    );

    expect(frase).toContain('[AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.ESCREVER(');
    expect(frase).not.toContain('ia.p1');
  });
});
