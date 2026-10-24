// Como o Instagram Direct arruma as mensagens (#2079): grupos do mesmo lado, horário
// entre os blocos, cantos de 4 px do lado colado e o "Visto" na última enviada.
// Funções puras sobre a lista já em camelCase (a mesma que a MessageList desenha).
import { MESSAGE_TYPES } from 'dashboard/components-next/message/constants';
import { diaDaMensagem, horaDaMensagem } from '../dataDaConversa';
import { ehReacaoDoAgente } from '../reacoes';

// Pausa entre duas mensagens que abre um horário novo no meio da conversa. O app não
// publica a regra; medido na conversa de teste: 28 min de pausa já abriram um horário.
export const PAUSA_DO_HORARIO = 20 * 60;

const LADOS = { ESQUERDA: 'esquerda', DIREITA: 'direita' };

const RECEBIDA = [MESSAGE_TYPES.INCOMING];
const NOSSA = [MESSAGE_TYPES.OUTGOING, MESSAGE_TYPES.TEMPLATE];

export const ladoDaMensagem = mensagem => {
  if (mensagem.private) return null;
  if (RECEBIDA.includes(mensagem.messageType)) return LADOS.ESQUERDA;
  if (NOSSA.includes(mensagem.messageType)) return LADOS.DIREITA;
  return null;
};

const abreHorario = (lista, indice) => {
  if (indice === 0) return true;
  return (
    lista[indice].createdAt - lista[indice - 1].createdAt > PAUSA_DO_HORARIO
  );
};

const juntas = (lista, a, b) => {
  if (a < 0 || b >= lista.length) return false;
  if (abreHorario(lista, b)) return false;
  const lado = ladoDaMensagem(lista[a]);
  return lado !== null && lado === ladoDaMensagem(lista[b]);
};

// Para cada mensagem: horário antes dela, grupo com a anterior e com a próxima.
export const sequenciaDoInstagram = lista => {
  const sequencia = new Map();
  lista.forEach((mensagem, indice) => {
    sequencia.set(mensagem.id, {
      horario: abreHorario(lista, indice),
      comAnterior: juntas(lista, indice - 1, indice),
      comProxima: juntas(lista, indice, indice + 1),
    });
  });
  return sequencia;
};

// O "Visto" fica embaixo da última mensagem nossa, quando ela é também a última
// mensagem trocada com o cliente (atividade e nota privada não contam) e o cliente já
// leu (o Instagram não tem "entregue").
export const vistoDaConversa = lista => {
  const ultima = lista.findLast(mensagem => ladoDaMensagem(mensagem) !== null);
  if (!ultima || ladoDaMensagem(ultima) !== LADOS.DIREITA) return null;
  return ultima.status === 'read' ? ultima.id : null;
};

// Cantos de 18 px, com 4 px do lado de quem mandou quando a mensagem está colada à
// anterior (em cima) ou à próxima (embaixo).
export const cantosDoBalao = ({ lado, comAnterior, comProxima }) => {
  const emCima = comAnterior ? '4px' : '18px';
  const embaixo = comProxima ? '4px' : '18px';
  return lado === LADOS.DIREITA
    ? { borderRadius: `18px ${emCima} ${embaixo} 18px` }
    : { borderRadius: `${emCima} 18px 18px ${embaixo}` };
};

const partesDaData = (quando, fuso, idioma) =>
  Object.fromEntries(
    new Intl.DateTimeFormat(idioma, {
      timeZone: fuso,
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    })
      .formatToParts(new Date(quando * 1000))
      .map(({ type, value }) => [type, value])
  );

// O horário como o app escreve: "12:41" no mesmo dia; "10 de out de 2026 06:58" no
// mesmo ano; "04/07/2025 16:29" antes disso. Sempre no fuso da conta.
export const horarioDoInstagram = ({ quando, agora, fuso, t, idioma }) => {
  const hora = horaDaMensagem(quando, fuso, idioma);
  if (diaDaMensagem(quando, fuso) === diaDaMensagem(agora, fuso)) return hora;
  const ano = diaDaMensagem(quando, fuso).slice(0, 4);
  if (ano !== diaDaMensagem(agora, fuso).slice(0, 4)) {
    const data = new Intl.DateTimeFormat(idioma, {
      timeZone: fuso,
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    }).format(new Date(quando * 1000));
    return `${data} ${hora}`;
  }
  const { day, month } = partesDaData(quando, fuso, idioma);
  const mes = month.endsWith('.') ? month.slice(0, -1) : month;
  return t('CONVERSA_CANAL.INSTAGRAM.HORARIO', { dia: day, mes, ano, hora });
};

// A linha que o agente da Autonomia cria para a reação do cliente ("[O cliente reagiu
// com …]") fica fora da lista: o selo da mensagem reagida já mostra a reação (#2113),
// como na pele do WhatsApp (ocultaNaPele).
export const mensagensDoInstagram = mensagens =>
  mensagens.filter(mensagem => !ehReacaoDoAgente(mensagem));
