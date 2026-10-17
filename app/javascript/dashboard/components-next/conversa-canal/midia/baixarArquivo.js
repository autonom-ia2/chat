// Baixar o arquivo de verdade, com o nome dele (#1702). O link direto para o
// armazenamento abre o arquivo noutra aba (o S3 responde `inline`, e o atributo
// `download` não vale entre domínios): aqui o painel busca o arquivo e salva.
export const baixarArquivo = async ({ url, nome }) => {
  const resposta = await fetch(url, { cache: 'no-store' });
  if (!resposta.ok) throw new Error(`Download failed: ${resposta.status}`);

  const endereco = URL.createObjectURL(await resposta.blob());
  const link = Object.assign(document.createElement('a'), {
    href: endereco,
    download: nome,
    style: 'display: none',
  });
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(endereco);
};
