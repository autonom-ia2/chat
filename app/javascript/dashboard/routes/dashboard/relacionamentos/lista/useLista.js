import { computed, ref, watch } from 'vue';
import { GRUPO_PADRAO } from '../fonte/grupos';
import { ORDENS } from '../fonte/listaFonte';
import { FILTROS_VAZIOS, contarFiltros } from './filtros';

const PRIMEIRA_PAGINA = 1;

// #2894 — o estado da lista de Relacionamentos: o que a pessoa escolheu (grupo,
// busca, ordem, filtros), a página que está à vista e o que a fonte respondeu.
// Trocar grupo, aba, busca, ordem ou filtro volta para a página 1 e chama
// `aoMudarConsulta` (a tela usa para desmarcar quem estava marcado). Resposta
// de pedido antigo nunca sobrescreve a de um pedido mais novo.
export const useLista = ({ fonte, aba, aoMudarConsulta = () => {} }) => {
  const grupo = ref(GRUPO_PADRAO[aba.value]);
  const busca = ref('');
  const ordem = ref(ORDENS.ULTIMA_CONVERSA);
  const filtros = ref({ ...FILTROS_VAZIOS });
  const pagina = ref(PRIMEIRA_PAGINA);
  const itens = ref([]);
  const total = ref(0);
  const temMais = ref(false);
  const contagens = ref({});
  const resumo = ref(null);
  const carregando = ref(false);
  const carregandoMais = ref(false);
  const erro = ref(null);
  let pedidoAtual = 0;

  const consulta = () => ({
    aba: aba.value,
    grupo: grupo.value,
    busca: busca.value,
    ordem: ordem.value,
    filtros: filtros.value,
  });

  const filtrosAtivos = computed(() => contarFiltros(filtros.value));

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
      erro.value = null;
    } catch (falha) {
      if (meu === pedidoAtual) erro.value = falha;
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
      if (meu === pedidoDeContagens) contagens.value = resposta;
    } catch (falha) {
      if (meu === pedidoDeContagens) erro.value = falha;
    }
  };

  const carregarResumo = async () => {
    try {
      resumo.value = await fonte.resumo();
    } catch (falha) {
      erro.value = falha;
    }
  };

  const recarregar = async () => {
    erro.value = null;
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
    grupo.value = GRUPO_PADRAO[nova];
    filtros.value = { ...FILTROS_VAZIOS };
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
    filtrosAtivos,
    iniciar: recarregar,
    recarregar,
    escolherGrupo: id => mudar(grupo, id),
    mudarBusca: texto => mudar(busca, texto, true),
    mudarOrdem: nova => mudar(ordem, nova),
    mudarFiltros: novos => {
      filtros.value = { ...FILTROS_VAZIOS, ...novos };
      return recomecarRecontando();
    },
    limparFiltros: () => {
      filtros.value = { ...FILTROS_VAZIOS };
      return recomecarRecontando();
    },
    mostrarMais: () =>
      temMais.value && !carregandoMais.value
        ? buscarPagina(pagina.value + 1)
        : undefined,
    todosDoGrupo: async () => (await fonte.listarTodos(consulta())).itens,
  };
};
