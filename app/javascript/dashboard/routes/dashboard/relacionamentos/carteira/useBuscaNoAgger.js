// #2900 (E7.3) — o caminho de "Trazer do Agger", do botão ao pronto. Fala com a
// fonte (fonte/trazerAggerFonte.js) e guarda o estado; as telas só desenham.
//
//   inicio → (login, se a conta ainda não conectou) → buscando (pergunta até a
//   busca sair de "lendo") → conferir → trazendo (pergunta pelo andamento) →
//   pronto
//
// A busca em que a pessoa está fica no endereço (`?busca=`): ela pode sair da
// página e voltar, e a busca continua no servidor. Recusa do servidor vira a
// frase do código (carteira/recusas.js); falha de rede, a frase de sempre.
//
// Toda espera que pode falhar tem saída: quando o acompanhamento falha
// (`semAcompanhar`), a busca parou no servidor (`busca.estado === 'parou'`) ou
// não anda há tempo demais (`parado`), `tentarDeNovo` começa uma busca nova,
// pelo mesmo caminho do botão grande (#2900, E7.5); no "Trazendo", pede o
// "Trazer" outra vez (o servidor é idempotente). Quando o Agger recusou o
// login (`busca.motivo === PEDE_LOGIN`), a tela pede o login de novo e, com
// ele aceito, busca de novo.
//
// "Buscar de novo" volta direto ao "Buscando", sem os avisos das seguradoras
// da busca anterior (#2900, E7.5): eles não valem para a busca que anda.
import { ref } from 'vue';
import { chaveDaRecusaDoAgger, codigoDaRecusa } from './recusas';

export const ETAPAS_DO_AGGER = {
  INICIO: 'inicio',
  BUSCANDO: 'buscando',
  CONFERIR: 'conferir',
  TRAZENDO: 'trazendo',
  PRONTO: 'pronto',
};
export const PEDE_LOGIN = 'agger_pede_login';
// O que `comecar` devolve quando a conta ainda não tem o login aceito: a tela
// abre a janela do login.
export const PEDIR_LOGIN = 'pedir_login';
// O que o Agger respondeu ao login (fonte/trazerAggerFonte.js): aceitou, está
// fora do ar (não é o login que está errado) ou recusou o login e a senha.
export const LOGIN = Object.freeze({
  ACEITO: 'aceito',
  FORA_DO_AR: 'fora_do_ar',
  RECUSADO: 'recusado',
});
const PERGUNTA_MS = 2000;
const PARADO_MS = 10 * 60 * 1000;
const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.AGGER.NAO_DEU';
const ESTADO_DA_ETAPA = {
  lendo: ETAPAS_DO_AGGER.BUSCANDO,
  parou: ETAPAS_DO_AGGER.BUSCANDO,
  lida: ETAPAS_DO_AGGER.CONFERIR,
  trazendo: ETAPAS_DO_AGGER.TRAZENDO,
};

