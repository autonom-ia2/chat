/* eslint-disable no-console -- script de linha de comando: o log do CI é a saída dele */
// Modo aprendiz da Central de Ajuda "Plataforma" (#614, etapa C).
//
// A cada push no main, compara o registro do deploy anterior com o de agora e abre UM
// Pull Request com o que mudou — no mesmo espírito do modo aprendiz do Guia (#537): a IA
// escreve RASCUNHO, ninguém publica sem revisar.
//
//   - tela nova sem artigo: rascunho de artigo, com `revisar: true` no mapa e as dúvidas
//     da IA no corpo do PR;
//   - tela removida (todas as rotas do artigo sumiram): apaga o artigo e a entrada do
//     mapa, tira a linha "- [id]" do Veja também dos outros — citação no meio do texto
//     vai para a lista de revisão do PR, sem editar a frase;
//   - perdeu só ALGUMA rota: limpa `rotas`, sem apagar o artigo;
//   - valor de i18n que mudou (mesma chave, valor novo): troca **antigo** por **novo**
//     nos artigos, sem GPT; valor que SAIU (não existe mais em lugar nenhum): vai para a
//     lista de revisão;
//   - evidência que sumiu: vai para a lista de revisão; se só mudou de linha, corrige o
//     número sozinho.
//
// Sem mudança relevante, este script não escreve nada (silêncio, como o modo aprendiz do
// Guia).
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';
import { pathToFileURL } from 'url';
import {
  lerArtigos,
  telasCobertas,
  evidenciasDoArtigo,
  carregarRegistro,
} from './conferir.mjs';
import { novasSemArtigo, valoresRemovidosDoI18n, valoresCitadosEmArtigos } from './trava.mjs';
import { lerPorques } from '../guide-map/build.mjs';
import { pedirAoGpt, lerRegistroDe, contextoDaTela, avisarGitHub } from '../guide-map/aprendiz.mjs';

const raiz = process.cwd();
const r = p => path.resolve(raiz, p);

const MAPA = 'docs/central-de-ajuda/mapa-de-artigos.json';
const PORQUES = 'lib/operator_guide/porques.md';
const KIT = 'docs/central-de-ajuda/kit-do-escritor.md';
const ARTIGOS = 'lib/central_de_ajuda';
const CAMINHOS_I18N_PT_BR = 'app/javascript/dashboard/i18n/locale/pt_BR';
const CAMINHOS_I18N_EXTRA = [
  'app/javascript/dashboard/i18n/locale/en/insurance.json',
  'app/javascript/dashboard/i18n/locale/en/prospecting.json',
];

// ---------------------------------------------------------------------------
// Próximo id livre dentro do capítulo

const todosArtigos = mapa => mapa.capitulos.flatMap(capitulo => capitulo.artigos);

export const proximoIdDoCapitulo = (mapa, capituloId) => {
  const capitulo = mapa.capitulos.find(cap => cap.id === capituloId);
  const numeros = (capitulo?.artigos || []).map(artigo =>
    Number(artigo.id.split('.')[1])
  );
  const proximo = numeros.length ? Math.max(...numeros) + 1 : 1;
  return `${capituloId}.${String(proximo).padStart(2, '0')}`;
};

// ---------------------------------------------------------------------------
// Tela removida: artigo inteiro sai, ou só perde uma rota

export const artigosParaRemover = ({ mapa, atualRegistro }) =>
  todosArtigos(mapa).filter(
    artigo =>
      (artigo.rotas || []).length > 0 &&
      artigo.rotas.every(rota => !atualRegistro.has(rota))
  );

export const artigosParaLimparRotas = ({ mapa, atualRegistro }) =>
  todosArtigos(mapa)
    .map(artigo => ({
      artigo,
      rotasQuePerderam: (artigo.rotas || []).filter(rota => !atualRegistro.has(rota)),
    }))
    .filter(
      ({ artigo, rotasQuePerderam }) =>
        rotasQuePerderam.length > 0 && rotasQuePerderam.length < artigo.rotas.length
    );

