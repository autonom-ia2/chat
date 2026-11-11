// #2897 — os passos de anexar o PDF de um seguro: soltar o arquivo, ler e
// mostrar o que mudou. Fala com a fonte e guarda o estado; o diálogo só desenha.
import { computed, ref } from 'vue';

export const ETAPAS_DO_PDF = {
  SOLTAR: 'soltar',
  LENDO: 'lendo',
  MUDOU: 'mudou',
};

// O nome do erro da fonte -> a frase do catálogo (RELACIONAMENTOS_CARTEIRA.PDF).
const FRASE_DO_ERRO = { NAO_E_APOLICE: 'NAO_E_APOLICE', NAO_LEU: 'NAO_LEU' };

export const useAnexarPdf = fonte => {
  const seguro = ref(null);
  const etapa = ref(ETAPAS_DO_PDF.SOLTAR);
  const erro = ref('');
  const mudancas = ref([]);
  const apoliceNova = ref(false);
  // Campos corrigidos à mão em que a pessoa pediu "Usar o do PDF".
  const escolhidos = ref([]);
  const guardando = ref(false);

  const comecar = alvo => {
    seguro.value = alvo;
    etapa.value = ETAPAS_DO_PDF.SOLTAR;
    erro.value = '';
    mudancas.value = [];
    escolhidos.value = [];
    apoliceNova.value = Boolean(alvo.renovadoEm);
  };

  const ler = async arquivo => {
    erro.value = '';
    etapa.value = ETAPAS_DO_PDF.LENDO;
    try {
      const lido = await fonte.lerPdf(seguro.value.id, arquivo);
      mudancas.value = lido.mudancas;
      etapa.value = ETAPAS_DO_PDF.MUDOU;
    } catch (falha) {
      erro.value = FRASE_DO_ERRO[falha?.name] ?? FRASE_DO_ERRO.NAO_LEU;
      etapa.value = ETAPAS_DO_PDF.SOLTAR;
    }
  };

  const usarDoPdf = campo => {
    escolhidos.value = [...new Set([...escolhidos.value, campo])];
  };

  // "Usar o que está no PDF" vale para o que não foi corrigido à mão e para o
  // que a pessoa escolheu, linha a linha; "Manter como está" não muda nada.
  const camposDoPdf = computed(() =>
    mudancas.value
      .filter(m => !m.corrigidoAMao || escolhidos.value.includes(m.campo))
      .map(m => m.campo)
  );

  // Devolve o seguro guardado, ou null se não deu.
  const guardar = async ({ usarPdf }) => {
    erro.value = '';
    guardando.value = true;
    try {
      return await fonte.guardarPdf(seguro.value.id, {
        usar: usarPdf ? camposDoPdf.value : [],
      });
    } catch {
      erro.value = 'NAO_GUARDOU';
      return null;
    } finally {
      guardando.value = false;
    }
  };

  return {
    seguro,
    etapa,
    erro,
    mudancas,
    apoliceNova,
    escolhidos,
    guardando,
    comecar,
    ler,
    usarDoPdf,
    guardar,
  };
};
