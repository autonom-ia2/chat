// Histórico em texto puro (#1869): quem responde pelo Mail do iPhone, ou em texto sem
// formatação, manda o e-mail anterior como linhas começando por ">" (">>" nos níveis
// mais fundos), muitas vezes com "Em ..., Fulano escreveu:" logo acima. Não há
// <blockquote>, então o extrator do Chatwoot não acha nada e o histórico aparece
// inteiro. O ">" no começo da linha é marca do próprio e-mail, não texto da pessoa:
// lemos por linha com métodos de string, e o cabeçalho só pela posição (a linha logo
// acima, terminada em ":"), sem lista de palavras. Só sai o bloco que vai até o fim do
// e-mail; citação no meio, com resposta embaixo, fica.

// Elementos que começam linha nova no HTML (o resto corre na mesma linha).
const QUEBRAM_LINHA = new Set([
  'ADDRESS',
  'ARTICLE',
  'BLOCKQUOTE',
  'BODY',
  'DD',
  'DIV',
  'DL',
  'DT',
  'FOOTER',
  'H1',
  'H2',
  'H3',
  'H4',
  'H5',
  'H6',
  'HEADER',
  'HR',
  'LI',
  'OL',
  'P',
  'PRE',
  'SECTION',
  'TABLE',
  'TD',
  'TR',
  'UL',
]);
const COM_CONTEUDO_SEM_TEXTO = ['IMG', 'VIDEO', 'AUDIO', 'PICTURE', 'SVG'];

// As linhas do e-mail como o leitor as vê, cada uma com o ponto do DOM onde começa.
const linhasDoHtml = raiz => {
  const linhas = [{ texto: '', inicio: null }];
  const atual = () => linhas[linhas.length - 1];
  const quebrar = () => {
    if (atual().texto || atual().inicio)
      linhas.push({ texto: '', inicio: null });
  };
  const ler = no => {
    if (no.nodeType === Node.TEXT_NODE) {
      let posicao = 0;
      no.data.split('\n').forEach((parte, indice) => {
        if (indice > 0) quebrar();
        if (parte && !atual().inicio) {
          atual().inicio = { no, posicao };
        }
        atual().texto += parte;
        posicao += parte.length + 1;
      });
      return;
    }
    if (no.nodeType !== Node.ELEMENT_NODE) return;
    if (no.tagName === 'BR') {
      quebrar();
      return;
    }
    const bloco = QUEBRAM_LINHA.has(no.tagName);
    if (bloco) quebrar();
    no.childNodes.forEach(ler);
    if (bloco) quebrar();
  };
  raiz.childNodes.forEach(ler);
  return linhas.filter(linha => linha.texto.trim() && linha.inicio);
};

const citada = linha => linha.texto.trimStart().startsWith('>');
const ehCabecalho = linha =>
  Boolean(linha) && linha.texto.trimEnd().endsWith(':');

// Onde começa o bloco citado que vai até o fim (com o cabeçalho, se houver); -1 se não há.
const inicioDaCitacaoFinal = linhas => {
  let primeira = linhas.length;
  while (primeira > 0 && citada(linhas[primeira - 1])) primeira -= 1;
  if (primeira === linhas.length) return -1;
  return ehCabecalho(linhas[primeira - 1]) ? primeira - 1 : primeira;
};

// Tira do fim as quebras e os elementos que ficaram vazios com o corte.
const limparFim = no => {
  let ultimo = no.lastChild;
  while (ultimo) {
    const vazio =
      ultimo.nodeName === 'BR' ||
      (ultimo.nodeType === Node.TEXT_NODE && !ultimo.data.trim()) ||
      (ultimo.nodeType === Node.ELEMENT_NODE &&
        !COM_CONTEUDO_SEM_TEXTO.includes(ultimo.tagName) &&
        !ultimo.querySelector(COM_CONTEUDO_SEM_TEXTO.join(',')) &&
        !ultimo.textContent.trim());
    if (!vazio) {
      if (ultimo.nodeType === Node.ELEMENT_NODE) limparFim(ultimo);
      return;
    }
    ultimo.remove();
    ultimo = no.lastChild;
  }
};

// Corta, na própria árvore, o histórico com ">" do fim do e-mail. Devolve se cortou.
// Se o corte deixaria o e-mail sem nada, não corta: melhor mostrar tudo que esconder.
export const cortarCitacaoComSinal = raiz => {
  const linhas = linhasDoHtml(raiz);
  const inicio = inicioDaCitacaoFinal(linhas);
  if (inicio <= 0) return false;

  const { no, posicao } = linhas[inicio].inicio;
  const trecho = document.createRange();
  trecho.setStart(no, posicao);
  trecho.setEnd(raiz, raiz.childNodes.length);
  trecho.deleteContents();
  limparFim(raiz);
  return true;
};
