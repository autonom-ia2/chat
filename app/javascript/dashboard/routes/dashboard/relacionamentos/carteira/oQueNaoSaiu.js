// #2897 — o que ia sair sozinho para a pessoa e o WhatsApp não deixou: o aviso
// de renovação, a pergunta "Algo mudou?", a proposta ou o texto em palavras
// simples. Função pura: o seguro traz a lista do que está pendente
// (`naoSaiu: [{ tipo, em, dias }]`) e daqui sai o nome da frase do mais
// recente, ou `null` quando não há nada. A gaveta do seguro diz isso no topo;
// `naRenovacao` marca o que o bloco "Renovação" também diz (a proposta não
// entra: a situação da renovação já fala dela).
const NAO_SAIRAM = {
  aviso_nao_saiu: { id: 'AVISO', naRenovacao: true },
  algo_mudou_nao_saiu: { id: 'ALGO_MUDOU', naRenovacao: true },
  proposta_nao_saiu: { id: 'PROPOSTA', naRenovacao: false },
  palavras_nao_saiu: { id: 'PALAVRAS', naRenovacao: false },
};

export const oQueNaoSaiu = seguro => {
  const maisRecente = (seguro?.naoSaiu ?? [])
    .filter(item => NAO_SAIRAM[item.tipo])
    .reduce(
      (achado, item) => (!achado || item.em > achado.em ? item : achado),
      null
    );
  return maisRecente
    ? { ...NAO_SAIRAM[maisRecente.tipo], dias: maisRecente.dias ?? null }
    : null;
};
