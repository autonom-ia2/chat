// PROTÓTIPO #1334 — adaptador falso: os arquivos de cada cartão do carrossel
// guardados com o modelo. A API de Modelos ainda não devolve essa lista; na
// implementação ela vem do perfil (`card_files`), trocando só esta função.
const GUARDADOS = {
  vitrine_de_outubro: [
    { nome: 'tenis-azul.jpg' },
    { nome: 'bolsa-de-couro.jpg' },
    { nome: 'oculos-de-sol.jpg' },
  ],
};

export const arquivosDosCartoes = modelo =>
  GUARDADOS[modelo?.nomeNoWhatsapp] || [];
