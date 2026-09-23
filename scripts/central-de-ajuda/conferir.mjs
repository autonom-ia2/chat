/* eslint-disable no-console -- script de linha de comando: o log do CI é a saída dele */
// Confere se a Central de Ajuda "Plataforma" está em dia com o Guia da Plataforma (#614).
//
// Cada artigo mora em lib/central_de_ajuda/<cap>/<id>-<slug>.md, com um cabeçalho YAML
// (id, me_leve_ate_la...) e é catalogado em docs/central-de-ajuda/mapa-de-artigos.json.
// Este script cruza as três fontes — os artigos no disco, o mapa e o roteador do painel
// (via app/javascript/dashboard/helper/guideRouteRegistry.js, gerado pelo Guia) — e falha
// quando elas saem de sincronia:
//   - tela do painel sem nenhum artigo que a explique;
//   - [dd.dd] no corpo de um artigo apontando para um id que não existe no mapa;
//   - me_leve_ate_la do cabeçalho diferente do que o mapa registrou;
//   - artigo no disco sem entrada no mapa, ou entrada do mapa sem arquivo no disco;
//   - id do cabeçalho que não bate com o prefixo do nome do arquivo.
//
// Uso: node scripts/central-de-ajuda/conferir.mjs (ou `pnpm central:check`)
import fs from 'fs';
import os from 'os';
import path from 'path';
import { pathToFileURL } from 'url';
import { parse as parseYaml } from 'yaml';
import { lerPorques, foraDoGuia } from '../guide-map/build.mjs';

const r = (raiz, p) => path.resolve(raiz, p);

const ARTIGOS = 'lib/central_de_ajuda';
const MAPA = 'docs/central-de-ajuda/mapa-de-artigos.json';
const PORQUES = 'lib/operator_guide/porques.md';
const REGISTRY = 'app/javascript/dashboard/helper/guideRouteRegistry.js';

const INICIO_CABECALHO = '---\n';
const FIM_CABECALHO = '\n---\n';

// ---------------------------------------------------------------------------
// Ler os artigos do disco

// Separa o cabeçalho YAML do corpo Markdown, do mesmo jeito que
// ArtigoFonte#separar (Ruby, app/services/autonomia/central_de_ajuda/artigo_fonte.rb)
// faz na publicação — para os dois lados nunca discordarem do que é cabeçalho.
export const separarArtigo = (texto, identificacao) => {
  if (!texto.startsWith(INICIO_CABECALHO)) {
    throw new Error(`${identificacao}: sem cabeçalho`);
  }
  const fim = texto.indexOf(FIM_CABECALHO, INICIO_CABECALHO.length);
  if (fim === -1) {
    throw new Error(`${identificacao}: cabeçalho sem fechamento`);
  }
  const cabecalho = parseYaml(texto.slice(INICIO_CABECALHO.length, fim));
  const eMapa =
    cabecalho !== null &&
    typeof cabecalho === 'object' &&
    !Array.isArray(cabecalho);
  if (!eMapa) {
    throw new Error(`${identificacao}: cabeçalho não é um mapa`);
  }
  const corpo = texto.slice(fim + FIM_CABECALHO.length);
  return { cabecalho, corpo };
};

const arquivosDeArtigos = raiz =>
  fs
    .readdirSync(r(raiz, ARTIGOS), { withFileTypes: true })
    .filter(entrada => entrada.isDirectory())
    .flatMap(capitulo => {
      const pasta = path.join(r(raiz, ARTIGOS), capitulo.name);
      return fs
        .readdirSync(pasta)
        .filter(nome => nome.endsWith('.md'))
        .map(nome => path.join(pasta, nome));
    })
    .sort();

export const lerArtigos = raiz =>
  arquivosDeArtigos(raiz).map(caminho => {
    const texto = fs.readFileSync(caminho, 'utf8');
    const { cabecalho, corpo } = separarArtigo(texto, caminho);
    return { caminho, arquivo: path.basename(caminho), cabecalho, corpo };
  });

// ---------------------------------------------------------------------------
// O mapa (docs/central-de-ajuda/mapa-de-artigos.json)

