// #1619 — horário em texto curto ("seg. a sex., das 9h às 18h"), para o horário do canal
// (inbox.working_hours) e para o horário de uma pessoa (blocos do calendário do SLA). As duas
// fontes viram a mesma lista de dias: [{ dia: 0..6, diaTodo, faixas: [[inicio, fim]] }], em
// minutos desde a meia-noite. Sem dia aberto, o texto é null ("sem horário").
const NS = 'HORARIO_DO_CANAL.TEXTO';
const DIA_INTEIRO = 1440;

const hora = (t, minutos) => {
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return m
    ? t(`${NS}.HORA_MINUTO`, { h, m: String(m).padStart(2, '0') })
    : t(`${NS}.HORA`, { h });
};

const assinatura = dia =>
  dia.diaTodo ? 'todo' : dia.faixas.map(faixa => faixa.join('-')).join(',');

const nomeDoDia = (t, dia) => t(`${NS}.DIAS.D${dia}`);

const textoDosDias = (t, dias) => {
  if (dias.length === 7) return t(`${NS}.TODOS_OS_DIAS`);
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

const textoDasFaixas = (t, faixas) =>
  faixas
    .map(([inicio, fim]) =>
      t(`${NS}.FAIXA`, { abre: hora(t, inicio), fecha: hora(t, fim) })
    )
    .join(` ${t(`${NS}.E`)} `);

const textoDoGrupo = (t, grupo) => {
  const dias = textoDosDias(t, grupo.dias);
  if (grupo.exemplo.diaTodo) return t(`${NS}.DIA_TODO`, { dias });
  return t(`${NS}.DIAS_E_FAIXAS`, {
    dias,
    faixas: textoDasFaixas(t, grupo.exemplo.faixas),
  });
};

export const horarioEmTexto = (dias, t) => {
  const abertos = [...(dias || [])]
    .filter(dia => dia.diaTodo || dia.faixas.length)
    .sort((a, b) => a.dia - b.dia);
  if (!abertos.length) return null;
  const grupos = abertos.reduce((lista, dia) => {
    const chave = assinatura(dia);
    const grupo = lista.find(item => item.chave === chave);
    if (!grupo) return [...lista, { chave, exemplo: dia, dias: [dia.dia] }];
    return lista.map(item =>
      item === grupo ? { ...item, dias: [...item.dias, dia.dia] } : item
    );
  }, []);
  return grupos.map(grupo => textoDoGrupo(t, grupo)).join('; ');
};

// Horário do canal (Chatwoot): desligado = sem horário.
export const diasDoCanal = caixa => {
  if (!caixa?.working_hours_enabled) return [];
  return (caixa.working_hours || [])
    .filter(dia => !dia.closed_all_day)
    .map(dia => ({
      dia: dia.day_of_week,
      diaTodo: Boolean(dia.open_all_day),
      faixas: dia.open_all_day
        ? []
        : [
            [
              dia.open_hour * 60 + dia.open_minutes,
              dia.close_hour * 60 + dia.close_minutes,
            ],
          ],
    }));
};

// Calendário de uma pessoa (Crm::ServiceSchedule): vários blocos por dia (almoço).
export const diasDosBlocos = blocos =>
  [0, 1, 2, 3, 4, 5, 6]
    .map(dia => {
      const faixas = (blocos || [])
        .filter(bloco => bloco.day_of_week === dia)
        .map(bloco => [bloco.start_minute, bloco.end_minute])
        .sort((a, b) => a[0] - b[0]);
      const diaTodo =
        faixas.length === 1 &&
        faixas[0][0] === 0 &&
        faixas[0][1] === DIA_INTEIRO;
      return { dia, diaTodo, faixas: diaTodo ? [] : faixas };
    })
    .filter(dia => dia.diaTodo || dia.faixas.length);

// "seg. a sex., …" no começo de uma linha de lista: "Seg. a sex., …".
export const comMaiuscula = texto =>
  texto ? texto.charAt(0).toUpperCase() + texto.slice(1) : texto;
