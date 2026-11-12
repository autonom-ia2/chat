import { soDigitos } from '../fonte/texto';

// #2894 — telefone brasileiro como a pessoa lê: +55 11 91031-0001. Número que
// não tem o tamanho de um telefone do Brasil volta como veio.
const PAIS = '55';
const TAMANHO_CELULAR = 13;
const TAMANHO_FIXO = 12;
const FIM_DO_DDD = 4;

export const formatarTelefone = valor => {
  if (!valor) return '';
  const digitos = soDigitos(valor);
  const tamanho = digitos.length;
  const ehBrasil =
    digitos.startsWith(PAIS) &&
    (tamanho === TAMANHO_CELULAR || tamanho === TAMANHO_FIXO);
  if (!ehBrasil) return String(valor);
  const ddd = digitos.slice(PAIS.length, FIM_DO_DDD);
  const numero = digitos.slice(FIM_DO_DDD);
  const corte = numero.length - 4;
  return `+${PAIS} ${ddd} ${numero.slice(0, corte)}-${numero.slice(corte)}`;
};
