// #2897 — ligar a conta ao Agger e buscar os seguros: o login (quando a conta
// ainda não está ligada), a busca seguradora por seguradora e o que fazer
// quando falta algo. A tela só fala em palavras do corretor; como a busca é
// feita não mora aqui.
import { computed, onScopeDispose, ref } from 'vue';
import { acompanhar } from './acompanhar';

export const INTERVALO_DA_BUSCA_MS = 600;

// O que deu errado ao entrar -> a frase do catálogo (TRAZER.AGGER.<chave>).
export const ERROS_DO_LOGIN = {
  NENHUM: '',
  NAO_CONFERE: 'NAO_CONFERE',
  SEM_APOLICES: 'SEM_APOLICES',
  NAO_ENTROU: 'NAO_ENTROU',
};

const ERRO_DE_CADA_FALHA = {
  LOGIN_NAO_CONFERE: ERROS_DO_LOGIN.NAO_CONFERE,
  AGGER_SEM_APOLICES: ERROS_DO_LOGIN.SEM_APOLICES,
};

export const useBuscaNoAgger = ({
  fonte,
  intervalo = INTERVALO_DA_BUSCA_MS,
}) => {
  const entrando = ref(false);
  const erroDoLogin = ref(ERROS_DO_LOGIN.NENHUM);
  // null = ainda não começou; depois, as seguradoras e, no fim, a leitura.
  const busca = ref(null);
  const naoRespondeu = ref(false);
  const buscandoDeNovo = ref(false);
  let buscaId = null;
  let vigia = null;

  const buscando = computed(() => busca.value !== null);
  const terminou = computed(() => Boolean(busca.value?.leitura));

  const parar = () => {
    vigia?.parar();
    vigia = null;
  };

  const acompanharABusca = () => {
    parar();
    naoRespondeu.value = false;
    vigia = acompanhar({
      intervalo,
      consultar: () => fonte.andamentoDaBusca(buscaId),
      aoChegar: andamento => {
        busca.value = andamento;
        return Boolean(andamento.leitura);
      },
      aoFalhar: () => {
        naoRespondeu.value = true;
      },
    });
  };

  // `pedir` é o jeito de começar: com login, ou direto na conta já ligada.
  const comecar = async pedir => {
    entrando.value = true;
    erroDoLogin.value = ERROS_DO_LOGIN.NENHUM;
    try {
      buscaId = (await pedir()).buscaId;
      busca.value = { seguradoras: [], leitura: null };
      acompanharABusca();
    } catch (falha) {
      erroDoLogin.value =
        ERRO_DE_CADA_FALHA[falha?.name] ?? ERROS_DO_LOGIN.NAO_ENTROU;
    } finally {
      entrando.value = false;
    }
  };

  const entrar = login => comecar(() => fonte.entrarNoAgger(login));
  const buscarNaContaLigada = () => comecar(() => fonte.buscarNoAgger());

  // "Buscar de novo agora": a seguradora que faltava é buscada outra vez.
  const buscarDeNovo = async () => {
    buscandoDeNovo.value = true;
    try {
      busca.value = await fonte.buscarDeNovo(buscaId);
      acompanharABusca();
    } catch {
      naoRespondeu.value = true;
    } finally {
      buscandoDeNovo.value = false;
    }
  };

  const limpar = () => {
    parar();
    busca.value = null;
    naoRespondeu.value = false;
    erroDoLogin.value = ERROS_DO_LOGIN.NENHUM;
    buscaId = null;
  };

  onScopeDispose(parar);

  return {
    entrando,
    erroDoLogin,
    busca,
    buscando,
    terminou,
    naoRespondeu,
    buscandoDeNovo,
    entrar,
    buscarNaContaLigada,
    buscarDeNovo,
    tentarAgora: acompanharABusca,
    limpar,
  };
};
