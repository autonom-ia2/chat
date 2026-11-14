import { onScopeDispose, ref } from 'vue';
import { ehSemAcesso } from '../lista/falhas';
import { INTERVALO_INICIAL_MS, agendaComRecuo } from './consultaComRecuo';
import { AVISO_ERRO_TRAZER } from './falhasDaTela';
import { SITUACOES_DA_LISTA } from './prazo';

// #2894 — "O que eu já trouxe": a lista de listas, a prévia do que sai e o
// desfazer. Enquanto alguma lista ainda está sendo trazida, a tela pergunta de
// novo sozinha (sem piscar o esqueleto), com a espera crescendo a cada pergunta
// e sem perguntar com a aba escondida (trazer/consultaComRecuo.js).
// #2896 — a lista que parou no meio tem "Tentar de novo"; e quem o servidor
// recusa por falta de acesso liga `semAcesso` (a tela diz isso, sem oferecer
// tentar).
export const INTERVALO_DO_HISTORICO_MS = INTERVALO_INICIAL_MS;

const AVISO_ERRO_DESFAZER = 'RELACIONAMENTOS_TRAZER.ERROS.DESFAZER';

const emAndamento = lista => lista.situacao === SITUACOES_DA_LISTA.TRAZENDO;

// As listas que a conta já trouxe e a carga delas.
const useCargaDoHistorico = ({ fonte, intervalo }) => {
  const listas = ref([]);
  const carregando = ref(false);
  const erro = ref(false);
  const semAcesso = ref(false);
  const agenda = agendaComRecuo({ inicial: intervalo });
  let encerrado = false;
  // Número da última carga pedida: resposta de carga mais velha é descartada.
  let ultimaCarga = 0;

  const carregar = async ({ silencioso = false, daAgenda = false } = {}) => {
    if (encerrado) return;
    ultimaCarga += 1;
    const minha = ultimaCarga;
    const vale = () => !encerrado && minha === ultimaCarga;
    if (!silencioso) carregando.value = true;
    erro.value = false;
    // A carga que alguém pediu recomeça a espera; a que a agenda disparou segue
    // o recuo.
    if (daAgenda) agenda.cancelar();
    else agenda.recomecar();
    try {
      const recebidas = await fonte.historico();
      if (!vale()) return;
      listas.value = recebidas;
      if (recebidas.some(emAndamento)) {
        agenda.agendar(() => carregar({ silencioso: true, daAgenda: true }));
      }
    } catch (falha) {
      if (!vale()) return;
      if (ehSemAcesso(falha)) semAcesso.value = true;
      else erro.value = true;
    } finally {
      if (minha === ultimaCarga) carregando.value = false;
    }
  };

  onScopeDispose(() => {
    encerrado = true;
    agenda.cancelar();
  });

  return { listas, carregando, erro, semAcesso, carregar };
};

// O desfazer de uma lista: a prévia do que sai e a confirmação.
const useDesfazerDaLista = ({ fonte, avisar, carregar }) => {
  const alvo = ref(null);
  const previa = ref(null);
  const previaComErro = ref(false);
  const desfazendo = ref(false);

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

  return {
    alvo,
    previa,
    previaComErro,
    desfazendo,
    abrirDesfazer,
    fecharDesfazer,
    confirmarDesfazer,
  };
};

export const useHistoricoDeListas = ({
  fonte,
  avisar = () => {},
  intervalo = INTERVALO_DO_HISTORICO_MS,
}) => {
  const carga = useCargaDoHistorico({ fonte, intervalo });
  const { semAcesso, carregar } = carga;
  // O id da lista que está tentando de novo (uma por vez).
  const tentando = ref(null);

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
      if (ehSemAcesso(falha)) semAcesso.value = true;
      else avisar(AVISO_ERRO_TRAZER);
      return false;
    } finally {
      tentando.value = null;
    }
  };

  return {
    ...carga,
    tentando,
    tentarDeNovo,
    ...useDesfazerDaLista({ fonte, avisar, carregar }),
  };
};
