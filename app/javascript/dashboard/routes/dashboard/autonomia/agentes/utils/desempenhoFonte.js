import { diaDe, pct } from './desempenhoContrato';

// #2226 v2 (desenho §6.1 e §6.5) — de onde o painel de desempenho lê. A tela recebe sempre um Painel
// do contrato v2, venha de onde vier:
//   1. API (#2251, o padrão quando a página passa `api`): `GET .../autonomia/agents/:id/desempenho`
//      devolve o Painel do período, calculado no servidor a partir da leitura guardada no banco. Sem
//      leitura para o agente, vem um painel vazio (`vazio: true`) com a situação `leitura_desligada`;
//      se a chamada falhar, o painel vazio leva o aviso `meta.aviso_fonte = 'api'`. Nunca cai na
//      demonstração em silêncio.
//   2. vida real: o pacote `public/desempenho-vida-real.json`, gerado fora do repositório a partir
//      da leitura das conversas (o arquivo nunca é versionado). Existe só na máquina de quem gerou
//      e só é lido no ambiente de desenvolvimento, quando o endereço pede (`?fonte=vida_real`); se a
//      leitura falhar, a tela mostra a demonstração com o aviso `meta.aviso_fonte`, nunca em
//      silêncio.
//   3. demonstração (`?fonte=demo`, só no desenvolvimento): `desempenhoDemo.json` (loja inventada, 30 dias, com
//      anúncios) e `desempenhoDemoPeriodos.json` (os períodos 7, 90 e tudo, recalculados das mesmas
//      procuras pelo mesmo gerador, para que as partes fechem com o todo em todo período).

export const PERIODOS = ['7', '30', '90', 'tudo'];
export const PERIODO_PADRAO = '30';
export const FONTES = ['vida_real', 'demo'];
const FONTE_API = 'api';
export const FORMATOS = ['pdf', 'xlsx'];

// As situações da tabela 2.11 (mais "pouco", a frase de "ainda é cedo").
export const SITUACOES = [
  'sem_conversas',
  'leitura_desligada',
  'lendo',
  'teto',
  'sem_ia',
  'erro',
  'chave_recusada',
  'sem_resultado',
  'conferencia_baixa',
  'pouco',
];

const ENDERECO_VIDA_REAL = '/desempenho-vida-real.json';
const NOME_NO_ARQUIVO = { vida_real: 'vida-real', demo: 'demo' };
const PERIODO_DA_DEMO = '30';

const periodoValido = periodo =>
  PERIODOS.includes(periodo) ? periodo : PERIODO_PADRAO;

const ehPacote = dado =>
  Boolean(
    dado &&
      dado.versao === 2 &&
      dado.pacote === true &&
      dado.catalogo &&
      Array.isArray(dado.procuras) &&
      dado.periodos
  );

// Painel de um período = o resumo do período + o catálogo + as procuras do período (datas no fuso
// da conta, limites inclusivos). É a mesma regra do `Contrato.do_pacote` do exportador.
export const comporPainel = (pacote, chave) => {
  const resumo = pacote.periodos[chave] || pacote.periodos[PERIODO_PADRAO];
  const { inicio, fim } = resumo.meta.periodo;
  return {
    ...resumo,
    catalogo: pacote.catalogo,
    procuras: pacote.procuras.filter(procura => {
      const dia = diaDe(procura.inicio);
      return dia >= inicio && dia <= fim;
    }),
  };
};

// --- Estado (a) da origem: a mesma demonstração, como se a conta não tivesse anúncio ligado. ---

const somarLinhas = (linhas, base) => {
  const soma = linhas.reduce(
    (acc, linha) => ({
      procuras: acc.procuras + linha.procuras,
      compra: acc.compra + linha.compra,
      fecharam: acc.fecharam + linha.fecharam,
    }),
    { procuras: 0, compra: 0, fecharam: 0 }
  );
  return {
    ...soma,
    pct: pct(soma.procuras, base),
    taxa_pct: pct(soma.fecharam, soma.compra),
  };
};

const ladoRecalculado = (lado, alvo) =>
  lado.id === alvo.id
    ? { ...lado, n: alvo.fecharam, m: alvo.compra, pct: alvo.taxa_pct }
    : lado;

