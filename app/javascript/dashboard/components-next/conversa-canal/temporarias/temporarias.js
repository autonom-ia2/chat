// Mensagens temporárias (#1709): quando o cliente liga, troca ou desliga o tempo, o
// servidor grava uma mensagem de aviso (activity) com
// content_attributes.waha_ephemeral = { expiration_seconds, at } (0 = desligadas).
// Com a pele, o aviso vira a frase do app ("…vão desaparecer desta conversa após 7 dias").

const SEGUNDOS_POR_HORA = 3600;
const SEGUNDOS_POR_DIA = 24 * SEGUNDOS_POR_HORA;
const A_PARTIR_DE_DIAS = 2;

export const avisoDeTemporarias = atributos => {
  const marca = atributos?.wahaEphemeral;
  const segundos = marca?.expirationSeconds;
  if (!Number.isInteger(segundos) || segundos < 0) return null;
  if (segundos === 0) return { ligadas: false };
  // O app oferece 24 horas, 7 dias e 90 dias: até 2 dias fala em horas ("24 horas"),
  // como o app; a partir daí, em dias.
  const dias = Math.floor(segundos / SEGUNDOS_POR_DIA);
  if (dias >= A_PARTIR_DE_DIAS) return { ligadas: true, dias };
  return {
    ligadas: true,
    horas: Math.max(1, Math.floor(segundos / SEGUNDOS_POR_HORA)),
  };
};
