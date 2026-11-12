import { onScopeDispose, ref } from 'vue';
import { SITUACOES_DA_LISTA } from './prazo';

// #2894 — "O que eu já trouxe": a lista de listas, a prévia do que sai e o
// desfazer. Enquanto alguma lista ainda está sendo trazida, a tela pergunta de
// novo a cada `intervalo` (sem piscar o esqueleto).
export const INTERVALO_DO_HISTORICO_MS = 1500;

const AVISO_ERRO_DESFAZER = 'RELACIONAMENTOS_TRAZER.ERROS.DESFAZER';

export const useHistoricoDeListas = ({
  fonte,
  avisar = () => {},
  intervalo = INTERVALO_DO_HISTORICO_MS,
}) => {
  const listas = ref([]);
  const carregando = ref(false);
  const erro = ref(false);
  const alvo = ref(null);
  const previa = ref(null);
  const previaComErro = ref(false);
  const desfazendo = ref(false);
  let relogio = null;
  let encerrado = false;
  // Número da última carga pedida: resposta de carga mais velha é descartada.
  let ultimaCarga = 0;

  const emAndamento = lista => lista.situacao === SITUACOES_DA_LISTA.TRAZENDO;

  const carregar = async ({ silencioso = false } = {}) => {
    if (encerrado) return;
    ultimaCarga += 1;
    const minha = ultimaCarga;
    if (!silencioso) carregando.value = true;
    erro.value = false;
    clearTimeout(relogio);
    try {
      const recebidas = await fonte.historico();
      if (encerrado || minha !== ultimaCarga) return;
      listas.value = recebidas;
      if (recebidas.some(emAndamento)) {
        clearTimeout(relogio);
        relogio = setTimeout(() => carregar({ silencioso: true }), intervalo);
      }
    } catch {
      if (!encerrado && minha === ultimaCarga) erro.value = true;
    } finally {
      if (minha === ultimaCarga) carregando.value = false;
    }
  };

  const abrirDesfazer = async lista => {
    alvo.value = lista;
    previa.value = null;
    previaComErro.value = false;
    try {
      const preview = await fonte.previaDoDesfazer(lista.id);
      if (alvo.value?.id === lista.id) previa.value = preview;
    } catch {
      previaComErro.value = true;
    }
  };

  const fecharDesfazer = () => {
    alvo.value = null;
    previa.value = null;
    previaComErro.value = false;
  };

  // Devolve true quando desfez (a tela fecha o diálogo).
  const confirmarDesfazer = async () => {
    if (!alvo.value) return false;
    desfazendo.value = true;
    try {
      await fonte.desfazer(alvo.value.id);
      await carregar({ silencioso: true });
      return true;
    } catch {
      avisar(AVISO_ERRO_DESFAZER);
      return false;
    } finally {
      desfazendo.value = false;
    }
  };

  onScopeDispose(() => {
    encerrado = true;
    clearTimeout(relogio);
  });

  return {
    listas,
    carregando,
    erro,
    alvo,
    previa,
    previaComErro,
    desfazendo,
    carregar,
    abrirDesfazer,
    fecharDesfazer,
    confirmarDesfazer,
  };
};
