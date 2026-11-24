// O que a tela "Limite de mensagens" (#3063) escolhe, nas mesmas faixas que o servidor aceita
// (Autonomia::RitmoDeEnvio::Config). `fim` é a hora em que para de mandar (20 = até 19h59).
export const MENSAGENS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
export const DIAS = [1, 7, 15, 30];
export const INICIOS = Array.from({ length: 23 }, (_, hora) => hora);
export const FINS = Array.from({ length: 23 }, (_, hora) => hora + 1);
// Segunda a domingo na tela; o valor é o do Date#getDay (0 = domingo).
export const DIAS_DA_SEMANA = [1, 2, 3, 4, 5, 6, 0];

// #3101: "pelo menos X horas entre duas mensagens" à mesma pessoa. 0 = sem intervalo mínimo.
export const INTERVALOS = [1, 2, 4, 8, 12, 24, 48];
export const SEM_INTERVALO = 0;

export const SEM_LIMITE = 0;
export const LIMITE_PADRAO = { mensagens: 3, dias: 7 };
export const HORARIO_PADRAO = {
  inicio: 8,
  fim: 20,
  dias_da_semana: [1, 2, 3, 4, 5],
};

/** O formulário a partir do que o servidor guardou. */
export const formularioDe = (ritmo = {}) => ({
  mensagens: ritmo.limite?.mensagens ?? SEM_LIMITE,
  dias: ritmo.limite?.dias ?? LIMITE_PADRAO.dias,
  intervalo: ritmo.intervalo?.horas ?? SEM_INTERVALO,
  comHorario: Boolean(ritmo.horario),
  inicio: ritmo.horario?.inicio ?? HORARIO_PADRAO.inicio,
  fim: ritmo.horario?.fim ?? HORARIO_PADRAO.fim,
  diasDaSemana: [
    ...(ritmo.horario?.dias_da_semana ?? HORARIO_PADRAO.dias_da_semana),
  ],
});

/** O pedido ao servidor a partir do formulário. */
export const pedidoDe = formulario => ({
  limite:
    formulario.mensagens === SEM_LIMITE
      ? null
      : { mensagens: formulario.mensagens, dias: formulario.dias },
  intervalo:
    formulario.intervalo === SEM_INTERVALO
      ? null
      : { horas: formulario.intervalo },
  horario: formulario.comHorario
    ? {
        inicio: formulario.inicio,
        fim: formulario.fim,
        dias_da_semana: [...formulario.diasDaSemana].sort((a, b) => a - b),
      }
    : null,
});

/** O que falta para salvar: o horário precisa terminar depois de começar e ter um dia. */
export const problemaDo = formulario => {
  if (!formulario.comHorario) return null;
  if (formulario.fim <= formulario.inicio) return 'FIM_ANTES';
  if (!formulario.diasDaSemana.length) return 'SEM_DIA';
  return null;
};

export const alternarDia = (dias, dia) =>
  dias.includes(dia) ? dias.filter(item => item !== dia) : [...dias, dia];

const DIAS_UTEIS = [1, 2, 3, 4, 5];

/** Como o resumo diz os dias: todos, de segunda a sexta, ou a lista (na ordem da tela). */
export const diasDoResumo = dias => {
  const escolhidos = DIAS_DA_SEMANA.filter(dia => dias.includes(dia));
  if (escolhidos.length === DIAS_DA_SEMANA.length) return { tipo: 'TODOS' };
  const soUteis =
    escolhidos.length === DIAS_UTEIS.length &&
    DIAS_UTEIS.every(dia => escolhidos.includes(dia));
  if (soUteis) return { tipo: 'UTEIS' };
  return { tipo: 'LISTA', dias: escolhidos };
};
