// #2897 — tudo que a gaveta do seguro mostra e faz. A tela só liga as peças:
// este composable fala com a fonte e guarda o resultado. Cada ação devolve
// `true` se deu certo e `false` se falhou; quando o servidor recusou com um
// código (carteira/recusas.js), ele fica em `recusa` para quem chama escolher a
// frase. A história carrega à parte: se ela falhar, o resto do seguro continua
// na tela.
// A resposta de uma ação só entra no seguro que estava aberto quando ela saiu:
// se a gaveta já mostra outro (o endereço trocou de `?apolice=` no meio), o
// seguro e a história que estão na tela não são tocados, e a recusa da ação
// antiga não fica guardada. A ação continua devolvendo se deu certo; quem
// chama confere se ainda está no mesmo seguro antes de avisar.
// #2898 — a renovação soma três ações (renovou, não renovou e o desfazer) e a
// apólice nova, que é outro seguro: `guardarApoliceNova` devolve o seguro novo
// (ou `null`, se não deu) e relê o que está aberto. `semAcesso` diz que a
// última ação falhou porque quem pediu não pode fazê-la (401 ou 403): fechar a
// renovação pede poder mexer no card dela no quadro, e quem não mexe naquele
// funil merece uma frase que diga isso, não "tente de novo".
import { ref, watch } from 'vue';
import { SEM_ACESSO } from '../ficha/falhas';
import { useEstadoDaFicha } from '../ficha/useEstadoDaFicha';
import { codigoDaRecusa } from './recusas';

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
  const recusa = ref('');
  const semAcesso = ref(false);
  let pedidoDaHistoria = 0;
  let acaoDaVez = 0;

  const carregarHistoria = async (doSeguro = id.value) => {
    pedidoDaHistoria += 1;
    const meu = pedidoDaHistoria;
    estadoDaHistoria.value = ESTADOS_DA_HISTORIA.CARREGANDO;
    try {
      const itens = await fonte.historia(doSeguro);
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
    if (!aindaVale()) return false;
    seguro.value = achado;
    carregarHistoria();
    return true;
  };

  // O seguro mudou (aqui ou no diálogo do PDF): guarda o novo e relê a história
  // dele. Seguro que não é o que está aberto não entra: devolve `false`.
  const receber = novo => {
    if (novo.id !== id.value) return false;
    seguro.value = novo;
    carregarHistoria(novo.id);
    return true;
  };

  // `acao(alvo)` fala com a fonte sobre o seguro `alvo`, o que estava aberto
  // quando a pessoa pediu.
  const executar = async (nome, acao) => {
    const alvo = id.value;
    acaoDaVez += 1;
    const minha = acaoDaVez;
    ocupado.value = nome;
    recusa.value = '';
    semAcesso.value = false;
    try {
      receber(await acao(alvo));
      return true;
    } catch (falha) {
      if (id.value === alvo) {
        recusa.value = codigoDaRecusa(falha);
        semAcesso.value = falha?.name === SEM_ACESSO;
      }
      return false;
    } finally {
      // Só quem ligou desliga: uma ação mais nova (ou outro seguro) pode ter
      // tomado o lugar, e `ocupado` já é dela.
      if (minha === acaoDaVez && ocupado.value === nome) ocupado.value = '';
    }
  };

  // Trocou o seguro aberto: o que estava em andamento era do anterior.
  watch(id, () => {
    acaoDaVez += 1;
    ocupado.value = '';
    recusa.value = '';
    semAcesso.value = false;
  });

  const acao = nome => dados =>
    executar(nome, alvo => fonte[nome](alvo, dados));

  const guardarApoliceNova = async dados => {
    let nova = null;
    const certo = await executar('apoliceNova', async alvo => {
      nova = await fonte.apoliceNova(alvo, dados);
      return fonte.seguro(alvo);
    });
    return certo ? nova : null;
  };

  return {
    estado,
    seguro,
    historia,
    estadoDaHistoria,
    ocupado,
    recusa,
    semAcesso,
    carregar: () => carregar(buscar),
    carregarHistoria: () => carregarHistoria(),
    receber,
    // O seguro mudou por outro caminho: lê de novo, sem piscar o esqueleto.
    reler: () => executar('reler', alvo => fonte.seguro(alvo)),
    cancelar: acao('cancelar'),
    voltarAAtivo: acao('voltarAAtivo'),
    corrigir: acao('corrigir'),
    tirarPdf: acao('tirarPdf'),
    renovou: acao('renovou'),
    naoRenovou: acao('naoRenovou'),
    desfazerDesfecho: acao('desfazerDesfecho'),
    guardarApoliceNova,
  };
};
