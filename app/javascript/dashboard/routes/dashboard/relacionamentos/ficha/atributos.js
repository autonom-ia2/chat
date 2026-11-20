// #3075 — os campos personalizados da pessoa, lidos das definições da conta
// (custom_attribute_definitions, attribute_model contact_attribute). Funções
// puras, sem mutar o que recebem. #3078 — e os da empresa (company_attribute,
// área `company_details` do configurador), pela mesma regra.
//
// Cada campo sai como { id, chave, rotulo, tipo, opcoes, valor, principal } (o
// solto, sem definição, não tem `id`):
//  - `rotulo` é o nome que a conta deu ao campo (attribute_display_name). Valor
//    gravado sem definição (por importação ou pela IA) usa o nome da chave;
//  - `tipo` é um dos TIPOS; tipo que a tela não conhece vira texto;
//  - `principal`: aparece na ficha e no topo da gaveta. É o campo escolhido pelo
//    configurador para a ficha (área `contact_details`, a mesma da ficha antiga)
//    ou o que já tem valor. O resto fica atrás de "Mais campos" na gaveta.
// Fora da lista, como nas outras telas: o campo com "Mostrar na tela"
// desligado (#2435), os internos da WAHA (#2138) e o CPF, que tem linha própria.
import { naTela } from 'dashboard/helper/atributosNaTela';
import { ehAtributoInternoDoWhatsapp } from 'dashboard/helper/atributosInternosDoWhatsapp';

export const TIPOS = ['text', 'number', 'link', 'date', 'list', 'checkbox'];
export const CHAVE_DO_CPF = 'cpf';

// O nome que a conta deu à informação. A chave não tem acento, então os nomes
// conhecidos vêm daqui; os outros saem da própria chave ("cor_favorita" ->
// "Cor favorita"). Só para o valor gravado sem definição.
const NOMES_CONHECIDOS = {
  melhor_horario: 'Melhor horário',
  como_prefere_ser_chamado: 'Como prefere ser chamado',
};

export const nomeDaInformacao = chave => {
  if (NOMES_CONHECIDOS[chave]) return NOMES_CONHECIDOS[chave];
  const palavras = String(chave).split('_').filter(Boolean).join(' ');
  return palavras.charAt(0).toUpperCase() + palavras.slice(1);
};

// "Não marcado" (false) é um valor; vazio, nulo e ausente não são.
export const temValor = valor =>
  valor !== undefined && valor !== null && valor !== '';

const foraDaFicha = chave =>
  chave === CHAVE_DO_CPF || ehAtributoInternoDoWhatsapp(chave);

const tipoConhecido = tipo => (TIPOS.includes(tipo) ? tipo : 'text');

// #3078 — a empresa tem os campos dela (attribute_model company_attribute); o
// CPF e os internos da WAHA são só da pessoa.
export const MODELOS = {
  pessoa: 'contact_attribute',
  empresa: 'company_attribute',
};

const foraDoModelo = (modelo, chave) =>
  modelo === MODELOS.pessoa && foraDaFicha(chave);

const doModelo = modelo => definicao =>
  definicao.attribute_model === modelo &&
  !foraDoModelo(modelo, definicao.attribute_key);

const campoDaDefinicao = (definicao, valores, escolhidos) => {
  const valor = valores[definicao.attribute_key];
  return {
    id: definicao.id,
    chave: definicao.attribute_key,
    rotulo: definicao.attribute_display_name || definicao.attribute_key,
    tipo: tipoConhecido(definicao.attribute_display_type),
    opcoes: definicao.attribute_values ?? [],
    valor: temValor(valor) ? valor : '',
    principal: escolhidos.has(definicao.id) || temValor(valor),
  };
};

// `definicoes`: as da conta, como o servidor manda (snake_case), inclusive as
// que estão fora da tela (para o valor delas não virar campo solto).
// `escolhidos`: os ids que o configurador pôs na ficha.
// `valores`: os custom_attributes da pessoa (ou da empresa, com `modelo`).
export const camposDoRegistro = ({
  definicoes = [],
  escolhidos = [],
  valores = {},
  modelo = MODELOS.pessoa,
}) => {
  const daConta = definicoes.filter(doModelo(modelo));
  const ids = new Set(escolhidos);
  const conhecidas = new Set(daConta.map(d => d.attribute_key));
  const comDefinicao = naTela(daConta).map(definicao =>
    campoDaDefinicao(definicao, valores, ids)
  );
  const soltos = Object.entries(valores)
    .filter(
      ([chave, valor]) =>
        !foraDoModelo(modelo, chave) &&
        !conhecidas.has(chave) &&
        temValor(valor)
    )
    .map(([chave, valor]) => ({
      chave,
      rotulo: nomeDaInformacao(chave),
      tipo: 'text',
      opcoes: [],
      valor,
      principal: true,
    }));
  // Na ordem da conta: os escolhidos, depois os outros que têm valor (os soltos
  // por último) e, no fim, os que não aparecem na ficha.
  const escolhido = campo => ids.has(campo.id);
  return [
    ...comDefinicao.filter(escolhido),
    ...comDefinicao.filter(campo => !escolhido(campo) && campo.principal),
    ...soltos,
    ...comDefinicao.filter(campo => !campo.principal),
  ];
};

export const camposDaPessoa = dados =>
  camposDoRegistro({ ...dados, modelo: MODELOS.pessoa });

export const camposDaEmpresa = dados =>
  camposDoRegistro({ ...dados, modelo: MODELOS.empresa });

// #3082 — as linhas do bloco "Seus campos" da ficha (da pessoa e da empresa):
// os campos que aparecem na ficha (`principal`), com o nome que a conta deu e o
// tipo. O valor vai como está gravado (a lista formata pelo `tipo`); o vazio
// vai como '' e a lista mostra "Não informado".
export const linhasDosCampos = (campos = []) =>
  campos
    .filter(campo => campo.principal)
    .map(campo => ({
      chave: `conta:${campo.chave}`,
      rotulo: campo.rotulo,
      tipo: campo.tipo,
      valor: temValor(campo.valor) ? campo.valor : '',
    }));

// O bloco "Seus campos" aparece quando há campo para mostrar ou quando quem
// olha pode criar e escolher campos (`podeMexer`); sem nenhum dos dois, some.
export const blocoDosCamposAparece = (campos = [], podeMexer = false) =>
  podeMexer || campos.some(campo => campo.principal);

// O link só vira link de verdade com http ou https (nada de javascript:).
export const linkSeguro = valor => {
  try {
    const endereco = new URL(String(valor));
    return ['http:', 'https:'].includes(endereco.protocol) ? endereco.href : '';
  } catch {
    return '';
  }
};

// O link como vai ser gravado: quem escreve "seusite.com.br" ganha o
// "https://" na frente. Devolve '' quando nem assim é um endereço de site. Quem
// confere é o parser de URL do navegador, não uma regra escrita à mão. O
// "https://" só entra quando o nome do site resultante tem ponto e não termina
// nele: o parser aceita qualquer palavra como nome ("naotenho" viraria
// "https://naotenho/"; no navegador, até "padaria bom dia" passa, com o espaço
// trocado por %20). O que já veio com "http://" ou "https://" vale como está.
export const linkCompleto = valor => {
  const escrito = String(valor ?? '').trim();
  if (!escrito) return '';
  if (linkSeguro(escrito)) return escrito;
  const comEsquema = `https://${escrito}`;
  const site = linkSeguro(comEsquema) ? new URL(comEsquema).hostname : '';
  return site.includes('.') && !site.endsWith('.') ? comEsquema : '';
};
