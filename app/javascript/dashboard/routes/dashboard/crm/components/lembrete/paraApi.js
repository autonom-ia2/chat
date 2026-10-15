import { repetirVazio } from './recorrencia';

// #1460/#1462 — a tradução entre o formulário (repetir, quem recebe) e o que
// a API de lembretes entende (recurrence, recipient_*), nos dois sentidos.
const FREQUENCIA = {
  dia: 'daily',
  semana: 'weekly',
  mes: 'monthly',
  ano: 'yearly',
};
const FIM = { nunca: 'never', data: 'on_date', vezes: 'after_count' };
const QUEM = {
  dono: 'card_owner',
  eu: 'creator',
  pessoas: 'users',
  time: 'team',
};
const inverso = mapa =>
  Object.fromEntries(
    Object.entries(mapa).map(([chave, valor]) => [valor, chave])
  );

export const recorrenciaParaApi = (repetir, inicio) => {
  if (repetir.frequencia === 'nunca') return null;
  const semana = repetir.dias.length
    ? repetir.dias
    : [new Date(`${inicio.slice(0, 10)}T12:00:00Z`).getUTCDay()];
  return {
    frequency: FREQUENCIA[repetir.frequencia],
    weekdays: repetir.frequencia === 'semana' ? semana : [],
    weekdays_only: repetir.frequencia === 'dia' && repetir.soDiasUteis,
    ends_mode: FIM[repetir.fim],
    ends_on: repetir.fim === 'data' ? repetir.ate : null,
    occurrences_count: repetir.fim === 'vezes' ? Number(repetir.vezes) : null,
  };
};

export const quemRecebeParaApi = quem => ({
  recipient_mode: QUEM[quem.tipo],
  recipient_user_ids: quem.tipo === 'pessoas' ? quem.pessoas : [],
  recipient_team_id: quem.tipo === 'time' ? quem.time : null,
});

export const repetirDaApi = serie => ({
  ...repetirVazio(),
  frequencia: inverso(FREQUENCIA)[serie.frequency] || 'nunca',
  soDiasUteis: Boolean(serie.weekdays_only),
  dias: serie.weekdays || [],
  fim: inverso(FIM)[serie.ends_mode] || 'nunca',
  ate: serie.ends_on || '',
  vezes: serie.occurrences_count || 10,
});

export const quemRecebeDaApi = item => ({
  tipo: inverso(QUEM)[item.recipient_mode] || 'dono',
  pessoas: item.recipient_user_ids || [],
  time: item.recipient_team_id || null,
});
