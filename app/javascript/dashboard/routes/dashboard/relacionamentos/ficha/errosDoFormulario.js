// #2894 — conferência do formulário "Alterar informações". Só cobra o que a
// pessoa mexeu: um dado antigo fora do formato não trava quem corrige o nome.
// Devolve a chave de tradução do problema (dentro de RELACIONAMENTOS_FICHA.GAVETA.ERRO).
import { soDigitos } from '../fonte/texto';
import { cpfValido, emailValido } from './validacao';
import { linkCompleto, temValor } from './atributos';

const mudou = (inicial, atual, campo) => inicial[campo] !== atual[campo];

// #3075 — o campo personalizado do tipo link aceita o endereço com ou sem o
// "https://" (ficha/atributos.js#linkCompleto); o erro, só quando nem assim é
// um endereço de site. O erro fica em `atributo:<chave>`.
// A empresa escrita na busca e não escolhida da lista (`empresaPendente`) trava
// o "Salvar": sem isso, o nome escrito se perderia calado.
const errosDosLinks = (inicial, atual, tipos) =>
  Object.fromEntries(
    Object.entries(atual.atributos ?? {})
      .filter(
        ([chave, valor]) =>
          tipos[chave] === 'link' &&
          temValor(valor) &&
          valor !== inicial.atributos?.[chave] &&
          !linkCompleto(valor)
      )
      .map(([chave]) => [`atributo:${chave}`, 'LINK'])
  );

export const errosDoFormulario = (inicial, atual, tipos = {}) => {
  const erros = {};
  if (!atual.nome.trim()) erros.nome = 'NOME';
  const email = atual.email.trim();
  if (email && mudou(inicial, atual, 'email') && !emailValido(email)) {
    erros.email = 'EMAIL';
  }
  if (atual.cpf && mudou(inicial, atual, 'cpf') && !cpfValido(atual.cpf)) {
    erros.cpf = 'CPF';
  }
  if (String(atual.empresaPendente ?? '').trim()) {
    erros.empresa = 'EMPRESA_SEM_ESCOLHA';
  }
  return { ...erros, ...errosDosLinks(inicial, atual, tipos) };
};

const TAMANHO_CNPJ = 14;

// Só cobra o CNPJ se a pessoa mexeu nele; vazio é permitido (limpar).
export const errosDaEmpresa = (inicial, atual) => {
  const erros = {};
  if (!atual.nome.trim()) erros.nome = 'NOME';
  const digitos = soDigitos(atual.cnpj);
  if (
    digitos &&
    mudou(inicial, atual, 'cnpj') &&
    digitos.length !== TAMANHO_CNPJ
  ) {
    erros.cnpj = 'CNPJ';
  }
  return erros;
};
