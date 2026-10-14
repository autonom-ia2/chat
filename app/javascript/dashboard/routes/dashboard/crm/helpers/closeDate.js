// O vencimento do card é uma data, não um instante (#1538): o formulário grava "AAAA-MM-DD" e quem lê usa o dia
// (negocio.prazo, lembretes de cobrança). Soltar o card no calendário guarda o dia em que ele caiu, na grade que a
// pessoa vê; o instante com hora viraria o dia seguinte em UTC depois das 21h em São Paulo.
const doisDigitos = numero => String(numero).padStart(2, '0');

export const diaDoVencimento = data => {
  const dia = new Date(data);
  return `${dia.getFullYear()}-${doisDigitos(dia.getMonth() + 1)}-${doisDigitos(dia.getDate())}`;
};
