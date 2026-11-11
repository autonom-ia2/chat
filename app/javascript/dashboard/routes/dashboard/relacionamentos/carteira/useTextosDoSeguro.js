// #2897 — os textos que várias peças da carteira dizem igual: o nome do tipo,
// a frase de tempo (lista, ficha ou painel) e os formatos no idioma do painel.
import { useI18n } from 'vue-i18n';
import { formatarDiaMes } from '../ficha/formatos';
import { useIdioma } from '../ficha/idioma';
import {
  formatarDataInteira,
  formatarHora,
  formatarValor,
} from './formatosDoSeguro';
import { quandoDoSeguro } from './quandoDoSeguro';
import { chaveDoTipo } from './tiposDeSeguro';

export const ONDE = { LISTA: 'LISTA', FICHA: 'FICHA', PAINEL: 'PAINEL' };

export const useTextosDoSeguro = () => {
  const { t } = useI18n();
  const idioma = useIdioma();

  const tipo = seguro => t(chaveDoTipo(seguro.tipo));
  const diaMes = (segundos, agora = null) =>
    formatarDiaMes(segundos, idioma.value, agora);
  const dataInteira = segundos => formatarDataInteira(segundos, idioma.value);

  // Na ficha a data vai inteira ("29/11/2026"); na lista, só dia e mês.
  const quando = (seguro, agora, onde = ONDE.LISTA) => {
    const { id, count, data } = quandoDoSeguro(seguro, agora);
    const comAno = onde === ONDE.FICHA && id.startsWith('VENCE');
    const dataEscrita = data
      ? (comAno ? dataInteira : diaMes)(data, agora)
      : '';
    return t(`RELACIONAMENTOS_CARTEIRA.QUANDO.${onde}.${id}`, {
      count,
      data: dataEscrita,
    });
  };

  // Um valor de um campo do seguro, do jeito que a tela escreve.
  const FORMATOS = {
    valor: numero => formatarValor(numero, idioma.value),
    comeca: dataInteira,
    termina: dataInteira,
    tipo: nome => t(chaveDoTipo(nome)),
  };
  const doCampo = (campo, conteudo) =>
    campo in FORMATOS ? FORMATOS[campo](conteudo) : String(conteudo ?? '');

  return {
    tipo,
    quando,
    doCampo,
    diaMes,
    dataInteira,
    hora: segundos => formatarHora(segundos, idioma.value),
    valor: numero => formatarValor(numero, idioma.value),
  };
};
