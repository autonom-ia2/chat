import { onScopeDispose, ref } from 'vue';
import { ehSemAcesso } from '../lista/falhas';
import { INTERVALO_INICIAL_MS, agendaComRecuo } from './consultaComRecuo';
import { avisoDoTentarDeNovo } from './falhasDaTela';
import { SITUACOES_DA_LISTA } from './prazo';

// #2894 — "O que eu já trouxe": a lista de listas, a prévia do que sai e o
// desfazer. Enquanto alguma lista ainda está sendo trazida, a tela pergunta de
// novo sozinha (sem piscar o esqueleto), com a espera crescendo a cada pergunta
// e sem perguntar com a aba escondida (trazer/consultaComRecuo.js).
// #2896 — o desfazer não é na hora: o servidor marca a lista como `desfazendo`
// e a tela acompanha do mesmo jeito, até ela virar `desfeito`. Se o desfazer
// quebra no servidor, a lista volta ao que era: a tela avisa que não deu. E a
// lista que o servidor ainda não deixa desfazer (não foi trazida até o fim)
// liga `naoPodeDesfazer`: o diálogo diz por quê, em vez de "tente de novo".
// #2896 — a lista que parou no meio tem "Tentar de novo"; e quem o servidor
// recusa por falta de acesso liga `semAcesso` (a tela diz isso, sem oferecer
// tentar), seja ao tentar de novo, ao pedir a prévia ou ao desfazer. O "Tentar
// de novo" recusado porque a conta está desfazendo uma lista avisa isso, com o
// que fazer (esperar o desfazer terminar), em vez de "não consegui trazer".
// O desfazer que travou no servidor (a lista segue `desfazendo`, mas volta com
// `podeDesfazer`) não é acompanhado: perguntar de novo não muda nada, quem
// resolve é a pessoa clicar em Desfazer.
// #3083 — o servidor manda as listas de página em página
// (Relacionamentos::Trazer::Historico::POR_PAGINA, o mesmo número daqui). A
// página cheia quer dizer que pode haver mais: "Ver mais" pede a próxima e a
// junta embaixo. A carga de sempre (a que a tela pede e a da agenda) relê
// todas as páginas que já estão na tela, para a lista de qualquer uma delas
// que está sendo trazida ou desfeita ser acompanhada, sem repetir lista. "Ver
// mais" que falha liga `erroDoMais` (a tela diz e o botão continua lá); por
// falta de acesso, `semAcesso`.
export const INTERVALO_DO_HISTORICO_MS = INTERVALO_INICIAL_MS;

export const LISTAS_POR_PAGINA = 100;

const AVISO_ERRO_DESFAZER = 'RELACIONAMENTOS_TRAZER.ERROS.DESFAZER';

const NAO_PODE_DESFAZER = 'NAO_PODE_DESFAZER';

const sendoDesfeita = lista => lista.situacao === SITUACOES_DA_LISTA.DESFAZENDO;
const emAndamento = lista =>
  lista.situacao === SITUACOES_DA_LISTA.TRAZENDO ||
  (sendoDesfeita(lista) && !lista.podeDesfazer);

// O desfazer que segue seu caminho: a lista continua sendo desfeita ou já foi.
const DESFAZER_ANDANDO = [
  SITUACOES_DA_LISTA.DESFAZENDO,
  SITUACOES_DA_LISTA.DESFEITO,
];

// Alguma lista que estava sendo desfeita voltou ao que era: o desfazer dela
// quebrou no servidor.
const desfazerQuebrou = (antes, agora) =>
  antes
    .filter(sendoDesfeita)
    .some(velha =>
      agora.some(
        nova =>
          nova.id === velha.id && !DESFAZER_ANDANDO.includes(nova.situacao)
      )
    );

const semRepetir = (primeiras, depois) => {
  const ids = new Set(primeiras.map(lista => lista.id));
  return [...primeiras, ...depois.filter(lista => !ids.has(lista.id))];
};

// "Ver mais": a próxima página do histórico, embaixo das que já estão na tela.
const usePaginasDoHistorico = ({ fonte, listas, semAcesso, encerrou }) => {
  const temMais = ref(false);
  const carregandoMais = ref(false);
  const erroDoMais = ref(false);
  let paginasLidas = 1;

  const verMais = async () => {
    if (carregandoMais.value || !temMais.value) return;
    carregandoMais.value = true;
    erroDoMais.value = false;
    const pagina = paginasLidas + 1;
    try {
      const recebidas = await fonte.historico(pagina);
      if (encerrou()) return;
      listas.value = semRepetir(listas.value, recebidas);
      paginasLidas = pagina;
      temMais.value = recebidas.length >= LISTAS_POR_PAGINA;
    } catch (falha) {
      if (encerrou()) return;
      if (ehSemAcesso(falha)) semAcesso.value = true;
      else erroDoMais.value = true;
    } finally {
      carregandoMais.value = false;
    }
  };

  // As páginas que já estão na tela, lidas de novo. Sem "Ver mais" ainda, é só
  // a primeira.
  const lerAsPaginas = async () => {
    const lidas = paginasLidas;
    if (lidas === 1) return { lidas, recebidas: await fonte.historico() };
    const paginas = await Promise.all(
      Array.from({ length: lidas }, (_, i) => fonte.historico(i + 1))
    );
    return { lidas, recebidas: paginas.reduce(semRepetir, []) };
  };

  // Só a primeira página diz se há mais. Depois de "Ver mais", o que a tela já
  // tinha e não voltou (a lista que uma nova empurrou para a página seguinte)
  // fica embaixo.
  const comAsPaginas = ({ lidas, recebidas }) => {
    if (lidas > 1 || paginasLidas > 1) {
      return semRepetir(recebidas, listas.value);
    }
    temMais.value = recebidas.length >= LISTAS_POR_PAGINA;
    return recebidas;
  };

  return {
    temMais,
    carregandoMais,
    erroDoMais,
    verMais,
    lerAsPaginas,
    comAsPaginas,
  };
};