// Quem veio de anúncio passa a contar no maior grupo sem anúncio ("Não sabemos", na demo): é o que
// a conta veria se o anúncio não estivesse rastreado. Os totais não mudam.
export const semAnuncio = painel => {
  const { origem, catalogo } = painel;
  const base = painel.meta.base.procuras;
  const deAnuncio = origem.grupos.filter(grupo => grupo.tipo === 'anuncio');
  const restantes = origem.grupos.filter(grupo => grupo.tipo !== 'anuncio');
  if (!restantes.length) return painel;
  const [maior, ...outros] = restantes;
  const alvo = { ...maior, ...somarLinhas([maior, ...deAnuncio], base) };
  const idsDeAnuncio = new Set(deAnuncio.map(grupo => grupo.id));
  const origens = Object.fromEntries(
    Object.entries(catalogo.origens).filter(
      ([, origemDoCatalogo]) => origemDoCatalogo.tipo !== 'anuncio'
    )
  );
  const avisos = painel.avisos.some(aviso => aviso.id === 'sem_anuncio')
    ? painel.avisos
    : [...painel.avisos, { id: 'sem_anuncio', valores: {} }];
  return {
    ...painel,
    meta: { ...painel.meta, anuncios_ligados: false },
    evolucao: {
      ...painel.evolucao,
      pontos: painel.evolucao.pontos.map(ponto => ({
        ...ponto,
        com_anuncio: 0,
        sem_anuncio: ponto.procuras,
      })),
    },
    comparacoes: painel.comparacoes.map(comparacao =>
      comparacao.recorte === 'origem'
        ? {
            ...comparacao,
            a: ladoRecalculado(comparacao.a, alvo),
            b: ladoRecalculado(comparacao.b, alvo),
          }
        : comparacao
    ),
    origem: {
      ...origem,
      anuncios_ligados: false,
      grupos: [alvo, ...outros].sort((a, b) => b.procuras - a.procuras),
      comparacao: null,
      anuncios: [],
      sem_saber_qual: 0,
      nota: null,
    },
    recomendacoes: painel.recomendacoes.filter(
      recomendacao => recomendacao.frente !== 'anuncio'
    ),
    avisos,
    catalogo: { ...catalogo, origens },
    procuras: painel.procuras.map(procura =>
      idsDeAnuncio.has(procura.origem_id)
        ? { ...procura, origem_id: alvo.id, anuncio_id: null }
        : procura
    ),
  };
};

export const comSituacao = (painel, situacao) =>
  SITUACOES.includes(situacao)
    ? { ...painel, meta: { ...painel.meta, situacao } }
    : painel;

const pediuSemAnuncio = anuncios => anuncios === false || anuncios === '0';

// Os JSON da demonstração só existem no ambiente de desenvolvimento (#2251): o `import.meta.env.DEV` é trocado
// por `false` no build de produção, o ramo some e os dois arquivos nem entram no pacote. Em produção o painel lê
// só a API, e `painelDemo` devolve null.
const ARQUIVOS_DA_DEMO = import.meta.env.DEV
  ? {
      painel: () => import('./desempenhoDemo.json'),
      periodos: () => import('./desempenhoDemoPeriodos.json'),
    }
  : null;

export const painelDemo = async ({ periodo, anuncios } = {}) => {
  if (!ARQUIVOS_DA_DEMO) return null;
  const chave = periodoValido(periodo);
  const { default: demo } = await ARQUIVOS_DA_DEMO.painel();
  let painel = demo;
  if (chave !== PERIODO_DA_DEMO) {
    const { default: outros } = await ARQUIVOS_DA_DEMO.periodos();
    painel = comporPainel(
      {
        catalogo: demo.catalogo,
        procuras: demo.procuras,
        periodos: { ...outros.periodos, [PERIODO_DA_DEMO]: demo },
      },
      chave
    );
  }
  return pediuSemAnuncio(anuncios) ? semAnuncio(painel) : painel;
};

// --- API (#2251) ----------------------------------------------------------------------------------

// O painel sem números: sem leitura para o agente (a situação vem do servidor) ou com a chamada falhando
// (`aviso`). A página não mostra os blocos de um painel vazio.
export const painelVazio = (chave, { situacao = null, aviso } = {}) => ({
  versao: 2,
  vazio: true,
  meta: {
    fonte: FONTE_API,
    situacao,
    periodo: { chave },
    dados_ate: null,
    base: null,
    ...(aviso ? { aviso_fonte: aviso } : {}),
  },
});

const ehPainel = dado =>
  Boolean(dado && dado.versao === 2 && dado.meta && Array.isArray(dado.kpis));

const lerDaApi = async (api, { accountId, agentId, origem, chave }) => {
  try {
    const { data } = await api.painel({
      accountId,
      agentId,
      origem,
      periodo: chave,
    });
    if (data?.vazio)
      return painelVazio(chave, { situacao: data.meta?.situacao });
    return ehPainel(data) ? data : painelVazio(chave, { aviso: FONTE_API });
  } catch {
    return painelVazio(chave, { aviso: FONTE_API });
  }
};

