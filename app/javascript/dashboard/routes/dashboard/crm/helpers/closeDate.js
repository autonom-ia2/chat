// O vencimento do card é uma data, não um instante (#1538): o formulário grava "AAAA-MM-DD" (00:00 UTC no banco) e
// quem lê usa o dia UTC (negocio.prazo, lembretes de cobrança). Gravar a hora local viraria o dia seguinte em UTC depois
// das 21h em São Paulo; ler o instante no fuso do navegador mostraria o dia anterior.
const doisDigitos = numero => String(numero).padStart(2, '0');

// O dia, na grade que a pessoa vê, em que o card foi solto: "AAAA-MM-DD".
export const diaDoVencimento = data =>
  `${data.getFullYear()}-${doisDigitos(data.getMonth() + 1)}-${doisDigitos(data.getDate())}`;

// O dia gravado no vencimento (a parte da data, como o servidor lê), como meia-noite local para a grade.
export const dataDoVencimento = valor => {
  const [ano, mes, dia] = String(valor || '')
    .slice(0, 10)
    .split('-')
    .map(Number);
  if (!ano || !mes || !dia) return null;
  return new Date(ano, mes - 1, dia);
};
