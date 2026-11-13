// #2897 — o que vai no rodapé da gaveta do seguro e o que vai no "⋯". Função
// pura: devolve os nomes; quem desenha traduz e liga cada nome à ação. O rodapé
// tem um botão azul só: "Ver PDF" quando o seguro tem o PDF guardado, "Guardar
// o PDF" quando falta e o seguro ainda vale. "Corrigir" fica ao lado e o resto
// mora no "⋯". No seguro vencido ou cancelado sem PDF não há botão azul:
// guardar o PDF deixa de ser o próximo passo e vai para o "⋯".
// Quem só pode ver a pessoa (`podeEditar` falso) não tem o que mude o seguro:
// fica só "Ver PDF", e só quando há PDF.
import { estaValendo } from '../fonte/selosDoSeguro';

export const DO_RODAPE = {
  VER_PDF: 'VER_PDF',
  GUARDAR_PDF: 'GUARDAR_PDF',
  GUARDAR_OUTRO_PDF: 'GUARDAR_OUTRO_PDF',
  APAGAR_PDF: 'APAGAR_PDF',
  CORRIGIR: 'CORRIGIR',
  MARCAR_CANCELADO: 'MARCAR_CANCELADO',
  DESFAZER_CANCELAMENTO: 'DESFAZER_CANCELAMENTO',
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
  return {
    azul: azulDe(seguro, valendo),
    secundario: DO_RODAPE.CORRIGIR,
    menu: [
      ...doPdfNoMenu(seguro, valendo),
      seguro.canceladoEm
        ? DO_RODAPE.DESFAZER_CANCELAMENTO
        : DO_RODAPE.MARCAR_CANCELADO,
    ],
  };
};
