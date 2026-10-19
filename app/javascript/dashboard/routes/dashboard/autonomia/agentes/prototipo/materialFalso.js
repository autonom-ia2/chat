// #1426/#1427 — ADAPTADOR FALSO do mockup dos temas 4 e 5. Mesmas funções que a API vai ter, com
// dados em memória (somem no F5, de propósito: a demonstração recomeça igual). Quem usa importa
// ./fonteMaterial.js, nunca este arquivo.
//
// Sem relógio próprio: cada material tem um ROTEIRO (o que muda e quando, em ms desde que entrou) e
// cada leitura aplica o que já passou. Assim a tela vê a mudança pela releitura, como verá na API
// de verdade (a reprovação chega sem recarregar), e o spec controla o tempo pelo `agora`.
// Não interpreta texto: a resposta do Testar é sempre um dos exemplos fixos.

const PAGINAS_DO_CATALOGO = 80;
const PASSO_DE_PAGINAS = 8;
const PASSO_MS = 1200;
const REVISAO_MS = 4000;
const PERGUNTA_DO_AUTOTESTE_MS = 700;
const PERGUNTAS_DO_MATERIAL = 8;
const PERGUNTAS_DE_FORA = 2;

const revisado = (status = 'accepted') => ({
  status,
  reviewed_at: '2026-10-19T12:00:00Z',
});

// O catálogo grande (4c): lê de 8 em 8 páginas, revisa e só então fica pronto.
const roteiroDeLeitura = (paginas, unidade = 'pagina') => {
  const passos = Math.ceil(paginas / PASSO_DE_PAGINAS);
  const leitura = Array.from({ length: passos }, (_, i) => ({
    em: (i + 1) * PASSO_MS,
    progresso: {
      feito: Math.min((i + 1) * PASSO_DE_PAGINAS, paginas),
      total: paginas,
      unidade,
    },
  }));
  const lido = (passos + 1) * PASSO_MS;
  return [
    ...leitura,
    { em: lido, status: 'ready', progresso: null, review: { status: null } },
    { em: lido + REVISAO_MS, review: revisado(), baseMudou: true },
  ];
};

const materiaisIniciais = () => [
  {
    id: 1,
    source_type: 'pdf',
    reference: 'cardapio-outubro.pdf',
    status: 'ready',
    review: revisado(),
  },
  {
    id: 2,
    source_type: 'link',
    reference: 'www.lanchesdabia.com.br',
    status: 'ready',
    review: revisado(),
  },
  // 4a — foto mandada na criação também vira base: o texto dela é lido (OCR) e revisado.
  {
    id: 3,
    source_type: 'foto',
    reference: 'tabela-de-precos.jpg',
    status: 'ready',
    review: revisado('needs_resend'),
  },
  {
    id: 4,
    source_type: 'pdf',
    reference: 'horarios.pdf',
    status: 'ready',
    review: revisado(),
  },
  {
    id: 5,
    source_type: 'pdf',
    reference: 'horarios (1).pdf',
    status: 'ready',
    review: revisado(),
  },
  // 4a — a reprovação chega depois de "lido", sem recarregar a página.
  {
    id: 6,
    source_type: 'xlsx',
    reference: 'precos-bebidas.xlsx',
    status: 'ready',
    review: { status: null },
    roteiro: [{ em: 5000, review: revisado('needs_resend') }],
  },
  {
    id: 7,
    source_type: 'pdf',
    reference: 'catalogo-completo.pdf',
    status: 'processing',
    progresso: { feito: 0, total: PAGINAS_DO_CATALOGO, unidade: 'pagina' },
    review: { status: null },
    roteiro: roteiroDeLeitura(PAGINAS_DO_CATALOGO),
  },
  {
    id: 8,
    source_type: 'pdf',
    reference: 'ficha-de-pedido.pdf',
    status: 'ready',
    review: revisado('needs_resend'),
  },
];