const artigosDoMapa = mapa =>
  new Map(
    mapa.capitulos.flatMap(capitulo =>
      capitulo.artigos.map(artigo => [artigo.id, artigo])
    )
  );

// Rotas que já têm explicação: as que o cabeçalho de algum artigo leva (me_leve_ate_la),
// as que o mapa associou a um artigo (rotas:) e as que o mapa marcou como fora do produto
// (fora:, com o motivo).
export const telasCobertas = (mapa, artigos) => {
  const cobertas = new Set();
  artigos.forEach(artigo => {
    const rota = artigo.cabecalho?.me_leve_ate_la?.rota;
    if (rota) cobertas.add(rota);
  });
  mapa.capitulos.forEach(capitulo => {
    capitulo.artigos.forEach(artigo => {
      (artigo.rotas || []).forEach(rota => cobertas.add(rota));
    });
  });
  (mapa.fora || []).forEach(item => cobertas.add(item.rota));
  return cobertas;
};

// ---------------------------------------------------------------------------
// Telas do Guia (guideRouteRegistry.js) sem nenhum artigo que as explique

// Tela do painel sem cobertura no mapa E sem estar declarada como fora do Guia
// (lib/operator_guide/porques.md, bloco _fora_do_guia) — aí não é "fora", é esquecida.
export const telasSemArtigo = (registro, cobertas, humanos) =>
  [...registro]
    .filter(rota => !cobertas.has(rota))
    .filter(rota => !foraDoGuia(humanos, rota))
    .sort();

// ---------------------------------------------------------------------------
// Referências [dd.dd] quebradas no corpo dos artigos

const eDigito = caractere => caractere >= '0' && caractere <= '9';

// "02.04": dois dígitos, ponto, dois dígitos — mesma regra de
// ArtigoFonte#numero_de_artigo? (Ruby).
const numeroDeArtigo = numero =>
  numero.length === 5 &&
  numero[2] === '.' &&
  eDigito(numero[0]) &&
  eDigito(numero[1]) &&
  eDigito(numero[3]) &&
  eDigito(numero[4]);

// "[dd.dd]" que não seja já o texto de um link Markdown pronto ("[dd.dd](...)") —
// mesma regra de ArtigoFonte#referencia_em (Ruby), varrendo com indexOf/slice em vez
// de expressão regular (regra do projeto: sem regex para interpretar texto).
const referenciaEm = (texto, posicao) => {
  const trecho = texto.slice(posicao, posicao + 7);
  if (trecho.length !== 7 || trecho[0] !== '[' || trecho[6] !== ']') return null;
  if (texto[posicao + 7] === '(') return null;

  const numero = trecho.slice(1, 6);
  return numeroDeArtigo(numero) ? numero : null;
};

const referenciasNoTexto = texto => {
  const encontradas = [];
  let posicao = texto.indexOf('[');
  while (posicao !== -1) {
    const referencia = referenciaEm(texto, posicao);
    if (referencia) {
      encontradas.push(referencia);
      posicao = texto.indexOf('[', posicao + 7);
    } else {
      posicao = texto.indexOf('[', posicao + 1);
    }
  }
  return encontradas;
};

export const referenciasQuebradas = (artigos, idsDoMapa) =>
  artigos.flatMap(artigo =>
    referenciasNoTexto(artigo.corpo)
      .filter(referencia => !idsDoMapa.has(referencia))
      .map(referencia => ({ artigo: artigo.arquivo, referencia }))
  );

// ---------------------------------------------------------------------------
// me_leve_ate_la do cabeçalho divergente do mapa

const meLeveIguais = (a, b) => {
  if (!a && !b) return true;
  if (!a || !b) return false;
  return a.rota === b.rota && (a.destaque ?? null) === (b.destaque ?? null);
};

export const meLeveDivergente = (artigos, mapa) => {
  const doMapa = artigosDoMapa(mapa);
  return artigos
    .filter(artigo => doMapa.has(artigo.cabecalho.id))
    .filter(
      artigo =>
        !meLeveIguais(
          artigo.cabecalho.me_leve_ate_la,
          doMapa.get(artigo.cabecalho.id).me_leve_ate_la
        )
    )
    .map(artigo => artigo.cabecalho.id);
};

// ---------------------------------------------------------------------------
// Disco e mapa desalinhados