// Tira a linha inteira "- [id] Título" do Veja também. Uma citação NO MEIO de uma frase
// não é editada — editar quebraria a frase — e vai para citacoesNoMeio, para quem revisa
// decidir o que fazer.
export const removerReferenciasVejaTambem = (corpo, id) => {
  const marca = `- [${id}]`;
  const referencia = `[${id}]`;
  const citacoesNoMeio = [];
  const linhas = corpo.split('\n').filter(linha => {
    const semEspacos = linha.trim();
    if (semEspacos.startsWith(marca)) return false;
    if (semEspacos.includes(referencia)) citacoesNoMeio.push(semEspacos);
    return true;
  });
  return { corpo: linhas.join('\n'), citacoesNoMeio };
};

export const removerArtigoDoMapa = (mapa, id) => ({
  ...mapa,
  capitulos: mapa.capitulos.map(capitulo => ({
    ...capitulo,
    artigos: capitulo.artigos.filter(artigo => artigo.id !== id),
  })),
});

export const limparRotasNoMapa = (mapa, id, rotasQuePerderam) => {
  const fora = new Set(rotasQuePerderam);
  return {
    ...mapa,
    capitulos: mapa.capitulos.map(capitulo => ({
      ...capitulo,
      artigos: capitulo.artigos.map(artigo =>
        artigo.id === id
          ? { ...artigo, rotas: artigo.rotas.filter(rota => !fora.has(rota)) }
          : artigo
      ),
    })),
  };
};

// ---------------------------------------------------------------------------
// Valor de i18n que mudou (mesma chave, valor novo) — troca sem GPT

// Só entra no par quando a MESMA chave, nos dois lados, é uma string diferente. Chave que
// sumiu não é "mudou", é "saiu" — isso quem acha é valoresRemovidosDoI18n (trava.mjs).
export const paresAntigoNovoPorChave = (antes, depois) => {
  if (typeof antes === 'string' && typeof depois === 'string') {
    return antes === depois ? [] : [{ antigo: antes, novo: depois }];
  }
  const saoObjetos =
    antes &&
    depois &&
    typeof antes === 'object' &&
    typeof depois === 'object' &&
    !Array.isArray(antes) &&
    !Array.isArray(depois);
  if (!saoObjetos) return [];

  return Object.keys(antes)
    .filter(chave => chave in depois)
    .flatMap(chave => paresAntigoNovoPorChave(antes[chave], depois[chave]));
};

// Só os artigos cujo corpo mudou entram no resultado — o resto do processo não precisa
// reescrever arquivo que não mudou.
export const substituirValorEmArtigos = (artigos, pares) =>
  artigos
    .map(artigo => {
      const corpo = pares.reduce(
        (texto, { antigo, novo }) =>
          texto.split(`**${antigo}**`).join(`**${novo}**`),
        artigo.corpo
      );
      return corpo === artigo.corpo ? null : { arquivo: artigo.arquivo, corpo };
    })
    .filter(Boolean);

// ---------------------------------------------------------------------------
// Evidência que só mudou de linha: corrige o número, mantém o trecho

export const corrigirEvidenciasDeLinha = (texto, linhaMudouList) =>
  linhaMudouList.reduce((atual, evidencia) => {
    const antiga = JSON.stringify(
      `${evidencia.caminho}:${evidencia.numero} | ${evidencia.trecho}`
    );
    const nova = JSON.stringify(
      `${evidencia.caminho}:${evidencia.novaLinha} | ${evidencia.trecho}`
    );
    return atual.split(antiga).join(nova);
  }, texto);

// ---------------------------------------------------------------------------
// O rascunho de artigo novo

