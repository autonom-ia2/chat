// Respostas FALSAS de "Criar com IA" e "Melhorar com IA", só para o protótipo.
// O texto aqui é fixo, por objetivo e por tom: quem entende o pedido de verdade
// será o modelo de linguagem no backend. Nada aqui lê o que a pessoa escreveu
// (regra do Rodrigo: sem lista de palavras nem expressão regular); só usa campos
// com estrutura (tom, pedido, objetivo, tipo e onde ficam os campos no texto).
//
// Demonstração do erro: ?demo=ia_erro.

const LATENCIA_MS = 2000;

const texto = v => ({ t: 'texto', v });
const campo = v => ({ t: 'campo', v });

const cenario = () =>
  new URLSearchParams(window.location.search).get('demo') || '';

export const responderDepois = valor =>
  new Promise((resolve, reject) => {
    setTimeout(() => {
      if (cenario() === 'ia_erro') {
        reject(new Error('ia_indisponivel'));
        return;
      }
      resolve(JSON.parse(JSON.stringify(valor)));
    }, LATENCIA_MS);
  });

const exemplosPadrao = {
  nome_cliente: 'Ana',
  data: '15/10',
  horario: '14h30',
  desconto: '20%',
  link: 'hub2you.com.br/ofertas',
};

const comExemplos = pedacos =>
  Object.fromEntries(
    pedacos
      .filter(pedaco => pedaco.t === 'campo')
      .map(pedaco => [pedaco.v, exemplosPadrao[pedaco.v] || ''])
  );

// Três jeitos de dizer, por tom. Cada lote de "Gerar outras" troca a ordem.
const OPCOES_POR_TOM = {
  curto: [
    {
      tipo: 'aviso',
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto('. Seu horário é dia '),
        campo('data'),
        texto(', às '),
        campo('horario'),
        texto('. Confirma?'),
      ],
      botoes: [{ tipo: 'resposta', texto: 'Confirmo', valor: '' }],
    },
    {
      tipo: 'divulgacao',
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto('! Só até '),
        campo('data'),
        texto(': '),
        campo('desconto'),
        texto(' de desconto. Quer ver?'),
      ],
      botoes: [
        {
          tipo: 'site',
          texto: 'Ver ofertas',
          valor: 'https://hub2you.com.br/ofertas',
        },
      ],
    },
    {
      tipo: 'aviso',
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto('. Seu pedido foi atualizado. Qualquer dúvida, é só responder.'),
      ],
      botoes: [],
    },
  ],
  simpatico: [
    {
      tipo: 'aviso',
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto('! Tudo bem? Passando para lembrar do seu horário no dia '),
        campo('data'),
        texto(', às '),
        campo('horario'),
        texto('. Podemos confirmar? 😊'),
      ],
      botoes: [
        { tipo: 'resposta', texto: 'Confirmo', valor: '' },
        { tipo: 'resposta', texto: 'Preciso remarcar', valor: '' },
      ],
    },
    {
      tipo: 'divulgacao',
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto('! Separamos uma surpresa: '),
        campo('desconto'),
        texto(' de desconto até '),
        campo('data'),
        texto('. Vem aproveitar com a gente?'),
      ],
      botoes: [
        {
          tipo: 'site',
          texto: 'Quero ver',
          valor: 'https://hub2you.com.br/ofertas',
        },
      ],
    },
    {
      tipo: 'aviso',
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto(
          '! Que bom falar com você. Ficou alguma dúvida do seu atendimento? É só responder aqui.'
        ),
      ],
      botoes: [{ tipo: 'resposta', texto: 'Tenho uma dúvida', valor: '' }],
    },
  ],
  formal: [
    {
      tipo: 'aviso',
      texto: [
        texto('Prezado(a) '),
        campo('nome_cliente'),
        texto(', confirmamos seu atendimento em '),
        campo('data'),
        texto(', às '),
        campo('horario'),
        texto('. Por gentileza, confirme sua presença.'),
      ],
      botoes: [
        { tipo: 'resposta', texto: 'Confirmo', valor: '' },
        { tipo: 'resposta', texto: 'Remarcar', valor: '' },
      ],
    },
    {
      tipo: 'divulgacao',
      texto: [
        texto('Prezado(a) '),
        campo('nome_cliente'),
        texto(', informamos uma condição especial de '),
        campo('desconto'),
        texto(' válida até '),
        campo('data'),
        texto('. Consulte os detalhes.'),
      ],
      botoes: [
        {
          tipo: 'site',
          texto: 'Ver condições',
          valor: 'https://hub2you.com.br/ofertas',
        },
      ],
    },
    {
      tipo: 'aviso',
      texto: [
        texto('Prezado(a) '),
        campo('nome_cliente'),
        texto(
          ', seu cadastro foi atualizado com sucesso. Em caso de dúvida, responda esta mensagem.'
        ),
      ],
      botoes: [],
    },
  ],
};

