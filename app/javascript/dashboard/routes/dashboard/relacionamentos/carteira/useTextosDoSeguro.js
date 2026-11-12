// #2897 — os textos que várias peças da carteira dizem igual: o nome do tipo,
// a frase de tempo (lista, ficha ou painel), em que pé está a renovação e os
// formatos no idioma do painel.
import { useI18n } from 'vue-i18n';
import { formatarDiaMes } from '../ficha/formatos';
import { useIdioma } from '../ficha/idioma';
import {
  formatarDataInteira,
  formatarHora,
  formatarValor,
} from './formatosDoSeguro';
import { periodoDoPreco } from './periodoDoPreco';
import { quandoDoSeguro } from './quandoDoSeguro';
import { situacaoDaRenovacao } from './situacaoDaRenovacao';
import { chaveDoTipo } from './tiposDeSeguro';

export const ONDE = { LISTA: 'LISTA', FICHA: 'FICHA', PAINEL: 'PAINEL' };

export const useTextosDoSeguro = () => {
  const { t } = useI18n();
  const idioma = useIdioma();

  const tipo = seguro => t(chaveDoTipo(seguro.tipo));
  const diaMes = (segundos, agora = null) =>
    formatarDiaMes(segundos, idioma.value, agora);
  const dataInteira = segundos => formatarDataInteira(segundos, idioma.value);

  // Na ficha a data vai inteira ("29/11/2026"); na lista, só dia e mês. Quem
  // vence longe (só a data, sem contar os dias) leva o ano em todo lugar.
  const quando = (seguro, agora, onde = ONDE.LISTA) => {
    const { id, count, data } = quandoDoSeguro(seguro, agora);
    const comAno =
      id === 'VENCE_NA_DATA' || (onde === ONDE.FICHA && id.startsWith('VENCE'));
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

  // "As opções já foram enviadas. Falta a resposta.": o que já foi feito na
  // renovação e o que falta.
  const renovacao = dados => {
    const { id, etapa } = situacaoDaRenovacao(dados);
    return t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.SITUACAO.${id}`, { etapa });
  };

  // "por ano" ou "por mês", conforme o preço (um seguro ou uma proposta).
  const periodo = preco =>
    t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.PERIODO.${periodoDoPreco(preco)}`);

  // "nº AT-000903". Quem mostra põe num pedaço que não quebra a linha
  // (`whitespace-nowrap`): sem isso o número parte no hífen.
  const numero = seguro =>
    t('RELACIONAMENTOS_CARTEIRA.NUMERO_DA_APOLICE', { numero: seguro.numero });

  return {
    tipo,
    quando,
    renovacao,
    periodo,
    numero,
    doCampo,
    diaMes,
    dataInteira,
    hora: segundos => formatarHora(segundos, idioma.value),
    valor: quanto => formatarValor(quanto, idioma.value),
  };
};
