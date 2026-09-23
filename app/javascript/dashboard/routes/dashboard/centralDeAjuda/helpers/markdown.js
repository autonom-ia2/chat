import MarkdownIt from 'markdown-it';

// Os artigos vêm do repositório em Markdown, com linhas quebradas a cada ~80 caracteres. Por isso
// `breaks: false` (o formatador das mensagens usa `true` e partiria o parágrafo) e `html: false`: nada de
// HTML cru. O HTML resultante ainda passa pelo v-dompurify-html na tela.
const md = new MarkdownIt({ html: false, linkify: true, breaks: false });

export const PREFIXO_DO_ARTIGO = 'plataforma-';

// Link para outro artigo da Central: `plataforma-02-04` → `02-04`. Qualquer outro link devolve null.
export const refDoLink = href =>
  href && href.startsWith(PREFIXO_DO_ARTIGO)
    ? href.slice(PREFIXO_DO_ARTIGO.length)
    : null;

const linkAberto = md.renderer.rules.link_open;
md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
  const href = tokens[idx].attrGet('href') || '';
  if (!refDoLink(href)) {
    tokens[idx].attrSet('target', '_blank');
    tokens[idx].attrSet('rel', 'noopener noreferrer');
  }
  return linkAberto
    ? linkAberto(tokens, idx, options, env, self)
    : self.renderToken(tokens, idx, options);
};

export const renderizar = texto => md.render(texto || '');
