/* eslint-disable no-console -- script de linha de comando: o log do CI é a saída dele */
// Modo aprendiz da Central de Ajuda "Plataforma" (#614).
//
// A cada push no main, compara o registro da plataforma com o de ANTES desse push (não
// com todo o histórico) e abre UM Pull Request com o que precisa de atenção — no mesmo
// espírito do modo aprendiz do Guia (#537): a IA escreve RASCUNHO, ninguém publica sem
// revisar.
//
//   (a) tela nova sem artigo: rascunho de artigo completo, escrito pela IA. O capítulo é
//       escolhido pela IA por enum — só entre os que já existem no mapa, nunca inventado.
//       Entrada no mapa com `revisar: true`.
//   (b) tela removida (TODAS as rotas do artigo sumiram do registro, e nenhuma delas está
//       em `_fora_do_guia`): apaga o artigo e a entrada do mapa — a publicação arquiva.
//       Tira a linha "- [id]" do Veja também de quem cita; citação no meio de uma frase
//       não é editada (vai para a lista do PR, com o nome do artigo onde está).
//   (c) evidência: só a que aponta para um arquivo alterado NESTE push e cujo trecho
//       sumiu do arquivo novo. O artigo ganha `revisar: true` e uma nota dizendo qual
//       evidência sumiu.
//   (d) i18n: só chave alterada ou removida NESTE push, cujo valor antigo não existe mais
//       em lugar nenhum do i18n e aparece em **negrito** em algum artigo. O artigo ganha
//       `revisar: true` e uma nota.
//
// Nada é reescrito automaticamente por conta própria — sem troca de texto, sem correção
// de número de linha, sem limpar rota parcial: tudo isso é sinal de que o artigo pode
// estar desatualizado, e quem decide o que fazer é quem revisa o PR.
//
// Sem mudança relevante nas quatro frentes: este script não escreve NADA (silêncio, como
// o modo aprendiz do Guia) — nunca um commit vazio.
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';
import { pathToFileURL } from 'url';
import {
  lerArtigos,
  telasCobertas,
  evidenciasDoArtigo,
  carregarRegistro,
  separarArtigo,
} from './conferir.mjs';
import { lerPorques, foraDoGuia } from '../guide-map/build.mjs';
import { pedirAoGpt, lerRegistroDe, contextoDaTela, avisarGitHub } from '../guide-map/aprendiz.mjs';

const raiz = process.cwd();
const r = p => path.resolve(raiz, p);

const MAPA = 'docs/central-de-ajuda/mapa-de-artigos.json';
const PORQUES = 'lib/operator_guide/porques.md';
const KIT = 'docs/central-de-ajuda/kit-do-escritor.md';
const CAMINHOS_I18N_PT_BR = 'app/javascript/dashboard/i18n/locale/pt_BR';
const CAMINHOS_I18N_EXTRA = [
  'app/javascript/dashboard/i18n/locale/en/insurance.json',
  'app/javascript/dashboard/i18n/locale/en/prospecting.json',
];

// String.prototype.replace(string, string) interpreta padrões como "$&" no texto de
// substituição — perigoso quando esse texto é conteúdo de artigo, que pode ter "$" (ex.:
// "R$"). indexOf/slice não interpreta nada — é o que este projeto pede para troca de
// texto (regra do Rodrigo, 21/09: nunca `.replace` com texto de substituição cru).
export const substituir = (texto, antigo, novo) => {
  const indice = texto.indexOf(antigo);
  if (indice === -1) return texto;
  return texto.slice(0, indice) + novo + texto.slice(indice + antigo.length);
};

const todosArtigos = mapa => mapa.capitulos.flatMap(capitulo => capitulo.artigos);

// ---------------------------------------------------------------------------
// (a) Tela nova sem artigo

