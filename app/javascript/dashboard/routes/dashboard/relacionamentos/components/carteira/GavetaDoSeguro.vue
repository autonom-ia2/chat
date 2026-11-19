<script setup>
import {
  computed,
  nextTick,
  onMounted,
  ref,
  toRef,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import VazioComUmBotao from '../comum/VazioComUmBotao.vue';
import GavetaLateral from '../ficha/GavetaLateral.vue';
import MenuMaisAcoes from '../lista/MenuMaisAcoes.vue';
import {
  enviaDeNovo,
  podeEnviarProposta,
} from '../../carteira/cotacaoDaRenovacao';
import { leituraDePdf } from '../../carteira/leituraDePdf';
import { chaveDaRecusa, seguroJaMudou } from '../../carteira/recusas';
import {
  DESTRUTIVOS,
  DO_RODAPE,
  rodapeDoSeguro,
} from '../../carteira/rodapeDoSeguro';
import { naoRenovou } from '../../carteira/situacaoDaRenovacao';
import { useConversarComPessoa } from '../../carteira/useConversarComPessoa';
import { useSeguroAberto } from '../../carteira/useSeguroAberto';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import { useVerPdf } from '../../carteira/useVerPdf';
import { ESTADOS_DA_FICHA as ESTADOS } from '../../ficha/useEstadoDaFicha';
import AvisoComDesfazer from './AvisoComDesfazer.vue';
import ConfirmarProposta from './ConfirmarProposta.vue';
import ConversaNova from './ConversaNova.vue';
import CorrigirSeguro from './CorrigirSeguro.vue';
import CotacaoDoSeguro from './CotacaoDoSeguro.vue';
import DadosDoSeguro from './DadosDoSeguro.vue';
import DialogoAnexarPdf from './DialogoAnexarPdf.vue';
import DialogoDeConfirmacao from './DialogoDeConfirmacao.vue';
import FraseDoSeguro from './FraseDoSeguro.vue';
import HistoriaDoSeguro from './HistoriaDoSeguro.vue';
import RenovacaoDoSeguro from './RenovacaoDoSeguro.vue';
import DialogoMotivo from './renovacao/DialogoMotivo.vue';
import PalavrasSimples from './renovacao/PalavrasSimples.vue';

// #2897 — a gaveta do seguro: tudo de um seguro e o que dá para fazer com ele.
// O rodapé (à vista também no celular) tem no máximo UM botão azul: "Ver PDF",
// ou "Guardar o PDF" quando falta e o seguro ainda vale. "Corrigir" fica ao
// lado e troca o conteúdo da mesma gaveta; o resto mora no "⋯"
// (carteira/rodapeDoSeguro.js). Marcar como cancelado não pede confirmação: o
// aviso traz "Desfazer", sem prazo. Apagar o PDF pede, porque não tem volta, e
// sair do Corrigir com algo mudado também. Quando o servidor recusa, o aviso
// diz o que houve e o que fazer (carteira/recusas.js), sem repetir o que foi
// digitado. Cada ação é do seguro que estava aberto quando começou: se a
// gaveta já mostra outro quando a resposta chega, nada é dito nem gravado nele.
// Quem só pode ver a pessoa (`podeEditar` falso) lê tudo e só tem "Ver PDF".
// `apoliceId` nulo = fechada.
// #2898 — o seguro que tem renovação mostra em que pé ela está, logo abaixo da
// frase do topo. Com a renovação aberta, o azul do rodapé é "Renovou" e ao lado
// fica "Não renovou", que pergunta o motivo em um toque. Nenhum dos dois pede
// confirmação: o aviso traz "Desfazer", e o "⋯" guarda "Desfazer a renovação",
// sem prazo. Depois de renovar, o azul é "Guardar a apólice nova": o mesmo
// formulário do Corrigir, já com o que não muda de um ano para o outro.
// #2899 — na conta que lê PDF, quem pode editar a pessoa tem "Seu seguro em
// palavras simples" (E6.6) no seguro da carteira que não está cancelado. O
// seguro de outra corretora (E6.5) tem "Apagar este seguro" no "⋯", com a
// pergunta antes; apagado, a gaveta fecha.
// #2901 (E8) — na conta com a cotação da renovação, o seguro que tem cotação
// mostra em que pé ela está, abaixo da renovação, com "Enviar proposta" quando
// ela está pronta (CotacaoDoSeguro.vue). O aviso diz que saiu; a recusa diz o
// que fazer, e a gaveta relê o seguro, que já mostra a cotação de agora.
// #3057 — "Enviar proposta" pergunta antes (ConfirmarProposta.vue): para quem
// vai, por qual WhatsApp, o PDF da proposta, "Enviar agora" e "Voltar". O
// envio é o mesmo pedido de antes. E onde a gaveta pode conversar
// (`podeConversar`: a aba Seguros e a ficha; no painel da conversa a pessoa já
// está no chat), o seguro que vence logo sem renovação aberta tem o azul
// "Conversar com {nome}", com o PDF ao lado (carteira/rodapeDoSeguro.js).
// #3057 (2ª rodada) — "Conversar" com quem não tem conversa abre a "Nova
// conversa" já com a pessoa (ConversaNova). Com a renovação aberta e a
// proposta pronta, "Enviar proposta" é o azul do rodapé (saiu de dentro da
// Cotação); a pergunta só abre depois de ler o nome do WhatsApp, e o azul gira
// enquanto isso.
const props = defineProps({
  apoliceId: { type: Number, default: null },
  fonte: { type: Object, required: true },
  podeEditar: { type: Boolean, default: false },
  podeExportar: { type: Boolean, default: false },
  podeConversar: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['fechar', 'mudou', 'abrirSegurado', 'abrirCard']);

const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.NAO_DEU';
// Fechar ou reabrir a renovação pede poder mexer no card dela no quadro.
const NAO_PODE_FECHAR =
  'RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.NAO_PODE_FECHAR_A_RENOVACAO';
const NAO_SALVOU = 'RELACIONAMENTOS_CARTEIRA.CORRIGIR.ERRO_AO_SALVAR';
// Enviar a proposta pede poder alterar a pessoa e enxergar o card no quadro.
const NAO_PODE_ENVIAR =
  'RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.NAO_PODE_ENVIAR_A_PROPOSTA';

const { t } = useI18n();
const tCarteira = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.${chave}`, valores);
const tg = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.${chave}`, valores);
const textos = useTextosDoSeguro();
const aberto = useSeguroAberto(props.fonte, toRef(props, 'apoliceId'));
const { seguro } = aberto;
const verPdfDe = useVerPdf(props.fonte);
const conversaNova = useTemplateRef('conversaNova');
const conversarCom = useConversarComPessoa({
  demo: props.fonte.usaDemo,
  abrirConversaNova: async pessoaId =>
    Boolean(await conversaNova.value?.abrir(pessoaId)),
});

const corrigindo = ref(false);
// O formulário aberto é o da apólice nova, e não o de corrigir este seguro.
const paraApoliceNova = ref(false);
const seguradoras = ref([]);
// O que acabou de acontecer (com o desfazer, quando há) e o que não deu certo.
const aviso = ref({ texto: '', desfazer: null });
const alerta = ref('');
// A recusa de "Apagar o PDF" aparece dentro da pergunta, que continua aberta.
const alertaDeApagar = ref('');
// Para onde a pessoa ia quando a gaveta perguntou "Sair sem salvar?".
const saidaPendente = ref(null);
const abrindoPdf = ref(false);
// A pergunta do "Enviar proposta" lendo o nome do WhatsApp antes de abrir.
const preparandoProposta = ref(false);
const corpo = useTemplateRef('corpo');
const formulario = useTemplateRef('formulario');
const dialogoDoPdf = useTemplateRef('dialogoDoPdf');
const dialogoDeApagar = useTemplateRef('dialogoDeApagar');
const dialogoDeSair = useTemplateRef('dialogoDeSair');
const dialogoDoMotivo = useTemplateRef('dialogoDoMotivo');
const dialogoDeApagarDeFora = useTemplateRef('dialogoDeApagarDeFora');
const dialogoDaProposta = useTemplateRef('dialogoDaProposta');
// A conta lê PDF? Perguntado uma vez, na primeira abertura; na dúvida, não.
const lePdf = ref(false);
let perguntouSeLe = false;
const apagandoDeFora = ref(false);
const alertaDeApagarDeFora = ref('');

const pronto = computed(() => aberto.estado.value === ESTADOS.PRONTO);
const comPalavras = computed(
  () =>
    lePdf.value &&
    props.podeEditar &&
    !seguro.value.deFora &&
    !seguro.value.canceladoEm
);
const primeiroNome = computed(() => {
  const nome = seguro.value?.pessoa?.name || '';
  return nome.trim().split(' ')[0];
});
const tipo = computed(() => (seguro.value ? textos.tipo(seguro.value) : ''));
const titulo = computed(() => {
  if (aberto.estado.value === ESTADOS.CARREGANDO) return tg('CARREGANDO');
  if (!pronto.value) return tCarteira('TITULO');
  if (corrigindo.value) {
    return tCarteira(
      paraApoliceNova.value ? 'APOLICE_NOVA.TITULO' : 'CORRIGIR.TITULO',
      { tipo: tipo.value }
    );
  }
  return tg('TITULO', {
    tipo: tipo.value,
    seguradora: seguro.value.seguradora,
  });
});
const comEnviar = computed(() =>
  podeEnviarProposta(seguro.value, props.podeEditar)
);
const rodape = computed(() =>
  rodapeDoSeguro(seguro.value, {
    podeEditar: props.podeEditar,
    podeConversar: props.podeConversar,
    podeEnviar: comEnviar.value,
    agora: props.agora,
  })
);
// O seguro vencido ou cancelado sem PDF não tem botão azul, mas tem "Corrigir"
// e o "⋯": o rodapé só some quando não há nada para pôr nele.
const temRodape = computed(
  () =>
    pronto.value &&
    Boolean(
      rodape.value.azul ||
        rodape.value.secundario ||
        alerta.value ||
        aviso.value.texto
    )
);

const dizer = (texto, desfazer = null) => {
  aviso.value = { texto, desfazer };
  alerta.value = '';
};
const alertar = texto => {
  aviso.value = { texto: '', desfazer: null };
  alerta.value = texto;
};
const focarTitulo = async () => {
  await nextTick();
  corpo.value
    ?.closest('[role="dialog"]')
    ?.querySelector('[data-view-title]')
    ?.focus();
};

// Espera a ação e diz se a resposta ainda é do seguro que está aberto
// (`vale`). Se a gaveta já mostra outro, só quem a abriu precisa saber que
// algo mudou (a lista e a ficha releem).
const noMesmoSeguro = async acao => {
  const alvo = props.apoliceId;
  const certo = await acao();
  const vale = props.apoliceId === alvo;
  if (!vale && certo) emit('mudou');
  return { vale, certo };
};

// O que não deu certo, na frase do código que o servidor mandou. Quando a
// recusa diz que o seguro já mudou por outro caminho (outra pessoa cancelou,
// apagou o PDF), a gaveta relê o seguro e avisa quem a abriu. `semAcesso` é a
// frase de quando o servidor diz que quem pediu não pode fazer aquilo.
const dizerRecusa = async (padrao, semAcesso = padrao) => {
  const codigo = aberto.recusa.value;
  alertar(
    t(aberto.semAcesso.value ? semAcesso : chaveDaRecusa(codigo, padrao))
  );
  if (seguroJaMudou(codigo) && (await aberto.reler())) emit('mudou');
};

// Um pedido por vez. Com uma escrita ainda a caminho, o segundo clique (no
// mesmo botão ou em outro) não manda outro pedido nem troca o aviso do
// primeiro por uma recusa. Os botões continuam ligados: a guarda fica no
// começo de cada ação.
const emAndamento = () => Boolean(aberto.ocupado.value);

// Cada ação que muda o seguro: avisa quem abriu a gaveta (a lista e a ficha
// releem) e diz o que aconteceu, com o desfazer quando há.
const agir = async (acao, texto, desfazer = null, semAcesso = NAO_DEU) => {
  if (emAndamento()) return false;
  const { vale, certo } = await noMesmoSeguro(acao);
  if (!vale) return false;
  if (!certo) {
    await dizerRecusa(NAO_DEU, semAcesso);
    return false;
  }
  emit('mudou');
  dizer(texto, desfazer);
  return true;
};

const desfazerCancelamento = () =>
  agir(aberto.voltarAAtivo, tg('AVISOS.CANCELAMENTO_DESFEITO'));
const marcarCancelado = () =>
  agir(aberto.cancelar, tg('AVISOS.CANCELADO'), () =>
    agir(aberto.voltarAAtivo, tg('AVISOS.DESFEITO'))
  );

// "Renovou" e "Não renovou" não pedem confirmação: o aviso traz "Desfazer".
// As três ações da renovação fecham ou reabrem o card dela: quem não mexe
// naquele funil lê que não pode, em vez de "tente de novo".
const naRenovacao = (acao, texto, desfazer = null) =>
  agir(acao, texto, desfazer, NAO_PODE_FECHAR);
const desfazerRenovacao = () =>
  naRenovacao(aberto.desfazerDesfecho, tg('AVISOS.RENOVACAO_DESFEITA'));
const desfazerNoAviso = () =>
  naRenovacao(aberto.desfazerDesfecho, tg('AVISOS.DESFEITO'));
const marcarRenovou = () =>
  naRenovacao(aberto.renovou, tg('AVISOS.RENOVOU'), desfazerNoAviso);
// O motivo de uma renovação que já estava perdida só completa o que faltava:
// não há o que desfazer.
const guardarMotivo = escolha =>
  naoRenovou(seguro.value)
    ? naRenovacao(
        () => aberto.naoRenovou(escolha),
        tg('AVISOS.MOTIVO_GUARDADO')
      )
    : naRenovacao(
        () => aberto.naoRenovou(escolha),
        tg('AVISOS.NAO_RENOVOU'),
        desfazerNoAviso
      );
const perguntarSeEnvia = async () => {
  if (emAndamento() || preparandoProposta.value) return;
  preparandoProposta.value = true;
  try {
    await dialogoDaProposta.value?.abrir();
  } finally {
    preparandoProposta.value = false;
  }
};
// Saiu ou não, a pergunta fecha quando a resposta chega: o rodapé diz que saiu
// ou o que fazer.
const enviarProposta = async () => {
  await agir(
    aberto.enviarProposta,
    tg('AVISOS.PROPOSTA_ENVIADA'),
    null,
    NAO_PODE_ENVIAR
  );
  dialogoDaProposta.value?.fechar();
};
const conversar = () => conversarCom(seguro.value.pessoa);
const perguntarMotivo = () => {
  if (emAndamento()) return;
  dialogoDoMotivo.value?.abrir();
};

const verPdf = async () => {
  const alvo = props.apoliceId;
  abrindoPdf.value = true;
  const naoAbriu = await verPdfDe(alvo);
  abrindoPdf.value = false;
  if (!naoAbriu || props.apoliceId !== alvo) return;
  alertar(naoAbriu);
  if (await aberto.reler()) emit('mudou');
};
const guardarPdf = () => dialogoDoPdf.value?.abrir(seguro.value);
// O diálogo guardou o PDF do seguro para o qual foi aberto: quem abriu a
// gaveta relê sempre, e o aviso só aparece se ela ainda mostra esse seguro. Só
// dá para desfazer quando o seguro não tinha PDF: aí desfazer é apagar o que
// entrou. Quando o novo trocou outro, o anterior já não existe.
const aoGuardarPdf = ({ seguro: novo, tinhaPdf }) => {
  emit('mudou');
  if (!aberto.receber(novo)) return;
  if (tinhaPdf) {
    dizer(tg('AVISOS.PDF_TROCADO'));
    return;
  }
  dizer(tg('AVISOS.PDF_GUARDADO'), () =>
    agir(aberto.tirarPdf, tg('AVISOS.DESFEITO'))
  );
};
const perguntarSeApaga = () => {
  alertaDeApagar.value = '';
  dialogoDeApagar.value?.abrir();
};
// A pergunta só fecha quando o PDF saiu. Se o servidor recusa, a frase aparece
// dentro dela; se a recusa é "este seguro já não tem PDF", não há mais o que
// perguntar: ela fecha e a gaveta relê o seguro.
const apagarPdf = async () => {
  if (emAndamento()) return;
  alertaDeApagar.value = '';
  const { vale, certo } = await noMesmoSeguro(aberto.tirarPdf);
  if (!vale) return;
  if (certo) {
    emit('mudou');
    dizer(tg('AVISOS.PDF_APAGADO'));
    dialogoDeApagar.value?.fechar();
    return;
  }
  if (seguroJaMudou(aberto.recusa.value)) {
    dialogoDeApagar.value?.fechar();
    await dizerRecusa(NAO_DEU);
    return;
  }
  alertaDeApagar.value = t(chaveDaRecusa(aberto.recusa.value, NAO_DEU));
};

const perguntarSeLe = async () => {
  lePdf.value = await leituraDePdf({
    demo: props.fonte.usaDemo,
    fonte: props.fonte,
  });
};

const perguntarSeApagaDeFora = () => {
  alertaDeApagarDeFora.value = '';
  dialogoDeApagarDeFora.value?.abrir();
};
// Apagou: a gaveta fecha e quem abriu relê. Não apagou: a frase fica dentro da
// pergunta, que continua aberta.
const apagarDeFora = async () => {
  if (apagandoDeFora.value) return;
  apagandoDeFora.value = true;
  alertaDeApagarDeFora.value = '';
  try {
    await props.fonte.apagarDeFora(props.apoliceId);
    dialogoDeApagarDeFora.value?.fechar();
    emit('mudou');
    emit('fechar');
  } catch {
    alertaDeApagarDeFora.value = t(NAO_DEU);
  } finally {
    apagandoDeFora.value = false;
  }
};
const aoEnviarPalavras = () => {
  aberto.carregarHistoria();
  dizer(tg('AVISOS.PALAVRAS_ENVIADAS'));
};

const abrirCorrecao = async () => {
  dizer('');
  try {
    seguradoras.value = (await props.fonte.opcoesDeFiltro()).seguradoras;
  } catch {
    // Sem a lista da conta, a escolha fica com a seguradora do próprio seguro.
    seguradoras.value = [seguro.value.seguradora];
  }
  corrigindo.value = true;
  focarTitulo();
};
const abrirApoliceNova = async () => {
  paraApoliceNova.value = true;
  await abrirCorrecao();
};
const sairDaCorrecao = () => {
  alerta.value = '';
  corrigindo.value = false;
  paraApoliceNova.value = false;
  focarTitulo();
};
const fecharGaveta = () => emit('fechar');
// Sair do Corrigir com algo mudado ("Voltar", Esc, clique fora, o X) pergunta
// antes; sem mudança, sai direto. `saida` é para onde a pessoa ia.
const sairOuPerguntar = saida => {
  if (!corrigindo.value || !formulario.value?.temMudanca()) {
    saida();
    return;
  }
  saidaPendente.value = saida;
  dialogoDeSair.value?.abrir();
};
const sairSemSalvar = () => {
  const saida = saidaPendente.value;
  saidaPendente.value = null;
  dialogoDeSair.value?.fechar();
  saida?.();
};
// O formulário serve aos dois: corrigir este seguro ou guardar a apólice nova
// dele (que é outro seguro; este só passa a dizer que já a tem).
const salvarCorrecao = async dados => {
  if (emAndamento()) return;
  alerta.value = '';
  const daApoliceNova = paraApoliceNova.value;
  const { vale, certo } = await noMesmoSeguro(async () =>
    daApoliceNova
      ? Boolean(await aberto.guardarApoliceNova(dados))
      : aberto.corrigir(dados)
  );
  if (!vale) return;
  if (!certo) {
    // O seguro mudou por outro caminho e a apólice nova já não cabe (outra
    // pessoa a guardou, o seguro foi cancelado): não há o que continuar
    // preenchendo. A gaveta volta ao seguro, já relido, e diz o que houve.
    if (daApoliceNova && seguroJaMudou(aberto.recusa.value)) sairDaCorrecao();
    await dizerRecusa(NAO_SALVOU);
    return;
  }
  emit('mudou');
  sairDaCorrecao();
  dizer(
    daApoliceNova ? tg('AVISOS.APOLICE_NOVA') : tCarteira('CORRIGIR.SALVO')
  );
};

// O que cada nome do rodapé (carteira/rodapeDoSeguro.js) faz e como aparece.
const DO_SEGURO = {
  [DO_RODAPE.CONVERSAR]: {
    icone: 'i-lucide-message-circle',
    fazer: conversar,
  },
  [DO_RODAPE.ENVIAR_PROPOSTA]: {
    icone: 'i-lucide-send',
    fazer: perguntarSeEnvia,
  },
  [DO_RODAPE.VER_PDF]: { icone: 'i-lucide-file-text', fazer: verPdf },
  [DO_RODAPE.GUARDAR_PDF]: { icone: 'i-lucide-paperclip', fazer: guardarPdf },
  [DO_RODAPE.GUARDAR_OUTRO_PDF]: {
    icone: 'i-lucide-paperclip',
    fazer: guardarPdf,
  },
  [DO_RODAPE.APAGAR_PDF]: {
    icone: 'i-lucide-trash-2',
    fazer: perguntarSeApaga,
  },
  [DO_RODAPE.CORRIGIR]: { icone: 'i-lucide-pencil', fazer: abrirCorrecao },
  [DO_RODAPE.DESFAZER_CANCELAMENTO]: {
    icone: 'i-lucide-rotate-ccw',
    fazer: desfazerCancelamento,
  },
  [DO_RODAPE.MARCAR_CANCELADO]: {
    icone: 'i-lucide-circle-slash',
    fazer: marcarCancelado,
  },
  [DO_RODAPE.RENOVOU]: { icone: 'i-lucide-check', fazer: marcarRenovou },
  [DO_RODAPE.NAO_RENOVOU]: { icone: 'i-lucide-x', fazer: perguntarMotivo },
  [DO_RODAPE.GUARDAR_APOLICE_NOVA]: {
    icone: 'i-lucide-file-plus',
    fazer: abrirApoliceNova,
  },
  [DO_RODAPE.DESFAZER_RENOVACAO]: {
    icone: 'i-lucide-rotate-ccw',
    fazer: desfazerRenovacao,
  },
  [DO_RODAPE.APAGAR_DE_FORA]: {
    icone: 'i-lucide-trash-2',
    fazer: perguntarSeApagaDeFora,
  },
};
// O `data-carteira` do botão ao lado do azul, e o que deixa o azul girando.
const MARCA_DO_SECUNDARIO = {
  [DO_RODAPE.CORRIGIR]: 'corrigir',
  [DO_RODAPE.NAO_RENOVOU]: 'nao-renovou',
  [DO_RODAPE.RENOVOU]: 'renovou',
  [DO_RODAPE.VER_PDF]: 'ver-pdf',
  [DO_RODAPE.GUARDAR_PDF]: 'guardar-pdf',
};
const azulOcupado = computed(
  () =>
    (rodape.value.azul === DO_RODAPE.VER_PDF && abrindoPdf.value) ||
    (rodape.value.azul === DO_RODAPE.RENOVOU &&
      aberto.ocupado.value === 'renovou') ||
    (rodape.value.azul === DO_RODAPE.ENVIAR_PROPOSTA &&
      (preparandoProposta.value || aberto.ocupado.value === 'enviarProposta'))
);
const secundarioOcupado = computed(
  () =>
    (rodape.value.secundario === DO_RODAPE.VER_PDF && abrindoPdf.value) ||
    (rodape.value.secundario === DO_RODAPE.RENOVOU &&
      aberto.ocupado.value === 'renovou')
);
const SALVANDO = ['corrigir', 'apoliceNova'];
const fazer = nome => DO_SEGURO[nome].fazer();
// "Conversar com Ana": o primeiro nome de quem conversa.
// A proposta que pode ter saído sem confirmação é enviada "de novo".
const chaveDoRotulo = id =>
  id === DO_RODAPE.ENVIAR_PROPOSTA && enviaDeNovo(seguro.value?.cotacao)
    ? 'ENVIAR_DE_NOVO'
    : id;
const rotuloDe = id =>
  tg(`RODAPE.${chaveDoRotulo(id)}`, { nome: primeiroNome.value });
const itensDoMenu = computed(() =>
  rodape.value.menu.map(id => ({
    id,
    rotulo: rotuloDe(id),
    icone: DO_SEGURO[id].icone,
    destrutivo: DESTRUTIVOS.includes(id),
  }))
);

watch(
  () => props.apoliceId,
  id => {
    corrigindo.value = false;
    paraApoliceNova.value = false;
    saidaPendente.value = null;
    dizer('');
    if (!id) return;
    aberto.carregar();
    if (perguntouSeLe) return;
    perguntouSeLe = true;
    perguntarSeLe();
  },
  { immediate: true }
);
// A gaveta que já nasce aberta (o endereço trouxe `?apolice=`) não passa pelo
// "abrir": o foco vai ao título por aqui.
onMounted(() => {
  if (props.apoliceId) focarTitulo();
});
</script>

<template>
  <GavetaLateral
    marca="gaveta-do-seguro"
    largura="sm:w-[32rem]"
    :aberta="Boolean(apoliceId)"
    :titulo="titulo"
    @fechar="sairOuPerguntar(fecharGaveta)"
  >
    <div
      ref="corpo"
      :data-carteira="corrigindo ? 'corrigir-gaveta' : 'gaveta-seguro'"
      class="flex flex-col gap-8"
    >
      <EsqueletoDeLista
        v-if="aberto.estado.value === ESTADOS.CARREGANDO"
        :linhas="5"
        data-carteira="carregando"
      />
      <div
        v-else-if="aberto.estado.value === ESTADOS.ERRO"
        data-carteira="erro"
      >
        <ErroComTentarDeNovo :mensagem="tg('ERRO')" @tentar="aberto.carregar" />
      </div>
      <div
        v-else-if="aberto.estado.value === ESTADOS.NAO_ACHEI"
        data-carteira="seguro-nao-esta"
      >
        <VazioComUmBotao
          :frase="tg('NAO_ESTA_MAIS')"
          :botao="tg('FECHAR')"
          @acao="emit('fechar')"
        />
      </div>
      <div
        v-else-if="aberto.estado.value === ESTADOS.SEM_ACESSO"
        data-carteira="seguro-sem-acesso"
      >
        <VazioComUmBotao
          :frase="tg('SEM_ACESSO')"
          :botao="tg('FECHAR')"
          @acao="emit('fechar')"
        />
      </div>
      <CorrigirSeguro
        v-else-if="corrigindo"
        ref="formulario"
        :seguro="seguro"
        :seguradoras="seguradoras"
        :apolice-nova="paraApoliceNova"
        @salvar="salvarCorrecao"
      />
      <template v-else>
        <FraseDoSeguro
          :seguro="seguro"
          :agora="agora"
          @abrir-segurado="emit('abrirSegurado', $event)"
        />
        <RenovacaoDoSeguro
          v-if="seguro.renovacao"
          :seguro="seguro"
          :pode-editar="podeEditar"
          @abrir-card="emit('abrirCard', $event)"
          @dizer-motivo="perguntarMotivo"
        />
        <CotacaoDoSeguro
          v-if="seguro.cotacao?.etapa"
          :seguro="seguro"
          :pode-enviar="comEnviar"
        />
        <DadosDoSeguro :seguro="seguro" :agora="agora" />
        <PalavrasSimples
          v-if="comPalavras"
          :seguro-id="seguro.id"
          :fonte="fonte"
          :nome="primeiroNome"
          @mudou="aoEnviarPalavras"
        />
        <HistoriaDoSeguro
          :itens="aberto.historia.value"
          :estado="aberto.estadoDaHistoria.value"
          :pode-exportar="podeExportar"
          :agora="agora"
          @tentar="aberto.carregarHistoria"
          @exportado="dizer(tg('AVISOS.HISTORICO_BAIXADO'))"
        />
      </template>
    </div>

    <template v-if="temRodape" #rodape>
      <div class="flex flex-wrap items-center w-full gap-3">
        <AvisoComDesfazer
          class="basis-full"
          :texto="aviso.texto"
          :pode-desfazer="Boolean(aviso.desfazer)"
          :desfazendo="Boolean(aberto.ocupado.value)"
          @desfazer="aviso.desfazer?.()"
        />
        <p
          v-if="alerta"
          role="alert"
          data-carteira="alerta-da-gaveta"
          class="m-0 text-base font-medium basis-full text-n-ruby-11"
        >
          {{ alerta }}
        </p>
        <template v-if="corrigindo">
          <Button
            size="lg"
            class="flex-1 sm:flex-none"
            data-carteira="salvar-correcao"
            :is-loading="SALVANDO.includes(aberto.ocupado.value)"
            :label="tCarteira('CORRIGIR.SALVAR')"
            @click="formulario?.tentarSalvar()"
          />
          <Button
            slate
            faded
            size="lg"
            class="flex-1 sm:flex-none"
            data-carteira="voltar-da-correcao"
            :label="tCarteira('CORRIGIR.VOLTAR')"
            @click="sairOuPerguntar(sairDaCorrecao)"
          />
        </template>
        <template v-else>
          <Button
            v-if="rodape.azul"
            size="lg"
            class="basis-full sm:basis-auto"
            data-carteira="gaveta-acao"
            :data-acao="rodape.azul"
            :icon="DO_SEGURO[rodape.azul].icone"
            :is-loading="azulOcupado"
            :label="rotuloDe(rodape.azul)"
            @click="fazer(rodape.azul)"
          />
          <!-- "Corrigir" e o "⋯" andam juntos: se não couberem ao lado do
               azul, descem os dois para a linha de baixo. Sem botão azul, são
               só eles. -->
          <div
            v-if="rodape.secundario"
            data-carteira="rodape-secundarios"
            class="flex flex-1 min-w-0 gap-3 sm:flex-none"
          >
            <Button
              slate
              faded
              size="lg"
              class="flex-1 sm:flex-none whitespace-nowrap"
              :data-carteira="MARCA_DO_SECUNDARIO[rodape.secundario]"
              :is-loading="secundarioOcupado"
              :label="rotuloDe(rodape.secundario)"
              @click="fazer(rodape.secundario)"
            />
            <div v-if="itensDoMenu.length" data-carteira="mais-do-seguro">
              <MenuMaisAcoes
                tamanho="lg"
                :rotulo="tg('RODAPE.MAIS')"
                :itens="itensDoMenu"
                @escolher="fazer"
              />
            </div>
          </div>
        </template>
      </div>
    </template>
  </GavetaLateral>
  <ConversaNova v-if="podeConversar" ref="conversaNova" />
  <template v-if="podeEditar">
    <DialogoAnexarPdf
      ref="dialogoDoPdf"
      :fonte="fonte"
      @guardado="aoGuardarPdf"
    />
    <DialogoDeConfirmacao
      ref="dialogoDeApagar"
      marca="apagar-pdf"
      :titulo="tCarteira('PDF.APAGAR.TITULO')"
      :aviso="tCarteira('PDF.APAGAR.AVISO')"
      :confirmar="tCarteira('PDF.APAGAR.CONFIRMAR')"
      :voltar="tCarteira('PDF.APAGAR.VOLTAR')"
      :ocupado="aberto.ocupado.value === 'tirarPdf'"
      :alerta="alertaDeApagar"
      @confirmar="apagarPdf"
    />
    <DialogoDeConfirmacao
      ref="dialogoDeSair"
      marca="sair-sem-salvar"
      :titulo="tCarteira('CORRIGIR.SAIR.TITULO')"
      :aviso="tCarteira('CORRIGIR.SAIR.AVISO')"
      :confirmar="tCarteira('CORRIGIR.SAIR.CONFIRMAR')"
      :voltar="
        tCarteira(
          paraApoliceNova ? 'APOLICE_NOVA.CONTINUAR' : 'CORRIGIR.SAIR.VOLTAR'
        )
      "
      @confirmar="sairSemSalvar"
      @fechou="saidaPendente = null"
    />
    <DialogoMotivo ref="dialogoDoMotivo" @escolher="guardarMotivo" />
    <ConfirmarProposta
      ref="dialogoDaProposta"
      :seguro="seguro"
      :demo="fonte.usaDemo"
      :ocupado="aberto.ocupado.value === 'enviarProposta'"
      @confirmar="enviarProposta"
    />
    <DialogoDeConfirmacao
      ref="dialogoDeApagarDeFora"
      marca="apagar-de-fora"
      :titulo="tCarteira('DE_FORA.APAGAR.TITULO')"
      :aviso="tCarteira('DE_FORA.APAGAR.AVISO')"
      :confirmar="tCarteira('DE_FORA.APAGAR.CONFIRMAR')"
      :voltar="tCarteira('DE_FORA.APAGAR.VOLTAR')"
      :ocupado="apagandoDeFora"
      :alerta="alertaDeApagarDeFora"
      @confirmar="apagarDeFora"
    />
  </template>
</template>
