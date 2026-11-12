import { computed, ref, watch } from 'vue';
import { GRUPO_PADRAO } from '../fonte/grupos';
import { ORDENS } from '../fonte/listaFonte';
import { ehSemAcesso } from './falhas';
import { FILTROS_VAZIOS, contarFiltros } from './filtros';

const PRIMEIRA_PAGINA = 1;
const SEM_ERRO = Object.freeze({ resumo: null, contagens: null, lista: null });

// #2894 — o estado da lista de Relacionamentos: o que a pessoa escolheu (grupo,
// busca, ordem, filtros), a página que está à vista e o que a fonte respondeu.
// Trocar grupo, aba, busca, ordem ou filtro volta para a página 1 e chama
// `aoMudarConsulta` (a tela usa para desmarcar quem estava marcado). Resposta
// de pedido antigo nunca sobrescreve a de um pedido mais novo. Resumo, contagens
// e lista são leituras separadas: cada uma guarda o próprio erro, e a que
// respondeu não apaga o erro da que falhou. Basta uma delas ser recusada por
// falta de acesso para `semAcesso` ligar: a tela mostra um estado só, sem
// "tentar de novo".
// #2897 — a aba Seguros usa o mesmo estado, com o grupo, a ordem e os filtros
// dela (`grupoPadrao`, `ordemPadrao`, `filtrosVazios`, `contar`).
export const useLista = ({
  fonte,
  aba,
  aoMudarConsulta = () => {},
  grupoPadrao = nome => GRUPO_PADRAO[nome],
  ordemPadrao = ORDENS.ULTIMA_CONVERSA,
  filtrosVazios = FILTROS_VAZIOS,
  contar = contarFiltros,
}) => {
  const grupo = ref(grupoPadrao(aba.value));
  const busca = ref('');
  const ordem = ref(ordemPadrao);
  const filtros = ref({ ...filtrosVazios });
  const pagina = ref(PRIMEIRA_PAGINA);
  const itens = ref([]);
  const total = ref(0);
  const temMais = ref(false);
  const contagens = ref({});
  const resumo = ref(null);
  const carregando = ref(false);
  const carregandoMais = ref(false);
  const erros = ref(SEM_ERRO);
  const erro = computed(
    () => erros.value.resumo || erros.value.contagens || erros.value.lista
  );
  const semAcesso = computed(() =>
    Object.values(erros.value).some(ehSemAcesso)
  );
  const guardarErro = (leitura, falha) => {
    erros.value = { ...erros.value, [leitura]: falha };
  };
  let pedidoAtual = 0;

  const consulta = () => ({
    aba: aba.value,
    grupo: grupo.value,
    busca: busca.value,
    ordem: ordem.value,
    filtros: filtros.value,
  });

  const filtrosAtivos = computed(() => contar(filtros.value));

  const terminar = (numero, aMais) => {
    if (numero !== pedidoAtual) return;
    (aMais ? carregandoMais : carregando).value = false;
  };

  const buscarPagina = async numero => {
    pedidoAtual += 1;
    const meu = pedidoAtual;
    const aMais = numero > PRIMEIRA_PAGINA;
    // Um pedido da página 1 atropela o "mostrar mais" em voo: a resposta dele
    // será descartada e não zeraria o "carregando mais".
    if (!aMais) carregandoMais.value = false;
    (aMais ? carregandoMais : carregando).value = true;
    try {
      const resposta = await fonte.listar({ ...consulta(), pagina: numero });
      if (meu !== pedidoAtual) return;
      itens.value = aMais
        ? [...itens.value, ...resposta.itens]
        : resposta.itens;
      total.value = resposta.total;
      temMais.value = resposta.temMais;
      pagina.value = numero;
      guardarErro('lista', null);
    } catch (falha) {
      if (meu === pedidoAtual) guardarErro('lista', falha);
    } finally {
      terminar(meu, aMais);
    }
  };

  // Os números das pílulas seguem a busca e os filtros (como a lista). Resposta
  // de pedido antigo não pisa na do mais novo.
  let pedidoDeContagens = 0;
  const carregarContagens = async () => {
    pedidoDeContagens += 1;
    const meu = pedidoDeContagens;
    try {
      const resposta = await fonte.contagens(aba.value, {
        busca: busca.value,
        filtros: filtros.value,
      });
      if (meu !== pedidoDeContagens) return;
      contagens.value = resposta;
      guardarErro('contagens', null);
    } catch (falha) {
      if (meu === pedidoDeContagens) guardarErro('contagens', falha);
    }
  };

  const carregarResumo = async () => {
    try {
      resumo.value = await fonte.resumo();
      guardarErro('resumo', null);
    } catch (falha) {
      guardarErro('resumo', falha);
    }
  };

  const recarregar = async () => {
    erros.value = SEM_ERRO;
    await Promise.all([
      carregarResumo(),
      carregarContagens(),
      buscarPagina(PRIMEIRA_PAGINA),
    ]);
  };

  const recomecar = () => {
    pagina.value = PRIMEIRA_PAGINA;
    aoMudarConsulta();
    return buscarPagina(PRIMEIRA_PAGINA);
  };

  // `recontar`: busca e filtro mudam o que cada pílula conta; grupo e ordem não.
  const recomecarRecontando = () => {
    carregarContagens();
    return recomecar();
  };

  const mudar = (alvo, valor, recontar = false) => {
    if (alvo.value === valor) return undefined;
    alvo.value = valor;
    return recontar ? recomecarRecontando() : recomecar();
  };

  watch(aba, nova => {
    grupo.value = grupoPadrao(nova);
    filtros.value = { ...filtrosVazios };
    recomecarRecontando();
  });

  return {
    grupo,
    busca,
    ordem,
    filtros,
    itens,
    total,
    temMais,
    contagens,
    resumo,
    carregando,
    carregandoMais,
    erro,
    semAcesso,
    filtrosAtivos,
    iniciar: recarregar,
    recarregar,
    escolherGrupo: id => mudar(grupo, id),
    mudarBusca: texto => mudar(busca, texto, true),
    mudarOrdem: nova => mudar(ordem, nova),
    mudarFiltros: novos => {
      filtros.value = { ...filtrosVazios, ...novos };
      return recomecarRecontando();
    },
    limparFiltros: () => {
      filtros.value = { ...filtrosVazios };
      return recomecarRecontando();
    },
    mostrarMais: () =>
      temMais.value && !carregandoMais.value
        ? buscarPagina(pagina.value + 1)
        : undefined,
    todosDoGrupo: async () => (await fonte.listarTodos(consulta())).itens,
  };
};
