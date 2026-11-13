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
import { chaveDaRecusa, seguroJaMudou } from '../../carteira/recusas';
import {
  DESTRUTIVOS,
  DO_RODAPE,
  rodapeDoSeguro,
} from '../../carteira/rodapeDoSeguro';
import { naoRenovou } from '../../carteira/situacaoDaRenovacao';
import { useSeguroAberto } from '../../carteira/useSeguroAberto';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import { useVerPdf } from '../../carteira/useVerPdf';
import { ESTADOS_DA_FICHA as ESTADOS } from '../../ficha/useEstadoDaFicha';
import AvisoComDesfazer from './AvisoComDesfazer.vue';
import CorrigirSeguro from './CorrigirSeguro.vue';
import DadosDoSeguro from './DadosDoSeguro.vue';
import DialogoAnexarPdf from './DialogoAnexarPdf.vue';
import DialogoDeConfirmacao from './DialogoDeConfirmacao.vue';
import FraseDoSeguro from './FraseDoSeguro.vue';
import HistoriaDoSeguro from './HistoriaDoSeguro.vue';
import RenovacaoDoSeguro from './RenovacaoDoSeguro.vue';
import DialogoMotivo from './renovacao/DialogoMotivo.vue';

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
const props = defineProps({
  apoliceId: { type: Number, default: null },
  fonte: { type: Object, required: true },
  podeEditar: { type: Boolean, default: false },
  podeExportar: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['fechar', 'mudou', 'abrirSegurado', 'abrirCard']);

const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.NAO_DEU';
const NAO_SALVOU = 'RELACIONAMENTOS_CARTEIRA.CORRIGIR.ERRO_AO_SALVAR';

const { t } = useI18n();
const tCarteira = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.${chave}`, valores);
const tg = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.${chave}`, valores);
const textos = useTextosDoSeguro();
const aberto = useSeguroAberto(props.fonte, toRef(props, 'apoliceId'));
const { seguro } = aberto;
const verPdfDe = useVerPdf(props.fonte);

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
const corpo = useTemplateRef('corpo');
const formulario = useTemplateRef('formulario');
const dialogoDoPdf = useTemplateRef('dialogoDoPdf');
const dialogoDeApagar = useTemplateRef('dialogoDeApagar');
const dialogoDeSair = useTemplateRef('dialogoDeSair');
const dialogoDoMotivo = useTemplateRef('dialogoDoMotivo');

const pronto = computed(() => aberto.estado.value === ESTADOS.PRONTO);
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
const rodape = computed(() =>
  rodapeDoSeguro(seguro.value, {
    podeEditar: props.podeEditar,
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
// apagou o PDF), a gaveta relê o seguro e avisa quem a abriu.
const dizerRecusa = async padrao => {
  const codigo = aberto.recusa.value;
  alertar(t(chaveDaRecusa(codigo, padrao)));
  if (seguroJaMudou(codigo) && (await aberto.reler())) emit('mudou');
};

// Cada ação que muda o seguro: avisa quem abriu a gaveta (a lista e a ficha
// releem) e diz o que aconteceu, com o desfazer quando há.
const agir = async (acao, texto, desfazer = null) => {
  const { vale, certo } = await noMesmoSeguro(acao);
  if (!vale) return false;
  if (!certo) {
    await dizerRecusa(NAO_DEU);
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
const desfazerRenovacao = () =>
  agir(aberto.desfazerDesfecho, tg('AVISOS.RENOVACAO_DESFEITA'));
const desfazerNoAviso = () =>
  agir(aberto.desfazerDesfecho, tg('AVISOS.DESFEITO'));
const marcarRenovou = () =>
  agir(aberto.renovou, tg('AVISOS.RENOVOU'), desfazerNoAviso);
// O motivo de uma renovação que já estava perdida só completa o que faltava:
// não há o que desfazer.
const guardarMotivo = escolha =>
  naoRenovou(seguro.value)
    ? agir(() => aberto.naoRenovou(escolha), tg('AVISOS.MOTIVO_GUARDADO'))
    : agir(
        () => aberto.naoRenovou(escolha),
        tg('AVISOS.NAO_RENOVOU'),
        desfazerNoAviso
      );
const perguntarMotivo = () => dialogoDoMotivo.value?.abrir();

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
  alerta.value = '';
  const daApoliceNova = paraApoliceNova.value;
  const { vale, certo } = await noMesmoSeguro(async () =>
    daApoliceNova
      ? Boolean(await aberto.guardarApoliceNova(dados))
      : aberto.corrigir(dados)
  );
  if (!vale) return;
  if (!certo) {
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
};
// O `data-carteira` do botão ao lado do azul, e o que deixa o azul girando.
const MARCA_DO_SECUNDARIO = {
  [DO_RODAPE.CORRIGIR]: 'corrigir',
  [DO_RODAPE.NAO_RENOVOU]: 'nao-renovou',
};
const azulOcupado = computed(
  () =>
    (rodape.value.azul === DO_RODAPE.VER_PDF && abrindoPdf.value) ||
    (rodape.value.azul === DO_RODAPE.RENOVOU &&
      aberto.ocupado.value === 'renovou')
);
const SALVANDO = ['corrigir', 'apoliceNova'];
const fazer = nome => DO_SEGURO[nome].fazer();
const rotuloDe = nome => tg(`RODAPE.${nome}`);
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
    if (id) aberto.carregar();
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
        <DadosDoSeguro :seguro="seguro" :agora="agora" />
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
              :label="rotuloDe(rodape.secundario)"
              @click="fazer(rodape.secundario)"
            />
            <div data-carteira="mais-do-seguro">
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
  </template>
</template>
