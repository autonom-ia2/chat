// O fuso como a plataforma o mostra em Configurações da conta (#954): o nome do
// fuso, com espaço no lugar de "_" ("America/Sao Paulo"). Regra do Rodrigo
// (#1456): nunca o nome longo do navegador ("Horário Padrão de …").
export const rotuloDoFuso = fuso =>
  String(fuso || '')
    .split('_')
    .join(' ');

const fusoValido = fuso => {
  if (!fuso) return false;
  try {
    Intl.DateTimeFormat('en', { timeZone: fuso });
    return true;
  } catch {
    return false;
  }
};

// #1568: o fuso da conta (Configurações grava custom_attributes.timezone e o
// servidor copia para settings.reporting_timezone). Sem fuso na conta, o padrão
// que o CRM usa no back, que o servidor manda em CRM_DEFAULT_TIMEZONE (sempre
// preenchido) — nunca o do navegador.
export const fusoDaConta = account =>
  [
    account?.timezone,
    account?.custom_attributes?.timezone,
    account?.settings?.reporting_timezone,
    window.globalConfig?.CRM_DEFAULT_TIMEZONE,
  ].find(fusoValido);
