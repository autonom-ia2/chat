// E-mail só com texto e imagem embutida (#1942): o Chatwoot põe a imagem dentro do próprio
// text_content.full, como `<img src="URL" alt="NOME">` (MailboxHelper
// #embed_plain_text_email_with_inline_image). Mostrado como texto, a tag aparecia crua.
// Aqui só esse formato fixo, achado por métodos de string, vira imagem; todo o resto
// continua texto (um "De: Ana <ana@x.com>" segue como está), escapado e linha a linha.
// O HTML que sai vai para o Letter, que sanitiza e confere o endereço da imagem.
const ABRE = '<img src="';
const ALT = '" alt="';
const FECHA = '">';

// Os pedaços do texto: { texto } ou { imagem: { src, alt } }, na ordem.
const pedacos = texto => {
  const saida = [];
  let resto = texto;
  while (resto.includes(ABRE)) {
    const inicio = resto.indexOf(ABRE);
    const meio = resto.indexOf(ALT, inicio + ABRE.length);
    const fim = meio === -1 ? -1 : resto.indexOf(FECHA, meio + ALT.length);
    if (fim === -1) break;
    const src = resto.slice(inicio + ABRE.length, meio);
    if (src.includes('"') || src.includes('<')) break;
    saida.push({ texto: resto.slice(0, inicio) });
    saida.push({ imagem: { src, alt: resto.slice(meio + ALT.length, fim) } });
    resto = resto.slice(fim + FECHA.length);
  }
  saida.push({ texto: resto });
  return saida;
};

// HTML do texto com as imagens do Chatwoot; '' quando não há imagem (o texto segue como texto).
export const htmlDoTextoComImagens = texto => {
  const lista = pedacos(String(texto || ''));
  if (!lista.some(pedaco => pedaco.imagem)) return '';
  const div = document.createElement('div');
  lista.forEach(({ texto: trecho, imagem }) => {
    if (imagem) {
      const img = document.createElement('img');
      img.setAttribute('src', imagem.src);
      img.setAttribute('alt', imagem.alt);
      div.append(img);
      return;
    }
    trecho.split('\n').forEach((linha, indice) => {
      if (indice) div.append(document.createElement('br'));
      div.append(document.createTextNode(linha));
    });
  });
  return div.innerHTML;
};
