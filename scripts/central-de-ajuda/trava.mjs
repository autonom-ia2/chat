/* eslint-disable no-console -- script de linha de comando: o log do CI é a saída dele */
// Trava da Central de Ajuda "Plataforma" no Pull Request (#614, etapa B).
//
// A decisão do Rodrigo, que não se reabre: a Central segue o Guia. Tela nova sem artigo
// barra o PR — mesmo mecanismo da trava do Guia (issue #535), reaproveitado daqui:
// decidir/motivoDaDispensa vêm de scripts/guide-map/trava.mjs, com o rótulo e a marca do
// motivo próprios da Central.
//
// Duas coisas diferentes, os dois com "Barra" na especificação, mas só uma dispensável:
//   - tela nova sem artigo: dispensa com o rótulo `central-nao-se-aplica` e o motivo no
//     corpo do PR ("Central não se aplica: <motivo>");
//   - estrutura quebrada (tudo que `pnpm central:check` já acusa como falha): bloqueia
//     sempre, sem dispensa — é o mesmo tipo de checagem que `guia:check` já faz incondicional.
//
// Evidência que sumiu e valor de i18n que mudou ou saiu NUNCA bloqueiam: só viram
// comentário, para quem revisa decidir se o artigo precisa de atenção.
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';
import { pathToFileURL } from 'url';
import {
  lerArtigos,
  telasCobertas,
  evidenciasDoArtigo,
  carregarRegistro,
  conferir,
} from './conferir.mjs';
import { lerPorques } from '../guide-map/build.mjs';
import { decidir as decidirTelas, motivoDaDispensa } from '../guide-map/trava.mjs';
import { lerRegistroDe } from '../guide-map/aprendiz.mjs';

export const ROTULO_DISPENSA = 'central-nao-se-aplica';
export const MARCA_DO_MOTIVO = 'central não se aplica:';
// Identifica o comentário da trava, para atualizar o mesmo em vez de empilhar um novo a
// cada push — mesmo esquema do job do Guia.
export const MARCA_DO_COMENTARIO = '<!-- central-trava -->';

const MAPA = 'docs/central-de-ajuda/mapa-de-artigos.json';
const PORQUES = 'lib/operator_guide/porques.md';
const CAMINHOS_I18N_PT_BR = 'app/javascript/dashboard/i18n/locale/pt_BR';
const CAMINHOS_I18N_EXTRA = [
  'app/javascript/dashboard/i18n/locale/en/insurance.json',
  'app/javascript/dashboard/i18n/locale/en/prospecting.json',
];

export { motivoDaDispensa };

// Reaproveita a decisão do Guia (#535) com o rótulo e a marca da Central.
export const decidir = ({ novas, rotulos, corpo }) =>
  decidirTelas({ novas, rotulos, corpo, rotulo: ROTULO_DISPENSA, marca: MARCA_DO_MOTIVO });

// ---------------------------------------------------------------------------
// Telas novas deste PR sem artigo

// `antes` é o registro do commit base (lerRegistroDe); `atual`, o registro de agora
// (carregarRegistro). Só entra na lista quem é NOVA nesta comparação — tela antiga sem
// artigo é dívida técnica de outro PR, não deste.
export const novasSemArtigo = ({ antes, atual, cobertas }) => {
  const nomesAntes = new Set(antes);
  return [...atual].filter(nome => !nomesAntes.has(nome) && !cobertas.has(nome));
};

// ---------------------------------------------------------------------------
// Valor de i18n que mudou ou saiu (comentário, nunca bloqueia)

// Valores-folha (string) de um JSON de tradução, recursivo — é o texto que aparece na
// tela, o que interessa comparar.
export const valoresI18n = objeto => {
  if (typeof objeto === 'string') return [objeto];
  if (objeto === null || typeof objeto !== 'object') return [];
  return Object.values(objeto).flatMap(valoresI18n);
};

// O que existia em ALGUM arquivo antes e não existe em NENHUM agora — mudar de arquivo
// não conta como "removido", só sumir de todo o i18n conta.
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
// O comentário no PR

const SAIDAS = [
  '1. **Escrever o artigo** — `lib/central_de_ajuda/<capítulo>/<id>-<slug>.md` e a entrada em `docs/central-de-ajuda/mapa-de-artigos.json`. O kit está em `docs/central-de-ajuda/kit-do-escritor.md`. Depois do merge, o modo aprendiz também propõe um rascunho, mas só quando ninguém tiver escrito antes.',
  `2. **Dispensar só neste PR** — rótulo \`${ROTULO_DISPENSA}\` e, no corpo do PR, uma linha \`Central não se aplica: <motivo>\`.`,
];

