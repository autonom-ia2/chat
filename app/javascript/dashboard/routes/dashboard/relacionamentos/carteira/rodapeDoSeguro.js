// #2897 — o que vai no rodapé da gaveta do seguro e o que vai no "⋯". Função
// pura: devolve os nomes; quem desenha traduz e liga cada nome à ação. O rodapé
// tem um botão azul só: "Ver PDF" quando o seguro tem o PDF guardado, "Guardar
// o PDF" quando falta e o seguro ainda vale. "Corrigir" fica ao lado e o resto
// mora no "⋯". No seguro vencido ou cancelado sem PDF não há botão azul:
// guardar o PDF deixa de ser o próximo passo e vai para o "⋯".
// Quem só pode ver a pessoa (`podeEditar` falso) não tem o que mude o seguro:
// fica só "Ver PDF", e só quando há PDF.
// #2898 — a renovação muda o próximo passo. Com a renovação aberta, o azul é
// "Renovou" e ao lado fica "Não renovou"; o PDF e o "Corrigir" vão para o "⋯".
// Depois de renovar, o azul é "Guardar a apólice nova", até ela existir. E toda
// renovação que terminou ganha "Desfazer" no "⋯", sem prazo. No seguro
// cancelado o servidor não desfaz a renovação (o cancelamento a fechou): o
// "Desfazer" dela só volta depois de desfazer o cancelamento.
import { estaValendo, renovacaoAberta } from '../fonte/selosDoSeguro';
import { faltaApoliceNova, terminou } from './situacaoDaRenovacao';

export const DO_RODAPE = {
  VER_PDF: 'VER_PDF',
  GUARDAR_PDF: 'GUARDAR_PDF',
  GUARDAR_OUTRO_PDF: 'GUARDAR_OUTRO_PDF',
  APAGAR_PDF: 'APAGAR_PDF',
  CORRIGIR: 'CORRIGIR',
  MARCAR_CANCELADO: 'MARCAR_CANCELADO',
  DESFAZER_CANCELAMENTO: 'DESFAZER_CANCELAMENTO',
  RENOVOU: 'RENOVOU',
  NAO_RENOVOU: 'NAO_RENOVOU',
  GUARDAR_APOLICE_NOVA: 'GUARDAR_APOLICE_NOVA',
  DESFAZER_RENOVACAO: 'DESFAZER_RENOVACAO',
};

// O que não tem volta fácil aparece em vermelho no "⋯".
export const DESTRUTIVOS = [DO_RODAPE.APAGAR_PDF, DO_RODAPE.MARCAR_CANCELADO];

const azulDe = (seguro, valendo) => {
  if (seguro.temPdf) return DO_RODAPE.VER_PDF;
  return valendo ? DO_RODAPE.GUARDAR_PDF : null;
};

const doPdfNoMenu = (seguro, valendo) => {
  if (seguro.temPdf) return [DO_RODAPE.GUARDAR_OUTRO_PDF, DO_RODAPE.APAGAR_PDF];
  return valendo ? [] : [DO_RODAPE.GUARDAR_PDF];
};

// Quando o azul é da renovação, tudo do PDF mora no "⋯": ver, guardar, trocar
// e apagar.
const pdfNoMenuInteiro = seguro =>
  seguro.temPdf
    ? [DO_RODAPE.VER_PDF, DO_RODAPE.GUARDAR_OUTRO_PDF, DO_RODAPE.APAGAR_PDF]
    : [DO_RODAPE.GUARDAR_PDF];

// Com "Não renovou" ao lado do azul, "Corrigir" também desce para o "⋯".
const pdfECorrigirNoMenu = seguro => {
  const [primeiro, ...resto] = pdfNoMenuInteiro(seguro);
  return [primeiro, DO_RODAPE.CORRIGIR, ...resto];
};

export const rodapeDoSeguro = (
  seguro,
  { podeEditar = true, agora = Date.now() } = {}
) => {
  if (!podeEditar) {
    return {
      azul: seguro.temPdf ? DO_RODAPE.VER_PDF : null,
      secundario: null,
      menu: [],
    };
  }
  const valendo = estaValendo(seguro, agora);
  const cancelarOuDesfazer = seguro.canceladoEm
    ? DO_RODAPE.DESFAZER_CANCELAMENTO
    : DO_RODAPE.MARCAR_CANCELADO;
  if (renovacaoAberta(seguro) && !seguro.canceladoEm) {
    return {
      azul: DO_RODAPE.RENOVOU,
      secundario: DO_RODAPE.NAO_RENOVOU,
      menu: [...pdfECorrigirNoMenu(seguro), cancelarOuDesfazer],
    };
  }
  const desfazer =
    terminou(seguro) && !seguro.canceladoEm
      ? [DO_RODAPE.DESFAZER_RENOVACAO]
      : [];
  // Renovou e a apólice nova ainda não foi guardada: guardar é o próximo passo.
  const guardaANova = faltaApoliceNova(seguro) && !seguro.canceladoEm;
  const doPdf = guardaANova
    ? pdfNoMenuInteiro(seguro)
    : doPdfNoMenu(seguro, valendo);
  return {
    azul: guardaANova
      ? DO_RODAPE.GUARDAR_APOLICE_NOVA
      : azulDe(seguro, valendo),
    secundario: DO_RODAPE.CORRIGIR,
    menu: [...doPdf, ...desfazer, cancelarOuDesfazer],
  };
};
