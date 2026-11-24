// #3100 — as frases que todas as telas da fidelidade repetem: "7 carimbos",
// "R$ 50", "10% de desconto", "12/11". Um lugar só, para a ficha, o cartão, o
// cupom e a automação dizerem igual.
import { useI18n } from 'vue-i18n';
import { formatarDinheiro } from 'dashboard/routes/dashboard/relacionamentos/ficha/compras';
import { formatarDiaMes } from 'dashboard/routes/dashboard/relacionamentos/ficha/formatos';
import { useIdioma } from 'dashboard/routes/dashboard/relacionamentos/ficha/idioma';
import { OFERTAS, TIPOS } from './regras';

export const F = 'FIDELIDADE';

export const useTextosDaFidelidade = () => {
  const { t } = useI18n();
  const idioma = useIdioma();

  const unidade = (quantos, tipo = TIPOS.CARIMBOS) =>
    t(`${F}.UNIDADE.${tipo}`, { count: quantos }, quantos);
  const nomeDaUnidade = (tipo = TIPOS.CARIMBOS) =>
    t(`${F}.NOME_DA_UNIDADE.${tipo}`);
  const dinheiro = (valor, moeda = 'BRL') =>
    formatarDinheiro(valor, moeda, idioma.value);
  const data = (segundos, agoraEmMs = null) =>
    formatarDiaMes(segundos, idioma.value, agoraEmMs);
  const oferta = (dada, moeda = 'BRL') => {
    if (!dada) return '';
    if (dada.tipo === OFERTAS.PORCENTAGEM)
      return t(`${F}.OFERTA.porcentagem`, { n: dada.valor ?? 0 });
    if (dada.tipo === OFERTAS.VALOR)
      return t(`${F}.OFERTA.valor`, { valor: dinheiro(dada.valor, moeda) });
    return (dada.texto || '').trim();
  };
  // "A cada R$ 50 em compras, ganha 1 carimbo."
  const regra = programa =>
    t(`${F}.CARTAO.REGRA`, {
      valor: dinheiro(programa.a_cada, programa.moeda),
      ganha: unidade(programa.ganha, programa.tipo),
    });

  // O prêmio no meio da frase ("Prêmio: uma lavagem grátis"): a primeira letra
  // em minúscula, sem mexer no que foi salvo. Sigla ("PIX de R$ 10") fica.
  const premioNaFrase = (premio = '') => {
    const texto = premio || '';
    const segunda = texto.charAt(1);
    if (!texto || segunda !== segunda.toLocaleLowerCase(idioma.value))
      return texto;
    return texto.charAt(0).toLocaleLowerCase(idioma.value) + texto.slice(1);
  };

  return {
    t,
    idioma,
    unidade,
    nomeDaUnidade,
    dinheiro,
    data,
    oferta,
    regra,
    premioNaFrase,
  };
};
