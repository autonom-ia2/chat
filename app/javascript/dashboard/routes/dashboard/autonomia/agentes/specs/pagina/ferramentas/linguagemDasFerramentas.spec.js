import {
  MASCARA_DO_SEGREDO,
  PASSOS,
  conferirEndereco,
  corpoPadrao,
  destinoMudou,
  enderecoDaTela,
  enderecoNaTela,
  enderecoLegivel,
  inserirNoCursor,
  mudarRotulo,
  novaInformacao,
  paraApi,
  paraRascunho,
  passosProvaveisDoErro,
  rascunhoVazio,
  validarPasso,
  valorFixo,
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

      expect(inserirNoCursor(link, 25, '[CEP]')).toEqual({
        texto: 'https://viacep.com.br/ws/[CEP]/json/',
        cursor: 30,
      });
      expect(inserirNoCursor('https://a.com/', null, '[CEP]').texto).toBe(
        'https://a.com/[CEP]'
      );
      expect(inserirNoCursor('https://a.com/xx/', 14, '[CEP]', 16)).toEqual({
        texto: 'https://a.com/[CEP]/',
        cursor: 19,
      });
    });

    // Pedido da coordenadora (09/11): o campo nunca mostra {{ }}. Mostra [CEP]; ao salvar, volta a {{cep}}.
    it('shows the link field with [label] and turns it back into {{name}}', () => {
      const numero = {
        ...novaInformacao(),
        rotulo: 'Número do pedido',
        nome: 'numero_do_pedido',
      };
      const salvo =
        'https://a.com/{{cep}}/p/{{ numero_do_pedido | url_encode }}?x={{solta}}';

      const naTela = enderecoNaTela(salvo, [cep, numero]);

      expect(naTela).toBe('https://a.com/[CEP]/p/[Número do pedido]?x=[solta]');
      expect(enderecoDaTela(naTela, [cep, numero], salvo)).toBe(
        'https://a.com/{{cep}}/p/{{numero_do_pedido}}?x={{solta}}'
      );
    });

    // Revisão do delta: colchete que já é do link (filter[status]) nunca vira informação na volta.
    it('keeps a bracket that belongs to the link itself', () => {
      const status = { ...novaInformacao(), rotulo: 'Status', nome: 'status' };
      const salvo = 'https://a.com/?filter[status]=open&q={{status}}';

      const naTela = enderecoNaTela(salvo, [status]);

      expect(naTela).toBe('https://a.com/?filter[status]=open&q=[Status]');
      expect(enderecoDaTela(naTela, [status], salvo)).toBe(salvo);

      const igual = { ...status, rotulo: 'status' };
      const ambiguo = enderecoNaTela(salvo, [igual]);
      expect(ambiguo).toBe('https://a.com/?filter%5Bstatus%5D=open&q=[status]');
      expect(enderecoDaTela(ambiguo, [igual], salvo)).toBe(
        'https://a.com/?filter%5Bstatus%5D=open&q={{status}}'
      );
    });

    it('step 2 refuses brackets and repeated labels', () => {
      const pedido = { ...cep, id: 'p', rotulo: 'Pedido [nº]', nome: 'pedido' };
      const outro = { ...cep, id: 'o', rotulo: 'cep ', nome: 'cep_entrega' };

      expect(
        validarPasso(2, { ...rascunhoVazio(), informacoes: [pedido] }).erros
      ).toEqual({ i0: 'COLCHETE' });
      expect(
        validarPasso(2, { ...rascunhoVazio(), informacoes: [cep, outro] }).erros
      ).toEqual({ i0: 'REPETIDO', i1: 'REPETIDO' });
    });

    it('keeps brackets that are not information, and other filters raw', () => {
      expect(enderecoDaTela('https://a.com/[1]/[CEP]', [cep], '')).toBe(
        'https://a.com/[1]/{{cep}}'
      );
      expect(enderecoNaTela('https://a.com/{{ cep | upcase }}', [cep])).toBe(
        'https://a.com/{{ cep | upcase }}'
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

  // Decisão do Rodrigo (09/11, repassada): a chave guardada não vai para link nem método novos, e senha não fica no link.
  describe('chave de acesso e link', () => {
    const salva = paraRascunho({
      http_method: 'GET',
      endpoint_url: 'https://api.loja.com/leads',
      headers_config: [
        { key: 'x-api-key', value: MASCARA_DO_SEGREDO, secret: true },
      ],
    });

    it('asks for the key again when the link or the method changes', () => {
      expect(destinoMudou(salva)).toBe(false);
      expect(
        destinoMudou({ ...salva, endereco: 'https://api.loja.com/persons' })
      ).toBe(true);
      expect(destinoMudou({ ...salva, metodo: 'POST' })).toBe(true);
      expect(destinoMudou(rascunhoVazio())).toBe(false);
      expect(
        validarPasso(4, { ...salva, endereco: 'https://api.loja.com/persons' })
          .erros
      ).toEqual({ c0: 'REDIGITAR' });
      expect(validarPasso(4, salva).erros).toEqual({});
    });

    it('never sends the stored key to a new link', () => {
      const enviado = paraApi({
        ...salva,
        nome: 'X',
        endereco: 'https://api.loja.com/persons',
      });

      expect(enviado.headers_config).toEqual([
        { key: 'x-api-key', value: '', secret: true },
      ]);
    });

    it('refuses a password in the link, by the URL parser and a list of names', () => {
      expect(conferirEndereco('https://a.com/x?token=abc')).toBe('SENHA');
      expect(conferirEndereco('https://a.com/x?API_KEY=abc&q=1')).toBe('SENHA');
      expect(conferirEndereco('https://ana:segredo@a.com/x')).toBe('SENHA');
      expect(conferirEndereco('https://a.com/x?token={{t}}')).toBe('');
      expect(
        conferirEndereco('https://a.com/x?keyword=pastilha&author=1')
      ).toBe('');
    });

    it('asks for the key again when what goes with the call changes', () => {
      const post = paraRascunho({
        http_method: 'POST',
        endpoint_url: 'https://api.loja.com/graphql',
        request_body_template: '{"query":"{ pedido }"}',
        headers_config: [
          { key: 'x-api-key', value: MASCARA_DO_SEGREDO, secret: true },
          { key: 'x-loja', value: '7', secret: false },
        ],
      });
      const comum = c =>
        c.chave === 'x-loja' ? { ...c, valor: '8' } : { ...c };

      expect(destinoMudou(post)).toBe(false);
      expect(destinoMudou({ ...post, corpo: '{"query":"{ clientes }"}' })).toBe(
        true
      );
      expect(
        destinoMudou({ ...post, cabecalhos: post.cabecalhos.map(comum) })
      ).toBe(true);
      expect(
        destinoMudou({
          ...post,
          cabecalhos: [
            ...post.cabecalhos,
            { chave: 'X-HTTP-Method-Override', valor: 'DELETE' },
          ],
        })
      ).toBe(true);
    });

    it('keeps only fixed text when it looks for a password in the link', () => {
      expect(valorFixo('{{t}}')).toBe('');
      expect(valorFixo('{{ t | url_encode }}')).toBe('');
      expect(valorFixo('abc{{t}}')).toBe('abc');
      expect(valorFixo('{{ "abc" }}')).toBe(' "abc" ');
      expect(valorFixo('{{ t | append: "x" }}')).toBe(' t | append: "x" ');
      [
        'https://a.com/x?api_token=abc',
        'https://a.com/x?token[]=abc',
        'https://a.com/x?client_secret=abc',
        'https://a.com/x?api_key=abc{{t}}',
        'https://a.com/x?token={{ "abc" }}',
      ].forEach(link => expect(conferirEndereco(link)).toBe('SENHA'));
      expect(
        conferirEndereco('https://a.com/x?token={{ t | url_encode }}')
      ).toBe('');
    });

    it('counts a new secret header as a new call and refuses repeated names', () => {
      const salva2 = paraRascunho({
        http_method: 'POST',
        endpoint_url: 'https://api.loja.com/leads',
        headers_config: [
          { key: 'x-api-key', value: MASCARA_DO_SEGREDO, secret: true },
        ],
      });
      const override = {
        ...salva2,
        cabecalhos: [
          ...salva2.cabecalhos,
          { chave: 'X-HTTP-Method-Override', valor: 'DELETE', segredo: true },
        ],
      };
      const repetido = {
        ...salva2,
        cabecalhos: [
          { chave: 'x-api-key', valor: 'lixo', segredo: true },
          ...salva2.cabecalhos,
        ],
      };

      expect(destinoMudou(override)).toBe(true);
      expect(validarPasso(4, repetido).erros.c1).toBe('REPETIDO');
      expect(conferirEndereco('https://a.com/x?{{ "token" }}=abc')).toBe(
        'SENHA'
      );
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
