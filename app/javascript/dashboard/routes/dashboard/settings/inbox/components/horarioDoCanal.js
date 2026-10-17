// #1619 — o horário do canal em 24 h ('09:00'), de e para o formato que a API da caixa já usa
// (working_hours: um intervalo por dia, que fecha no máximo às 23:59).
export const ULTIMA_HORA = '23:59';
const PASSO = 30;
const DIAS = [0, 1, 2, 3, 4, 5, 6];
const NOVO_DIA = { abre: '09:00', fecha: '18:00' };

const doisDigitos = numero => String(numero).padStart(2, '0');

export const deMinutos = minutos =>
  `${doisDigitos(Math.floor(minutos / 60))}:${doisDigitos(minutos % 60)}`;

export const emMinutos = hora => {
  const [h, m] = String(hora || '').split(':');
  return Number(h) * 60 + Number(m);
};

const horasDoDia = () =>
  Array.from({ length: 1440 / PASSO }, (_, i) => deMinutos(i * PASSO));

// Hora gravada fora do passo de 30 min (09:15) entra na lista, para não trocar sozinha ao abrir a tela.
const comAtual = (horas, atual) =>
  !atual || horas.includes(atual)
    ? horas
    : [...horas, atual].sort((a, b) => emMinutos(a) - emMinutos(b));

const opcoes = horas => horas.map(hora => ({ value: hora, label: hora }));

export const opcoesDeAbrir = atual => opcoes(comAtual(horasDoDia(), atual));

export const opcoesDeFechar = atual =>
  opcoes(comAtual([...horasDoDia().slice(1), ULTIMA_HORA], atual));

export const diaValido = dia =>
  !dia.ligado || dia.diaTodo || emMinutos(dia.fecha) > emMinutos(dia.abre);

const doServidor = (linha, dia) => {
  if (!linha || linha.closed_all_day) {
    return { dia, ligado: false, diaTodo: false, ...NOVO_DIA };
  }
  if (linha.open_all_day) {
    return { dia, ligado: true, diaTodo: true, ...NOVO_DIA };
  }
  return {
    dia,
    ligado: true,
    diaTodo: false,
    abre: deMinutos(linha.open_hour * 60 + linha.open_minutes),
    fecha: deMinutos(linha.close_hour * 60 + linha.close_minutes),
  };
};

// Caixa sem linhas ainda: seg. a sex., 09:00 às 18:00, como no protótipo.
export const diasDaCaixa = caixa => {
  const linhas = caixa?.working_hours || [];
  if (!linhas.length) {
    return DIAS.map(dia => ({
      dia,
      ligado: dia >= 1 && dia <= 5,
      diaTodo: false,
      ...NOVO_DIA,
    }));
  }
  return DIAS.map(dia =>
    doServidor(
      linhas.find(linha => linha.day_of_week === dia),
      dia
    )
  );
};

const fechado = dia => ({
  day_of_week: dia.dia,
  closed_all_day: true,
  open_all_day: false,
  open_hour: '',
  open_minutes: '',
  close_hour: '',
  close_minutes: '',
});

export const paraWorkingHours = dias =>
  dias.map(dia => {
    if (!dia.ligado) return fechado(dia);
    if (dia.diaTodo) {
      return {
        day_of_week: dia.dia,
        closed_all_day: false,
        open_all_day: true,
        open_hour: 0,
        open_minutes: 0,
        close_hour: 23,
        close_minutes: 59,
      };
    }
    const abre = emMinutos(dia.abre);
    const fecha = emMinutos(dia.fecha);
    return {
      day_of_week: dia.dia,
      closed_all_day: false,
      open_all_day: false,
      open_hour: Math.floor(abre / 60),
      open_minutes: abre % 60,
      close_hour: Math.floor(fecha / 60),
      close_minutes: fecha % 60,
    };
  });