export const artigosSemMapa = (artigos, mapa) => {
  const doMapa = artigosDoMapa(mapa);
  return artigos
    .filter(artigo => !doMapa.has(artigo.cabecalho.id))
    .map(artigo => artigo.arquivo);
};

export const mapaSemArquivo = (artigos, mapa) => {
  const noDisco = new Set(artigos.map(artigo => artigo.cabecalho.id));
  return [...artigosDoMapa(mapa).keys()].filter(id => !noDisco.has(id));
};

// O id no cabeçalho e o prefixo do nome do arquivo (ex.: "12.05" em
// "12.05-atributos-personalizados.md") precisam ser o mesmo id — um dos dois foi
// copiado e não ajustado.
export const idDivergenteDoArquivo = artigos =>
  artigos
    .filter(artigo => artigo.arquivo.slice(0, 5) !== artigo.cabecalho.id)
    .map(artigo => artigo.arquivo);

// ---------------------------------------------------------------------------
// Evidências: `caminho:linha | trecho`, conferidas contra o código de hoje.
//
// O trecho é o que prova que a evidência ainda vale — a linha pode mudar de número
// (revisão de código alheia à Central) sem que o fato deixe de ser verdade; só quando
// o TRECHO some do arquivo é que o artigo precisa de revisão (kit do escritor, seção 6).

// Separação sem regex (regra do projeto): indexOf(' | ') acha o fim de "caminho:linha";
// lastIndexOf(':') dentro dessa parte acha o número, mesmo que o trecho tenha ":" dentro.
export const analisarEvidencia = linha => {
  const separador = linha.indexOf(' | ');
  if (separador === -1) return null;

  const local = linha.slice(0, separador);
  const trecho = linha.slice(separador + 3);
  const doisPontos = local.lastIndexOf(':');
  if (doisPontos === -1) return null;

  const caminho = local.slice(0, doisPontos);
  const numero = Number(local.slice(doisPontos + 1));
  if (!caminho || !trecho || !Number.isInteger(numero) || numero <= 0) return null;

  return { caminho, numero, trecho };
};

const situacaoDaEvidencia = (evidencia, raiz) => {
  const analisada = analisarEvidencia(evidencia);
  if (!analisada) return { situacao: 'malformada', evidencia };

  const { caminho, numero, trecho } = analisada;
  const absoluto = r(raiz, caminho);
  if (!fs.existsSync(absoluto)) {
    return { situacao: 'arquivo_ausente', caminho, numero, trecho };
  }

  const linhas = fs.readFileSync(absoluto, 'utf8').split('\n');
  if ((linhas[numero - 1] || '').trim() === trecho) {
    return { situacao: 'ok', caminho, numero, trecho };
  }

  const novaLinha = linhas.findIndex(linha => linha.trim() === trecho);
  if (novaLinha !== -1) {
    return { situacao: 'linha_mudou', caminho, numero, trecho, novaLinha: novaLinha + 1 };
  }

  return { situacao: 'trecho_sumiu', caminho, numero, trecho };
};

// Uma linha por evidência do artigo, com a situação dela contra o arquivo-fonte.
export const evidenciasDoArtigo = (artigo, raiz) =>
  (artigo.cabecalho.evidencias || []).map(evidencia => ({
    artigo: artigo.arquivo,
    ...situacaoDaEvidencia(evidencia, raiz),
  }));

// ---------------------------------------------------------------------------
// Junta tudo

const listar = (titulo, itens, formatar = String) =>
  itens.length ? [titulo, ...itens.map(item => `  - ${formatar(item)}`)] : [];