// `antes` é o registro de ANTES deste push (lerRegistroDe); `atual`, o de agora
// (carregarRegistro). "Nova" é só quem entrou NESTE push — tela antiga sem artigo é
// dívida de outro dia, não deste.
export const telasNovasSemArtigo = ({ antes, atual, cobertas }) => {
  const nomesAntes = new Set(antes);
  return [...atual].filter(nome => !nomesAntes.has(nome) && !cobertas.has(nome));
};

export const montarEntradaDoMapa = ({ id, tela, rascunho }) => ({
  id,
  titulo: rascunho.titulo,
  para_que_serve: rascunho.o_que_e,
  publico: rascunho.publico,
  prioridade: rascunho.prioridade,
  assuntos: [],
  rotas: [tela.nome],
  me_leve_ate_la: { rota: tela.nome, destaque: null },
  requer: null,
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
export const montarArtigoMarkdown = ({ id, capitulo, tela, rascunho, titulos = {} }) => {
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
    'requer: null',
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

const CAMPOS_ARTIGO = [
  'titulo',
  'publico',
  'prioridade',
  'o_que_e',
  'por_que_importa',
  'como_faz',
  'o_que_da_errado',
];

// O capítulo só pode ser um dos que já existem no mapa — nada de "99" nem "a revisar"
// inventado: sem opção que sirva, o robô não escreve o artigo (fica para a próxima vez
// que alguém escrever esse capítulo à mão, ou para revisão direta do Rodrigo).
// O mesmo vale para o "Veja também": só ids que existem, senão o PR do robô nasce com link quebrado.
const esquemaArtigo = (idsDosCapitulos, idsDosArtigos) => ({
  type: 'object',
  additionalProperties: false,
  required: ['capitulo', ...CAMPOS_ARTIGO, 'veja_tambem', 'duvidas'],
  properties: {
    capitulo: { type: 'string', enum: idsDosCapitulos },
    titulo: { type: 'string' },
    publico: { type: 'string', enum: ['admin', 'atendente', 'ambos'] },
    prioridade: { type: 'string', enum: ['P1', 'P2', 'P3'] },
    o_que_e: { type: 'string' },
    por_que_importa: { type: 'string' },
    como_faz: { type: 'string' },
    o_que_da_errado: { type: 'string' },
    veja_tambem: { type: 'array', items: { type: 'string', enum: idsDosArtigos } },
    duvidas: { type: 'string' },
  },
});

export const pedirArtigoAoGpt = ({
  tela,
  contexto,
  exemplos,
  blocoPorques,
  kit,
  capitulos,
  idsDosArtigos,
  chave,
  modelo,
  buscar,
}) => {
  const listaDeCapitulos = capitulos.map(cap => `${cap.id} - ${cap.titulo}`).join('\n');
  const entrada = [
    `Tela: ${tela.nome}`,
    `Endereço: ${tela.caminho}`,
    '',
    'Capítulos que já existem na Central (escolha um pelo id):',
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
    esquema: esquemaArtigo(
      capitulos.map(cap => cap.id),
      idsDosArtigos
    ),
    nome: 'artigo_da_central',
    chave,
    modelo,
    buscar,
  });
};

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
    .map(artigo => `# ${artigo.cabecalho.titulo}\n\n${artigo.corpo}`)
    .join('\n\n---\n\n');

// ---------------------------------------------------------------------------
// (b) Tela removida

// Artigo cujas rotas sumiram TODAS do registro — e nenhuma delas está em `_fora_do_guia`:
// uma rota que só foi reclassificada (tela de sistema, redirecionamento) não é uma rota
// removida do produto, é a mesma tela com outro rótulo. E só conta rota que sumiu NESTE push
// (estava em `antesRegistro`): a que já tinha sumido antes é assunto do PR daquele push.
export const artigosParaRemover = ({ mapa, antesRegistro, atualRegistro, humanos }) => {
  // lerRegistroDe devolve lista; carregarRegistro, Set. Aceita os dois, como telasNovasSemArtigo.
  const antes = new Set(antesRegistro);
  return todosArtigos(mapa).filter(artigo => {
    const rotas = artigo.rotas || [];
    if (!rotas.length) return false;
    if (!rotas.some(rota => antes.has(rota))) return false;
    const todasSumiram = rotas.every(rota => !atualRegistro.has(rota));
    if (!todasSumiram) return false;
    return !rotas.some(rota => foraDoGuia(humanos, rota));
  });
};

export const removerArtigoDoMapa = (mapa, id) => ({
  ...mapa,
  capitulos: mapa.capitulos.map(capitulo => ({
    ...capitulo,
    artigos: capitulo.artigos.filter(artigo => artigo.id !== id),
  })),
});

// Tira a linha inteira "- [id] Título" do Veja também. Uma citação NO MEIO de uma frase
// não é editada — editar quebraria a frase — e volta em citacoesNoMeio, para a lista do PR.
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

// Tira, do Veja também de cada artigo que SOBROU, a referência a cada id removido — lendo
// o arquivo do disco a cada edição (não o corpo em memória, carregado antes de qualquer
// escrita): um artigo pode citar dois ids removidos na mesma seção, e a segunda edição
// precisa enxergar o resultado da primeira, não escrever por cima dela.
export const limparVejaTambemDeTodos = (artigosRestantes, idsRemovidos, raizDosArtigos = raiz) => {
  const citacoesNoMeio = [];
  artigosRestantes.forEach(outro => {
    const caminhoAbsoluto = path.resolve(raizDosArtigos, outro.caminho);
    idsRemovidos.forEach(idRemovido => {
      if (!fs.existsSync(caminhoAbsoluto)) return;
      const textoAtual = fs.readFileSync(caminhoAbsoluto, 'utf8');
      const { corpo } = separarArtigo(textoAtual, caminhoAbsoluto);
      const { corpo: corpoNovo, citacoesNoMeio: citas } = removerReferenciasVejaTambem(
        corpo,
        idRemovido
      );
      citas.forEach(() => citacoesNoMeio.push({ id: idRemovido, arquivo: outro.arquivo }));
      if (corpoNovo !== corpo) {
        fs.writeFileSync(caminhoAbsoluto, substituir(textoAtual, corpo, corpoNovo));
      }
    });
  });
  return citacoesNoMeio;
};

// ---------------------------------------------------------------------------
// Marcar artigo para revisão (evidência sumida ou valor de i18n sumido) — junta os
// motivos de um mesmo artigo numa nota só, sem sobrescrever revisar:true já marcado.
export const marcarParaRevisao = (mapa, id, motivo) => ({
  ...mapa,
  capitulos: mapa.capitulos.map(capitulo => ({
    ...capitulo,
    artigos: capitulo.artigos.map(artigo => {
      if (artigo.id !== id) return artigo;
      const notaAnterior = artigo.revisar && artigo.nota ? `${artigo.nota}; ` : '';
      return { ...artigo, revisar: true, nota: `${notaAnterior}${motivo}` };
    }),
  })),
});

// ---------------------------------------------------------------------------
// (c) Evidência que sumiu — só em arquivo alterado neste push

export const evidenciasQuebradasNoPush = ({ artigos, raiz: raizDosArtigos, arquivosAlterados }) =>
  artigos
    .flatMap(artigo => evidenciasDoArtigo(artigo, raizDosArtigos))
    .filter(
      evidencia =>
        (evidencia.situacao === 'trecho_sumiu' || evidencia.situacao === 'arquivo_ausente') &&
        arquivosAlterados.has(evidencia.caminho)
    );

// ---------------------------------------------------------------------------
// (d) Valor de i18n que saiu de vez (mudou ou foi removido neste push) e algum artigo cita

// Valores-folha (string) de um JSON de tradução, recursivo — é o texto que aparece na
// tela, o que interessa comparar.
export const valoresI18n = objeto => {
  if (typeof objeto === 'string') return [objeto];
  if (objeto === null || typeof objeto !== 'object') return [];
  return Object.values(objeto).flatMap(valoresI18n);
};

// O que existia em ALGUM arquivo antes deste push e não existe em NENHUM agora — mudar de
// arquivo, ou de chave para outra chave com o mesmo texto, não conta como "saiu".
export const valoresRemovidosDoI18n = (objetosAntes, objetosDepois) => {
  const antes = new Set(objetosAntes.flatMap(valoresI18n));
  const depois = new Set(objetosDepois.flatMap(valoresI18n));
  return [...antes].filter(valor => !depois.has(valor)).sort();
};

// Só interessa o valor removido que algum artigo ainda cita em negrito — achado com
// includes (kit do escritor, seção 4: nome de botão em negrito, exatamente como na tela).
export const valoresCitadosEmArtigos = (valores, artigos) =>
  valores
    .map(valor => ({
      valor,
      artigos: artigos
        .filter(artigo => artigo.corpo.includes(`**${valor}**`))
        .map(artigo => artigo.arquivo),
    }))
    .filter(item => item.artigos.length > 0);

// ---------------------------------------------------------------------------
// Só escreve quando há algo de verdade — nunca um commit vazio.
export const houveMudancaRelevante = ({ novas, removidos, evidenciasQuebradas, i18nCitado }) =>
  novas.length > 0 ||
  removidos.length > 0 ||
  evidenciasQuebradas.length > 0 ||
  i18nCitado.length > 0;

// ---------------------------------------------------------------------------
// O corpo do Pull Request

export const corpoDoPr = ({
  commit,
  rascunhos,
  removidos,
  citacoesNoMeio,
  paraRevisaoPorEvidencia,
  paraRevisaoPorI18n,
}) => {
  const partes = [
    `Rascunho do **modo aprendiz da Central** (#614): o registro da plataforma mudou no push de \`${commit || 'local'}\`.`,
    '',
    '**Nada disto está no ar.** A Central só passa a usar o que estiver neste PR depois do merge.',
    'Revise, corrija o que a IA errou, e faça o merge — ou feche, se não for para a Central.',
    '',
    'PR aberto pelo robô não dispara os checks; feche e reabra para rodar a trava.',
  ];

  if (rascunhos.length && removidos.length) {
    partes.push(
      '',
      '**Se isto foi uma renomeação de tela**, a tela nova e a removida aparecem juntas neste PR — junte à mão (não publique as duas separadas).'
    );
  }

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
    partes.push('', `## Artigos removidos (${removidos.length}) — todas as rotas saíram`);
    removidos.forEach(artigo => partes.push(`- \`${artigo.id}\` ${artigo.titulo}`));
  }

  if (citacoesNoMeio.length) {
    partes.push('', '## Citação no meio do texto de um artigo removido (não editada)');
    citacoesNoMeio.forEach(({ id, arquivo }) =>
      partes.push(`- \`${id}\` citado em \`${arquivo}\`, no meio de uma frase — ajuste à mão.`)
    );
  }

  if (paraRevisaoPorEvidencia.length) {
    partes.push('', '## Evidência que sumiu (arquivo alterado neste push)');
    paraRevisaoPorEvidencia.forEach(({ id, motivo }) => partes.push(`- \`${id}\`: ${motivo}`));
  }

  if (paraRevisaoPorI18n.length) {
    partes.push('', '## Texto de tela citado num artigo saiu do i18n neste push');
    paraRevisaoPorI18n.forEach(({ id, motivo }) => partes.push(`- \`${id}\`: ${motivo}`));
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

// `--no-renames`: arquivo renomeado aparece pelo nome antigo também, e a evidência que o
// cita não fica de fora. Sem try/catch: se o git falhar, o job fica vermelho com o motivo,
// em vez de pular a conferência calado.
const arquivosAlteradosNoPush = commit =>
  new Set(
    execFileSync('git', ['diff', '--name-only', '--no-renames', `${commit}`, 'HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    })
      .split('\n')
      .filter(Boolean)
  );

const rascunharArtigoNovo = async ({ nomeDaRota, mapa, artigos, porquesTexto, kitTexto, chave, modelo }) => {
  const tela = { nome: nomeDaRota, caminho: `rota: ${nomeDaRota}` };
  const capitulos = mapa.capitulos.map(cap => ({ id: cap.id, titulo: cap.titulo }));
  const rascunho = await pedirArtigoAoGpt({
    tela,
    contexto: contextoDaTela(nomeDaRota),
    exemplos: exemplosDeArtigos(artigos),
    blocoPorques: blocoDoPorquesPara(porquesTexto, nomeDaRota),
    kit: kitTexto,
    capitulos,
    idsDosArtigos: todosArtigos(mapa).map(artigo => artigo.id),
    chave,
    modelo,
  });
  const capitulo = mapa.capitulos.find(cap => cap.id === rascunho.capitulo);
  const proximo =
    Math.max(0, ...capitulo.artigos.map(a => Number(a.id.split('.')[1] || 0))) + 1;
  const id = `${capitulo.id}.${String(proximo).padStart(2, '0')}`;
  return { id, capitulo: capitulo.id, tela, rascunho };
};

const executar = async () => {
  const antesCommit = process.env.ANTES;
  if (!antesCommit || [...antesCommit].every(c => c === '0')) {
    console.log('Sem push anterior para comparar. Nada a propor.');
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
  const humanos = lerPorques(porquesTexto);
  const atualRegistro = await carregarRegistro(raiz);
  const cobertas = telasCobertas(mapa, artigos);

  // (a) telas novas sem artigo
  const novas = telasNovasSemArtigo({ antes: antesRegistro, atual: atualRegistro, cobertas });

  // (b) artigos removidos
  const removidos = artigosParaRemover({ mapa, antesRegistro, atualRegistro, humanos });
  const idsRemovidos = new Set(removidos.map(a => a.id));

  // (c) evidência quebrada só em arquivo alterado neste push, em artigo que NÃO foi removido
  const arquivosMudados = arquivosAlteradosNoPush(antesCommit);
  const evidenciasQuebradas = evidenciasQuebradasNoPush({
    artigos: artigos.filter(a => !idsRemovidos.has(a.cabecalho.id)),
    raiz,
    arquivosAlterados: arquivosMudados,
  }).filter(evidencia => !idsRemovidos.has(evidencia.artigo));

  // (d) valor de i18n que saiu de vez e algum artigo (não removido) cita
  const arquivos = arquivosI18n();
  const objetosAntes = arquivos.map(caminho => jsonDoCommit(antesCommit, caminho));
  const objetosDepois = arquivos.map(jsonDoDisco);
  const removidosDoI18n = valoresRemovidosDoI18n(objetosAntes, objetosDepois);
  const artigosNaoRemovidos = artigos.filter(a => !idsRemovidos.has(a.cabecalho.id));
  const i18nCitado = valoresCitadosEmArtigos(removidosDoI18n, artigosNaoRemovidos);

  if (!houveMudancaRelevante({ novas, removidos, evidenciasQuebradas, i18nCitado })) {
    console.log('Nada para revisar: nenhuma mudança relevante desde o push anterior.');
    return avisarGitHub('mudou', 'false');
  }

  const chave = process.env.OPENAI_API_KEY;
  if (novas.length && !chave) {
    console.error(
      `Entraram ${novas.length} tela(s) nova(s) sem artigo, mas o segredo OPENAI_API_KEY não está cadastrado.`
    );
    process.exit(1);
  }

  // --- (a) escreve os rascunhos novos ---
  const rascunhos = [];
  // Uma tela por vez: erro numa não pode sumir no meio de chamadas em paralelo.
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
      capitulos: mapa.capitulos.map(cap =>
        cap.id === rascunho.capitulo
          ? { ...cap, artigos: [...cap.artigos, montarEntradaDoMapa(rascunho)] }
          : cap
      ),
    };
    const pastaCapitulo = r(path.join('lib/central_de_ajuda', rascunho.capitulo));
    if (!fs.existsSync(pastaCapitulo)) fs.mkdirSync(pastaCapitulo, { recursive: true });
    fs.writeFileSync(
      path.join(pastaCapitulo, `${rascunho.id}-rascunho.md`),
      montarArtigoMarkdown(rascunho)
    );
  }

  // --- (b) apaga os artigos removidos e limpa quem os citava ---
  removidos.forEach(artigo => {
    mapa = removerArtigoDoMapa(mapa, artigo.id);
    const original = artigos.find(a => a.cabecalho.id === artigo.id);
    if (original && fs.existsSync(r(original.caminho))) fs.unlinkSync(r(original.caminho));
  });
  const artigosRestantes = artigos.filter(a => !idsRemovidos.has(a.cabecalho.id));
  const citacoesNoMeio = removidos.length
    ? limparVejaTambemDeTodos(artigosRestantes, [...idsRemovidos], raiz)
    : [];

  // --- (c) marca para revisão quem tem evidência quebrada ---
  const porArtigoEvidencia = new Map();
  evidenciasQuebradas.forEach(evidencia => {
    const artigoDoArquivo = artigosRestantes.find(a => a.arquivo === evidencia.artigo);
    if (!artigoDoArquivo) return;
    const id = artigoDoArquivo.cabecalho.id;
    const motivo = `evidência sumiu: ${evidencia.caminho}:${evidencia.numero}`;
    porArtigoEvidencia.set(id, [...(porArtigoEvidencia.get(id) || []), motivo]);
    mapa = marcarParaRevisao(mapa, id, motivo);
  });
  const paraRevisaoPorEvidencia = [...porArtigoEvidencia.entries()].map(([id, motivos]) => ({
    id,
    motivo: motivos.join('; '),
  }));

  // --- (d) marca para revisão quem cita valor de i18n que saiu ---
  const porArtigoI18n = new Map();
  i18nCitado.forEach(({ valor, artigos: arquivosQueCitam }) => {
    arquivosQueCitam.forEach(arquivo => {
      const artigoDoArquivo = artigosRestantes.find(a => a.arquivo === arquivo);
      if (!artigoDoArquivo) return;
      const id = artigoDoArquivo.cabecalho.id;
      const motivo = `texto de tela "${valor}" saiu do i18n`;
      porArtigoI18n.set(id, [...(porArtigoI18n.get(id) || []), motivo]);
      mapa = marcarParaRevisao(mapa, id, motivo);
    });
  });
  const paraRevisaoPorI18n = [...porArtigoI18n.entries()].map(([id, motivos]) => ({
    id,
    motivo: motivos.join('; '),
  }));

  fs.writeFileSync(r(MAPA), JSON.stringify(mapa, null, 1));

  fs.writeFileSync(
    process.env.CORPO_DO_PR || r('tmp/central-aprendiz.md'),
    corpoDoPr({
      commit: process.env.GITHUB_SHA || 'local',
      rascunhos,
      removidos,
      citacoesNoMeio,
      paraRevisaoPorEvidencia,
      paraRevisaoPorI18n,
    })
  );

  console.log(
    `Rascunho pronto: ${rascunhos.length} artigo(s) novo(s), ${removidos.length} removido(s), ` +
      `${paraRevisaoPorEvidencia.length} para revisão por evidência, ${paraRevisaoPorI18n.length} por i18n.`
  );
  return avisarGitHub('mudou', 'true');
};

// Comparação pela URL do módulo, não só pelo sufixo do nome do arquivo: este script tem o
// MESMO nome (aprendiz.mjs) que scripts/guide-map/aprendiz.mjs, de onde importa
// pedirAoGpt/lerRegistroDe/contextoDaTela/avisarGitHub — um `endsWith('aprendiz.mjs')`
// dispararia o executar() de lá também (mesmo problema achado em trava.mjs).
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await executar();
}
