// IA entende a conversa F3 — a sugestão de FECHAR o card (perdido com motivo,
// resolvido ou "era teste") usa o mesmo cartão da sugestão de etapa, com o
// texto dela. null quando a sugestão é só de etapa.
const F = 'CRM_CARD.FECHAR_SUGESTAO';
const RESULTADOS = ['perdido', 'resolvido', 'arquivado'];
const MOTIVOS = ['adiou', 'recusou', 'fechou_com_outra'];

export const textoDoFechamento = sugestao => {
  const { resultado, motivo } = sugestao?.fechar || {};
  if (!RESULTADOS.includes(resultado)) return null;
  const chave = resultado.toUpperCase();
  return {
    frase: `${F}.FRASE.${chave}`,
    curta: `${F}.CURTO.${chave}`,
    botao: resultado === 'arquivado' ? `${F}.ARQUIVAR` : `${F}.ENCERRAR`,
    motivo: MOTIVOS.includes(motivo)
      ? `${F}.MOTIVO.${motivo.toUpperCase()}`
      : '',
    retorno: motivo === 'adiou' ? `${F}.RETORNO` : '',
  };
};
