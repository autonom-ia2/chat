// #1801 — a tela inicial da caixa de conversas (painel da direita sem conversa aberta).
// Três opções em teste; a escolha vem da URL (?inicio=1|2|3, ?vazio=1 simula "nada esperando").
export const OPCOES = ['1', '2', '3'];

export const opcaoDaTela = query => {
  const opcao = String(query?.inicio ?? '');
  return OPCOES.includes(opcao) ? opcao : null;
};

export const vazioForcado = query => String(query?.vazio ?? '') === '1';

const MANHA_COMECA = 5;
const TARDE_COMECA = 12;
const NOITE_COMECA = 18;

export const periodoDoDia = hora => {
  if (hora >= MANHA_COMECA && hora < TARDE_COMECA) return 'MANHA';
  if (hora >= TARDE_COMECA && hora < NOITE_COMECA) return 'TARDE';
  return 'NOITE';
};

// A hora (0–23) no fuso da conta, nunca no do navegador.
export const horaNoFuso = (agora, fuso) =>
  Number(
    new Intl.DateTimeFormat('en-US', {
      hour: 'numeric',
      hourCycle: 'h23',
      timeZone: fuso,
    }).format(agora)
  );

export const primeiroNome = nome =>
  String(nome || '')
    .trim()
    .split(' ')[0];

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
