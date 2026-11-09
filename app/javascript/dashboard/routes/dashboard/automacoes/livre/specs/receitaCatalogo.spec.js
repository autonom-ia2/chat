import {
  falta,
  inserirPasso,
  novoId,
  tirarPasso,
  trocarPasso,
} from '../receita';
import { entradaDoPasso, gravarCampo, lerCampo, novoPasso } from '../catalogo';
import { fraseDaCondicao, fraseDoPasso } from '../frases';
import {
  comApagados,
  opcoesDosValores,
  textoDaTela,
  textoNaTela,
} from '../texto';
import pt from 'dashboard/i18n/locale/pt_BR';

// #2414 F5 — a receita muda sempre por cópia e o que o editor não conhece passa
// intacto (a ida e volta do 🟠6): trocar um passo não reescreve os outros.
const t = (chave, valores) =>
  valores ? `${chave} ${JSON.stringify(valores)}` : chave;

const CATALOGO = {
  gatilhos: [{ tipo: 'conversa.criada', frase: 'G' }],
  operadores: [{ op: 'igual', pede_valor: true, frase: 'IGUAL' }],
  unidades: [{ valor: 'dias', frase: 'DIAS' }],
  valores: [{ caminho: 'conversa.status', frase: 'STATUS' }],
  passos: [
    { tipo: 'esperar', grupo: 'CONTROLE', frase: 'ESPERAR', campos: [] },
    { tipo: 'se', grupo: 'CONTROLE', frase: 'SE', campos: [] },
    {
      tipo: 'acao',
      nome: 'empresa_alterar',
      acao: 'PATCH companies/:id',
      grupo: 'CONTATO',
      frase: 'EMPRESA',
      caminho: { id: { $valor: 'contato.empresa_id' } },
      envelope: 'company',
      fixos: {},
      campos: [{ nome: 'name', peca: 'texto' }],
    },
    {
      tipo: 'acao',
      nome: 'conversa_status',
      acao: 'POST conversations/:id/toggle_status',
      grupo: 'CONVERSA',
      frase: 'STATUS_PASSO',
      caminho: { id: { $valor: 'conversa.id' } },
      fixos: {},
      campos: [
        {
          nome: 'status',
          peca: 'escolha',
          opcoes: [{ valor: 'open', frase: 'ABERTA' }],
        },
      ],
    },
    {
      tipo: 'acao',
      nome: 'conversa_etiquetas',
      acao: 'PATCH conversations/:conversation_id/labels/alterar',
      grupo: 'CONVERSA',
      frase: 'ETIQUETAS',
      caminho: { conversation_id: { $valor: 'conversa.id' } },
      fixos: {},
      campos: [
        { nome: 'por', peca: 'etiquetas' },
        { nome: 'tirar', peca: 'etiquetas' },
      ],
    },
    {
      tipo: 'acao',
      nome: 'atributo_alterar',
      acao: 'PATCH custom_attribute_definitions/:id',
      grupo: 'ATRIBUTO',
      frase: 'ATRIBUTO',
      caminho: { id: { escolher: 'atributo', rotulo: 'QUAL' } },
      fixos: {},
      campos: [
        {
          nome: 'custom_attribute_definition.attribute_values',
          peca: 'lista_de_textos',
        },
      ],
    },
  ],
};

const AVANCADO = {
  id: 'p9',
  tipo: 'acao',
  acao: 'PUT labels/:id',
  descricao: 'Trocar a etiqueta inteira',
  caminho: { id: 7 },
  corpo: { title: 'vip', extra: { $valor: 'contato.nome' } },
};

// #2486: mensagem e avisar entram no editor; um tipo que este painel ainda não
// conhece (vindo de uma versão mais nova do motor) também passa intacto.
const MENSAGEM = {
  id: 'p5',
  tipo: 'mensagem',
  texto: ['Oi ', { $valor: 'contato.nome' }, ', seu pedido saiu.'],
};
const AVISAR = {
  id: 'p6',
  tipo: 'avisar',
  texto: ['Cliente ', { $valor: 'contato.atributos.placa' }, ' voltou'],
  para: { responsavel: true, times: [3], pessoas: [8, 9] },
};
const DESCONHECIDO = { id: 'p7', tipo: 'ligar_para', numero: { x: [1] } };