// 4b — as conferências. Cada uma aponta os materiais envolvidos (`fontes`) e o que dá para fazer.
const problemasIniciais = () => [
  {
    id: 'vazio-8',
    tipo: 'vazio',
    fontes: [8],
    nome: 'ficha-de-pedido.pdf',
  },
  {
    id: 'ocr-3',
    tipo: 'ocr',
    fontes: [3],
    nome: 'tabela-de-precos.jpg',
  },
  {
    id: 'duplicado-4-5',
    tipo: 'duplicado',
    fontes: [4, 5],
    nome: 'horarios.pdf',
    outro: 'horarios (1).pdf',
    manter: 4,
    tirar: 5,
  },
  {
    id: 'contradicao-2-4',
    tipo: 'contradicao',
    fontes: [2, 4],
    assunto: 'horário de sábado',
    opcoes: [
      { valor: 2, onde: 'www.lanchesdabia.com.br', diz: 'das 9h às 13h' },
      { valor: 4, onde: 'horarios.pdf', diz: 'das 9h às 12h' },
    ],
  },
  {
    id: 'autoteste-1',
    tipo: 'autoteste',
    fontes: [],
    pergunta: 'Vocês entregam no Centro?',
    resposta: 'Não fazemos entregas, só retirada no balcão.',
    material:
      'cardapio-outubro.pdf diz: "Entregamos no Centro e na Vila Nova."',
  },
];

// Aparecem quando a revisão termina (roteiro do material 6).
const problemasDoRoteiro = {
  6: {
    id: 'cabecalho-6',
    tipo: 'sem_cabecalho',
    fontes: [6],
    nome: 'precos-bebidas.xlsx',
    amostra: ['Coca 350', '6,00', '12', 'S'],
  },
};

const PERGUNTAS = [
  { pergunta: 'Quanto custa o X-Burger?', origem: 'material', ok: true },
  { pergunta: 'Vocês abrem no domingo?', origem: 'material', ok: true },
  { pergunta: 'Tem opção vegetariana?', origem: 'material', ok: true },
  { pergunta: 'Vocês entregam no Centro?', origem: 'material', ok: false },
  {
    pergunta: 'Qual o valor da taxa de entrega?',
    origem: 'material',
    ok: true,
  },
  { pergunta: 'Aceitam Pix?', origem: 'material', ok: true },
  { pergunta: 'O combo vem com refrigerante?', origem: 'material', ok: true },
  { pergunta: 'Até que horas fica aberto?', origem: 'material', ok: true },
  { pergunta: 'Vocês vendem bolo de casamento?', origem: 'fora', ok: true },
  { pergunta: 'Qual a senha do Wi-Fi?', origem: 'fora', ok: true },
];

const RESPOSTA_DA_FOTO =
  'Pela foto, é o nosso X-Salada. Ele custa R$ 27,90 e vem com batata pequena. Quer pedir um?';