export const montarEntradaDoMapa = ({ id, tela, rascunho, requer }) => ({
  id,
  titulo: rascunho.titulo,
  para_que_serve: rascunho.o_que_e,
  publico: rascunho.publico,
  prioridade: rascunho.prioridade,
  assuntos: [],
  rotas: [tela.nome],
  me_leve_ate_la: { rota: tela.nome, destaque: null },
  requer,
  prints: [],
  fontes: ['aprendiz: rascunho automático (#614)'],
  // Sempre true: rascunho de robô nunca vai ao ar sem revisão humana (kit, e decisão do
  // Rodrigo #614: "nada vai ao ar sem PR revisado").
  revisar: true,
  nota: rascunho.duvidas || null,
});

const linhaDoYaml = valor => JSON.stringify(valor);

// Evidências ficam vazias de propósito: a IA nunca viu o código linha a linha com a
// confiança que o kit do escritor exige (seção 6, "não confirmou, não escreva") — quem
// revisa preenche depois de conferir.
export const montarArtigoMarkdown = ({ id, capitulo, tela, rascunho, requer, titulos = {} }) => {
  const vejaTambem = (rascunho.veja_tambem || [])
    .map(refId => (titulos[refId] ? `- [${refId}] ${titulos[refId]}` : `- [${refId}]`))
    .join('\n');

  const cabecalho = [
    '---',
    `id: ${linhaDoYaml(id)}`,
    `titulo: ${linhaDoYaml(rascunho.titulo)}`,
    `capitulo: ${linhaDoYaml(capitulo)}`,
    `publico: ${rascunho.publico}`,
    `prioridade: ${rascunho.prioridade}`,
    'me_leve_ate_la:',
    `  rota: ${tela.nome}`,
    '  destaque: null',
    `requer: ${requer ? linhaDoYaml(requer) : 'null'}`,
    'assuntos: []',
    'conferido_em: null',
    'evidencias: []',
    '---',
    '',
  ].join('\n');

  const corpo = [
    '## O que é',
    '',
    rascunho.o_que_e,
    '',
    '## Por que importa',
    '',
    rascunho.por_que_importa,
    '',
    '## Como faz',
    '',
    rascunho.como_faz,
    '',
    '## O que dá errado',
    '',
    rascunho.o_que_da_errado,
    '',
    '## Veja também',
    '',
    vejaTambem,
    '',
  ].join('\n');

  return `${cabecalho}${corpo}`;
};

// ---------------------------------------------------------------------------
// O pedido à IA — mesma chamada do Guia (pedirAoGpt, extraída de guide-map/aprendiz.mjs),
// instruções e esquema próprios da Central.

const CAMPOS_ARTIGO = [
  'titulo',
  'publico',
  'prioridade',
  'o_que_e',
  'por_que_importa',
  'como_faz',
  'o_que_da_errado',
];

// `idsDosCapitulos` restringe a escolha da IA aos capítulos que já existem no mapa — ela
// não inventa numeração de capítulo, só escolhe entre os que existem (o kit não tem regra
// de "qual capítulo pega qual assunto"; sem capítulo nenhum que sirva, sobra "99").
const esquemaArtigo = idsDosCapitulos => ({
  type: 'object',
  additionalProperties: false,
  required: ['capitulo', ...CAMPOS_ARTIGO, 'veja_tambem', 'duvidas'],
  properties: {
    capitulo: { type: 'string', enum: [...idsDosCapitulos, '99'] },
    titulo: { type: 'string' },
    publico: { type: 'string', enum: ['admin', 'atendente', 'ambos'] },
    prioridade: { type: 'string', enum: ['P1', 'P2', 'P3'] },
    o_que_e: { type: 'string' },
    por_que_importa: { type: 'string' },
    como_faz: { type: 'string' },
    o_que_da_errado: { type: 'string' },
    veja_tambem: { type: 'array', items: { type: 'string' } },
    duvidas: { type: 'string' },
  },
});

