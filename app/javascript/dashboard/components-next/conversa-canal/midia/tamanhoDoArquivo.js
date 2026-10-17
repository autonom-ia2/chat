// Tamanho e tipo do arquivo como o WhatsApp mostra no cartão (#1702): "PDF • 107 KB",
// "MP4 • 6 MB". Bytes do anexo; sem tamanho, só o tipo.
const KB = 1024;
const MB = KB * 1024;

export const tamanhoDoArquivo = (bytes, idioma = 'pt-BR') => {
  if (!bytes) return '';
  // Arredonda antes de escolher a unidade: 1.048.575 bytes é "1 MB", não "1024 KB".
  const quilos = Math.max(1, Math.round(bytes / KB));
  if (quilos < KB) return `${quilos} KB`;
  const megas = bytes / MB;
  const casas = megas < 10 ? 1 : 0;
  return `${new Intl.NumberFormat(idioma, { maximumFractionDigits: casas }).format(megas)} MB`;
};

export const nomeDoArquivo = (anexo = {}) => {
  const endereco = anexo.dataUrl || '';
  const nome = endereco.slice(endereco.lastIndexOf('/') + 1).split('?')[0];
  try {
    return decodeURIComponent(nome);
  } catch {
    return nome;
  }
};

// Extensão pelo nome do arquivo no endereço (o anexo nem sempre traz `extension`).
export const extensaoDoArquivo = (anexo = {}) => {
  const doAnexo = anexo.extension || '';
  if (doAnexo) return doAnexo.replace('.', '').toUpperCase();
  const nome = nomeDoArquivo(anexo);
  const ponto = nome.lastIndexOf('.');
  return ponto > 0 ? nome.slice(ponto + 1).toUpperCase() : '';
};

export const resumoDoArquivo = (anexo, idioma) =>
  [extensaoDoArquivo(anexo), tamanhoDoArquivo(anexo?.fileSize, idioma)]
    .filter(Boolean)
    .join(' • ');