export const useBuscaNoAgger = (
  fonte,
  { ligado = false, aoMudarBusca = () => {} } = {}
) => {
  const etapa = ref(ETAPAS_DO_AGGER.INICIO);
  const busca = ref(null);
  const andamento = ref(null);
  const erro = ref('');
  const ocupado = ref(false);
  const semAcompanhar = ref(false);
  const parado = ref(false);
  // A conta tem o login do Agger aceito (o resumo da carteira, `aggerLigado`).
  const conectado = ref(ligado);
  let relogio = null;
  let ultimoAvanco = 0;
  let ultimaMarca = '';

  const parar = () => {
    clearTimeout(relogio);
    relogio = null;
  };

  const falhou = falha => {
    erro.value = chaveDaRecusaDoAgger(codigoDaRecusa(falha), NAO_DEU);
  };

  const falhouAoAcompanhar = falha => {
    falhou(falha);
    semAcompanhar.value = true;
  };

  // Parado é o que não muda há PARADO_MS.
  const marcarAvanco = marca => {
    if (marca !== ultimaMarca) {
      ultimaMarca = marca;
      ultimoAvanco = Date.now();
    }
    parado.value = Date.now() - ultimoAvanco >= PARADO_MS;
  };

  const zerarAcompanhamento = () => {
    erro.value = '';
    semAcompanhar.value = false;
    parado.value = false;
    ultimaMarca = '';
    ultimoAvanco = Date.now();
  };

  const comAndamento = async id => {
    andamento.value = await fonte.andamento(id);
    if (andamento.value.estado === 'trazendo') {
      marcarAvanco(`${andamento.value.porcentagem}-${andamento.value.seguros}`);
      relogio = setTimeout(
        () => comAndamento(id).catch(falhouAoAcompanhar),
        PERGUNTA_MS
      );
      return;
    }
    parado.value = false;
    etapa.value = ETAPAS_DO_AGGER.PRONTO;
  };

  const comBusca = async id => {
    const atual = await fonte.busca(id);
    busca.value = atual;
    etapa.value = ESTADO_DA_ETAPA[atual.estado] || ETAPAS_DO_AGGER.PRONTO;
    if (atual.estado === 'lendo') {
      marcarAvanco(JSON.stringify([atual.recebidos, atual.porSeguradora]));
      relogio = setTimeout(
        () => comBusca(id).catch(falhouAoAcompanhar),
        PERGUNTA_MS
      );
    } else if (
      atual.estado !== 'parou' &&
      etapa.value !== ETAPAS_DO_AGGER.CONFERIR
    ) {
      await comAndamento(id);
    }
  };

  const abrir = async id => {
    parar();
    zerarAcompanhamento();
    try {
      await comBusca(id);
    } catch (falha) {
      falhouAoAcompanhar(falha);
    }
  };

  const tentar = async pedido => {
    ocupado.value = true;
    erro.value = '';
    try {
      return await pedido();
    } catch (falha) {
      falhou(falha);
      return null;
    } finally {
      ocupado.value = false;
    }
  };

  const comecarBusca = async () => {
    parar();
    const criada = await tentar(() => fonte.buscar());
    if (!criada) return;
    aoMudarBusca(criada.leituraId);
    // Já no "Buscando", antes da primeira resposta.
    busca.value = { id: criada.leituraId, estado: 'lendo', porSeguradora: [] };
    etapa.value = ETAPAS_DO_AGGER.BUSCANDO;
    await abrir(criada.leituraId);
  };

  // O botão grande: sem o login aceito, devolve PEDIR_LOGIN e a tela abre a
  // janela do login antes.
  const comecar = async () => {
    if (ocupado.value) return null;
    if (!conectado.value) return PEDIR_LOGIN;
    await comecarBusca();
    return null;
  };

  const deNovo = async () => {
    parar();
    const { id } = busca.value;
    const conferir = await tentar(() => fonte.deNovo(id));
    if (!conferir) {
      semAcompanhar.value = true;
      return;
    }
    busca.value = { id, estado: 'lendo', porSeguradora: [] };
    etapa.value = ETAPAS_DO_AGGER.BUSCANDO;
    await abrir(id);
  };

  // A janela do login: devolve o que o Agger respondeu (LOGIN). Aceito, segue
  // de onde a pessoa estava (a primeira busca, ou a busca que parou pelo
  // login). A falha de rede sobe para a janela dizer.
  const conectar = async credenciais => {
    const resposta = await fonte.conectar(credenciais);
    if (resposta !== LOGIN.ACEITO) return resposta;
    conectado.value = true;
    if (busca.value?.estado === 'parou') await deNovo();
    else if (etapa.value === ETAPAS_DO_AGGER.INICIO) await comecarBusca();
    return resposta;
  };

  const trazer = async () => {
    parar();
    const pedido = await tentar(() => fonte.trazer(busca.value.id));
    if (!pedido) {
      semAcompanhar.value = etapa.value === ETAPAS_DO_AGGER.TRAZENDO;
      return;
    }
    zerarAcompanhamento();
    andamento.value = pedido;
    etapa.value = ETAPAS_DO_AGGER.TRAZENDO;
    await comAndamento(busca.value.id).catch(falhouAoAcompanhar);
  };

  // "Tentar de novo": no "Trazendo", pede o Trazer outra vez; na busca,
  // começa uma busca nova, como o botão grande. Se uma busca da conta ainda
  // anda de fato, o servidor devolve essa mesma, e a tela volta a acompanhá-la.
  const tentarDeNovo = () => {
    if (etapa.value === ETAPAS_DO_AGGER.TRAZENDO) return trazer();
    return comecarBusca();
  };

  const recomecar = () => {
    parar();
    busca.value = null;
    andamento.value = null;
    zerarAcompanhamento();
    etapa.value = ETAPAS_DO_AGGER.INICIO;
    aoMudarBusca(null);
  };

  return {
    etapa,
    busca,
    andamento,
    erro,
    ocupado,
    semAcompanhar,
    parado,
    conectado,
    abrir,
    comecar,
    conectar,
    deNovo,
    trazer,
    tentarDeNovo,
    recomecar,
    parar,
  };
};