export const conferir = ({ artigos, mapa, registro, humanos, raiz = process.cwd() }) => {
  const idsDoMapa = new Set(artigosDoMapa(mapa).keys());
  const cobertas = telasCobertas(mapa, artigos);

  const evidencias = artigos.flatMap(artigo => evidenciasDoArtigo(artigo, raiz));
  const evidenciasMalformadas = evidencias.filter(e => e.situacao === 'malformada');
  const evidenciasParaRevisao = evidencias.filter(
    e => e.situacao === 'arquivo_ausente' || e.situacao === 'trecho_sumiu'
  );
  const evidenciasComLinhaMudada = evidencias.filter(e => e.situacao === 'linha_mudou');

  const problemas = [
    ...listar(
      'Telas do Guia sem artigo na Central:',
      telasSemArtigo(registro, cobertas, humanos)
    ),
    ...listar(
      'Referências [dd.dd] quebradas:',
      referenciasQuebradas(artigos, idsDoMapa),
      ref => `${ref.artigo}: [${ref.referencia}]`
    ),
    ...listar(
      'me_leve_ate_la do cabeçalho diferente do mapa:',
      meLeveDivergente(artigos, mapa)
    ),
    ...listar('Artigo no disco sem entrada no mapa:', artigosSemMapa(artigos, mapa)),
    ...listar('Entrada do mapa sem arquivo no disco:', mapaSemArquivo(artigos, mapa)),
    ...listar(
      'Id do cabeçalho diferente do nome do arquivo:',
      idDivergenteDoArquivo(artigos)
    ),
    ...listar(
      'Evidência mal formada (não separa em "caminho:linha | trecho"):',
      evidenciasMalformadas,
      e => `${e.artigo}: ${e.evidencia}`
    ),
  ];

  // Evidência sumida é sinal de que o FATO pode ter mudado, não prova disso — por
  // isso é aviso local, e não falha o `central:check`. Quem decide se isso barra o
  // PR é a trava (scripts/central-de-ajuda/trava.mjs, #614 etapa B).
  const avisos = [
    ...listar(
      'Evidência para revisão (o trecho sumiu do arquivo, ou o arquivo foi apagado):',
      evidenciasParaRevisao,
      e => `${e.artigo}: ${e.caminho}:${e.numero}`
    ),
    ...listar(
      'Evidência mudou de linha no arquivo-fonte (só aviso, o trecho continua valendo):',
      evidenciasComLinhaMudada,
      e => `${e.artigo}: ${e.caminho}:${e.numero} → :${e.novaLinha}`
    ),
  ];

  return {
    ok: problemas.length === 0,
    problemas,
    avisos,
    artigos: artigos.length,
    telas: cobertas.size,
  };
};

// ---------------------------------------------------------------------------
// Execução

// Copiado para um arquivo .mjs temporário antes do import: o pacote não declara
// "type": "module", e importar o .js original por file:// dispara o aviso
// MODULE_TYPELESS_PACKAGE_JSON do Node (mesma solução de lerRegistroDe, em
// scripts/guide-map/aprendiz.mjs).
// Exportada para scripts/central-de-ajuda/trava.mjs (#614, etapa B) reaproveitar a
// leitura do registro atual, em vez de duplicar a solução do arquivo .js sem "type": "module".
export const carregarRegistro = async raiz => {
  const conteudo = fs.readFileSync(r(raiz, REGISTRY), 'utf8');
  const temporario = path.join(
    os.tmpdir(),
    `guide-route-registry-${process.pid}.mjs`
  );
  fs.writeFileSync(temporario, conteudo);
  try {
    const modulo = await import(pathToFileURL(temporario).href);
    return modulo.GUIDE_ROUTE_REGISTRY;
  } finally {
    fs.unlinkSync(temporario);
  }
};

const main = async () => {
  const raiz = process.cwd();
  const artigos = lerArtigos(raiz);
  const mapa = JSON.parse(fs.readFileSync(r(raiz, MAPA), 'utf8'));
  const humanos = lerPorques(fs.readFileSync(r(raiz, PORQUES), 'utf8'));
  const registro = await carregarRegistro(raiz);

  const resultado = conferir({ artigos, mapa, registro, humanos, raiz });

  if (resultado.avisos.length) {
    console.warn('Avisos (não falham o check local — a trava do PR decide):');
    resultado.avisos.forEach(linha => console.warn(linha));
  }

  if (!resultado.ok) {
    console.error('Central de Ajuda fora de dia:');
    resultado.problemas.forEach(linha => console.error(linha));
    process.exit(1);
  }

  console.log(
    `Central em dia: ${resultado.artigos} artigos, ${resultado.telas} telas cobertas.`
  );
};

if (process.argv[1] && process.argv[1].endsWith('conferir.mjs')) {
  await main();
}
