// #2897 — o arquivo de uma apólice: PDF ou foto de celular. A conferência é
// pelo fim do nome do arquivo, sem regex (como trazer/arquivo.js).
export const EXTENSOES_DE_APOLICE = ['.pdf', '.jpg', '.jpeg', '.png', '.heic'];
export const ACEITA_APOLICES = EXTENSOES_DE_APOLICE.join(',');

export const ehApolice = nome => {
  const minusculo = String(nome ?? '')
    .trim()
    .toLowerCase();
  return EXTENSOES_DE_APOLICE.some(extensao => minusculo.endsWith(extensao));
};

export const soApolices = arquivos =>
  [...(arquivos ?? [])].filter(arquivo => ehApolice(arquivo?.name));