const RESPOSTA_PADRAO =
  'Abrimos de segunda a sábado, das 11h às 22h. Posso ajudar em algo mais?';

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export const criarMaterialFalso = ({
  relogio = () => Date.now(),
  espera = 400,
} = {}) => {
  const inicio = relogio();
  let materiais = materiaisIniciais().map(m => ({ ...m, desde: inicio }));
  let problemas = problemasIniciais();
  let proximoId = 100;
  let autoteste = {
    estado: 'pronto',
    quando: 'pedido',
    desde: inicio - 60000,
  };

  const errosDoAutoteste = () =>
    problemas.filter(problema => problema.tipo === 'autoteste').length;

  const resultadoDoAutoteste = () => {
    const erros = errosDoAutoteste();
    return PERGUNTAS.map(item =>
      item.origem === 'material' && !item.ok && !erros
        ? { ...item, ok: true }
        : item
    );
  };

  const rodarAutoteste = quando => {
    autoteste = { estado: 'rodando', quando, desde: relogio() };
  };

  const aplicarRoteiro = agora =>
    materiais.map(material => {
      const passou = (material.roteiro || []).filter(
        passo => passo.em <= agora - material.desde
      );
      if (!passou.length) return material;
      const resto = (material.roteiro || []).slice(passou.length);
      const atualizado = passou.reduce(
        (acc, { em, baseMudou, ...mudanca }) => ({ ...acc, ...mudanca }),
        { ...material, roteiro: resto }
      );
      if (passou.some(passo => passo.baseMudou)) rodarAutoteste('base_mudou');
      const novo = problemasDoRoteiro[material.id];
      if (novo && atualizado.review?.status === 'needs_resend') {
        problemas = [...problemas.filter(p => p.id !== novo.id), novo];
      }
      return atualizado;
    });

  const autotesteAgora = agora => {
    if (autoteste.estado !== 'rodando') return autoteste;
    const feitas = Math.floor(
      (agora - autoteste.desde) / PERGUNTA_DO_AUTOTESTE_MS
    );
    if (feitas < PERGUNTAS.length) return { ...autoteste, feitas };
    autoteste = { ...autoteste, estado: 'pronto' };
    return autoteste;
  };

  const retrato = () => {
    const agora = relogio();
    materiais = aplicarRoteiro(agora);
    const teste = autotesteAgora(agora);
    const resultados = resultadoDoAutoteste();
    return {
      fontes: materiais.map(({ roteiro, desde, ...visivel }) => visivel),
      problemas: [...problemas],
      autoteste: {
        estado: teste.estado,
        quando: teste.quando,
        feitas: teste.estado === 'rodando' ? teste.feitas : PERGUNTAS.length,
        total: PERGUNTAS.length,
        doMaterial: PERGUNTAS_DO_MATERIAL,
        deFora: PERGUNTAS_DE_FORA,
        certasDoMaterial: resultados.filter(
          r => r.origem === 'material' && r.ok
        ).length,
        certasDeFora: resultados.filter(r => r.origem === 'fora' && r.ok)
          .length,
        resultados: teste.estado === 'pronto' ? resultados : [],
      },
    };
  };

  const ler = async () => {
    await esperar(espera);
    return retrato();
  };

  // Arquivo, foto ou site novo: lê em lotes (página por página), revisa e muda a base.
  const enviar = async ({ arquivo, url }) => {
    await esperar(espera);
    proximoId += 1;
    const foto = (arquivo?.type || '').startsWith('image/');
    let tipo = 'pdf';
    if (url) tipo = 'link';
    else if (foto) tipo = 'foto';
    const paginas = foto || url ? 1 : 6;
    materiais = [
      ...materiais,
      {
        id: proximoId,
        source_type: tipo,
        reference: url || arquivo?.name || 'arquivo',
        status: 'processing',
        progresso:
          paginas > 1 ? { feito: 0, total: paginas, unidade: 'pagina' } : null,
        review: { status: null },
        desde: relogio(),
        roteiro: roteiroDeLeitura(paginas),
      },
    ];
    return retrato();
  };

  const tirar = async fonteId => {
    await esperar(espera);
    materiais = materiais.filter(material => material.id !== fonteId);
    problemas = problemas
      .map(problema => ({
        ...problema,
        fontes: problema.fontes.filter(id => id !== fonteId),
      }))
      .filter(
        problema => problema.tipo === 'autoteste' || problema.fontes.length
      );
    rodarAutoteste('base_mudou');
    return retrato();
  };

  // Resolve um problema com a escolha da pessoa. Duplicado "ficar com um só" tira o outro;
  // contradição grava qual vale; o resto só sai da lista (na API, cada um vira a ação dele).
  const resolver = async (problemaId, escolha = null) => {
    await esperar(espera);
    const problema = problemas.find(item => item.id === problemaId);
    problemas = problemas.filter(item => item.id !== problemaId);
    if (problema?.tipo === 'duplicado' && escolha === 'um_so') {
      materiais = materiais.filter(material => material.id !== problema.tirar);
      rodarAutoteste('base_mudou');
    }
    if (problema?.tipo === 'contradicao') rodarAutoteste('base_mudou');
    materiais = materiais.map(material =>
      problema?.fontes.includes(material.id) &&
      material.review?.status === 'needs_resend'
        ? { ...material, review: revisado() }
        : material
    );
    return retrato();
  };

  const pedirAutoteste = async () => {
    await esperar(espera);
    rodarAutoteste('pedido');
    return retrato();
  };

  // Tema 5 — o Testar da página. Mesma forma do `autonomiaAgents/test`. Foto só vale neste turno.
  const testar = async ({ images }) => {
    await esperar(espera * 3);
    return { reply: images?.length ? RESPOSTA_DA_FOTO : RESPOSTA_PADRAO };
  };

  return { ler, enviar, tirar, resolver, pedirAutoteste, testar };
};

export default criarMaterialFalso;
