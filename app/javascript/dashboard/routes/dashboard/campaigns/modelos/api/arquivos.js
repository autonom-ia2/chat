// Arquivos escolhidos na tela (foto do topo, mídia dos cartões) até o envio.
// O rascunho é copiado como JSON (helpers/conteudo.js), então guarda só a
// chave daqui (`local`); o arquivo sobe para a Meta no "Enviar para aprovação",
// pela caixa da conta do WhatsApp que vai receber o modelo.
const arquivos = new Map();
let proximo = 0;

export const guardarArquivo = arquivo => {
  proximo += 1;
  const chave = `arquivo_${proximo}`;
  arquivos.set(chave, arquivo);
  return chave;
};

export const arquivoGuardado = chave => (chave ? arquivos.get(chave) : null);

// Depois do envio, os arquivos do rascunho saem da memória.
export const esquecerArquivos = conteudo => {
  [conteudo?.topo?.local, ...(conteudo?.cartoes || []).map(c => c.local)]
    .filter(Boolean)
    .forEach(chave => arquivos.delete(chave));
};
