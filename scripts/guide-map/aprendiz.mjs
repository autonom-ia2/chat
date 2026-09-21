/* eslint-disable no-console -- script de linha de comando: o log do CI é a saída dele */
// Modo aprendiz do Guia da Plataforma (issue #537).
//
// O mapa do Guia vem do código (#534), mas o "porquê" de cada tela continua
// escrito por gente — e escrever isso do zero é o que trava a atualização. A
// cada deploy, este script compara o mapa novo com o do deploy anterior e, se
// entrou tela nova, pede à IA o RASCUNHO da explicação. O rascunho chega como
// Pull Request: nada vai para o Guia sem alguém revisar e fazer o merge.
//
// Sem mudança no mapa, não faz nada e não avisa ninguém.
import fs from 'fs';
import os from 'os';
import path from 'path';
import { execFileSync } from 'child_process';
import { pathToFileURL } from 'url';
import { construir } from './build.mjs';

const raiz = process.cwd();
const r = p => path.resolve(raiz, p);

const PORQUES = 'lib/operator_guide/porques.md';
const REGISTRY = 'app/javascript/dashboard/helper/guideRouteRegistry.js';
const ROTAS = 'app/javascript/dashboard/routes';
const FORA_DO_GUIA = '_fora_do_guia';
const CABECALHO = '### ';
const ENDPOINT = 'https://api.openai.com/v1/responses';
// O mesmo modelo que escreve as respostas do Guia em produção.
const MODELO_PADRAO = 'gpt-5.6-sol';
// O suficiente para entender a tela; um componente inteiro às vezes passa de
// mil linhas, e o que importa está no começo (template e props).
const MAX_CODIGO = 8000;
const LINHAS_EM_VOLTA = 15;

// ---------------------------------------------------------------------------
// O que mudou

// `antes` é o que foi para o ar no deploy anterior (os nomes do registro que o
// build gerou); `depois` é o roteador de agora. Tela nova só pede rascunho se
// ainda não tiver explicação — quem escreveu o porquê junto com a tela não
// precisa de rascunho.
export const mudancasDoMapa = ({ antes, depois, semExplicacao, humanos }) => {
  const nomesAntes = new Set(antes);
  const nomesDepois = new Set(depois.map(tela => tela.nome));
  const precisamDeExplicacao = new Set(semExplicacao);

  const entraram = depois.filter(
    tela => !nomesAntes.has(tela.nome) && precisamDeExplicacao.has(tela.nome)
  );
  const sairam = [...nomesAntes].filter(nome => !nomesDepois.has(nome));
  const saiu = new Set(sairam);

  const blocosSemTela = Object.entries(humanos)
    .filter(
      ([chave, humano]) => chave !== FORA_DO_GUIA && saiu.has(humano.rota)
    )
    .map(([chave]) => chave);

  // Bloco que explica várias telas e perdeu UMA delas não sai: só perde o nome
  // da tela que sumiu, na lista `cobre:`. O texto dele continua valendo.
  const cobreSemTela = Object.entries(humanos)
    .filter(([chave]) => !blocosSemTela.includes(chave))
    .map(([chave, humano]) => ({
      chave,
      telas: (humano.cobre || '')
        .split(',')
        .map(nome => nome.trim())
        .filter(nome => saiu.has(nome)),
    }))
    .filter(({ telas }) => telas.length);

  return { entraram, sairam, blocosSemTela, cobreSemTela };
};

// "Mudou" quer dizer: há algo para alguém revisar. Tela que saiu sem nenhum
// texto citando ela não pede nada a ninguém — e um PR sem mudança nenhuma nem
// pode ser aberto. Medido rodando contra um deploy antigo: saiu
// `onboarding_first_steps`, nenhum bloco a citava, e a versão anterior
// anunciava mudança sem ter arquivo nenhum para mostrar.
export const nadaMudou = ({ entraram, blocosSemTela, cobreSemTela }) =>
  entraram.length === 0 &&
  blocosSemTela.length === 0 &&
  cobreSemTela.length === 0;

// ---------------------------------------------------------------------------
// O rascunho no formato do porques.md

// Cada campo mora numa linha só: é assim que o gerador lê o arquivo. Quebra de
// linha no meio do texto da IA faria o resto do campo sumir do Guia.
const numaLinha = texto =>
  String(texto || '')
    .split('\n')
    .map(parte => parte.trim())
    .filter(Boolean)
    .join(' ');

const CAMPOS = [
  'titulo',
  'intent',
  'onde_fica',
  'perfil',
  'pre_requisitos',
  'passos',
  'gotchas',
];

