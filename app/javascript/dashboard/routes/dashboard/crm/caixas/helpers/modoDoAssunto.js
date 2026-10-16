// #1676 — o modo da caixa em texto, sem Vue. Com a flag crm_avaliar_toda_mensagem
// da conta (piloto 1, 16 e 18), o servidor grava a IA de assunto em Automática
// também na caixa de 1 funil, e os textos acompanham: "à mão" vira "quando
// entender o assunto", com texto próprio de 1 funil (um card para cada pedido do
// cliente, AUTO_UM), e "assim que chega" diz que a IA dá o nome. Sem a IA de
// assunto, os textos de sempre. A caixa de vários funis não muda.
export const FLAG_IA_DE_ASSUNTO = 'crm_avaliar_toda_mensagem';

export const iaDeAssuntoLigada = conta =>
  conta?.features?.[FLAG_IA_DE_ASSUNTO] === true;

// A IA de assunto como está gravada na caixa hoje (o que acontece agora, antes
// de salvar). Depois de salvar, vale a flag da conta: é o que o servidor grava.
export const iaSalva = caixa =>
  Boolean(caixa?.subject_ai_mode) && caixa.subject_ai_mode !== 'off';

// O sufixo das chaves de CRM_CAIXAS.SOZINHO e CRM_CAIXAS.MODO_RESUMO. O valor
// gravado continua o mesmo ('chegou' ou 'off'): só o texto muda.
export const chaveDoModo = (modo, umFunil, iaDeAssunto) => {
  if (umFunil && iaDeAssunto && modo === 'off') return 'AUTO_UM';
  if (umFunil && iaDeAssunto && modo === 'chegou') return 'CHEGOU_IA';
  return modo.toUpperCase();
};
