import {
  PASSOS,
  corpoPadrao,
  enderecoLegivel,
  inserirInformacao,
  mudarRotulo,
  novaInformacao,
  paraApi,
  paraRascunho,
  passosProvaveisDoErro,
  rascunhoVazio,
  validarPasso,
} from '../../../utils/ferramentas';
import {
  passoDaCorrecao,
  respostaDeixaDeFora,
  respostaLegivel,
} from '../../../utils/testeDaFerramenta';
import ptBR from 'dashboard/i18n/locale/pt_BR/agents.json';

// #1430 (decisão do Rodrigo, 09/11: "1A 2 recomendado") — o assistente fala a língua de quem usa: a
// pessoa diz primeiro o que o agente descobre na conversa (com nome de gente, "CEP") e depois cola o
// link e toca na informação para encaixar. Nada de GET/POST, corpo, cabeçalho ou chaves duplas na tela.

const cep = { ...novaInformacao(), rotulo: 'CEP', nome: 'cep' };

describe('linguagem das Ferramentas (#1430)', () => {
  it('asks what the agent finds out before the link', () => {
    expect(PASSOS).toEqual([
      'O_QUE_FAZ',
      'PREENCHE',
      'PARA_ONDE',
      'COMO_ENTRA',
    ]);
  });

  describe('informação com nome de gente', () => {
    it('derives the technical name from the label while the card is new', () => {
      const info = mudarRotulo(novaInformacao(), 'Número do pedido');

      expect(info.rotulo).toBe('Número do pedido');
      expect(info.nome).toBe('numero_do_pedido');
      expect(mudarRotulo(info, '').nome).toBe('');
    });

    it('keeps the saved technical name, so the link keeps working', () => {
      const salva = paraRascunho({
        param_schema: [{ name: 'cep', type: 'string', label: 'CEP' }],
      }).informacoes[0];

      const renomeada = mudarRotulo(salva, 'CEP do cliente');

      expect(renomeada.nome).toBe('cep');
      expect(renomeada.rotulo).toBe('CEP do cliente');
    });

    it('shows the technical name when an old tool has no label', () => {
      const antiga = paraRascunho({
        param_schema: [{ name: 'termo_busca', type: 'string' }],
      }).informacoes[0];

      expect(antiga.rotulo).toBe('termo_busca');
    });

    it('sends the label to the API', () => {
      const rascunho = {
        ...rascunhoVazio(),
        nome: 'CEP',
        endereco: 'https://viacep.com.br/ws/{{cep}}/json/',
        informacoes: [cep],
      };

      expect(paraApi(rascunho).param_schema[0]).toMatchObject({
        name: 'cep',
        label: 'CEP',
      });
    });

    it('step 2 checks the label and repeated names', () => {
      const vazia = { ...rascunhoVazio(), informacoes: [novaInformacao()] };
      const repetida = {
        ...rascunhoVazio(),
        informacoes: [cep, { ...cep, id: 'outro', rotulo: 'Cep' }],
      };

      expect(validarPasso(2, vazia).erros).toEqual({ i0: 'VAZIO' });
      expect(validarPasso(2, repetida).erros).toEqual({
        i0: 'REPETIDO',
        i1: 'REPETIDO',
      });
    });

    it('step 3 checks the link', () => {
      expect(validarPasso(3, rascunhoVazio()).erros).toEqual({
        endereco: 'VAZIO',
      });
    });
  });

  describe('link com a informação encaixada', () => {
    it('puts the information where the cursor is', () => {
      const link = 'https://viacep.com.br/ws//json/';

      expect(inserirInformacao(link, 25, 'cep')).toBe(
        'https://viacep.com.br/ws/{{cep}}/json/'
      );
      expect(inserirInformacao('https://a.com/', null, 'cep')).toBe(
        'https://a.com/{{cep}}'
      );
    });

    it('reads the link with the label in brackets', () => {
      expect(
        enderecoLegivel('https://viacep.com.br/ws/{{ cep }}/json/?x={{y}}', [
          cep,
        ])
      ).toBe('https://viacep.com.br/ws/[CEP]/json/?x=[y]');
    });

    it('builds what goes along when the tool sends information', () => {
      const qtd = {
        ...novaInformacao(),
        rotulo: 'Qtd',
        nome: 'qtd',
        tipo: 'integer',
      };
      const talvez = { ...qtd, nome: 'talvez', podeFaltar: true };

      expect(
        JSON.parse(corpoPadrao([cep, qtd, talvez]).split('{{qtd}}').join('1'))
      ).toEqual({
        cep: '{{cep}}',
        qtd: 1,
        talvez: '{{talvez}}',
      });
      expect(corpoPadrao([])).toBe('');
    });

    it('opens the right step after the order changed', () => {
      expect(passosProvaveisDoErro(['endpoint_url'])).toEqual([3]);
      expect(passosProvaveisDoErro(['param_schema'])).toEqual([2]);
      expect(passosProvaveisDoErro(['headers_config', 'slug'])).toEqual([3, 4]);
      expect(passosProvaveisDoErro(['name'])).toEqual([2, 3]);
      expect(passoDaCorrecao('ENDERECO')).toBe(3);
      expect(passoDaCorrecao('PREENCHE')).toBe(2);
      expect(passoDaCorrecao('ONDE')).toBe(3);
      expect(passoDaCorrecao('CHAVE')).toBe(4);
    });
  });

  describe('resposta do teste em linhas de gente', () => {
    it('lists the filled top-level fields with a readable name', () => {
      const corpo = JSON.stringify({
        cep: '01001-000',
        logradouro: 'Praça da Sé',
        complemento: '',
        nomeDaCidade: 'São Paulo',
        siafi: 7107,
        ativo: true,
        endereco: { rua: 'x' },
      });

      expect(respostaLegivel(corpo)).toEqual([
        [
          { rotulo: 'Cep', valor: '01001-000' },
          { rotulo: 'Logradouro', valor: 'Praça da Sé' },
          { rotulo: 'Nome da cidade', valor: 'São Paulo' },
          { rotulo: 'Siafi', valor: '7107' },
          { rotulo: 'Ativo', valor: 'sim' },
        ],
      ]);
    });

    it('shows one group per item of a list, up to five', () => {
      const lista = Array.from({ length: 7 }, (_, i) => ({
        nome_peca: `P${i}`,
      }));

      const grupos = respostaLegivel(JSON.stringify(lista));

      expect(grupos).toHaveLength(5);
      expect(grupos[0]).toEqual([{ rotulo: 'Nome peca', valor: 'P0' }]);
    });

    it('opens a list wrapped in an object, as many systems answer', () => {
      const corpo = JSON.stringify({
        itens: [{ nome: 'Pastilha', preco: 89.9 }],
      });

      expect(respostaLegivel(corpo)).toEqual([
        [
          { rotulo: 'Nome', valor: 'Pastilha' },
          { rotulo: 'Preco', valor: '89.9' },
        ],
      ]);
    });

    it('keeps acronyms as they come', () => {
      const corpo = JSON.stringify({
        CEP: '1',
        UF: 'SP',
        NOME_COMPLETO: 'Ana',
        nomeDaMae: 'Bia',
      });

      expect(respostaLegivel(corpo)[0].map(c => c.rotulo)).toEqual([
        'CEP',
        'UF',
        'NOME COMPLETO',
        'Nome da mae',
      ]);
    });

    it('says when the lines leave something out, so the details open', () => {
      expect(respostaDeixaDeFora('{"cep":"1","uf":"SP"}')).toBe(false);
      expect(respostaDeixaDeFora('{"itens":[{"a":1}]}')).toBe(false);
      expect(respostaDeixaDeFora('{"total":3,"itens":[{"a":1}]}')).toBe(true);
      expect(respostaDeixaDeFora('{"itens":[{"a":{"b":1}}]}')).toBe(true);
      expect(respostaDeixaDeFora(JSON.stringify(Array(6).fill({ a: 1 })))).toBe(
        true
      );
      expect(respostaDeixaDeFora('texto')).toBe(false);
    });

    it('gives up on text or nothing readable, and the screen shows it as it came', () => {
      expect(respostaLegivel('Rua X, 10')).toBeNull();
      expect(respostaLegivel('{"a":{"b":1}}')).toBeNull();
    });
  });

  it('keeps technical words out of the steps a person goes through', () => {
    const passos = ptBR.AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS;
    const teste = ptBR.AGENTS.JORNADA.PAGINA.FERRAMENTAS.TESTE;
    const textos = [
      ...Object.values(passos.NOMES),
      ...Object.values(passos.DOIS).filter(v => typeof v === 'string'),
      passos.TRES.INTRO,
      passos.TRES.NOME,
      passos.TRES.NOME_AJUDA,
      ...Object.values(passos.QUATRO).filter(v => typeof v === 'string'),
      teste.PRECISA,
      teste.REAL,
      teste.RECEBE,
      teste.VER_DETALHES,
    ];
    const tecnicas = [
      'GET',
      'POST',
      'corpo',
      'cabeçalho',
      'Content-Type',
      'JSON',
      '{{',
      'chaves duplas',
    ];

    textos.forEach(texto => {
      tecnicas.forEach(palavra => expect(texto).not.toContain(palavra));
    });
  });
});
