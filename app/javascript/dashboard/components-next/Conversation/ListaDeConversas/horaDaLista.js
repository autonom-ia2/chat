// #2202 — o horário da linha 1 da lista, como no WhatsApp, no fuso da conta (#1568):
// "17:21" (hoje), "Ontem", "seg" (de 2 a 6 dias), "12/10" (mesmo ano) e "12/10/2025".
// E o horário com hora do "Adiada até", que é um compromisso no futuro:
// "hoje 15:00", "amanhã 9:00", "seg 9:00", "12/11 9:00".
// `quando` e `agora` em segundos. Sem regex: as datas saem do Intl em partes.
import {
  diaDaMensagem,
  horaDaMensagem,
} from 'dashboard/components-next/conversa-canal/dataDaConversa';

const DIA_EM_MS = 86400000;
const SEMANA = 7;

// "aaaa-mm-dd" (diaDaMensagem) → { ano, mes, dia, semana }.
const partesDoDia = chave => {
  const [ano, mes, dia] = chave.split('-').map(Number);
  const semana = new Date(Date.UTC(ano, mes - 1, dia)).getUTCDay();
  return { ano, mes, dia, semana };
};

const diasEntre = (chaveA, chaveB) =>
  Math.round((Date.parse(chaveA) - Date.parse(chaveB)) / DIA_EM_MS);

const doisDigitos = numero => String(numero).padStart(2, '0');

const dataCurta = ({ dia, mes }) => `${doisDigitos(dia)}/${doisDigitos(mes)}`;

const formatadores = new Map();
const horaSemZero = (quando, fuso) => {
  if (!formatadores.has(fuso)) {
    formatadores.set(
      fuso,
      new Intl.DateTimeFormat('pt-BR', {
        timeZone: fuso,
        hour: 'numeric',
        minute: '2-digit',
        hourCycle: 'h23',
      })
    );
  }
  return formatadores.get(fuso).format(new Date(quando * 1000));
};

const diaCurto = (partes, t) =>
  t(`LISTA_DE_CONVERSAS.HORA.DIA_CURTO.${partes.semana}`);

// Linha 1: quando foi a última mensagem.
export const horaDaLista = ({ quando, agora, fuso, t }) => {
  const chave = diaDaMensagem(quando, fuso);
  const chaveDeHoje = diaDaMensagem(agora, fuso);
  const diferenca = diasEntre(chaveDeHoje, chave);
  const partes = partesDoDia(chave);
  if (diferenca <= 0) return horaDaMensagem(quando, fuso);
  if (diferenca === 1) return t('LISTA_DE_CONVERSAS.HORA.ONTEM');
  if (diferenca < SEMANA) return diaCurto(partes, t);
  if (partes.ano === partesDoDia(chaveDeHoje).ano) return dataCurta(partes);
  return `${dataCurta(partes)}/${partes.ano}`;
};

// Linha 3 da lista de adiadas: até quando a conversa fica adiada.
export const horaComDia = ({ quando, agora, fuso, t }) => {
  const chave = diaDaMensagem(quando, fuso);
  const diferenca = diasEntre(chave, diaDaMensagem(agora, fuso));
  const hora = horaSemZero(quando, fuso);
  if (diferenca <= 0) return t('LISTA_DE_CONVERSAS.HORA.HOJE', { hora });
  if (diferenca === 1) return t('LISTA_DE_CONVERSAS.HORA.AMANHA', { hora });
  const partes = partesDoDia(chave);
  const dia = diferenca < SEMANA ? diaCurto(partes, t) : dataCurta(partes);
  return t('LISTA_DE_CONVERSAS.HORA.DIA_E_HORA', { dia, hora });
};