// As listas que a conta já trouxe e a carga delas.
const useCargaDoHistorico = ({ fonte, avisar, intervalo }) => {
  const listas = ref([]);
  const carregando = ref(false);
  const erro = ref(false);
  const semAcesso = ref(false);
  const agenda = agendaComRecuo({ inicial: intervalo });
  let encerrado = false;
  // Número da última carga pedida: resposta de carga mais velha é descartada.
  let ultimaCarga = 0;
  const { lerAsPaginas, comAsPaginas, ...paginas } = usePaginasDoHistorico({
    fonte,
    listas,
    semAcesso,
    encerrou: () => encerrado,
  });

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
      const lidas = await lerAsPaginas();
      if (!vale()) return;
      const { recebidas } = lidas;
      if (desfazerQuebrou(listas.value, recebidas)) avisar(AVISO_ERRO_DESFAZER);
      listas.value = comAsPaginas(lidas);
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

  return { listas, carregando, erro, semAcesso, carregar, ...paginas };
};

// O desfazer de uma lista: a prévia do que sai e a confirmação.
const useDesfazerDaLista = ({ fonte, avisar, carga }) => {
  const { listas, semAcesso, carregar } = carga;
  const alvo = ref(null);
  const previa = ref(null);
  const previaComErro = ref(false);
  // O pedido de desfazer está indo ao servidor (o botão fica ocupado).
  const desfazendo = ref(false);
  const naoPodeDesfazer = ref(false);
  // Número da última prévia pedida: a resposta de uma prévia mais velha (a
  // pessoa fechou o diálogo, ou abriu o de outra lista) é descartada.
  let ultimaPrevia = 0;

  // O servidor ainda não deixa desfazer esta lista: o diálogo diz por quê, e o
  // histórico é lido de novo para a linha mostrar como ela está de verdade.
  const recusar = () => {
    naoPodeDesfazer.value = true;
    return carregar({ silencioso: true });
  };

  const limpar = () => {
    ultimaPrevia += 1;
    previa.value = null;
    previaComErro.value = false;
    naoPodeDesfazer.value = false;
  };

  const abrirDesfazer = async lista => {
    limpar();
    alvo.value = lista;
    const minha = ultimaPrevia;
    const vale = () => minha === ultimaPrevia;
    try {
      const preview = await fonte.previaDoDesfazer(lista.id);
      if (vale()) previa.value = preview;
    } catch (falha) {
      if (!vale()) return;
      if (falha?.name === NAO_PODE_DESFAZER) await recusar();
      else if (ehSemAcesso(falha)) semAcesso.value = true;
      else previaComErro.value = true;
    }
  };

  const fecharDesfazer = () => {
    limpar();
    alvo.value = null;
  };

  // A linha fica como o servidor respondeu ao pedido, sem botão nenhum, antes
  // de o histórico ser lido de novo. Se o desfazer quebrar antes dessa leitura,
  // ela já traz a lista de volta ao que era, e é por esta marca que a tela
  // percebe e avisa.
  const marcarComo = (id, situacao) => {
    listas.value = listas.value.map(lista =>
      lista.id === id
        ? { ...lista, situacao, podeTentar: false, podeDesfazer: false }
        : lista
    );
  };

  // Devolve true quando o servidor aceitou desfazer (a tela fecha o diálogo); a
  // carga seguinte volta a perguntar pela lista até ela ser desfeita. Um pedido
  // por vez: o botão não fica desligado durante o pedido, e o segundo clique
  // não pede de novo.
  const confirmarDesfazer = async () => {
    if (!alvo.value || naoPodeDesfazer.value || desfazendo.value) return false;
    const { id } = alvo.value;
    desfazendo.value = true;
    try {
      const { situacao } = await fonte.desfazer(id);
      marcarComo(id, situacao);
      await carregar({ silencioso: true });
      return true;
    } catch (falha) {
      if (falha?.name === NAO_PODE_DESFAZER) await recusar();
      else if (ehSemAcesso(falha)) semAcesso.value = true;
      else avisar(AVISO_ERRO_DESFAZER);
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
    naoPodeDesfazer,
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
  const carga = useCargaDoHistorico({ fonte, avisar, intervalo });
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
      else avisar(avisoDoTentarDeNovo(falha));
      return false;
    } finally {
      tentando.value = null;
    }
  };

  return {
    ...carga,
    tentando,
    tentarDeNovo,
    ...useDesfazerDaLista({ fonte, avisar, carga }),
  };
};
