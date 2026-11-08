// #2692 — a regra do destino pronto da folha "O que fazer com as {n}?" (v4, F1).
// Nunca pergunta se a resposta existe. Nesta ordem:
//   1. o último funil e etapa que esta pessoa escolheu (guardado no navegador);
//   2. o padrão da conta;
//   3. o único funil de Vender visível, na primeira etapa;
//   4. senão, nada: a linha "Para onde" vem vazia e pede "Escolha o funil".
// Vale só funil de Vender (counts_as_sale) que a pessoa vê.

const mesmoId = (a, b) => a != null && b != null && String(a) === String(b);

const doFunil = (funil, etapaId) => {
  const etapa =
    funil.etapas.find(item => mesmoId(item.id, etapaId)) || funil.etapas[0];
  return etapa ? { funil, etapa } : null;
};

export const escolherDestino = ({
  funis = [],
  ultimo = null,
  padrao = null,
}) => {
  const vendas = funis.filter(funil => funil.venda);
  const daPreferencia = preferencia => {
    if (!preferencia?.funilId) return null;
    const funil = vendas.find(item => mesmoId(item.id, preferencia.funilId));
    return funil ? doFunil(funil, preferencia.etapaId) : null;
  };

  return (
    daPreferencia(ultimo) ||
    daPreferencia(padrao) ||
    (vendas.length === 1 ? doFunil(vendas[0]) : null)
  );
};

const chaveDoUltimo = (contaId, usuarioId) =>
  `prospeccao-achar:destino:${contaId}:${usuarioId}`;

// O navegador pode recusar (aba privada, site bloqueado): sem ele, segue sem o
// último escolhido.
export const lerUltimoDestino = (contaId, usuarioId) => {
  try {
    const valor = window.localStorage.getItem(
      chaveDoUltimo(contaId, usuarioId)
    );
    return valor ? JSON.parse(valor) : null;
  } catch {
    return null;
  }
};

export const lembrarDestino = (contaId, usuarioId, { funilId, etapaId }) => {
  try {
    window.localStorage.setItem(
      chaveDoUltimo(contaId, usuarioId),
      JSON.stringify({ funilId, etapaId })
    );
  } catch {
    // sem navegador para guardar: a próxima vez cai no padrão da conta.
  }
};