export const montarBloco = (tela, rascunho) => {
  const linhas = [`${CABECALHO}${tela.nome}`];
  CAMPOS.forEach(campo => {
    const valor = numaLinha(rascunho[campo]);
    if (valor) linhas.push(`- ${campo}: ${valor}`);
    // A rota vai logo depois do título, como nos blocos escritos à mão.
    if (campo === 'titulo') linhas.push(`- rota: ${tela.nome}`);
  });
  return linhas.join('\n');
};

const PREFIXO_COBRE = '- cobre:';

// A linha `cobre:` sem as telas que saíram. Se não sobrar nenhuma, a linha sai.
const cobreSem = (linha, telas) => {
  const fora = new Set(telas);
  const restantes = linha
    .slice(PREFIXO_COBRE.length)
    .split(',')
    .map(nome => nome.trim())
    .filter(nome => nome && !fora.has(nome));
  return restantes.length ? `${PREFIXO_COBRE} ${restantes.join(', ')}` : null;
};

// Tira os blocos das telas que saíram, limpa o `cobre:` dos que perderam uma
// tela, e acrescenta os rascunhos no fim. O resto do arquivo fica exatamente
// como estava — é texto de gente.
export const aplicarNoPorques = (
  texto,
  { novos, remover, limparCobre = [] }
) => {
  const sai = new Set(remover);
  const cobrePorBloco = new Map(
    limparCobre.map(({ chave, telas }) => [chave, telas])
  );
  let atual = null;
  const mantidas = texto.split('\n').flatMap(linha => {
    if (linha.startsWith(CABECALHO))
      atual = linha.slice(CABECALHO.length).trim();
    if (sai.has(atual)) return [];
    if (cobrePorBloco.has(atual) && linha.startsWith(PREFIXO_COBRE)) {
      const limpa = cobreSem(linha, cobrePorBloco.get(atual));
      return limpa ? [limpa] : [];
    }
    return [linha];
  });

  const corpo = mantidas.join('\n').trimEnd();
  if (!novos.length) return `${corpo}\n`;
  return `${corpo}\n\n${novos.join('\n\n')}\n`;
};

// ---------------------------------------------------------------------------
// A IA

const INSTRUCOES = [
  'Você escreve o RASCUNHO da explicação de uma tela de uma plataforma de atendimento e CRM,',
  'para o Guia da Plataforma: o assistente que ajuda atendentes, gestores e administradores a',
  'usarem o produto. Alguém vai revisar antes de publicar.',
  '',
  'Regras:',
  '- Escreva em português do Brasil, com as palavras que aparecem na tela, sem jargão técnico.',
  '- Use SÓ o que o código mostra. O que não der para saber com segurança, não invente: diga',
  '  em `duvidas`, para quem revisa completar.',
  '- `intent`: 3 ou 4 jeitos de uma pessoa perguntar por esta tela, separados por ponto e vírgula.',
  '- `onde_fica`: o caminho no menu, no formato "Seção > Tela".',
  '- `passos`: numerados, curtos, separados por ponto e vírgula.',
  '- `gotchas`: o que costuma dar errado ou confundir. Vazio se o código não mostrar nada.',
  '- Cada campo é UMA linha de texto.',
  '',
  'Siga o estilo dos exemplos, que foram escritos à mão.',
].join('\n');

const ESQUEMA = {
  type: 'object',
  additionalProperties: false,
  required: [...CAMPOS, 'duvidas'],
  properties: Object.fromEntries(
    [...CAMPOS, 'duvidas'].map(campo => [campo, { type: 'string' }])
  ),
};

// A resposta da API crua não traz `output_text` pronto (isso é do SDK): o texto
// mora nos itens de saída do tipo mensagem.
const textoDaResposta = dados =>
  (dados.output || [])
    .filter(item => item.type === 'message')
    .flatMap(item => item.content || [])
    .filter(parte => parte.type === 'output_text')
    .map(parte => parte.text)
    .join('');

export const pedirRascunho = async ({
  tela,
  contexto,
  exemplos,
  chave,
  modelo = MODELO_PADRAO,
  buscar = fetch,
}) => {
  const entrada = [
    `Tela: ${tela.nome}`,
    `Endereço: ${tela.caminho}`,
    `Quem pode ver: ${(tela.papeis || []).join(', ') || 'sem restrição declarada'}`,
    tela.flag ? `Depende da feature: ${tela.flag}` : null,
    '',
    'Exemplos escritos à mão:',
    exemplos,
    '',
    'O que o código mostra desta tela:',
    contexto,
  ]
    .filter(linha => linha !== null)
    .join('\n');

  const resposta = await buscar(ENDPOINT, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${chave}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: modelo,
      instructions: INSTRUCOES,
      input: entrada,
      reasoning: { effort: 'medium' },
      text: {
        format: {
          type: 'json_schema',
          name: 'rascunho_da_tela',
          schema: ESQUEMA,
          strict: true,
        },
      },
    }),
  });

  // A chave nunca vai para a mensagem de erro — só o que a OpenAI disse.
  if (!resposta.ok) {
    const corpo = await resposta.json().catch(() => ({}));
    throw new Error(
      `a OpenAI recusou o rascunho de ${tela.nome} (HTTP ${resposta.status}): ${corpo?.error?.message || 'sem detalhe'}`
    );
  }

  return JSON.parse(textoDaResposta(await resposta.json()));
};

