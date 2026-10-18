// Baixar o arquivo com um link direto (#1702). O painel não pode buscar o arquivo
// com fetch: o bucket de produção não tem CORS e a busca falha depois do redirect.
// O Active Storage aceita `disposition=attachment` e manda o armazenamento entregar
// como download, com o nome do arquivo. Endereço de fora (link externo) fica como
// está e abre noutra aba.
const CAMINHO_DO_ACTIVE_STORAGE = '/rails/active_storage/';

const lerEndereco = url => {
  try {
    return new URL(url, window.location.href);
  } catch {
    return null;
  }
};

export const doActiveStorage = url =>
  !!url && !!lerEndereco(url)?.pathname.includes(CAMINHO_DO_ACTIVE_STORAGE);

export const enderecoParaBaixar = url => {
  if (!doActiveStorage(url)) return url || '';
  const endereco = lerEndereco(url);
  endereco.searchParams.set('disposition', 'attachment');
  return endereco.toString();
};

// Para quem baixa sem um link na tela (o "Baixar" do menu do áudio): o mesmo link,
// clicado por baixo.
export const baixarPeloLink = ({ url, nome = '' }) => {
  const daqui = doActiveStorage(url);
  const link = Object.assign(document.createElement('a'), {
    href: enderecoParaBaixar(url),
    download: nome,
    style: 'display: none',
  });
  if (!daqui) {
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
  }
  document.body.append(link);
  link.click();
  link.remove();
};
