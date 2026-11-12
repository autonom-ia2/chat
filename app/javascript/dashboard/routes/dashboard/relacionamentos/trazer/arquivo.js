// #2894 — a planilha que a pessoa solta: só Excel e CSV. A conferência é pelo
// fim do nome do arquivo, sem regex.
export const EXTENSOES_ACEITAS = ['.xlsx', '.xls', '.csv'];
export const ACEITA_NO_SELETOR = EXTENSOES_ACEITAS.join(',');

export const ehPlanilha = nome => {
  const minusculo = String(nome ?? '')
    .trim()
    .toLowerCase();
  return EXTENSOES_ACEITAS.some(extensao => minusculo.endsWith(extensao));
};
