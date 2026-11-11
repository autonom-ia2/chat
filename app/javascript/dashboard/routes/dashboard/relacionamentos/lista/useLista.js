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

  const carregarContagens = async () => {
    const daAba = aba.value;
    try {
      const resposta = await fonte.contagens(daAba);
      if (daAba === aba.value) contagens.value = resposta;
    } catch (falha) {
      erro.value = falha;
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

  const mudar = (alvo, valor) => {
    if (alvo.value === valor) return undefined;
    alvo.value = valor;
    return recomecar();
  };

  watch(aba, nova => {
    grupo.value = GRUPO_PADRAO[nova];
    filtros.value = { ...FILTROS_VAZIOS };
    carregarContagens();
    recomecar();
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
    mudarBusca: texto => mudar(busca, texto),
    mudarOrdem: nova => mudar(ordem, nova),
    mudarFiltros: novos => {
      filtros.value = { ...FILTROS_VAZIOS, ...novos };
      return recomecar();
    },
    limparFiltros: () => {
      filtros.value = { ...FILTROS_VAZIOS };
      return recomecar();
    },
    mostrarMais: () =>
      temMais.value && !carregandoMais.value
        ? buscarPagina(pagina.value + 1)
        : undefined,
    todosDoGrupo: async () => (await fonte.listarTodos(consulta())).itens,
  };
};