let lote = 0;

// criarComIA({ objetivo, tom, numeros }) → { opcoes: [Opcao] } (2 ou 3).
// Opcao = { id, nome, tipo, conteudo: { formato, topo, texto, exemplos,
//   rodape, botoes } }. `nome` usa a frase da pessoa como está.
export const criarComIA = ({ objetivo, tom }) => {
  lote += 1;
  const base = OPCOES_POR_TOM[tom] || OPCOES_POR_TOM.simpatico;
  const quantas = lote % 2 === 0 ? 2 : 3;
  const giradas = [
    ...base.slice(lote % base.length),
    ...base.slice(0, lote % base.length),
  ];
  const nome = String(objetivo || '')
    .trim()
    .slice(0, 60);
  return responderDepois({
    opcoes: giradas.slice(0, quantas).map((opcao, indice) => ({
      id: `ia-${lote}-${indice}`,
      nome,
      tipo: opcao.tipo,
      conteudo: {
        formato: 'padrao',
        topo: { tipo: 'nenhum', arquivo: '' },
        texto: opcao.texto,
        exemplos: comExemplos(opcao.texto),
        rodape: '',
        botoes: opcao.botoes,
      },
    })),
  });
};

// Objetivos que são divulgação por natureza (oferta, boas-vindas, retomar):
// "manter como aviso" não dá, e a tela diz o custo sem disfarçar.
const OBJETIVOS_DE_DIVULGACAO = [
  'promocao',
  'boas_vindas',
  'retomar',
  'carrossel',
  'oferta',
  'catalogo',
];

const primeiroCampo = pedacos =>
  pedacos.find(pedaco => pedaco.t === 'campo')?.v || 'nome_cliente';

// melhorarComIA({ texto, pedido, objetivo, tipo }) → { texto, tipo,
//   continuaDivulgacao } — `pedido`: 'mais_curto' | 'mais_claro' |
//   'manter_aviso' | 'corrigir_recusa'. `continuaDivulgacao`: pediu aviso,
//   mas o conteúdo é divulgação.
export const melhorarComIA = ({ texto: atual, pedido, objetivo, tipo }) => {
  const nome = primeiroCampo(atual);
  const respostas = {
    mais_curto: () => ({
      texto: [
        texto('Oi, '),
        campo(nome),
        texto('! Tudo certo? Responda aqui se precisar.'),
      ],
      tipo,
    }),
    mais_claro: () => ({
      texto: [
        texto('Olá, '),
        campo(nome),
        texto(
          '. Esta mensagem é da Hub2you. Se tiver qualquer dúvida, responda aqui que a gente ajuda.'
        ),
      ],
      tipo,
    }),
    manter_aviso: () =>
      OBJETIVOS_DE_DIVULGACAO.includes(objetivo) || tipo === 'divulgacao'
        ? { texto: atual, tipo: 'divulgacao', continuaDivulgacao: true }
        : {
            texto: [
              texto('Olá, '),
              campo(nome),
              texto(
                '. Temos uma atualização sobre o seu atendimento. Responda aqui se precisar.'
              ),
            ],
            tipo: 'aviso',
          },
    corrigir_recusa: () => {
      const pedacos = atual.filter(
        pedaco => pedaco.t === 'campo' || pedaco.v.trim()
      );
      const comeco = pedacos[0]?.t === 'campo' ? [texto('Olá, ')] : [];
      const fim =
        pedacos[pedacos.length - 1]?.t === 'campo'
          ? [texto('. Qualquer dúvida, é só responder.')]
          : [];
      return { texto: [...comeco, ...atual, ...fim], tipo };
    },
  };
  const resposta = (respostas[pedido] || respostas.mais_claro)();
  return responderDepois({
    ...resposta,
    exemplos: comExemplos(resposta.texto),
  });
};
