// Tamanho da foto e do vídeo no balão, como no WhatsApp Web (#1702), medido no teste
// do Rodrigo em 17/10: o lado maior vai até 330 px e a proporção é a da mídia.
//   deitada (16:9, 3:2) — 330 de largura, altura pela proporção;
//   em pé (3:4, quadrada) — 330 de altura, largura pela proporção;
//   alta (9:16, print de celular) — 238 × 330, cortada no meio (o app não afina mais
//   que 0,72 de largura por altura).
// Sem as medidas ainda (antes de carregar), sai deitada.
export const PROPORCAO_MINIMA = 0.72;

export const FORMATOS = {
  deitada: 'w-[330px] h-auto max-w-full',
  emPe: 'h-[330px] w-auto max-w-full object-cover',
  alta: 'h-[330px] w-[238px] max-w-full object-cover',
};

export const formatoDaMidia = (largura, altura) => {
  if (!largura || !altura) return FORMATOS.deitada;
  const proporcao = largura / altura;
  if (proporcao >= 1) return FORMATOS.deitada;
  if (proporcao >= PROPORCAO_MINIMA) return FORMATOS.emPe;
  return FORMATOS.alta;
};