const receita = () => ({
  gatilho: { tipo: 'conversa.criada' },
  passos: [
    { id: 'p1', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
    { id: 'p2', tipo: 'se', condicao: null, entao: [AVANCADO] },
    MENSAGEM,
    AVISAR,
    DESCONHECIDO,
  ],
});

describe('receita do editor livre', () => {
  it('põe passo num galho opcional que ainda não existe', () => {
    const novo = { id: 'p3', tipo: 'parar' };
    const passos = inserirPasso(receita().passos, 'p2:senao', 0, novo);
    expect(passos[1].senao).toEqual([novo]);
  });

  it('não cria galho vazio ao mexer em outra lista', () => {
    const novo = { id: 'p3', tipo: 'parar' };
    const passos = inserirPasso(receita().passos, 'raiz', 0, novo);
    expect(passos[2]).not.toHaveProperty('senao');
    expect(passos[2].entao).toEqual([AVANCADO]);
  });

  // F7 (#2500): a travessia única anda pelos caminhos do "decidir" e pelo
  // "nenhum se aplica", como o servidor (Receita.ramos).
  describe('caminhos do decidir', () => {
    const decidir = () => [
      {
        id: 'd1',
        tipo: 'decidir',
        caminhos: [
          { chave: 'sinistro', passos: [{ id: 'a1', tipo: 'parar' }] },
          { chave: 'cotacao', passos: [] },
        ],
        nenhum: [{ id: 'n1', tipo: 'parar' }],
      },
    ];

    it('acha e numera os passos de dentro dos caminhos e do nenhum', () => {
      // d1, a1 e n1 contam: sem andar pelos galhos, o id novo seria p2.
      expect(novoId(decidir())).toBe('p4');
      const comP4 = inserirPasso(decidir(), 'd1:caminhos.0', 0, { id: 'p4' });
      expect(novoId(comP4)).toBe('p5');
    });

    it('põe e tira passo num caminho sem mexer nos outros', () => {
      const novo = { id: 'p9', tipo: 'parar' };
      const passos = inserirPasso(decidir(), 'd1:caminhos.1', 0, novo);
      expect(passos[0].caminhos[1].passos).toEqual([novo]);
      expect(passos[0].caminhos[0]).toEqual(decidir()[0].caminhos[0]);
      expect(passos[0].nenhum).toEqual(decidir()[0].nenhum);

      const semA1 = tirarPasso(passos, 'a1');
      expect(semA1[0].caminhos[0].passos).toEqual([]);
      expect(semA1[0].caminhos[0].chave).toBe('sinistro');
    });

    it('não quebra com caminho vazio na lista', () => {
      const torto = [{ id: 'd1', tipo: 'decidir', caminhos: [null] }];
      expect(novoId(torto)).toBe('p2');
    });

    it('troca um passo de dentro do nenhum', () => {
      const trocado = trocarPasso(decidir(), { id: 'n1', tipo: 'esperar' });
      expect(trocado[0].nenhum).toEqual([{ id: 'n1', tipo: 'esperar' }]);
    });
  });

  it('trocar um passo devolve idênticos o avançado, mensagem, avisar e o tipo desconhecido', () => {
    const original = receita();
    const trocado = {
      ...original.passos[0],
      duracao: { valor: 3, unidade: 'dias' },
    };
    const passos = trocarPasso(original.passos, trocado);
    expect(passos[0].duracao.valor).toBe(3);
    expect(passos.slice(1)).toEqual(original.passos.slice(1));
    expect(passos.slice(2)).toEqual([MENSAGEM, AVISAR, DESCONHECIDO]);
    expect(original.passos[0].duracao.valor).toBe(1);
  });

  // O texto vai à tela com [rótulo] e volta aos mesmos pedaços: abrir e salvar
  // sem mexer não muda a receita.
  describe('ida e volta do texto', () => {
    const catalogo = {
      valores: [
        { caminho: 'contato.nome', frase: 'NOME' },
        {
          caminho: 'contato.atributos',
          atributos: 'contact_attribute',
          frase: 'ATRIB',
        },
      ],
    };
    const tTexto = (chave, valores) =>
      valores ? `${valores.base}: ${valores.chave}` : `${chave}!`;
    const comPlaca = () => [
      { attribute_key: 'placa', attribute_display_name: 'Placa do carro' },
    ];
    const opcoes = opcoesDosValores(catalogo, comPlaca, tTexto);

    it.each([
      ['mensagem', MENSAGEM.texto, 'Oi [NOME!], seu pedido saiu.'],
      ['avisar', AVISAR.texto, 'Cliente [ATRIB!: Placa do carro] voltou'],
    ])(
      '%s: {$valor} volta como [rótulo] e o rótulo volta ao {$valor}',
      (_tipo, partes, tela) => {
        expect(textoNaTela(partes, opcoes)).toBe(tela);
        expect(textoDaTela(tela, opcoes)).toEqual(partes);
      }
    );

    // Campo apagado continua dado (decisão da Automação, 03/11): virar texto
    // mandaria "[Placa]" ao cliente; o salvar recusa até a pessoa trocar.
    it('campo que a conta apagou continua dado, marcado, na ida e volta', () => {
      const semPlaca = opcoesDosValores(catalogo, () => [], tTexto);
      const comApagado = comApagados(
        AVISAR.texto,
        semPlaca,
        caminho => `Dado apagado: ${caminho}`
      );
      const tela = textoNaTela(AVISAR.texto, comApagado);

      expect(comApagado.at(-1)).toEqual({
        value: 'contato.atributos.placa',
        label: 'Dado apagado: contato.atributos.placa',
        apagado: true,
      });
      expect(tela).toBe(
        'Cliente [Dado apagado: contato.atributos.placa] voltou'
      );
      expect(textoDaTela(tela, comApagado)).toEqual(AVISAR.texto);
      expect(textoDaTela(`${tela} de novo`, comApagado)).toEqual([
        ...AVISAR.texto.slice(0, 2),
        ' voltou de novo',
      ]);
    });

    it('rótulo com colchete no nome volta inteiro', () => {
      const comColchete = [
        { value: 'contato.atributos.valor', label: 'Valor [R$]' },
        { value: 'contato.atributos.v', label: 'Valor' },
      ];
      const partes = ['Total: ', { $valor: 'contato.atributos.valor' }, '.'];
      const tela = textoNaTela(partes, comColchete);

      expect(tela).toBe('Total: [Valor [R$]].');
      expect(textoDaTela(tela, comColchete)).toEqual(partes);
      expect(textoDaTela('[Valor] e [Valor [R$]]', comColchete)).toEqual([
        { $valor: 'contato.atributos.v' },
        ' e ',
        { $valor: 'contato.atributos.valor' },
      ]);
    });

    it('dois campos com o mesmo nome levam a chave no rótulo', () => {
      const repetidos = () => [
        { attribute_key: 'placa', attribute_display_name: 'Placa' },
        { attribute_key: 'placa_2', attribute_display_name: 'Placa' },
      ];
      const opcoesRepetidas = opcoesDosValores(catalogo, repetidos, tTexto);
      const partes = [{ $valor: 'contato.atributos.placa_2' }];

      expect(opcoesRepetidas.map(item => item.label)).toEqual([
        'NOME!',
        'ATRIB!: Placa (placa)',
        'ATRIB!: Placa (placa_2)',
      ]);
      expect(
        textoDaTela(textoNaTela(partes, opcoesRepetidas), opcoesRepetidas)
      ).toEqual(partes);
    });

    it('colchete solto ou sem fechar é texto', () => {
      expect(textoDaTela('a [b [NOME!] c] [d', opcoes)).toEqual([
        'a [b ',
        { $valor: 'contato.nome' },
        ' c] [d',
      ]);
      expect(textoDaTela('', opcoes)).toEqual([]);
    });
  });

  it('tira um passo de dentro de um galho', () => {
    const passos = tirarPasso(receita().passos, 'p9');
    expect(passos[1].entao).toEqual([]);
  });

  it('dá id que ainda não existe, contando os galhos', () => {
    expect(novoId(receita().passos)).toBe('p8');
  });

  it('diz o que falta para salvar', () => {
    expect(falta({ gatilho: null, passos: [] })).toBe('GATILHO');
    expect(falta({ gatilho: { tipo: 'x' }, passos: [] })).toBe('PASSO');
    expect(falta(receita())).toBe('COMPLETAR');
    const completa = receita();
    completa.passos[1].condicao = {
      campo: { $valor: 'conversa.status' },
      op: 'vazio',
    };
    expect(falta(completa)).toBeNull();
    completa.passos[1].entao = [];
    expect(falta(completa)).toBe('COMPLETAR');
  });
});

describe('catálogo do editor livre', () => {
  const empresa = CATALOGO.passos[2];
  const atributo = CATALOGO.passos[5];

  it('lê e grava dentro do envelope', () => {
    const passo = gravarCampo(
      { tipo: 'acao', corpo: {} },
      empresa,
      'name',
      'Acme'
    );
    expect(passo.corpo).toEqual({ company: { name: 'Acme' } });
    expect(lerCampo(passo, empresa, 'name')).toBe('Acme');
  });

  it('grava campo de dentro pelo ponto e tira o que ficou vazio', () => {
    const nome = 'custom_attribute_definition.attribute_values';
    const passo = gravarCampo({ corpo: {} }, atributo, nome, ['a', 'b']);
    expect(passo.corpo.custom_attribute_definition.attribute_values).toEqual([
      'a',
      'b',
    ]);
    const vazio = gravarCampo(passo, atributo, nome, '');
    expect(vazio.corpo.custom_attribute_definition).toEqual({});
  });

  it('monta a ação nova com o alvo que vem da conversa', () => {
    const passo = novoPasso(empresa, 'p5', t);
    expect(passo).toEqual({
      id: 'p5',
      tipo: 'acao',
      acao: 'PATCH companies/:id',
      descricao: 'EMPRESA',
      caminho: { id: { $valor: 'contato.empresa_id' } },
      corpo: {},
    });
  });

  it('deixa o alvo a escolher fora do caminho', () => {
    expect(novoPasso(atributo, 'p6', t).caminho).toEqual({});
  });

  it('passo que o editor não conhece vira ação avançada', () => {
    expect(entradaDoPasso(AVANCADO, CATALOGO)).toBeNull();
    expect(fraseDoPasso(AVANCADO, CATALOGO, t)).toContain(
      'Trocar a etiqueta inteira'
    );
  });

  it('tipo desconhecido sem descrição fica "Ação avançada", sem os dois-pontos', () => {
    expect(entradaDoPasso(DESCONHECIDO, CATALOGO)).toBeNull();
    expect(fraseDoPasso(DESCONHECIDO, CATALOGO, t)).toBe(
      'AUTOMACAO_LIVRE.FRASES.AVANCADA_SEM_NOME'
    );
  });

  it('monta mensagem e avisar novos com o texto vazio', () => {
    expect(novoPasso({ tipo: 'mensagem' }, 'p8', t)).toEqual({
      id: 'p8',
      tipo: 'mensagem',
      texto: [],
    });
    expect(novoPasso({ tipo: 'avisar' }, 'p9', t)).toEqual({
      id: 'p9',
      tipo: 'avisar',
      texto: [],
      para: { responsavel: true },
    });
  });

  it('monta o "Passar para a agente de IA" novo sem agente escolhida', () => {
    expect(novoPasso({ tipo: 'ia_assumir' }, 'p10', t)).toEqual({
      id: 'p10',
      tipo: 'ia_assumir',
      agente_id: null,
    });
  });

  // G66: sem escolha; a conversa vai para quem cuida do card na hora.
  it('monta o "Passar a conversa para o responsável do card" só com id e tipo', () => {
    expect(novoPasso({ tipo: 'conversa_ao_responsavel' }, 'p11', t)).toEqual({
      id: 'p11',
      tipo: 'conversa_ao_responsavel',
    });
  });

  it('mostra status pela opção, não pelo valor gravado', () => {
    const condicao = {
      campo: { $valor: 'conversa.status' },
      op: 'igual',
      valor: 'open',
    };
    expect(fraseDaCondicao(condicao, CATALOGO, t)).toContain(
      '"valor":"ABERTA"'
    );
  });

  describe('frase do passo de etiqueta, com o texto de verdade', () => {
    // O t daqui lê o pt_BR e preenche {nome}: a frase sai como a pessoa vê.
    const textoDe = chave =>
      chave.split('.').reduce((no, parte) => no?.[parte], pt);
    const tReal = (chave, valores = {}) =>
      Object.entries(valores).reduce(
        (texto, [nome, valor]) => texto.replaceAll(`{${nome}}`, valor),
        textoDe(chave) ?? chave
      );
    const etiquetas = corpo => ({
      id: 'p1',
      tipo: 'acao',
      acao: 'PATCH conversations/:conversation_id/labels/alterar',
      descricao: 'x',
      corpo,
    });

    it.each([
      [{ por: ['billing'] }, 'Pôr a etiqueta billing na conversa'],
      [{ tirar: ['lead'] }, 'Tirar a etiqueta lead da conversa'],
      [
        { por: ['vip', 'lead', 'billing'] },
        'Pôr as etiquetas vip, lead e billing na conversa',
      ],
      [
        { por: ['billing'], tirar: ['lead'] },
        'Na conversa, pôr billing e tirar lead',
      ],
      [{}, 'ETIQUETAS'],
    ])('%j vira "%s"', (corpo, frase) => {
      expect(fraseDoPasso(etiquetas(corpo), CATALOGO, tReal)).toBe(frase);
    });
  });

  describe('frase de esperar, mensagem e avisar, com o texto de verdade', () => {
    const textoDe = chave =>
      chave.split('.').reduce((no, parte) => no?.[parte], pt);
    // Plural do vue-i18n: "1 time | {n} times".
    const tReal = (chave, valores, n) => {
      const formas = (textoDe(chave) ?? chave).split(' | ');
      const forma = n === undefined || n === 1 ? formas[0] : formas.at(-1);
      return Object.entries(valores || {}).reduce(
        (texto, [nome, valor]) => texto.replaceAll(`{${nome}}`, valor),
        forma
      );
    };
    const catalogo = {
      ...CATALOGO,
      valores: [
        {
          caminho: 'contato.nome',
          frase: 'AUTOMACAO_LIVRE.VALORES.CONTATO_NOME',
        },
      ],
      passos: [
        ...CATALOGO.passos,
        { tipo: 'mensagem', frase: 'M', campos: [] },
        { tipo: 'avisar', frase: 'A', campos: [] },
      ],
    };
    const nome = textoDe('AUTOMACAO_LIVRE.VALORES.CONTATO_NOME');

    it.each([
      [1, 'minutos', 'Esperar 1 minuto'],
      [2, 'minutos', 'Esperar 2 minutos'],
      [1, 'horas', 'Esperar 1 hora'],
      [2, 'horas', 'Esperar 2 horas'],
      [1, 'dias', 'Esperar 1 dia'],
      [2, 'dias', 'Esperar 2 dias'],
    ])('esperar %i %s vira "%s"', (valor, unidade, frase) => {
      const comUnidades = {
        ...catalogo,
        unidades: ['minutos', 'horas', 'dias'].map(item => ({
          valor: item,
          frase: `AUTOMACAO_LIVRE.UNIDADES.${item.toUpperCase()}`,
        })),
      };
      const passo = { id: 'p1', tipo: 'esperar', duracao: { valor, unidade } };
      expect(fraseDoPasso(passo, comUnidades, tReal)).toBe(frase);
    });

    it('mensagem mostra o texto com o dado entre colchetes', () => {
      expect(fraseDoPasso(MENSAGEM, catalogo, tReal)).toBe(
        `Mandar ao cliente: “Oi [${nome}], seu pedido saiu.”`
      );
    });

    it('avisar diz quem e o texto; texto longo corta', () => {
      const passo = { ...AVISAR, texto: ['x'.repeat(80)] };
      expect(fraseDoPasso(passo, catalogo, tReal)).toBe(
        `Avisar quem cuida da conversa, 1 time e 2 pessoas: “${'x'.repeat(60)}…”`
      );
    });

    it('avisar sem texto diz o que falta', () => {
      const passo = { id: 'p1', tipo: 'avisar', texto: [], para: {} };
      expect(fraseDoPasso(passo, catalogo, tReal)).toBe(
        'Avisar a equipe: “falta escrever o texto”'
      );
    });

    // #2500 — passo de IA ainda sem pergunta ou instrução diz o que falta,
    // sem aspas vazias.
    const comIa = {
      ...catalogo,
      passos: [
        ...catalogo.passos,
        ...['decidir', 'escrever'].map(tipo => ({ tipo, grupo: 'IA' })),
      ],
    };
    it.each([
      [
        { pergunta: '', caminhos: [{}, {}] },
        'A IA decide o caminho: falta escrever a pergunta (2 caminhos)',
      ],
      [
        { pergunta: '   ', caminhos: [{}, {}] },
        'A IA decide o caminho: falta escrever a pergunta (2 caminhos)',
      ],
      [
        { pergunta: 'O que o cliente quer?', caminhos: [{}, {}] },
        'A IA decide: “O que o cliente quer?” (2 caminhos)',
      ],
    ])('decidir %j vira "%s"', (campos, frase) => {
      const passo = { id: 'p1', tipo: 'decidir', ...campos };
      expect(fraseDoPasso(passo, comIa, tReal)).toBe(frase);
    });

    it.each([
      [
        'mensagem',
        'A IA escreve e manda ao cliente: falta escrever a instrução',
      ],
      [
        'sugestao',
        'A IA escreve uma sugestão para a equipe: falta escrever a instrução',
      ],
    ])('escrever para %s sem instrução diz o que falta', (destino, frase) => {
      const passo = { id: 'p1', tipo: 'escrever', instrucao: '', destino };
      expect(fraseDoPasso(passo, comIa, tReal)).toBe(frase);
    });
  });
});
