// Janela de pareamento do WhatsApp via WAHA: o 1º QR vale 60 s e cada um dos
// seguintes vale 20 s, até 6 códigos. Depois a sessão vai para FAILED e precisa
// ser reiniciada (https://waha.devlike.pro/docs/how-to/sessions/).
export const FIRST_QR_SECONDS = 60;
export const NEXT_QR_SECONDS = 20;
export const MAX_QR_CODES = 6;

const secondsForCode = index =>
  index <= 1 ? FIRST_QR_SECONDS : NEXT_QR_SECONDS;

// Segundos que ainda restam para ler algum QR desta rodada de pareamento.
// `index` é a posição (1..6) do código na tela e `elapsed`, há quantos
// segundos ele apareceu. Como a tela pode abrir no meio de uma rodada, o
// valor é uma estimativa e a interface deve mostrá-lo como "cerca de".
export const qrSecondsLeft = (index, elapsed) => {
  const position = Math.min(Math.max(index, 1), MAX_QR_CODES);
  const current = Math.max(secondsForCode(position) - elapsed, 0);
  return current + (MAX_QR_CODES - position) * NEXT_QR_SECONDS;
};

export const formatSeconds = total => {
  const seconds = Math.max(Math.round(total), 0);
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, '0')}`;
};