const secaoDecisao = ({ decisao, novas }) => {
  if (decisao.situacao === 'em_dia') {
    return ['✅ **Central em dia:** toda tela nova deste PR tem artigo.'];
  }
  if (decisao.situacao === 'dispensada') {
    return [
      `✅ **Dispensado pelo rótulo \`${ROTULO_DISPENSA}\`.** Motivo: ${decisao.motivo}`,
    ];
  }
  if (decisao.situacao === 'dispensa_sem_motivo') {
    return [
      `🔒 **O rótulo \`${ROTULO_DISPENSA}\` está no PR, mas falta o motivo.**`,
      '',
      'Escreva no corpo do PR uma linha `Central não se aplica: <motivo>`. Sem o motivo, a dispensa não deixa rastro de por que a tela ficou fora da Central.',
    ];
  }
  return [
    `🔒 **Este PR cria ${novas.length} tela(s) que a Central ainda não explica.**`,
    '',
    'Duas saídas:',
    '',
    ...SAIDAS,
    '',
    ...novas.map(nome => `- \`${nome}\``),
  ];
};

export const comentarioDaTrava = ({ estrutura, decisao, novas, paraRevisao, i18nCitado }) => {
  const partes = [MARCA_DO_COMENTARIO];

  if (estrutura.length) {
    partes.push(
      '🔒 **A Central de Ajuda está com a estrutura quebrada** — isso sempre bloqueia, não tem dispensa por rótulo:',
      '',
      '```',
      ...estrutura,
      '```',
      ''
    );
  }

  partes.push(...secaoDecisao({ decisao, novas }));

  if (paraRevisao.length) {
    partes.push(
      '',
      '### Evidências para revisão (não bloqueia)',
      '',
      'O trecho que provava o fato sumiu do arquivo, ou o arquivo foi apagado. O artigo pode',
      'estar desatualizado — confira quando puder:',
      '',
      ...paraRevisao.map(e => `- \`${e.artigo}\`: ${e.caminho}:${e.numero}`)
    );
  }

  if (i18nCitado.length) {
    partes.push(
      '',
      '### Texto de tela citado num artigo mudou ou saiu do i18n (não bloqueia)',
      '',
      ...i18nCitado.map(
        item =>
          `- **${item.valor}** citado em: ${item.artigos.map(a => `\`${a}\``).join(', ')}`
      )
    );
  }

  return `${partes.join('\n')}\n`;
};

// ---------------------------------------------------------------------------
// Execução

const r = p => path.resolve(process.cwd(), p);

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

export const avisarGitHub = (nome, valor) => {
  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `${nome}=${valor}\n`);
  }
};

const executar = async () => {
  const base = process.env.BASE;
  const antes = await lerRegistroDe(base);
  if (!antes) {
    console.log(`O registro da Central não existia na base (${base}). Nada a conferir.`);
    avisarGitHub('bloqueia', 'false');
    return avisarGitHub('comentario', 'nenhum');
  }

  const raiz = process.cwd();
  const artigos = lerArtigos(raiz);
  const mapa = JSON.parse(fs.readFileSync(r(MAPA), 'utf8'));
  const humanos = lerPorques(fs.readFileSync(r(PORQUES), 'utf8'));
  const atual = await carregarRegistro(raiz);

  const resultado = conferir({ artigos, mapa, registro: atual, humanos, raiz });
  const cobertas = telasCobertas(mapa, artigos);
  const novas = novasSemArtigo({ antes, atual, cobertas });

  const decisao = decidir({
    novas,
    rotulos: String(process.env.ROTULOS || '').split(','),
    corpo: process.env.PR_BODY,
  });
  const bloqueia = resultado.problemas.length > 0 || decisao.bloqueia;

  const evidencias = artigos.flatMap(artigo => evidenciasDoArtigo(artigo, raiz));
  const paraRevisao = evidencias.filter(
    e => e.situacao === 'arquivo_ausente' || e.situacao === 'trecho_sumiu'
  );

  const arquivos = arquivosI18n();
  const objetosAntes = arquivos.map(caminho => jsonDoCommit(base, caminho));
  const objetosDepois = arquivos.map(jsonDoDisco);
  const removidos = valoresRemovidosDoI18n(objetosAntes, objetosDepois);
  const i18nCitado = valoresCitadosEmArtigos(removidos, artigos);

  fs.writeFileSync(
    process.env.COMENTARIO,
    comentarioDaTrava({
      estrutura: resultado.problemas,
      decisao,
      novas,
      paraRevisao,
      i18nCitado,
    })
  );
  console.log(
    `Situação: ${decisao.situacao}. Telas novas sem artigo: ${novas.length}. ` +
      `Estrutura quebrada: ${resultado.problemas.length > 0}.`
  );
  avisarGitHub('bloqueia', String(bloqueia));
  return avisarGitHub(
    'comentario',
    decisao.situacao === 'em_dia' && resultado.problemas.length === 0
      ? 'resolvido'
      : 'novo'
  );
};

// Comparação pela URL do módulo, não só pelo sufixo do nome do arquivo: este script tem
// o MESMO nome (trava.mjs) que scripts/guide-map/trava.mjs, que ele importa — um
// `endsWith('trava.mjs')` disparava o `executar()` de lá também.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await executar();
}
