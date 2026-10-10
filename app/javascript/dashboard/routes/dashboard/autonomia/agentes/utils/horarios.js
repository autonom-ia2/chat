// #1181 PR3 — horário de atendimento de uma caixa em texto curto, para as opções de "Quando"
// (protótipo whenSub: "Horário do canal: seg. a sex., das 9h às 18h"). Vem de inbox.working_hours
// (weekly_schedule) e working_hours_enabled. Caixa sem horário ligado → null: só "Sempre" serve.
const NS = 'AGENTS.JORNADA.PAGINA.HORARIO';

const hora = (t, h, m) =>
  m
    ? t(`${NS}.HORA_MINUTO`, { h, m: String(m).padStart(2, '0') })
    : t(`${NS}.HORA`, { h });

const assinatura = dia =>
  dia.open_all_day
    ? 'todo'
    : `${dia.open_hour}:${dia.open_minutes}-${dia.close_hour}:${dia.close_minutes}`;

const nomeDoDia = (t, dia) => t(`${NS}.DIAS.D${dia}`);

const textoDosDias = (t, dias) => {
  if (dias.length === 1) return nomeDoDia(t, dias[0]);
  const seguidos = dias.every((dia, i) => i === 0 || dia === dias[i - 1] + 1);
  if (seguidos && dias.length > 2) {
    return t(`${NS}.INTERVALO_DIAS`, {
      inicio: nomeDoDia(t, dias[0]),
      fim: nomeDoDia(t, dias[dias.length - 1]),
    });
  }
  return dias.map(dia => nomeDoDia(t, dia)).join(', ');
};

const textoDoGrupo = (t, grupo) => {
  const dias = textoDosDias(t, grupo.dias);
  const { exemplo } = grupo;
  if (exemplo.open_all_day) return t(`${NS}.DIA_TODO`, { dias });
  return t(`${NS}.DIAS_E_HORAS`, {
    dias,
    abre: hora(t, exemplo.open_hour, exemplo.open_minutes),
    fecha: hora(t, exemplo.close_hour, exemplo.close_minutes),
  });
};

export const horarioDaCaixa = (caixa, t) => {
  if (!caixa?.working_hours_enabled) return null;
  const abertos = (caixa.working_hours || []).filter(
    dia => !dia.closed_all_day
  );
  if (!abertos.length) return null;
  const grupos = abertos.reduce((lista, dia) => {
    const chave = assinatura(dia);
    const grupo = lista.find(item => item.chave === chave);
    if (grupo) {
      return lista.map(item =>
        item === grupo
          ? { ...item, dias: [...item.dias, dia.day_of_week] }
          : item
      );
    }
    return [...lista, { chave, exemplo: dia, dias: [dia.day_of_week] }];
  }, []);
  return grupos.map(grupo => textoDoGrupo(t, grupo)).join('; ');
};

// { [inbox_id]: texto | null } para o OndeQuandoEscolha.
export const horariosDasCaixas = (caixas, t) =>
  Object.fromEntries(
    (caixas || []).map(caixa => [caixa.id, horarioDaCaixa(caixa, t)])
  );
