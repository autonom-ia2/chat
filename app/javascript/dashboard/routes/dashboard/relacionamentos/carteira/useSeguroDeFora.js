// #2899 (E6.5) — guardar o seguro que a pessoa tem em outra corretora: escolher
// o PDF (um que já chegou na conversa ou um do computador), ler, conferir o que
// foi lido, dizer se a pessoa quer o lembrete e guardar. Fala com a fonte e
// guarda o estado; a gaveta só desenha. Molde: carteira/useAnexarPdf.js.
//
// O que o PDF não trouxe fica vazio ("não achei" nunca vira dado) e a tela pede
// para a pessoa escrever. O valor achado sem certeza (`confira`) só é guardado
// se a pessoa disser que está certo. Arquivo grande demais nem é enviado. A
// resposta de uma leitura antiga nunca preenche a tela de outra (`rodada`).
import { computed, ref } from 'vue';
import { doCampoDeData, paraCampoDeData } from './formatosDoSeguro';
import { ARQUIVO_GRANDE, chaveDaRecusa, codigoDaRecusa } from './recusas';
import { useLimiteDoPdf } from './useLimiteDoPdf';

export const PASSOS_DE_FORA = {
  ABRINDO: 'abrindo',
  ERRO: 'erro',
  ARQUIVO: 'arquivo',
  LENDO: 'lendo',
  LIDO: 'lido',
};

export const QUER = { SIM: 'sim', NAO: 'nao' };

const NAO_LEU = 'RELACIONAMENTOS_CARTEIRA.DE_FORA.NAO_LEU';
const NAO_GUARDOU = 'RELACIONAMENTOS_CARTEIRA.DE_FORA.NAO_GUARDOU';
const NAO_E_APOLICE = 'nao_e_apolice';
// Recusas cuja frase de sempre não serve aqui: ela fala de "guardar sem ler"
// (que não existe para o seguro de fora) ou do motivo da renovação.
const FRASES_DE_FORA = {
  nao_deu_para_ler: 'RELACIONAMENTOS_CARTEIRA.DE_FORA.NAO_DEU_PARA_LER',
  leitura_desligada: 'RELACIONAMENTOS_CARTEIRA.DE_FORA.DESLIGADA',
  texto_longo: 'RELACIONAMENTOS_CARTEIRA.DE_FORA.TEXTO_LONGO',
};
const fraseDaRecusa = (codigo, padrao) =>
  FRASES_DE_FORA[codigo] || chaveDaRecusa(codigo, padrao);
const FORMULARIO_VAZIO = {
  tipo: '',
  seguradora: '',
  termina: '',
  corretora: '',
};
const OBRIGATORIOS = ['tipo', 'seguradora', 'termina'];
const SEM_FALTA = {
  tipo: false,
  seguradora: false,
  termina: false,
  quer: false,
};

