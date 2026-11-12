// #2435: o atributo com "Mostrar na tela" desligado some das telas que mostram
// os campos (card, contato, empresa e conversa, nos painéis antigo e novo).
// Ele continua no store e no servidor: filtros, automação e IA ainda o usam.
// Só as telas que mostram os campos passam a lista por aqui.
const oculto = definicao =>
  Boolean(definicao?.oculto_na_tela ?? definicao?.ocultoNaTela);

export const naTela = definicoes => (definicoes || []).filter(d => !oculto(d));

// As chaves dos atributos fora da tela, para quem conta valores soltos.
export const chavesOcultas = definicoes =>
  new Set(
    (definicoes || [])
      .filter(oculto)
      .map(d => d.attribute_key ?? d.attributeKey)
  );
