// #2894 — conferência do formulário "Alterar informações". Só cobra o que a
// pessoa mexeu: um dado antigo fora do formato não trava quem corrige o nome.
// Devolve a chave de tradução do problema (dentro de RELACIONAMENTOS_FICHA.GAVETA.ERRO).
import { soDigitos } from '../fonte/texto';
import { cpfValido, emailValido } from './validacao';
import { linkCompleto, temValor } from './atributos';
import { attributeDate } from 'dashboard/helper/attributeDate';

const mudou = (inicial, atual, campo) => inicial[campo] !== atual[campo];

// #3075 — o campo personalizado do tipo link aceita o endereço com ou sem o
// "https://" (ficha/atributos.js#linkCompleto); o erro, só quando nem assim é
// um endereço de site. O erro fica em `atributo:<chave>`.
// A empresa escrita na busca e não escolhida da lista (`empresaPendente`) trava
// o "Salvar": sem isso, o nome escrito se perderia calado.
// #3082 — a data escrita que não vira um dia de verdade ("31/02/2026", ano com
// dois números) também trava o "Salvar" (ficha/dataDoCampo.js#valorDaData).
const PROBLEMA_DO_TIPO = {
  link: valor => !linkCompleto(valor) && 'LINK',
  date: valor => !attributeDate(valor) && 'DATA',
};

const errosDosAtributos = (inicial, atual, tipos) =>
  Object.fromEntries(
    Object.entries(atual.atributos ?? {})
      .filter(
        ([chave, valor]) =>
          temValor(valor) && valor !== inicial.atributos?.[chave]
      )
      .map(([chave, valor]) => [
        `atributo:${chave}`,
        PROBLEMA_DO_TIPO[tipos[chave]]?.(valor),
      ])
      .filter(([, problema]) => problema)
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
  return { ...erros, ...errosDosAtributos(inicial, atual, tipos) };
};

const TAMANHO_CNPJ = 14;

// Só cobra o CNPJ e o site se a pessoa mexeu neles; vazio é permitido (limpar).
// #3078 — o site aceita "padaria.com.br" ou "https://padaria.com.br" (quem
// confere é atributos.js#linkCompleto), e os campos do tipo link da empresa
// seguem a regra da pessoa.
export const errosDaEmpresa = (inicial, atual, tipos = {}) => {
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
  const site = atual.site.trim();
  if (site && mudou(inicial, atual, 'site') && !linkCompleto(site)) {
    erros.site = 'LINK';
  }
  return { ...erros, ...errosDosAtributos(inicial, atual, tipos) };
};
