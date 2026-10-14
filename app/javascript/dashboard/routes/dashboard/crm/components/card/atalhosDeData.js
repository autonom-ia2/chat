// #1423 — os atalhos de data e hora do retorno ("Amanhã, 09:00"…), usados ao
// marcar e ao adiar. O valor é "AAAA-MM-DDTHH:MM" no fuso de quem usa.
const HORA_LIMITE_HOJE = 16;
const dois = numero => String(numero).padStart(2, '0');
const em = (dias, hora) => {
  const data = new Date();
  data.setDate(data.getDate() + dias);
  return `${data.getFullYear()}-${dois(data.getMonth() + 1)}-${dois(data.getDate())}T${hora}`;
};
const proximaSegunda = () => {
  const hoje = new Date().getDay();
  return em((8 - hoje) % 7 || 7, '09:00');
};

export const atalhosDeData = t => {
  const N = 'CRM_CARD.RETORNO.ATALHO';
  return [
    ...(new Date().getHours() < HORA_LIMITE_HOJE
      ? [{ rotulo: t(`${N}.HOJE`), valor: em(0, '17:00') }]
      : []),
    { rotulo: t(`${N}.AMANHA`), valor: em(1, '09:00') },
    { rotulo: t(`${N}.TRES_DIAS`), valor: em(3, '09:00') },
    { rotulo: t(`${N}.SEGUNDA`), valor: proximaSegunda() },
  ];
};
