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

// Miniatura da foto escolhida na campanha (#1465), pela referência do upload:
// object URL do próprio arquivo, só nesta aba. O rascunho guarda só a
// referência; depois de recarregar, a tela volta ao ícone com o nome.
const previas = new Map();

export const guardarPrevia = (referencia, arquivo) => {
  if (!referencia || !arquivo?.type?.startsWith('image/')) return;
  previas.set(referencia, URL.createObjectURL(arquivo));
};

// Arquivo trocado ou desfeito: a miniatura sai da memória.
export const esquecerPrevia = referencia => {
  if (!previas.has(referencia)) return;
  URL.revokeObjectURL(previas.get(referencia));
  previas.delete(referencia);
};

const previaDoArquivo = referencia => previas.get(referencia) || '';

// A miniatura do arquivo que vai: o escolhido agora (só a prévia local, nunca a
// aprovada no lugar dele) ou, sem escolha, o link da foto aprovada. '' = ícone.
export const miniaturaDe = (escolhido, guardado = null) =>
  escolhido ? previaDoArquivo(escolhido.referencia) : guardado?.url || '';

// Depois do envio, os arquivos do rascunho saem da memória.
export const esquecerArquivos = conteudo => {
  [conteudo?.topo?.local, ...(conteudo?.cartoes || []).map(c => c.local)]
    .filter(Boolean)
    .forEach(chave => arquivos.delete(chave));
};