export const pedirArtigoAoGpt = ({
  tela,
  contexto,
  exemplos,
  blocoPorques,
  kit,
  capitulos = [],
  chave,
  modelo,
  buscar,
}) => {
  const listaDeCapitulos = capitulos.map(cap => `${cap.id} - ${cap.titulo}`).join('\n');
  const entrada = [
    `Tela: ${tela.nome}`,
    `Endereço: ${tela.caminho}`,
    '',
    'Capítulos que já existem na Central (escolha um pelo id, ou "99" se nenhum servir):',
    listaDeCapitulos,
    '',
    'Dois artigos de exemplo, escritos à mão:',
    exemplos,
    '',
    'O bloco do Guia da Plataforma sobre esta tela (porques.md), se existir:',
    blocoPorques || '(nenhum)',
    '',
    'O que o código mostra desta tela:',
    contexto,
  ].join('\n');

  return pedirAoGpt({
    instrucoes: kit,
    entrada,
    esquema: esquemaArtigo(capitulos.map(cap => cap.id)),
    nome: `artigo para ${tela.nome}`,
    chave,
    modelo,
    buscar,
  });
};

// ---------------------------------------------------------------------------
// O bloco do porques.md de uma rota (para dar contexto à IA) — mesma técnica de
// exemplosDoPorques (guide-map/aprendiz.mjs): split por string, sem regex.
const CABECALHO_BLOCO = '### ';

const blocosDoPorques = texto =>
  texto
    .split(`\n${CABECALHO_BLOCO}`)
    .slice(1)
    .map(bloco => `${CABECALHO_BLOCO}${bloco}`);

const campoDoBloco = (bloco, campo) => {
  const marca = `- ${campo}: `;
  const linha = bloco.split('\n').find(l => l.trim().startsWith(marca));
  return linha ? linha.trim().slice(marca.length).trim() : null;
};

export const blocoDoPorquesPara = (texto, nomeDaRota) =>
  blocosDoPorques(texto).find(bloco => campoDoBloco(bloco, 'rota') === nomeDaRota) || null;

// Dois artigos reais como exemplo de estilo — o capítulo 02 é o exemplo-ouro do kit.
const exemplosDeArtigos = artigos =>
  artigos
    .filter(artigo => artigo.cabecalho.capitulo === '02')
    .slice(0, 2)
    .map(artigo => `${'#'.repeat(1)} ${artigo.cabecalho.titulo}\n\n${artigo.corpo}`)
    .join('\n\n---\n\n');

// ---------------------------------------------------------------------------
// O corpo do Pull Request

export const corpoDoPr = ({
  commit,
  rascunhos,
  removidos,
  limpezasDeRotas,
  i18nMudou,
  i18nSaiuCitado,
  paraRevisao,
}) => {
  const partes = [
    `Rascunho do **modo aprendiz da Central** (#614, etapa C): o registro da plataforma mudou no deploy de \`${commit || 'local'}\`.`,
    '',
    '**Nada disto está no ar.** A Central só passa a usar o que estiver neste PR depois do merge.',
    'Revise, corrija o que a IA errou, e faça o merge — ou feche, se não for para a Central.',
    '',
    'PR aberto pelo robô não dispara os checks; feche e reabra para rodar a trava.',
  ];

  if (rascunhos.length) {
    partes.push('', `## Artigos novos (${rascunhos.length}) — rascunho escrito pela IA`);
    rascunhos.forEach(({ id, tela, rascunho }) => {
      partes.push(
        '',
        `### \`${id}\` — \`${tela.nome}\``,
        `- **O que a IA não conseguiu saber:** ${rascunho.duvidas || 'nada declarado'}`
      );
    });
  }

  if (removidos.length) {
    partes.push('', `## Artigos removidos (${removidos.length}) — a tela deles saiu`);
    removidos.forEach(artigo => partes.push(`- \`${artigo.id}\` ${artigo.titulo}`));
  }

  if (limpezasDeRotas.length) {
    partes.push('', '## Artigos que perderam uma das telas que explicavam');
    limpezasDeRotas.forEach(({ id, rotasQuePerderam }) =>
      partes.push(
        `- \`${id}\`: tirei do \`rotas\` ${rotasQuePerderam.map(rota => `\`${rota}\``).join(', ')}.`
      )
    );
  }

  if (i18nMudou.length) {
    partes.push('', '## Texto trocado automaticamente nos artigos');
    i18nMudou.forEach(({ antigo, novo }) => partes.push(`- **${antigo}** → **${novo}**`));
  }

  if (i18nSaiuCitado.length) {
    partes.push('', '## Texto de tela que saiu do i18n — revisar');
    i18nSaiuCitado.forEach(item =>
      partes.push(
        `- **${item.valor}** citado em: ${item.artigos.map(a => `\`${a}\``).join(', ')}`
      )
    );
  }

  if (paraRevisao.length) {
    partes.push('', '## Evidências para revisão (o trecho sumiu, ou o arquivo foi apagado)');
    paraRevisao.forEach(e => partes.push(`- \`${e.artigo}\`: ${e.caminho}:${e.numero}`));
  }

  return `${partes.join('\n')}\n`;
};

