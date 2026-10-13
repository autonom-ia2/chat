// PROTÓTIPO (#1338): números de mentira da "saúde do modelo" para o Rodrigo
// aprovar a tela. Sai quando o endpoint real existir: a lista de modelos passa a
// trazer `health` de cada um e o adaptador lê de lá (uma linha em adaptadorHttp).
//
// Saude = {
//   dias: 30,                  janela contada (últimos 30 dias)
//   enviadas, entregues, lidas, responderam,   pessoas, só envios pelo Chat2You
//   custo: { total, porResposta | null, moeda } | null,
//   mediaDeRespostas,          % médio de resposta dos modelos da conta
// }
// `enviadas: 0`: não saiu nos últimos 30 dias.

const PRECO = { MARKETING: 0.3217, UTILITY: 0.035, AUTHENTICATION: 0.035 };
const MEDIA_DE_RESPOSTAS = 14;

const NUMEROS = {
  customer_satisfaction_survey_41: [412, 405, 371, 96],
  agendamento_1_dia_antes_v1: [863, 851, 802, 377],
  boas_vindas_v1: [1240, 1198, 610, 31],
  novidades_da_semana: [530, 522, 301, 42],
  confirmacao_pedido: [97, 95, 88, 40],
  chat2you_resumo_anuncios: [30, 30, 27, 2],
  chat2you_alerta_anuncio: [4, 4, 4, 1],
  retomar_conversa: [380, 371, 140, 9],
};

const arredondar = valor => Math.round(valor * 100) / 100;

export const saudeFalsa = template => {
  const [enviadas, entregues, lidas, responderam] = NUMEROS[template.name] || [
    0, 0, 0, 0,
  ];
  const preco = PRECO[String(template.category).toUpperCase()] || 0;
  const total = arredondar(entregues * preco);
  return {
    dias: 30,
    enviadas,
    entregues,
    lidas,
    responderam,
    custo: enviadas
      ? {
          total,
          porResposta: responderam ? arredondar(total / responderam) : null,
          moeda: 'BRL',
        }
      : null,
    mediaDeRespostas: MEDIA_DE_RESPOSTAS,
  };
};
