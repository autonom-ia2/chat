// #2138 — o nome do arquivo a partir do endereço dele, sem a parte depois do "?".
// Nome com % solto (ex.: "50%.pdf") faz o decodeURIComponent lançar: fica o nome
// cru, para a lista de arquivos não quebrar por causa de um nome.
export const nomeDoArquivo = anexo => {
  const nome = String(anexo?.data_url || '')
    .split('?')[0]
    .split('/')
    .pop();
  if (!nome) return '';
  try {
    return decodeURIComponent(nome);
  } catch {
    return nome;
  }
};