// ---------------------------------------------------------------------------
// Execução

const arquivosI18n = () => {
  const doPtBr = fs
    .readdirSync(r(CAMINHOS_I18N_PT_BR), { recursive: true })
    .filter(nome => nome.endsWith('.json'))
    .map(nome => path.join(CAMINHOS_I18N_PT_BR, nome));
  return [...doPtBr, ...CAMINHOS_I18N_EXTRA];
};

const jsonDoDisco = caminho => {
  if (!fs.existsSync(r(caminho))) return {};
  try {
    return JSON.parse(fs.readFileSync(r(caminho), 'utf8'));
  } catch {
    return {};
  }
};

const jsonDoCommit = (commit, caminho) => {
  try {
    const texto = execFileSync('git', ['show', `${commit}:${caminho}`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return JSON.parse(texto);
  } catch {
    return {};
  }
};

// O capítulo do artigo novo é ESCOLHIDO PELA IA, entre os que já existem no mapa (ou "99",
// se nenhum servir) — o esquema (esquemaArtigo) já restringe a resposta a essas opções, e
// aqui só confiamos nisso: se por algum motivo vier um id fora da lista (a IA não é
// infalível, mesmo com json_schema strict), cai em "99 - a revisar" em vez de estourar.
const rascunharArtigoNovo = async ({ nomeDaRota, mapa, artigos, porquesTexto, kitTexto, chave, modelo }) => {
  const tela = { nome: nomeDaRota, caminho: `rota: ${nomeDaRota}` };
  const rascunho = await pedirArtigoAoGpt({
    tela,
    contexto: contextoDaTela(nomeDaRota),
    exemplos: exemplosDeArtigos(artigos),
    blocoPorques: blocoDoPorquesPara(porquesTexto, nomeDaRota),
    kit: kitTexto,
    capitulos: mapa.capitulos.map(cap => ({ id: cap.id, titulo: cap.titulo })),
    chave,
    modelo,
  });
  const capituloAlvo = mapa.capitulos.find(cap => cap.id === rascunho.capitulo) || {
    id: '99',
    titulo: 'A revisar',
    artigos: [],
  };
  const id = proximoIdDoCapitulo({ capitulos: [...mapa.capitulos, capituloAlvo] }, capituloAlvo.id);
  return { id, capitulo: capituloAlvo.id, tela, rascunho };
};

const executar = async () => {
  const antesCommit = process.env.ANTES;
  if (!antesCommit || [...antesCommit].every(c => c === '0')) {
    console.log('Sem deploy anterior para comparar. Nada a propor.');
    return avisarGitHub('mudou', 'false');
  }

  const antesRegistro = await lerRegistroDe(antesCommit);
  if (!antesRegistro) {
    console.log(`O registro da Central não existia em ${antesCommit}. Nada a comparar.`);
    return avisarGitHub('mudou', 'false');
  }

  const artigos = lerArtigos(raiz);
  let mapa = JSON.parse(fs.readFileSync(r(MAPA), 'utf8'));
  const porquesTexto = fs.readFileSync(r(PORQUES), 'utf8');
  const kitTexto = fs.readFileSync(r(KIT), 'utf8');
  const atualRegistro = await carregarRegistro(raiz);
  const cobertas = telasCobertas(mapa, artigos);

  const novas = novasSemArtigo({ antes: antesRegistro, atual: atualRegistro, cobertas });
  const removidos = artigosParaRemover({ mapa, atualRegistro });
  const limpezas = artigosParaLimparRotas({ mapa, atualRegistro });

  const arquivos = arquivosI18n();
  const objetosAntes = arquivos.map(caminho => jsonDoCommit(antesCommit, caminho));
  const objetosDepois = arquivos.map(jsonDoDisco);
  const paresMudaram = objetosAntes.flatMap((obj, indice) =>
    paresAntigoNovoPorChave(obj, objetosDepois[indice])
  );
  const antigosQueMudaram = new Set(paresMudaram.map(p => p.antigo));
  const removidosDoI18n = valoresRemovidosDoI18n(objetosAntes, objetosDepois).filter(
    valor => !antigosQueMudaram.has(valor)
  );
  const i18nSaiuCitado = valoresCitadosEmArtigos(removidosDoI18n, artigos);

  const evidencias = artigos.flatMap(artigo => evidenciasDoArtigo(artigo, raiz));
  const linhaMudouPorArtigo = new Map();
  evidencias
    .filter(e => e.situacao === 'linha_mudou')
    .forEach(e => {
      const lista = linhaMudouPorArtigo.get(e.artigo) || [];
      lista.push(e);
      linhaMudouPorArtigo.set(e.artigo, lista);
    });
  const paraRevisao = evidencias.filter(
    e => e.situacao === 'arquivo_ausente' || e.situacao === 'trecho_sumiu'
  );

  if (
    novas.length === 0 &&
    removidos.length === 0 &&
    limpezas.length === 0 &&
    paresMudaram.length === 0 &&
    i18nSaiuCitado.length === 0 &&
    linhaMudouPorArtigo.size === 0 &&
    paraRevisao.length === 0
  ) {
    console.log('Nada para revisar: nenhuma mudança relevante desde o deploy anterior.');
    return avisarGitHub('mudou', 'false');
  }

  const chave = process.env.OPENAI_API_KEY;
  if (novas.length && !chave) {
    console.error(
      `Entraram ${novas.length} tela(s) nova(s) sem artigo, mas o segredo OPENAI_API_KEY não está cadastrado.`
    );
    process.exit(1);
  }

  const rascunhos = [];
  // Uma tela por vez: mesmo motivo do Guia — erro numa não pode sumir no meio de
  // chamadas em paralelo.
  // eslint-disable-next-line no-restricted-syntax
  for (const nomeDaRota of novas) {
    // eslint-disable-next-line no-await-in-loop
    const rascunho = await rascunharArtigoNovo({
      nomeDaRota,
      mapa,
      artigos,
      porquesTexto,
      kitTexto,
      chave,
      modelo: process.env.MODELO,
    });
    rascunhos.push(rascunho);
    mapa = {
      ...mapa,
      capitulos: mapa.capitulos.some(cap => cap.id === rascunho.capitulo)
        ? mapa.capitulos.map(cap =>
            cap.id === rascunho.capitulo
              ? { ...cap, artigos: [...cap.artigos, montarEntradaDoMapa({ ...rascunho, requer: null })] }
              : cap
          )
        : [
            ...mapa.capitulos,
            {
              id: rascunho.capitulo,
              titulo: 'A revisar',
              artigos: [montarEntradaDoMapa({ ...rascunho, requer: null })],
            },
          ],
    };
    fs.writeFileSync(
      r(path.join(ARTIGOS, rascunho.capitulo, `${rascunho.id}-rascunho.md`)),
      montarArtigoMarkdown({ ...rascunho, requer: null })
    );
  }

  const citacoesNoMeioTotais = [];
  removidos.forEach(artigo => {
    mapa = removerArtigoDoMapa(mapa, artigo.id);
    const caminhoArtigo = artigos.find(a => a.cabecalho.id === artigo.id)?.caminho;
    if (caminhoArtigo) fs.unlinkSync(r(caminhoArtigo));
    artigos
      .filter(a => a.cabecalho.id !== artigo.id)
      .forEach(outro => {
        const { corpo, citacoesNoMeio } = removerReferenciasVejaTambem(outro.corpo, artigo.id);
        if (citacoesNoMeio.length) citacoesNoMeioTotais.push(...citacoesNoMeio);
        if (corpo !== outro.corpo) {
          const textoOriginal = fs.readFileSync(r(outro.caminho), 'utf8');
          fs.writeFileSync(r(outro.caminho), textoOriginal.replace(outro.corpo, corpo));
        }
      });
  });

  limpezas.forEach(({ artigo, rotasQuePerderam }) => {
    mapa = limparRotasNoMapa(mapa, artigo.id, rotasQuePerderam);
  });

  const alterados = substituirValorEmArtigos(artigos, paresMudaram);
  alterados.forEach(({ arquivo, corpo }) => {
    const original = artigos.find(a => a.arquivo === arquivo);
    if (!original) return;
    const textoOriginal = fs.readFileSync(r(original.caminho), 'utf8');
    fs.writeFileSync(r(original.caminho), textoOriginal.replace(original.corpo, corpo));
  });

  linhaMudouPorArtigo.forEach((lista, arquivo) => {
    const original = artigos.find(a => a.arquivo === arquivo);
    if (!original) return;
    const textoOriginal = fs.readFileSync(r(original.caminho), 'utf8');
    fs.writeFileSync(r(original.caminho), corrigirEvidenciasDeLinha(textoOriginal, lista));
  });

  fs.writeFileSync(r(MAPA), JSON.stringify(mapa, null, 1));

  fs.writeFileSync(
    process.env.CORPO_DO_PR || r('tmp/central-aprendiz.md'),
    corpoDoPr({
      commit: process.env.GITHUB_SHA || 'local',
      rascunhos,
      removidos,
      limpezasDeRotas: limpezas.map(({ artigo, rotasQuePerderam }) => ({
        id: artigo.id,
        rotasQuePerderam,
      })),
      i18nMudou: paresMudaram,
      i18nSaiuCitado,
      paraRevisao: [
        ...paraRevisao,
        ...citacoesNoMeioTotais.map(linha => ({ artigo: '(citação no meio do texto)', caminho: linha, numero: '' })),
      ],
    })
  );

  console.log(
    `Rascunho pronto: ${rascunhos.length} artigo(s) novo(s), ${removidos.length} removido(s), ` +
      `${limpezas.length} com rota limpa, ${paresMudaram.length} valor(es) de i18n trocado(s).`
  );
  return avisarGitHub('mudou', 'true');
};

// Comparação pela URL do módulo, não só pelo sufixo do nome do arquivo: este script tem o
// MESMO nome (aprendiz.mjs) que scripts/guide-map/aprendiz.mjs, de onde importa
// pedirAoGpt/lerRegistroDe/contextoDaTela/avisarGitHub — um `endsWith('aprendiz.mjs')`
// dispararia o executar() de lá também (mesmo problema achado em trava.mjs, #614 etapa B).
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await executar();
}