export const useSeguroDeFora = ({ fonte, pessoaId }) => {
  const cabe = useLimiteDoPdf();
  const passo = ref(PASSOS_DE_FORA.ABRINDO);
  const arquivos = ref([]);
  // A chave do catálogo da frase de erro; vazia quando não há erro.
  const erro = ref('');
  const leituraId = ref(null);
  const formulario = ref({ ...FORMULARIO_VAZIO });
  // Os campos que a leitura não achou: a tela diz "Não achei" embaixo deles.
  const naoAchou = ref([]);
  const tambem = ref([]);
  const confirmados = ref([]);
  const quer = ref('');
  const falta = ref({ ...SEM_FALTA });
  const guardando = ref(false);
  // A última leitura pedida, para "Tentar de novo" quando ela falha.
  const ultimaOrigem = ref(null);
  let rodada = 0;

  const zerar = () => {
    rodada += 1;
    erro.value = '';
    quer.value = '';
    falta.value = { ...SEM_FALTA };
    confirmados.value = [];
  };

  const abrir = async () => {
    zerar();
    ultimaOrigem.value = null;
    const minha = rodada;
    passo.value = PASSOS_DE_FORA.ABRINDO;
    try {
      const lista = await fonte.arquivosDeFora(pessoaId());
      if (minha !== rodada) return;
      arquivos.value = lista;
      passo.value = PASSOS_DE_FORA.ARQUIVO;
    } catch {
      if (minha === rodada) passo.value = PASSOS_DE_FORA.ERRO;
    }
  };

  const receber = ({ leituraId: id, lido, tambem: resto }) => {
    leituraId.value = id;
    formulario.value = {
      tipo: lido.tipo ?? '',
      seguradora: lido.seguradora ?? '',
      termina: lido.termina ? paraCampoDeData(lido.termina) : '',
      corretora: lido.corretora ?? '',
    };
    naoAchou.value = Object.keys(FORMULARIO_VAZIO).filter(
      campo => !formulario.value[campo]
    );
    tambem.value = resto;
    passo.value = PASSOS_DE_FORA.LIDO;
  };

  // `origem`: `{ arquivo }` (o File do computador) ou `{ anexoId }`.
  const ler = async origem => {
    if (origem.arquivo && !cabe(origem.arquivo)) {
      erro.value = chaveDaRecusa(ARQUIVO_GRANDE, NAO_LEU);
      return;
    }
    zerar();
    const minha = rodada;
    ultimaOrigem.value = origem;
    passo.value = PASSOS_DE_FORA.LENDO;
    try {
      const lida = await fonte.lerDeFora(pessoaId(), origem);
      if (minha === rodada) receber(lida);
    } catch (falha) {
      if (minha !== rodada) return;
      const codigo = codigoDaRecusa(falha);
      erro.value = fraseDaRecusa(codigo, NAO_LEU);
      // O PDF que não é apólice não muda lendo de novo: só outro arquivo.
      if (codigo === NAO_E_APOLICE) ultimaOrigem.value = null;
      passo.value = PASSOS_DE_FORA.ARQUIVO;
    }
  };

  const tentarDeNovo = () => {
    if (ultimaOrigem.value) ler(ultimaOrigem.value);
  };

  const outroArquivo = () => {
    zerar();
    ultimaOrigem.value = null;
    passo.value = PASSOS_DE_FORA.ARQUIVO;
  };

  const mudar = (campo, valor) => {
    formulario.value = { ...formulario.value, [campo]: valor };
    if (campo in falta.value) falta.value = { ...falta.value, [campo]: false };
  };

  const responder = resposta => {
    quer.value = resposta;
    falta.value = { ...falta.value, quer: false };
  };

  const trocarConfirmado = campo => {
    confirmados.value = confirmados.value.includes(campo)
      ? confirmados.value.filter(nome => nome !== campo)
      : [...confirmados.value, campo];
  };

  // Devolve o seguro guardado; `null` quando falta algo (a tela diz o quê) ou
  // quando não deu para guardar (a frase fica em `erro`).
  const guardar = async () => {
    const termina = doCampoDeData(formulario.value.termina);
    falta.value = {
      ...Object.fromEntries(
        OBRIGATORIOS.map(campo => [campo, !formulario.value[campo].trim()])
      ),
      termina: termina === null,
      quer: !quer.value,
    };
    if (Object.values(falta.value).some(Boolean)) return null;
    erro.value = '';
    guardando.value = true;
    try {
      return await fonte.guardarDeFora(pessoaId(), {
        leituraId: leituraId.value,
        querLembrete: quer.value === QUER.SIM,
        campos: { ...formulario.value, termina },
        confirmados: confirmados.value,
      });
    } catch (falha) {
      erro.value = fraseDaRecusa(codigoDaRecusa(falha), NAO_GUARDOU);
      return null;
    } finally {
      guardando.value = false;
    }
  };

  return {
    passo,
    arquivos,
    erro,
    formulario,
    naoAchou,
    tambem,
    confirmados,
    quer,
    falta,
    guardando,
    podeTentarDeNovo: computed(() => Boolean(erro.value && ultimaOrigem.value)),
    abrir,
    ler,
    tentarDeNovo,
    outroArquivo,
    mudar,
    responder,
    trocarConfirmado,
    guardar,
  };
};
