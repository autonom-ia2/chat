// "Tabela de preços.pdf" vira "Tabela de preços" (extensão curta some, como no protótipo); endereço
// de site fica inteiro, e nome sem extensão de verdade (ponto no começo, "extensão" longa ou com
// espaço) também. Serve ao material da conversa da criação e ao "Usou: …" do celular de teste.
const MAX_EXTENSAO = 4;

export const nomeSemExtensao = nomeCompleto => {
  const nome = nomeCompleto || '';
  const ponto = nome.lastIndexOf('.');
  const extensao = nome.slice(ponto + 1);
  const site = nome.startsWith('www.') || nome.includes('/');
  if (
    site ||
    ponto <= 0 ||
    extensao.length > MAX_EXTENSAO ||
    extensao.includes(' ')
  ) {
    return nome;
  }
  return nome.slice(0, ponto);
};
