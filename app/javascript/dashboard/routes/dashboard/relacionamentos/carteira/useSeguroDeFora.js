// #2897 — guardar o seguro que a pessoa tem em outra corretora (Tela 20):
// escolher o arquivo, ler, conferir o que foi lido, dizer se a pessoa quer o
// lembrete e guardar. Fala com a fonte e guarda o estado; a gaveta só desenha.
import { computed, ref } from 'vue';
import { doCampoDeData, paraCampoDeData } from './formatosDoSeguro';

export const PASSOS_DE_FORA = {
  ABRINDO: 'abrindo',
  ERRO: 'erro',
  ARQUIVO: 'arquivo',
  LENDO: 'lendo',
  LIDO: 'lido',
};

export const QUER = { SIM: 'sim', AINDA_NAO: 'ainda_nao' };

// O nome do erro da fonte -> a frase do catálogo (RELACIONAMENTOS_CARTEIRA.DE_FORA).
const FRASE_DO_ERRO = {
  NAO_PARECE_SEGURO: 'NAO_PARECE_SEGURO',
  FOTO_ESCURA: 'FOTO_ESCURA',
};
const NAO_LEU = 'NAO_LEU';
const NAO_GUARDOU = 'NAO_GUARDOU';

const LIDO_VAZIO = { tipo: '', seguradora: '', termina: '' };
const SEM_FALTA = { termina: false, quer: false };

export const useSeguroDeFora = ({ fonte, pessoaId }) => {
  const passo = ref(PASSOS_DE_FORA.ABRINDO);
  const pessoa = ref(null);
  const arquivos = ref([]);
  const erro = ref('');
  const lido = ref({ ...LIDO_VAZIO });
  // Os campos que a leitura não achou: a tela pede para a pessoa escrever.
  const naoAchou = ref([]);
  const quer = ref('');
  const falta = ref({ ...SEM_FALTA });
  const guardando = ref(false);

  const primeiroNome = computed(() =>
    String(pessoa.value?.name ?? '')
      .trim()
      .split(' ')
      .at(0)
  );

  const abrir = async () => {
    passo.value = PASSOS_DE_FORA.ABRINDO;
    erro.value = '';
    quer.value = '';
    falta.value = { ...SEM_FALTA };
    try {
      const conversa = await fonte.arquivosDaConversa(pessoaId());
      pessoa.value = conversa.pessoa;
      arquivos.value = conversa.arquivos;
      passo.value = PASSOS_DE_FORA.ARQUIVO;
    } catch {
      passo.value = PASSOS_DE_FORA.ERRO;
    }
  };

  const escolher = async arquivo => {
    erro.value = '';
    passo.value = PASSOS_DE_FORA.LENDO;
    try {
      const achado = await fonte.lerDeFora(arquivo);
      lido.value = {
        tipo: achado.tipo ?? '',
        seguradora: achado.seguradora ?? '',
        termina: achado.termina ? paraCampoDeData(achado.termina) : '',
      };
      naoAchou.value = Object.keys(LIDO_VAZIO).filter(
        campo => !lido.value[campo]
      );
      passo.value = PASSOS_DE_FORA.LIDO;
    } catch (falha) {
      erro.value = FRASE_DO_ERRO[falha?.name] ?? NAO_LEU;
      passo.value = PASSOS_DE_FORA.ARQUIVO;
    }
  };

  const outroArquivo = () => {
    erro.value = '';
    quer.value = '';
    falta.value = { ...SEM_FALTA };
    passo.value = PASSOS_DE_FORA.ARQUIVO;
  };

  const mudar = (campo, valor) => {
    lido.value = { ...lido.value, [campo]: valor };
    if (campo in falta.value) falta.value = { ...falta.value, [campo]: false };
  };

  const responder = resposta => {
    quer.value = resposta;
    falta.value = { ...falta.value, quer: false };
  };

  // Devolve o seguro guardado; `null` quando falta algo (a tela diz o quê) ou
  // quando não deu para guardar.
  const guardar = async () => {
    const termina = doCampoDeData(lido.value.termina);
    falta.value = { termina: termina === null, quer: quer.value !== QUER.SIM };
    if (falta.value.termina || falta.value.quer) return null;
    erro.value = '';
    guardando.value = true;
    try {
      return await fonte.guardarDeFora(pessoaId(), { ...lido.value, termina });
    } catch {
      erro.value = NAO_GUARDOU;
      return null;
    } finally {
      guardando.value = false;
    }
  };

  return {
    passo,
    pessoa,
    primeiroNome,
    arquivos,
    erro,
    lido,
    naoAchou,
    quer,
    falta,
    guardando,
    abrir,
    escolher,
    outroArquivo,
    mudar,
    responder,
    guardar,
  };
};
