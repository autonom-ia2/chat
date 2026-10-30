// #2283 — a "situação" de cada linha da Lista nova: o que está acontecendo com
// o cliente, numa frase, com a cor e o ícone. Datas sempre no fuso da conta
// (decisão 3: retorno de hoje fica âmbar desde a manhã e vermelho só depois do
// horário). Devolve a chave de i18n e os valores; o texto sai do t().
import { GRUPOS, grupoDoCard } from './grupos';

export const ICONE_OCULTA = 'i-lucide-lock';
export const ICONE_RETORNO = 'i-lucide-clock';

const MINUTO = 60 * 1000;
const HORA = 60 * MINUTO;
const DIA = 24 * HORA;

// Data (epoch em segundos, ISO ou Date) → Date; null quando vazia ou inválida.
export const paraData = valor => {
  if (valor === null || valor === undefined || valor === '') return null;
  const data =
    typeof valor === 'number' ? new Date(valor * 1000) : new Date(valor);
  return Number.isNaN(data.getTime()) ? null : data;
};

// Dia do calendário no fuso (AAAA-MM-DD), para comparar "hoje" e "ontem".
const diaNoFuso = (data, fuso) =>
  new Intl.DateTimeFormat('en-CA', {
    timeZone: fuso,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(data);

const contarDias = dia => {
  const [ano, mes, numero] = dia.split('-').map(Number);
  return Date.UTC(ano, mes - 1, numero) / DIA;
};

// Quantos dias do calendário de `data` até `agora`, no fuso (0 = hoje,
// 1 = ontem, -1 = amanhã).
export const diasAte = (data, agora, fuso) =>
  contarDias(diaNoFuso(agora, fuso)) - contarDias(diaNoFuso(data, fuso));

const idiomaDe = locale => String(locale || 'pt_BR').replace('_', '-');

export const horaNoFuso = (data, fuso, locale) =>
  new Intl.DateTimeFormat(idiomaDe(locale), {
    timeZone: fuso,
    hour: '2-digit',
    minute: '2-digit',
  }).format(data);

export const diaCurtoNoFuso = (data, fuso, locale) =>
  new Intl.DateTimeFormat(idiomaDe(locale), {
    timeZone: fuso,
    day: 'numeric',
    month: 'short',
  }).format(data);

const diaDaSemanaNoFuso = (data, fuso, locale) =>
  new Intl.DateTimeFormat(idiomaDe(locale), {
    timeZone: fuso,
    weekday: 'long',
  }).format(data);

// Daqui para a frente: HOJE "às 16:00", AMANHA, NO_DIA "quinta", NA_DATA
// "3 de nov.". Cada frase tem uma chave por tipo (a gramática muda).
export const quandoFuturo = (data, { agora, fuso, locale }) => {
  const dias = -diasAte(data, agora, fuso);
  const hora = horaNoFuso(data, fuso, locale);
  if (dias <= 0) return { tipo: 'HOJE', valores: { hora } };
  if (dias === 1) return { tipo: 'AMANHA', valores: { hora } };
  if (dias < 7)
    return {
      tipo: 'NO_DIA',
      valores: { dia: diaDaSemanaNoFuso(data, fuso, locale), hora },
    };
  return {
    tipo: 'NA_DATA',
    valores: { data: diaCurtoNoFuso(data, fuso, locale), hora },
  };
};

// Para trás: AGORA, HA_MIN, HA_HORAS, ONTEM, HA_DIAS.
export const quandoPassado = (data, { agora, fuso }) => {
  const passou = Math.max(0, agora - data);
  const dias = diasAte(data, agora, fuso);
  if (dias <= 0 && passou < MINUTO) return { tipo: 'AGORA', valores: {} };
  if (dias <= 0 && passou < HORA)
    return { tipo: 'HA_MIN', valores: { n: Math.floor(passou / MINUTO) } };
  if (dias <= 0)
    return { tipo: 'HA_HORAS', valores: { n: Math.floor(passou / HORA) } };
  if (dias === 1) return { tipo: 'ONTEM', valores: {} };
  return { tipo: 'HA_DIAS', valores: { n: dias } };
};

// O tom do retorno da pessoa: vermelho depois da hora, âmbar antes (no dia
// inteiro de hoje, desde a manhã). Sem retorno, nenhum.
export const tomDoRetorno = (card, agora) => {
  const vence = paraData(card.next_follow_up_due_at);
  if (!vence) return '';
  return vence < agora ? 'vermelho' : 'ambar';
};

const situacaoDoRetorno = (card, contexto) => {
  const vence = paraData(card.next_follow_up_due_at);
  if (!vence)
    return { chave: 'SITUACAO.RETORNO_MARCADO', valores: {}, tom: 'ambar' };
  const { agora, fuso, locale } = contexto;
  const hora = horaNoFuso(vence, fuso, locale);
  if (vence >= agora)
    return { chave: 'SITUACAO.RETORNO_HOJE', valores: { hora }, tom: 'ambar' };
  const dias = diasAte(vence, agora, fuso);
  const chave = { 0: 'RETORNO_VENCEU_HOJE', 1: 'RETORNO_VENCEU_ONTEM' }[dias];
  return {
    chave: `SITUACAO.${chave || 'RETORNO_VENCEU_HA_DIAS'}`,
    valores: { hora, n: dias },
    tom: 'vermelho',
  };
};

const comQuando = (base, quando, extra = {}) => ({
  chave: `${base}.${quando.tipo}`,
  valores: quando.valores,
  ...extra,
});

const situacaoDosDemais = (card, contexto) => {
  const retorno = paraData(card.next_follow_up_due_at);
  if (retorno)
    return comQuando('SITUACAO.RETORNO_EM', quandoFuturo(retorno, contexto), {
      icone: ICONE_RETORNO,
    });
  // Sem retorno da pessoa, o que tem hora marcada é do sistema: a mensagem
  // automática ou o toque do assistente (sem "Feito").
  const sistema = paraData(card.next_follow_up_at);
  if (sistema && sistema >= contexto.agora) {
    const chave =
      card.next_follow_up_source === 'ai'
        ? 'SITUACAO.ASSISTENTE_RETOMA'
        : 'SITUACAO.MENSAGEM_PROGRAMADA';
    return comQuando(chave, quandoFuturo(sistema, contexto), {
      icone: ICONE_RETORNO,
    });
  }
  const mensagem = paraData(card.last_message_at);
  if (mensagem)
    return comQuando(
      'SITUACAO.ULTIMA_MENSAGEM',
      quandoPassado(mensagem, contexto)
    );
  return { chave: 'SITUACAO.SEM_MENSAGEM', valores: {} };
};

// O último movimento do card: mensagem ou mudança de etapa (o mesmo critério
// do servidor para "parado").
const ultimoMovimento = card =>
  [paraData(card.last_message_at), paraData(card.entered_stage_at)]
    .filter(Boolean)
    .sort((a, b) => b - a)[0] || null;

const situacaoAberta = (grupo, card, contexto) => {
  const { agora } = contexto;
  if (grupo === 'esperando') {
    const desde = paraData(card.conversation?.waiting_since);
    if (!desde) return { chave: 'SITUACAO.ESPERANDO', valores: {} };
    return comQuando(
      'SITUACAO.ESPERANDO_DESDE',
      quandoPassado(desde, contexto)
    );
  }
  if (grupo === 'retorno') return situacaoDoRetorno(card, contexto);
  if (grupo === 'ninguem') {
    const entrou = paraData(card.created_at) || agora;
    return comQuando('SITUACAO.ENTROU', quandoPassado(entrou, contexto));
  }
  if (grupo === 'parado') {
    const ultimo = ultimoMovimento(card);
    if (!ultimo) return { chave: 'SITUACAO.PARADO', valores: {} };
    return {
      chave: 'SITUACAO.PARADO_HA_DIAS',
      valores: { n: Math.max(1, Math.floor((agora - ultimo) / DIA)) },
    };
  }
  return situacaoDosDemais(card, contexto);
};

// { chave, valores, tom, icone }: a chave de i18n (abaixo de CRM_LISTA_ACAO) e
// os valores dela.
export const situacaoDoCard = (card, contexto) => {
  const grupo = grupoDoCard(card);
  const fechado = { tom: GRUPOS[grupo].tom, icone: GRUPOS[grupo].icone };
  if (grupo === 'arquivado')
    return { ...fechado, chave: 'SITUACAO.ARQUIVADO', valores: {} };
  // Ganho e perdido com o nome do desfecho do funil (e do pacote do segmento).
  if (grupo === 'ganho' || grupo === 'perdido') {
    const rotulo = contexto.rotuloDoStatus?.(card.status) || '';
    return card.lost_reason && grupo === 'perdido'
      ? {
          ...fechado,
          chave: 'SITUACAO.FECHADO_COM_MOTIVO',
          valores: { rotulo, motivo: card.lost_reason },
        }
      : { ...fechado, chave: 'SITUACAO.FECHADO', valores: { rotulo } };
  }
  // Conversa que a pessoa não vê: sem nome de ninguém (decisão 2). Retorno e
  // Parados continuam pelos campos do card.
  if (card.conversation_hidden && !['retorno', 'parado'].includes(grupo))
    return {
      chave: 'SITUACAO.OUTRA_PESSOA',
      valores: {},
      tom: 'cinza',
      icone: ICONE_OCULTA,
    };
  const situacao = situacaoAberta(grupo, card, contexto);
  return {
    tom: GRUPOS[grupo].tom,
    icone: GRUPOS[grupo].icone,
    ...situacao,
  };
};