// ---------------------------------------------------------------------------
// O corpo do Pull Request

export const corpoDoPr = ({ commit, mudancas, rascunhos }) => {
  const partes = [
    `Rascunho do **modo aprendiz** (#537): o mapa da plataforma mudou no deploy de \`${commit}\`.`,
    '',
    '**Nada disto está no ar.** O Guia só passa a usar o que estiver neste PR depois do merge.',
    'Revise, corrija o que a IA errou, e faça o merge — ou feche, se não for para o Guia.',
  ];

  if (rascunhos.length) {
    partes.push(
      '',
      `## Telas novas (${rascunhos.length}) — rascunho escrito pela IA`
    );
    rascunhos.forEach(({ tela, rascunho }) => {
      partes.push(
        '',
        `### \`${tela.nome}\` — \`${tela.caminho}\``,
        `- Quem pode ver: ${(tela.papeis || []).join(', ') || 'sem restrição declarada'}`,
        `- **O que a IA não conseguiu saber:** ${numaLinha(rascunho.duvidas) || 'nada declarado'}`
      );
    });
  }

  if (mudancas.blocosSemTela.length) {
    partes.push(
      '',
      `## Blocos removidos (${mudancas.blocosSemTela.length}) — a tela deles não existe mais`
    );
    mudancas.blocosSemTela.forEach(chave => partes.push(`- \`${chave}\``));
  }

  if (mudancas.cobreSemTela.length) {
    partes.push('', '## Blocos que perderam uma das telas que explicavam');
    mudancas.cobreSemTela.forEach(({ chave, telas }) =>
      partes.push(
        `- \`${chave}\`: tirei do \`cobre:\` ${telas
          .map(nome => `\`${nome}\``)
          .join(
            ', '
          )}. O texto do bloco ficou como estava — confira se ainda faz sentido sem ela.`
      )
    );
  }

  return `${partes.join('\n')}\n`;
};

// ---------------------------------------------------------------------------
// Ler o que mudou (git, arquivos)

// O registro que foi para o ar no deploy anterior. Ele é um módulo JS gerado;
// importar é mais seguro do que tentar ler o texto dele.
const lerRegistroDe = async commit => {
  let fonte;
  try {
    fonte = execFileSync('git', ['show', `${commit}:${REGISTRY}`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch {
    return null; // o registro não existia naquele commit
  }
  const temporario = path.join(os.tmpdir(), `registro-${commit}.mjs`);
  fs.writeFileSync(temporario, fonte);
  const modulo = await import(pathToFileURL(temporario).href);
  return [...modulo.GUIDE_ROUTE_REGISTRY];
};

const arquivosDeRotas = () =>
  fs
    .readdirSync(r(ROTAS), { recursive: true })
    .filter(nome => nome.endsWith('.js'))
    .map(nome => path.join(r(ROTAS), nome));

const ALIAS_DASHBOARD = 'dashboard/';

const caminhoDoImport = (linhaDeImport, arquivo) => {
  const aspas = linhaDeImport.includes("'") ? "'" : '"';
  const inicio = linhaDeImport.indexOf(aspas) + 1;
  const destino = linhaDeImport.slice(
    inicio,
    linhaDeImport.indexOf(aspas, inicio)
  );
  if (destino.startsWith(ALIAS_DASHBOARD)) {
    return r(
      `app/javascript/dashboard/${destino.slice(ALIAS_DASHBOARD.length)}`
    );
  }
  if (destino.startsWith('.'))
    return path.resolve(path.dirname(arquivo), destino);
  return null;
};

const codigoDoComponente = (linhas, trecho, arquivo) => {
  const linhaDoComponente = trecho
    .split('\n')
    .find(linha => linha.trim().startsWith('component:'));
  if (!linhaDoComponente) return 'O componente da tela não foi identificado.';

  const nomeDoComponente = linhaDoComponente
    .split('component:')[1]
    .split(',')[0]
    .trim();
  const importacao = linhas.find(
    linha =>
      linha.startsWith('import ') &&
      linha.includes(` ${nomeDoComponente} `) &&
      linha.includes(' from ')
  );
  const destino = importacao && caminhoDoImport(importacao, arquivo);
  if (!destino || !fs.existsSync(destino)) {
    return `O componente \`${nomeDoComponente}\` não foi localizado no disco.`;
  }
  const codigo = fs.readFileSync(destino, 'utf8').slice(0, MAX_CODIGO);
  return `Componente (${path.relative(raiz, destino)}):\n${codigo}`;
};

