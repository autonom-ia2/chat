import * as Sentry from '@sentry/vue';

// O que vai ao Sentry não leva dado de cliente (#2092). Endereços de API
// carregam e-mail e telefone na query string (a busca de contatos põe o termo
// em `?q=`), então breadcrumbs e eventos saem só com o caminho.
const CATEGORIAS_COM_URL = ['xhr', 'fetch', 'navigation'];
const CHAVES_DE_URL = ['url', 'from', 'to'];

export const semQuery = url =>
  typeof url === 'string' ? url.split('#')[0].split('?')[0] : url;

const limparDados = (dados = {}) =>
  Object.fromEntries(
    Object.entries(dados).map(([chave, valor]) => [
      chave,
      CHAVES_DE_URL.includes(chave) ? semQuery(valor) : valor,
    ])
  );

export const breadcrumbSemQuery = breadcrumb =>
  CATEGORIAS_COM_URL.includes(breadcrumb?.category) && breadcrumb.data
    ? { ...breadcrumb, data: limparDados(breadcrumb.data) }
    : breadcrumb;

export const eventoSemQuery = evento => {
  const { request } = evento;
  const { query_string: _semQuery, ...resto } = request || {};
  return {
    ...evento,
    ...(request ? { request: { ...resto, url: semQuery(request.url) } } : {}),
    ...(evento.breadcrumbs
      ? { breadcrumbs: evento.breadcrumbs.map(breadcrumbSemQuery) }
      : {}),
  };
};

// A mensagem de uma exceção pode conter o que a pessoa digitou (ex.: o valor
// que quebrou um `.trim()`). Vai só o nome da classe e a pilha.
export const excecaoSemDados = erro => {
  const nome = erro?.name || 'Error';
  const mensagem = erro?.message || '';
  const pilha = typeof erro?.stack === 'string' ? erro.stack : '';
  // V8 abre a pilha com "Nome: mensagem"; Firefox e Safari só têm os quadros.
  const cabecalho = mensagem ? `${nome}: ${mensagem}` : nome;
  const quadros = pilha.startsWith(cabecalho)
    ? pilha.slice(cabecalho.length)
    : `\n${pilha}`;
  const limpa = new Error();
  limpa.name = nome;
  limpa.stack = `${nome}${quadros}`;
  return limpa;
};

// Reporta um defeito de tela sem dado pessoal: exceção sem mensagem nem
// causa, e evento sem breadcrumbs, `extra`, usuário nem endereço com query.
export const reportarSemDados = (erro, tags) =>
  Sentry.withScope(escopo => {
    escopo.clearBreadcrumbs();
    escopo.setTags(tags);
    escopo.addEventProcessor(evento => ({
      ...eventoSemQuery(evento),
      breadcrumbs: [],
      extra: {},
      user: undefined,
    }));
    Sentry.captureException(excecaoSemDados(erro));
  });
