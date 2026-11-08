// O tamanho do privado do Instagram (#2543): a Meta aceita até 1000 bytes em UTF-8, não 1000 letras. Acento ocupa
// 2 bytes e emoji 4, então 700 letras acentuadas já podem passar. Espelha Crm::MetaAdsCommentCare::MESSAGE_LIMIT, a
// régua do servidor para todo privado (o da IA e o que a pessoa escreve).
export const LIMITE_DO_PRIVADO_EM_BYTES = 1000;

const codificador = new TextEncoder();

export const bytesDoTexto = (texto = '') => codificador.encode(texto).length;

export const privadoLongoDemais = (texto = '') =>
  bytesDoTexto(texto) > LIMITE_DO_PRIVADO_EM_BYTES;