// O arquivo da API é montado na hora pelo servidor: não há o que perguntar antes, só baixar.
const exportarDaApi = (api, painel, formato, pedido) => {
  if (painel.vazio) return null;
  const { chave } = painel.meta.periodo;
  return {
    nome: `desempenho-${chave}.${formato}`,
    baixar: async () => {
      const { data } = await api.exportar({
        accountId: pedido.accountId,
        agentId: pedido.agentId,
        origem: pedido.origem,
        periodo: chave,
        formato,
      });
      return data;
    },
  };
};

// --- Fonte ----------------------------------------------------------------------------------------

const buscarPadrao = (...args) => globalThis.fetch(...args);

// A vida real e a demonstração só existem no ambiente de desenvolvimento (#2251): em produção o painel lê só a
// API, e `?fonte=` no endereço não muda nada.
// `api`: o cliente da API do painel. Com ele, o padrão é a API; sem ele (testes da vida real e da demonstração),
// o padrão continua o arquivo local.
export const fonteDoPainel = ({
  buscar = buscarPadrao,
  vidaRealPermitida = Boolean(import.meta.env.DEV),
  demoPermitida = Boolean(import.meta.env.DEV),
  api = null,
} = {}) => {
  // Uma ida só ao arquivo por fonte (o pacote tem ~3 MB); quem quiser reler cria outra fonte.
  let leitura = null;

  // Devolve { pacote } ou { falha }: 'sem_arquivo' (não achou), 'formato' (não é o contrato v2)
  // ou 'leitura' (rede ou JSON quebrado).
  const lerVidaReal = () => {
    if (!leitura) {
      leitura = Promise.resolve()
        .then(() => buscar(ENDERECO_VIDA_REAL, { cache: 'no-cache' }))
        .then(async resposta => {
          if (!resposta?.ok) return { falha: 'sem_arquivo' };
          const dado = await resposta.json();
          return ehPacote(dado) ? { pacote: dado } : { falha: 'formato' };
        })
        .catch(() => ({ falha: 'leitura' }));
    }
    return leitura;
  };

  const carregar = async ({
    periodo,
    demo = {},
    accountId,
    agentId,
    origem,
  } = {}) => {
    const chave = periodoValido(periodo);
    // Com a API, ela é a fonte sempre em produção e, no desenvolvimento, quando o endereço não pede o arquivo
    // local ou a demonstração.
    const pediuOutra = demo.fonte !== undefined && demo.fonte !== FONTE_API;
    if (api && !(demoPermitida && pediuOutra)) {
      return lerDaApi(api, { accountId, agentId, origem, chave });
    }
    if (!demoPermitida) return painelVazio(chave, { aviso: FONTE_API });
    // Sem a API e sem ?fonte= no endereço, o painel abre na vida real quando o arquivo existe; a demonstração
    // fica para ?fonte=demo ou para quando o arquivo não está lá (aí sem aviso, porque ninguém pediu).
    const pediuVidaReal = demo.fonte === 'vida_real';
    const lida =
      (pediuVidaReal || demo.fonte === undefined) && vidaRealPermitida
        ? await lerVidaReal()
        : {};
    if (lida.pacote)
      return comSituacao(comporPainel(lida.pacote, chave), demo.situacao);
    const painel = await painelDemo({
      periodo: chave,
      anuncios: demo.anuncios,
    });
    const comAviso =
      lida.falha && pediuVidaReal
        ? { ...painel, meta: { ...painel.meta, aviso_fonte: lida.falha } }
        : painel;
    return comSituacao(comAviso, demo.situacao);
  };

  // O arquivo exportado só vale para o painel que a pessoa está vendo: demonstração mexida (sem
  // anúncio ou noutra situação) não tem arquivo próprio.
  // `pedido`: o mesmo do `carregar` (agente e origem), para a API saber de quem é o arquivo.
  const exportar = async (painel, formato, pedido = {}) => {
    if (!FORMATOS.includes(formato) || !painel?.meta) return null;
    const { fonte, situacao, anuncios_ligados: anuncios } = painel.meta;
    if (fonte === FONTE_API) {
      return api ? exportarDaApi(api, painel, formato, pedido) : null;
    }
    const nomeDaFonte = NOME_NO_ARQUIVO[fonte];
    if (!nomeDaFonte || !demoPermitida) return null;
    if (fonte === 'demo' && (situacao || anuncios === false)) return null;
    const nome = `desempenho-${nomeDaFonte}-${painel.meta.periodo.chave}.${formato}`;
    const url = `/${nome}`;
    try {
      const resposta = await buscar(url, { method: 'HEAD', cache: 'no-cache' });
      return resposta?.ok ? { url, nome } : null;
    } catch {
      return null;
    }
  };

  const temVidaReal = async () =>
    vidaRealPermitida && Boolean((await lerVidaReal()).pacote);

  return { nome: 'arquivo', carregar, exportar, temVidaReal };
};
