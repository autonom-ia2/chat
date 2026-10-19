// Endereços que o HTML do remetente pode usar (#1884). Só endereço completo: relativo
// resolveria contra o painel (pedido com a sessão do atendente).
const PROTOCOLOS_DE_LINK = ['http:', 'https:', 'mailto:', 'tel:'];
const PROTOCOLOS_DE_IMAGEM = ['http:', 'https:'];
const IMAGEM_EMBUTIDA = 'data:image/';

// Completo de verdade: o mesmo resolvido contra qualquer página. `http:/x` (esquema sem
// "//") parece completo sozinho, mas na página de mesmo esquema vira caminho do painel.
const BASES_DE_PROVA = ['https://a.invalid/', 'http://b.invalid/'];
const enderecoCom = protocolos => endereco => {
  try {
    const texto = String(endereco || '').trim();
    const url = new URL(texto);
    const independente = BASES_DE_PROVA.every(
      base => new URL(texto, base).href === url.href
    );
    return independente && protocolos.includes(url.protocol) ? url.href : '';
  } catch {
    return '';
  }
};

export const linkSeguro = enderecoCom(PROTOCOLOS_DE_LINK);
const imagemWeb = enderecoCom(PROTOCOLOS_DE_IMAGEM);

export const imagemSegura = endereco => {
  const texto = String(endereco || '').trim();
  if (texto.toLowerCase().startsWith(IMAGEM_EMBUTIDA)) return texto;
  return imagemWeb(texto);
};

// Os endereços de um valor de CSS como o navegador o grava (CSSOM): `url("…")`, com
// `\"` e `\\` escapados. Lê a estrutura, sem regex.
const INICIO = 'url(';
const ASPAS = ['"', "'"];
const lerAspas = (texto, inicio) => {
  const aspa = texto[inicio];
  let valor = '';
  let i = inicio + 1;
  while (i < texto.length && texto[i] !== aspa) {
    if (texto[i] === '\\') i += 1;
    valor += texto[i] || '';
    i += 1;
  }
  return { valor, fim: i + 1 };
};
const lerEndereco = (texto, inicio) => {
  let i = inicio;
  while (texto[i] === ' ') i += 1;
  if (ASPAS.includes(texto[i])) return lerAspas(texto, i);
  const fim = texto.indexOf(')', i);
  const ate = fim < 0 ? texto.length : fim;
  return { valor: texto.slice(i, ate).trim(), fim: ate };
};

export const urlsDoValor = texto => {
  const minusculo = texto.toLowerCase();
  const urls = [];
  let achou = minusculo.indexOf(INICIO);
  while (achou >= 0) {
    const { valor, fim } = lerEndereco(texto, achou + INICIO.length);
    urls.push(valor);
    achou = minusculo.indexOf(INICIO, fim);
  }
  return urls;
};

// Tira do estilo toda declaração com endereço que não seja imagem completa web ou
// embutida. O sanitizador troca url() por regex e, se a troca sai inválida (um ")" dentro
// das aspas), o navegador ignora e o original fica: por isso a conferência vem antes.
export const semUrlInsegura = estilo => {
  const nomes = Array.from({ length: estilo.length }, (_, i) => estilo.item(i));
  nomes
    .filter(nome =>
      urlsDoValor(estilo.getPropertyValue(nome)).some(url => !imagemSegura(url))
    )
    .forEach(nome => estilo.removeProperty(nome));
};
