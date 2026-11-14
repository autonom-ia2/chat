// #2894 — a planilha que a pessoa solta: só Excel e CSV. A conferência é pelo
// fim do nome do arquivo, sem regex. O Excel antigo (.xls) ficou de fora
// (#2896): o servidor só lê .xlsx e .csv.
const EXTENSOES_ACEITAS = ['.xlsx', '.csv'];
export const ACEITA_NO_SELETOR = EXTENSOES_ACEITAS.join(',');

export const ehPlanilha = nome => {
  const minusculo = String(nome ?? '')
    .trim()
    .toLowerCase();
  return EXTENSOES_ACEITAS.some(extensao => minusculo.endsWith(extensao));
};
