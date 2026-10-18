// #1801 — a tela inicial da caixa de conversas (painel da direita sem conversa aberta).

const MINUTO = 60;
const HORA = 60;
const DIA = 24;

// Quanto tempo desde `desde` (segundos), na maior unidade inteira.
export const tempoDeEspera = (desde, agoraEmSegundos) => {
  const minutos = Math.max(1, Math.floor((agoraEmSegundos - desde) / MINUTO));
  if (minutos < HORA) return { unidade: 'MINUTOS', valor: minutos };
  const horas = Math.floor(minutos / HORA);
  if (horas < DIA) return { unidade: 'HORAS', valor: horas };
  return { unidade: 'DIAS', valor: Math.floor(horas / DIA) };
};
