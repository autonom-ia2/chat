// #3082 — a data de um campo personalizado escrita no formato do idioma do
// painel ("15/11/2026" em português, "11/15/2026" em inglês), e não no do
// navegador. O campo de data do navegador mostra o formato do navegador: num
// navegador em inglês, a ficha em português pedia "mm/dd/aaaa".
// O servidor continua recebendo "AAAA-MM-DD", o formato que a ficha grava.
import { attributeDate } from 'dashboard/helper/attributeDate';

const DIGITOS = '0123456789';
// Entre o dia, o mês e o ano: barra, traço, ponto ou espaço. Qualquer outra
// coisa ("de maio", "abc") faz o texto não ser uma data.
const SEPARADORES = '/-. ';
const TAMANHO = { day: 2, month: 2, year: 4 };
const DIA_DE_EXEMPLO = new Date(2006, 0, 2, 12);

const formatos = new Map();

// A ordem das partes (dia, mês, ano) e o separador, lidos do próprio Intl.
export const formatoDaData = idioma => {
  if (!formatos.has(idioma)) {
    const partes = new Intl.DateTimeFormat(idioma, {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    }).formatToParts(DIA_DE_EXEMPLO);
    const ordem = partes
      .map(parte => parte.type)
      .filter(tipo => tipo in TAMANHO);
    const separador =
      partes.find(parte => parte.type === 'literal')?.value ?? '/';
    formatos.set(idioma, { ordem, separador });
  }
  return formatos.get(idioma);
};

// O que aparece no campo: a data gravada no formato do idioma. Um valor que
// não é uma data "AAAA-MM-DD" (importado de outro jeito, ou ainda sendo
// escrito) aparece como está, para ninguém perder o que foi escrito.
export const textoDaData = (valor, idioma) => {
  const dia = attributeDate(valor);
  if (!dia) return valor === undefined || valor === null ? '' : String(valor);
  const [year, month, day] = dia.split('-');
  const partes = { day, month, year };
  const { ordem, separador } = formatoDaData(idioma);
  return ordem.map(tipo => partes[tipo]).join(separador);
};

const gruposDeDigitos = texto =>
  [...String(texto)]
    .reduce(
      (grupos, letra) => {
        if (DIGITOS.includes(letra)) {
          const ultimo = grupos.length - 1;
          return [...grupos.slice(0, ultimo), grupos[ultimo] + letra];
        }
        return grupos[grupos.length - 1] === '' ? grupos : [...grupos, ''];
      },
      ['']
    )
    .filter(Boolean);

// "15112026" (só os números) também vale: corta pelo tamanho de cada parte.
const cortarPelaOrdem = (digitos, ordem) =>
  ordem.reduce(
    ({ partes, resto }, tipo) => ({
      partes: [...partes, resto.slice(0, TAMANHO[tipo])],
      resto: resto.slice(TAMANHO[tipo]),
    }),
    { partes: [], resto: digitos }
  ).partes;

const partesEscritas = (grupos, ordem) => {
  if (grupos.length === ordem.length) return grupos;
  const tamanhoTotal = ordem.reduce((soma, tipo) => soma + TAMANHO[tipo], 0);
  if (grupos.length === 1 && grupos[0].length === tamanhoTotal)
    return cortarPelaOrdem(grupos[0], ordem);
  return null;
};

// O que vai ao servidor: "AAAA-MM-DD" quando o texto é uma data que existe,
// '' quando o campo está vazio, e o próprio texto quando não é uma data (a
// conferência do formulário avisa antes de salvar).
export const valorDaData = (texto, idioma) => {
  const escrito = String(texto ?? '').trim();
  if (!escrito) return '';
  const { ordem } = formatoDaData(idioma);
  const soDataEscrita = [...escrito].every(
    letra => DIGITOS.includes(letra) || SEPARADORES.includes(letra)
  );
  const partes =
    soDataEscrita && partesEscritas(gruposDeDigitos(escrito), ordem);
  if (!partes) return escrito;
  const porTipo = Object.fromEntries(ordem.map((tipo, i) => [tipo, partes[i]]));
  if (porTipo.year.length !== TAMANHO.year) return escrito;
  const dia = attributeDate(
    `${porTipo.year}-${porTipo.month.padStart(2, '0')}-${porTipo.day.padStart(2, '0')}`
  );
  return dia || escrito;
};

// O formato para mostrar a quem escreve ("dd/mm/aaaa"), com as letras do idioma.
export const exemploDaData = (idioma, letras) => {
  const { ordem, separador } = formatoDaData(idioma);
  return ordem.map(tipo => letras[tipo]).join(separador);
};
