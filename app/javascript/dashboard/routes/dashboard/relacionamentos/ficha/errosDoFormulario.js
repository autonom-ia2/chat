// #2894 — conferência do formulário "Alterar informações". Só cobra o que a
// pessoa mexeu: um dado antigo fora do formato não trava quem corrige o nome.
// Devolve a chave de tradução do problema (dentro de RELACIONAMENTOS_FICHA.GAVETA.ERRO).
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
