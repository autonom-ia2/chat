// Telefone do contato no "+" (#1702): o atendente escolhe o país (Brasil por
// padrão) e digita o número como fala, que já sai formatado do jeito daquele
// país. O sistema não adivinha o país: ele vem da escolha. Mesmo modelo do
// PhoneCountryInput do Orth (google-saas), com a libphonenumber-js.
import {
  AsYouType,
  getCountries,
  getCountryCallingCode,
  getExampleNumber,
  parsePhoneNumberFromString,
} from 'libphonenumber-js';
import exemplos from 'libphonenumber-js/examples.mobile.json';

export const PAIS_PADRAO = 'BR';

// "BR" → 🇧🇷: cada letra vira o seu indicador regional.
const bandeira = sigla =>
  [...sigla.toUpperCase()]
    .map(letra => String.fromCodePoint(127397 + letra.charCodeAt(0)))
    .join('');

const nomesPorIdioma = new Map();

// Um por país, em ordem alfabética no idioma do painel. O botão mostra só
// bandeira e DDI; a lista mostra também o nome, e digitar o nome pula para ele.
export const paisesDoTelefone = idioma => {
  if (nomesPorIdioma.has(idioma)) return nomesPorIdioma.get(idioma);
  const nomes = new Intl.DisplayNames([idioma], { type: 'region' });
  const paises = getCountries()
    .map(sigla => {
      const nome = nomes.of(sigla) || sigla;
      const ddi = `+${getCountryCallingCode(sigla)}`;
      return {
        value: sigla,
        label: `${bandeira(sigla)} ${nome} (${ddi})`,
        shortLabel: `${bandeira(sigla)} ${ddi}`,
        searchLabel: nome,
      };
    })
    .sort((a, b) => a.searchLabel.localeCompare(b.searchLabel, idioma));
  nomesPorIdioma.set(idioma, paises);
  return paises;
};

export const soDigitosDoTelefone = texto =>
  [...String(texto || '')].filter(c => c >= '0' && c <= '9').join('');

// O número como o país escreve, enquanto digita: "11987654321" → "(11) 98765-4321".
export const formatarNoPais = (digitos, pais) =>
  digitos ? new AsYouType(pais).input(digitos) : '';

// Exemplo do país, para o campo vazio: "(11) 96123-4567" no Brasil.
export const exemploDoPais = pais =>
  getExampleNumber(pais, exemplos)?.formatNational() || '';

// O número completo (+5511987654321), só quando é um número válido daquele país.
export const telefoneCompleto = (digitos, pais) => {
  const numero = parsePhoneNumberFromString(digitos || '', pais);
  return numero?.isValid() ? numero.number : '';
};

// Número com + (contato da base, colado ou digitado): separa país e número
// assim que o código do país fica claro ("+55" já é Brasil). Enquanto não fica
// (só "+", "+1" de vários países, "+800" sem país), devolve o texto como está
// em `cru`: o campo mostra o que a pessoa escreveu e não vale como número.
// Sem + não adivinha: fica no país escolhido.
export const separarTelefone = (texto, paisAtual = PAIS_PADRAO) => {
  const bruto = String(texto || '').trim();
  if (!bruto.startsWith('+')) {
    return { pais: paisAtual, digitos: soDigitosDoTelefone(bruto), cru: '' };
  }
  const leitor = new AsYouType();
  leitor.input(bruto);
  const pais = leitor.getCountry();
  if (!pais) return { pais: paisAtual, digitos: '', cru: bruto };
  return { pais, digitos: leitor.getNationalNumber(), cru: '' };
};

// Onde fica o cursor depois de formatar: logo depois do mesmo número de
// dígitos que estavam antes dele.
export const posicaoDepoisDosDigitos = (formatado, quantos) => {
  if (quantos <= 0) return 0;
  let vistos = 0;
  for (let i = 0; i < formatado.length; i += 1) {
    if (formatado[i] >= '0' && formatado[i] <= '9') vistos += 1;
    if (vistos === quantos) return i + 1;
  }
  return formatado.length;
};
