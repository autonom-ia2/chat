// Chave de uma tentativa de reserva (`request_id`). O servidor só devolve a reserva já feita a quem manda a mesma
// chave: telefone e horário iguais não bastam. Aleatória e sem dado da pessoa; 16 a 64 letras, dígitos ou `-`.
const RANDOM_BYTES = 16;

const hex = bytes =>
  Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');

export const newRequestId = (cryptoApi = globalThis.crypto) => {
  if (typeof cryptoApi?.randomUUID === 'function')
    return cryptoApi.randomUUID();
  return hex(cryptoApi.getRandomValues(new Uint8Array(RANDOM_BYTES)));
};
