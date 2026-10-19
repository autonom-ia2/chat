// Validação do campo Nome com o nome livre ligado (#1823, F1a): o título técnico
// que sai do nome precisa de 2 caracteres (como o Label) e o nome cabe na
// tabela própria (80).
import {
  TAMANHO_MAXIMO_DO_NOME,
  tituloTecnicoDoNome,
} from 'dashboard/helper/nomeDaEtiqueta';

export const nomeLivreLongoDemais = (nome = '') =>
  nome.trim().length > TAMANHO_MAXIMO_DO_NOME;

// Editar (#1823): o nome livre muda sozinho, o título técnico fica.
export const nomeLivreEditavel = (nome = '') =>
  nome.trim().length > 0 && !nomeLivreLongoDemais(nome);

export const nomeLivreValido = (nome = '') =>
  tituloTecnicoDoNome(nome).length >= 2 && !nomeLivreLongoDemais(nome);
