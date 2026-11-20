// #3075 — o país da pessoa (additional_attributes.country_code e country), como
// a ficha antiga grava (ContactsForm): o código e o nome em inglês da lista da
// casa (shared/constants/countries.js). Na tela o nome sai no idioma do painel
// pelo Intl, com a bandeira na frente.
import countries from 'shared/constants/countries';
import { PAIS_PADRAO } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

const nomesNoIdioma = new Map();
const nomesDoIdioma = idioma => {
  if (!nomesNoIdioma.has(idioma)) {
    nomesNoIdioma.set(
      idioma,
      new Intl.DisplayNames([idioma], { type: 'region' })
    );
  }
  return nomesNoIdioma.get(idioma);
};

// O nome do país no idioma do painel; sem código conhecido, o texto gravado.
export const nomeDoPais = (codigo, idioma, gravado = '') => {
  const pais = countries.find(item => item.id === codigo);
  if (!pais) return gravado;
  try {
    return nomesDoIdioma(idioma).of(codigo) || pais.name;
  } catch {
    return pais.name;
  }
};

export const paisNaTela = (adicionais, idioma) =>
  nomeDoPais(adicionais?.country_code, idioma, adicionais?.country ?? '');

// O nome que vai para `country`, igual ao da ficha antiga.
export const nomeGravadoDoPais = codigo =>
  countries.find(item => item.id === codigo)?.name ?? '';

// As opções da escolha: o país padrão do telefone (o mesmo do CampoDeTelefone)
// logo no começo, e os outros em ordem alfabética no idioma do painel. `nenhum`
// é o texto da opção que deixa o país em branco: só entra quando há um país
// escolhido (sem país, a escolha mostra o texto de "escolha o país").
export const opcoesDePais = (idioma, nenhum, atual = '') => {
  const todas = countries
    .map(({ id, emoji }) => {
      const nome = nomeDoPais(id, idioma);
      return { value: id, label: `${emoji} ${nome}`, searchLabel: nome };
    })
    .sort((a, b) => a.searchLabel.localeCompare(b.searchLabel, idioma));
  const padrao = todas.filter(opcao => opcao.value === PAIS_PADRAO);
  const resto = todas.filter(opcao => opcao.value !== PAIS_PADRAO);
  const limpar = atual ? [{ value: '', label: nenhum }] : [];
  return [...limpar, ...padrao, ...resto];
};
