import { TIPO_CANAL, tipoDoCanal } from './canais';

// #1181 PR2 — leitura das caixas e do horário para a criação (T04 e T05).

// #2490 — o canal que o dono pediu ao Construtor (state.canal_pedido da thread). "nenhum" e o vazio
// (thread antiga, ou sem a conversa na tela) não restringem.
const SEM_CANAL_PEDIDO = 'nenhum';

// O botão "Começar a atender no {canal}" só diz o canal quando não há dúvida (#2489, 5b): uma única
// caixa livre que quem cria alcança. Com mais de uma, nenhuma ou só ocupadas, devolve null e o botão
// vira "Escolher canal": a pessoa escolhe no Comece. Caixa ocupada ou com outro sistema nunca é
// sugerida. Se o dono pediu um canal (#2490), só caixas desse canal (`canal` da caixa, que conta a
// WAHA como WhatsApp) entram: o canal pedido ocupado, ou sem caixa, vira "Escolher canal".
export const canalSugerido = (canais, agenteId, canalPedido = null) => {
  const pediu = Boolean(canalPedido) && canalPedido !== SEM_CANAL_PEDIDO;
  const candidatas = (canais || []).filter(
    canal =>
      tipoDoCanal(canal, agenteId) === TIPO_CANAL.LIVRE &&
      canal.alcanca !== false &&
      (!pediu || canal.canal === canalPedido)
  );
  return candidatas.length === 1 ? candidatas[0] : null;
};

// Há alguma caixa para escolher no Comece (livre, ou ocupada por outro agente, que vira troca), que
// quem cria alcança? Sem nenhuma, a Confira mostra o aviso de conectar um canal em vez do botão.
export const temCanalParaEscolher = (canais, agenteId) =>
  (canais || []).some(
    canal =>
      canal.alcanca !== false &&
      [TIPO_CANAL.LIVRE, TIPO_CANAL.OCUPADO].includes(
        tipoDoCanal(canal, agenteId)
      )
  );

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
