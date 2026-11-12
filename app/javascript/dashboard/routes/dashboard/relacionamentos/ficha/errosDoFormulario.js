// #2894 — conferência do formulário "Alterar informações". Só cobra o que a
// pessoa mexeu: um dado antigo fora do formato não trava quem corrige o nome.
// Devolve a chave de tradução do problema (dentro de RELACIONAMENTOS_FICHA.GAVETA.ERRO).
import { soDigitos } from '../fonte/texto';
import { cpfValido, emailValido } from './validacao';

const mudou = (inicial, atual, campo) => inicial[campo] !== atual[campo];

export const errosDoFormulario = (inicial, atual) => {
  const erros = {};
  if (!atual.nome.trim()) erros.nome = 'NOME';
  const email = atual.email.trim();
  if (email && mudou(inicial, atual, 'email') && !emailValido(email)) {
    erros.email = 'EMAIL';
  }
  if (atual.cpf && mudou(inicial, atual, 'cpf') && !cpfValido(atual.cpf)) {
    erros.cpf = 'CPF';
  }
  return erros;
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
