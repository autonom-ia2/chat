import { TIPO_CANAL, tipoDoCanal } from './canais';

// #1181 PR2 — leitura das caixas e do horário para a criação (T04 e T05).

const WHATSAPP = 'Channel::Whatsapp';

// O botão "Começar a atender no {canal}" já diz o canal (protótipo ctaChannel): uma caixa livre,
// de preferência o WhatsApp; sem caixa livre, uma ocupada por outro agente (vira troca). Caixa com
// outro sistema nunca é sugerida.
export const canalSugerido = (canais, agenteId) => {
  const lista = canais || [];
  const doTipo = tipo =>
    lista.filter(canal => tipoDoCanal(canal, agenteId) === tipo);
  const preferirWhatsapp = grupo =>
    grupo.find(canal => canal.channel_type === WHATSAPP) || grupo[0] || null;
  return (
    preferirWhatsapp(doTipo(TIPO_CANAL.LIVRE)) ||
    preferirWhatsapp(doTipo(TIPO_CANAL.OCUPADO))
  );
};

// Como o botão chama o canal: pelo tipo (AGENTS.JORNADA.CRIAR.CANAL.<chave>) ou, num tipo sem nome
// próprio (API, SMS…), pelo nome da caixa.
const TIPOS = {
  'Channel::Whatsapp': 'WHATSAPP',
  'Channel::Instagram': 'INSTAGRAM',
  'Channel::WebWidget': 'SITE',
  'Channel::Email': 'EMAIL',
  'Channel::FacebookPage': 'FACEBOOK',
  'Channel::Telegram': 'TELEGRAM',
};

export const tipoDoCanalParaTexto = canal => {
  const chave = TIPOS[canal?.channel_type];
  return chave ? { chave } : { nome: canal?.name || '' };
};

// Horário de atendimento da caixa, em texto curto ("seg a sex, das 9h às 18h, e sáb, das 9h às
// 13h"). undefined = caixa fora da store (aparece sem horário, sem travar); null = sem horário (só
// "Sempre" fica disponível). Os dias seguidos com o mesmo horário viram um intervalo; a semana
// começa na segunda.
const ORDEM_DOS_DIAS = [1, 2, 3, 4, 5, 6, 0];
const NS = 'AGENTS.JORNADA.CRIAR.HORARIO';

const hora = (h, m, t) =>
  m
    ? t(`${NS}.HORA_MIN`, { h, m: String(m).padStart(2, '0') })
    : t(`${NS}.HORA`, { h });

const faixaDoDia = (dia, t) => {
  if (!dia || dia.closed_all_day) return null;
  if (dia.open_all_day) return { todo: true, chave: 'todo' };
  const abre = hora(dia.open_hour, dia.open_minutes, t);
  const fecha = hora(dia.close_hour, dia.close_minutes, t);
  return { abre, fecha, chave: `${abre}-${fecha}` };
};

const agrupar = (semana, t) =>
  ORDEM_DOS_DIAS.reduce((grupos, numero) => {
    const faixa = faixaDoDia(
      semana.find(dia => dia.day_of_week === numero),
      t
    );
    const ultimo = grupos[grupos.length - 1];
    const seguido = ultimo && ultimo.fim === ORDEM_DOS_DIAS.indexOf(numero) - 1;
    if (!faixa) return grupos;
    if (seguido && ultimo.faixa.chave === faixa.chave) {
      return [
        ...grupos.slice(0, -1),
        { ...ultimo, fim: ORDEM_DOS_DIAS.indexOf(numero), ultimoDia: numero },
      ];
    }
    const posicao = ORDEM_DOS_DIAS.indexOf(numero);
    return [
      ...grupos,
      {
        faixa,
        inicio: posicao,
        fim: posicao,
        primeiroDia: numero,
        ultimoDia: numero,
      },
    ];
  }, []);

const textoDoGrupo = (grupo, t) => {
  const nomeDoDia = numero => t(`${NS}.DIAS.${numero}`);
  const dias =
    grupo.primeiroDia === grupo.ultimoDia
      ? nomeDoDia(grupo.primeiroDia)
      : t(`${NS}.INTERVALO`, {
          inicio: nomeDoDia(grupo.primeiroDia),
          fim: nomeDoDia(grupo.ultimoDia),
        });
  if (grupo.faixa.todo) return t(`${NS}.DIA_TODO`, { dias });
  return t(`${NS}.FAIXA`, {
    dias,
    abre: grupo.faixa.abre,
    fecha: grupo.faixa.fecha,
  });
};

export const textoDoHorario = (caixa, t) => {
  if (!caixa) return undefined;
  if (!caixa.working_hours_enabled) return null;
  const grupos = agrupar(caixa.working_hours || [], t);
  if (!grupos.length) return null;
  return grupos
    .map(grupo => textoDoGrupo(grupo, t))
    .reduce((antes, depois) => t(`${NS}.E`, { antes, depois }));
};

// { [inbox_id]: texto | null } das caixas que a store conhece.
export const horariosDasCaixas = (canais, caixas, t) =>
  Object.fromEntries(
    (canais || []).flatMap(canal => {
      const caixa = (caixas || []).find(item => item.id === canal.inbox_id);
      return caixa ? [[canal.inbox_id, textoDoHorario(caixa, t)]] : [];
    })
  );
