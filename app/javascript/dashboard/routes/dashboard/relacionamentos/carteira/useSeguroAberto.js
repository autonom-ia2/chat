// #2897 — tudo que a gaveta do seguro mostra e faz. A tela só liga as peças:
// este composable fala com a fonte e guarda o resultado. Cada ação devolve
// `true` se deu certo e `false` se falhou; quem chama decide o aviso. A
// história carrega à parte: se ela falhar, o resto do seguro continua na tela.
import { ref } from 'vue';
import { useEstadoDaFicha } from '../ficha/useEstadoDaFicha';

export const ESTADOS_DA_HISTORIA = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  ERRO: 'erro',
};

export const useSeguroAberto = (fonte, id) => {
  const { estado, carregar } = useEstadoDaFicha();
  const seguro = ref(null);
  const historia = ref([]);
  const estadoDaHistoria = ref(ESTADOS_DA_HISTORIA.CARREGANDO);
  const ocupado = ref('');
  let pedidoDaHistoria = 0;

  const carregarHistoria = async () => {
    pedidoDaHistoria += 1;
    const meu = pedidoDaHistoria;
    estadoDaHistoria.value = ESTADOS_DA_HISTORIA.CARREGANDO;
    try {
      const itens = await fonte.historia(id.value);
      if (meu !== pedidoDaHistoria) return;
      historia.value = itens;
      estadoDaHistoria.value = ESTADOS_DA_HISTORIA.PRONTO;
    } catch {
      if (meu === pedidoDaHistoria) {
        estadoDaHistoria.value = ESTADOS_DA_HISTORIA.ERRO;
      }
    }
  };

  const buscar = async aindaVale => {
    const achado = await fonte.seguro(id.value);
    if (!aindaVale() || !achado) return false;
    seguro.value = achado;
    carregarHistoria();
    return true;
  };

  // O seguro mudou (aqui ou no diálogo do PDF): guarda o novo e relê a história.
  const receber = novo => {
    seguro.value = novo;
    carregarHistoria();
  };

  const executar = async (nome, acao) => {
    ocupado.value = nome;
    try {
      receber(await acao());
      return true;
    } catch {
      return false;
    } finally {
      ocupado.value = '';
    }
  };

  const acao = nome => dados =>
    executar(nome, () => fonte[nome](id.value, dados));

  return {
    estado,
    seguro,
    historia,
    estadoDaHistoria,
    ocupado,
    carregar: () => carregar(buscar),
    carregarHistoria,
    receber,
    cancelar: acao('cancelar'),
    voltarAAtivo: acao('voltarAAtivo'),
    corrigir: acao('corrigir'),
    cotar: acao('cotar'),
    desfazerPdf: acao('desfazerPdf'),
  };
};