// Onde a tela é declarada no roteador, e o componente que ela abre. É o melhor
// retrato da tela que o código oferece sem subir a aplicação.
const contextoDaTela = nome => {
  const marca = `name: '${nome}'`;
  const arquivo = arquivosDeRotas().find(caminho =>
    fs.readFileSync(caminho, 'utf8').includes(marca)
  );
  if (!arquivo) return 'Não encontrei a declaração desta tela no roteador.';

  const linhas = fs.readFileSync(arquivo, 'utf8').split('\n');
  const onde = linhas.findIndex(linha => linha.includes(marca));
  const trecho = linhas
    .slice(Math.max(0, onde - LINHAS_EM_VOLTA), onde + LINHAS_EM_VOLTA)
    .join('\n');

  return [
    `Declaração no roteador (${path.relative(raiz, arquivo)}):`,
    trecho,
    '',
    codigoDoComponente(linhas, trecho, arquivo),
  ].join('\n');
};

// Dois blocos de verdade, para a IA copiar o estilo e não o conteúdo.
const exemplosDoPorques = humanosTexto =>
  humanosTexto
    .split(`\n${CABECALHO}`)
    .filter(bloco => !bloco.startsWith(FORA_DO_GUIA))
    .slice(1, 3)
    .map(bloco => `${CABECALHO}${bloco.trim()}`)
    .join('\n\n');

// ---------------------------------------------------------------------------
// Execução

const avisarGitHub = (nome, valor) => {
  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `${nome}=${valor}\n`);
  }
};

const semCommitAnterior = commit =>
  !commit || [...commit].every(caractere => caractere === '0');

const executar = async () => {
  const antes = process.env.ANTES;
  if (semCommitAnterior(antes)) {
    console.log('Sem deploy anterior para comparar. Nada a propor.');
    return avisarGitHub('mudou', 'false');
  }

  const registroAntes = await lerRegistroDe(antes);
  if (!registroAntes) {
    console.log(`O mapa do Guia não existia em ${antes}. Nada a comparar.`);
    return avisarGitHub('mudou', 'false');
  }

  const atual = await construir({ escrever: false });
  const mudancas = mudancasDoMapa({
    antes: registroAntes,
    depois: atual.telas,
    semExplicacao: atual.semExplicacao,
    humanos: atual.humanos,
  });

  // Silêncio quando não há o que dizer (critério da #537).
  if (nadaMudou(mudancas)) {
    console.log(
      'Nada para revisar: nenhuma tela nova sem explicação, nenhuma explicação apontando ' +
        `para tela que saiu. (Telas que saíram sem ninguém citar: ${mudancas.sairam.length}.)`
    );
    return avisarGitHub('mudou', 'false');
  }

  const chave = process.env.OPENAI_API_KEY;
  if (mudancas.entraram.length && !chave) {
    console.error(
      `Entraram ${mudancas.entraram.length} tela(s) nova(s), mas o segredo OPENAI_API_KEY não está ` +
        'cadastrado no repositório. Cadastre em Settings > Secrets and variables > Actions.'
    );
    process.exit(1);
  }

  const texto = fs.readFileSync(r(PORQUES), 'utf8');
  const exemplos = exemplosDoPorques(texto);
  const rascunhos = [];
  // Uma tela por vez: são poucas por deploy, e erro numa não pode sumir no meio
  // de chamadas em paralelo.
  // eslint-disable-next-line no-restricted-syntax
  for (const tela of mudancas.entraram) {
    // eslint-disable-next-line no-await-in-loop
    const rascunho = await pedirRascunho({
      tela,
      contexto: contextoDaTela(tela.nome),
      exemplos,
      chave,
      modelo: process.env.MODELO || MODELO_PADRAO,
    });
    rascunhos.push({ tela, rascunho });
  }

  fs.writeFileSync(
    r(PORQUES),
    aplicarNoPorques(texto, {
      novos: rascunhos.map(({ tela, rascunho }) => montarBloco(tela, rascunho)),
      remover: mudancas.blocosSemTela,
      limparCobre: mudancas.cobreSemTela,
    })
  );
  await construir({ escrever: true });

  fs.writeFileSync(
    process.env.CORPO_DO_PR || r('tmp/guia-aprendiz.md'),
    corpoDoPr({
      commit: process.env.GITHUB_SHA || 'local',
      mudancas,
      rascunhos,
    })
  );
  console.log(
    `Rascunho pronto: ${rascunhos.length} tela(s) nova(s), ${mudancas.sairam.length} tela(s) que saíram.`
  );
  return avisarGitHub('mudou', 'true');
};

if (process.argv[1] && process.argv[1].endsWith('aprendiz.mjs')) {
  await executar();
}
