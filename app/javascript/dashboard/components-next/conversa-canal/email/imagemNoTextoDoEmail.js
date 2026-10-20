// E-mail só com texto e imagem embutida (#1942): o Chatwoot põe a imagem dentro do próprio
// text_content.full, como `<img src="URL" alt="NOME">` (MailboxHelper
// #embed_plain_text_email_with_inline_image). Mostrado como texto, a tag aparecia crua.
// Aqui só esse formato fixo, achado por métodos de string, vira imagem; todo o resto
// continua texto (um "De: Ana <ana@x.com>" segue como está), escapado e linha a linha.
// Só vale a imagem que o próprio Chatwoot guardou: endereço deste painel, no caminho dos
// arquivos (url_for do blob). Uma tag escrita pelo remetente com outro endereço segue como
// texto: não vira pixel de leitura nem pedido a outra rota do painel com a sessão.
// O HTML que sai vai para o Letter, que sanitiza e confere o endereço de novo.
const ABRE = '<img src="';
const ALT = '" alt="';
const FECHA = '">';
const ARQUIVOS_DO_PAINEL = '/rails/active_storage/blobs/';

const ehArquivoDoPainel = src => {
  try {
    const endereco = new URL(src);
    return (
      endereco.origin === window.location.origin &&
      endereco.pathname.startsWith(ARQUIVOS_DO_PAINEL)
    );
  } catch {
    return false;
  }
};

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
    const alt = resto.slice(meio + ALT.length, fim);
    const valida =
      !src.includes('"') && !alt.includes('"') && ehArquivoDoPainel(src);
    const fimDaTag = fim + FECHA.length;
    saida.push(
      valida
        ? { texto: resto.slice(0, inicio) }
        : { texto: resto.slice(0, fimDaTag) }
    );
    if (valida) saida.push({ imagem: { src, alt } });
    resto = resto.slice(fimDaTag);
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
