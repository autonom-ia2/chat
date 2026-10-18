// Modelo de e-mail das Campanhas na resposta (#1786): o que o navegador faz com ele.
// 1. tira o rodapé de descadastro (a mj-section com css-class "footer-locked"), que
//    não tem sentido numa resposta a um cliente;
// 2. compila o MJML com o compilador único do painel, o mesmo do editor das Campanhas
//    (compileEmailMjml, #1118), carregado só quando alguém abre um modelo;
// 3. troca as variáveis {{ ... }} pelos valores que o atendente conferiu.
// Tudo por estrutura (DOMParser) e por busca de texto, sem regex.

const ABRE = '{{';
const FECHA = '}}';
const RODAPE = 'footer-locked';

const temClasse = (elemento, classe) =>
  String(elemento.getAttribute('css-class') || elemento.className || '')
    .split(' ')
    .includes(classe);

export const mjmlSemRodape = mjml => {
  const doc = new DOMParser().parseFromString(mjml, 'application/xml');
  if (doc.getElementsByTagName('parsererror').length) return mjml;
  [...doc.getElementsByTagName('mj-section')]
    .filter(secao => temClasse(secao, RODAPE))
    .forEach(secao => secao.remove());
  return new XMLSerializer().serializeToString(doc);
};

export const htmlSemRodape = html => {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  doc.querySelectorAll(`.${RODAPE}`).forEach(no => no.remove());
  return `<!doctype html>${doc.documentElement.outerHTML}`;
};

// MJML do modelo, sem o rodapé, compilado; sem MJML (ou se não compilar), o HTML
// salvo. O rodapé sai de novo depois de compilar: MJML com HTML solto dentro (um <br>)
// não é XML válido, e aí só o HTML compilado (div.footer-locked) dá para cortar.
export const montarModelo = async ({ mjml, html }) => {
  // Importado só aqui: o compilador (GrapesJS) não pesa na caixa de resposta.
  const { compileEmailMjml } = await import(
    'dashboard/helper/compileEmailMjml'
  );
  const compilado = mjml ? await compileEmailMjml(mjmlSemRodape(mjml)) : '';
  return htmlSemRodape(compilado || html || '');
};

// O valor pode cair dentro de um atributo (href, alt): aspas também viram entidade.
const escapar = texto => {
  const div = document.createElement('div');
  div.textContent = String(texto ?? '');
  return div.innerHTML.split('"').join('&quot;').split("'").join('&#39;');
};

// Troca cada {{ chave }} (com ou sem filtro "| ...") pelo valor. `marcar`: na prévia,
// campo vazio aparece destacado com o nome, para o atendente ver o que falta.
export const preencherModelo = (html, valores, { marcar = false } = {}) => {
  let saida = '';
  let posicao = 0;
  let inicio = html.indexOf(ABRE);
  while (inicio >= 0) {
    const fim = html.indexOf(FECHA, inicio + ABRE.length);
    if (fim < 0) break;
    const chave = html
      .slice(inicio + ABRE.length, fim)
      .split('|')[0]
      .trim();
    const valor = String(valores[chave] ?? '').trim();
    let troca = escapar(valor);
    if (!valor && marcar) {
      troca = `<mark style="background:#fde68a;color:#78350f;border-radius:3px;padding:0 3px">${escapar(chave)}</mark>`;
    }
    saida += html.slice(posicao, inicio) + troca;
    posicao = fim + FECHA.length;
    inicio = html.indexOf(ABRE, posicao);
  }
  return saida + html.slice(posicao);
};

// Texto do modelo (o "conteúdo" da mensagem quando o atendente manda só o modelo):
// o CRM e a IA leem isto.
const BLOCOS = 'p, div, tr, li, h1, h2, h3, h4, h5, h6, table, blockquote';
export const textoDoModelo = html => {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  doc.querySelectorAll('style, script, head').forEach(no => no.remove());
  doc.querySelectorAll('br').forEach(no => no.replaceWith('\n'));
  doc.querySelectorAll(BLOCOS).forEach(no => no.append('\n'));
  return (doc.body?.textContent || '')
    .split('\n')
    .map(linha => linha.trim())
    .filter(Boolean)
    .join('\n');
};

// Nome amigável dos campos mais comuns; o resto aparece como está no modelo.
const NOMES = {
  'contact.name': 'NOME',
  nome: 'NOME',
  name: 'NOME',
  'contact.first_name': 'PRIMEIRO_NOME',
  primeiro_nome: 'PRIMEIRO_NOME',
  'contact.email': 'EMAIL',
  email: 'EMAIL',
  'contact.phone_number': 'TELEFONE',
  telefone: 'TELEFONE',
  'contact.company': 'EMPRESA',
  empresa: 'EMPRESA',
  'agent.name': 'ATENDENTE',
};
export const chaveDoNomeDoCampo = chave => NOMES[String(chave).toLowerCase()];

// Prévia do modelo numa moldura (iframe sandbox, sem script): links sem clique, e sem o que
// navega a moldura sozinho (meta refresh, base) — o servidor tira os mesmos no envio.
export const htmlDePrevia = html => {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  doc
    .querySelectorAll('script, base, meta[http-equiv]')
    .forEach(no => no.remove());
  const estilo = doc.createElement('style');
  estilo.textContent = 'a{pointer-events:none}body{margin:0}';
  doc.head.append(estilo);
  return `<!doctype html>${doc.documentElement.outerHTML}`;
};
