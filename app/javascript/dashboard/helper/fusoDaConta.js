// O fuso como a plataforma o mostra em Configurações da conta (#954): o nome do
// fuso, com espaço no lugar de "_" ("America/Sao Paulo"). Regra do Rodrigo
// (#1456): nunca o nome longo do navegador ("Horário Padrão de …").
export const rotuloDoFuso = fuso =>
  String(fuso || '')
    .split('_')
    .join(' ');
