import { onScopeDispose, ref } from 'vue';
import { SEM_ACESSO } from '../ficha/falhas';
import { SITUACOES_DA_LISTA } from './prazo';

// #2894 — "O que eu já trouxe": a lista de listas, a prévia do que sai e o
// desfazer. Enquanto alguma lista ainda está sendo trazida, a tela pergunta de
// novo a cada `intervalo` (sem piscar o esqueleto).
// #2896 — a lista que parou no meio tem "Tentar de novo"; e quem o servidor
// recusa por falta de acesso liga `semAcesso` (a tela diz isso, sem oferecer
// tentar).
export const INTERVALO_DO_HISTORICO_MS = 1500;

const AVISO_ERRO_DESFAZER = 'RELACIONAMENTOS_TRAZER.ERROS.DESFAZER';
const AVISO_ERRO_TRAZER = 'RELACIONAMENTOS_TRAZER.ERROS.TRAZER';

export const useHistoricoDeListas = ({
  fonte,
  avisar = () => {},
  intervalo = INTERVALO_DO_HISTORICO_MS,
}) => {
  const listas = ref([]);
  const carregando = ref(false);
  const erro = ref(false);
  const semAcesso = ref(false);
  // O id da lista que está tentando de novo (uma por vez).
  const tentando = ref(null);
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
    } catch (falha) {
      if (encerrado || minha !== ultimaCarga) return;
      if (falha?.name === SEM_ACESSO) semAcesso.value = true;
      else erro.value = true;
    } finally {
      if (minha === ultimaCarga) carregando.value = false;
    }
  };

  // Devolve true quando o servidor aceitou continuar a lista; a carga seguinte
  // já a mostra sendo trazida (e volta a perguntar pelo andamento).
  const tentarDeNovo = async lista => {
    if (tentando.value !== null) return false;
    tentando.value = lista.id;
    try {
      await fonte.tentarDeNovo(lista.id);
      await carregar({ silencioso: true });
      return true;
    } catch (falha) {
      if (falha?.name === SEM_ACESSO) semAcesso.value = true;
      else avisar(AVISO_ERRO_TRAZER);
      return false;
    } finally {
      tentando.value = null;
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
    semAcesso,
    tentando,
    alvo,
    previa,
    previaComErro,
    desfazendo,
    carregar,
    tentarDeNovo,
    abrirDesfazer,
    fecharDesfazer,
    confirmarDesfazer,
  };
};
