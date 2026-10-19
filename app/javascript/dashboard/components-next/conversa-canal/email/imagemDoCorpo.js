// #1869: foto que o iPhone (e outros) manda dentro do corpo do e-mail não vira anexo:
// o servidor guarda o arquivo e deixa só um <img> no texto. Sem isto, clicar nela não
// fazia nada. O clique abre a imagem inteira numa aba nova, onde dá para ampliar e
// salvar. Imagem dentro de link segue o link; endereço que não é web não abre.
import { enderecoSeguro } from '../midia/enderecoParaBaixar';

export const abrirImagemDoCorpo = evento => {
  const imagem = evento.target?.closest?.('img');
  if (!imagem || imagem.closest('a')) return;
  const endereco = enderecoSeguro(imagem.getAttribute('src'));
  if (!endereco) return;
  window.open(endereco, '_blank', 'noopener,noreferrer');
};
