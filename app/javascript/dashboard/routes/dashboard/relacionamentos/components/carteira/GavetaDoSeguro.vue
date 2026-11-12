<script setup>
import {
  computed,
  nextTick,
  onMounted,
  ref,
  toRef,
  useId,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import VazioComUmBotao from '../comum/VazioComUmBotao.vue';
import GavetaLateral from '../ficha/GavetaLateral.vue';
import MenuMaisAcoes from '../lista/MenuMaisAcoes.vue';
import { SELOS, seloDoSeguro } from '../../fonte/selosDoSeguro';
import { COTACAO, cotacaoDoCard } from '../../carteira/cotacaoDoCard';
import { cardNasceAmanha } from '../../carteira/formularioDoSeguro';
import { oQueNaoSaiu } from '../../carteira/oQueNaoSaiu';
import { DO_RODAPE, rodapeDoSeguro } from '../../carteira/rodapeDoSeguro';
import { PASSOS_DO_SEGURO, passoDoSeguro } from '../../carteira/passoDoSeguro';
import { useSeguroAberto } from '../../carteira/useSeguroAberto';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import { ESTADOS_DA_FICHA as ESTADOS } from '../../ficha/useEstadoDaFicha';
import { motivoDeFora } from '../../lista/quemFicaDeFora';
import AvisoComDesfazer from './AvisoComDesfazer.vue';
import CorrigirSeguro from './CorrigirSeguro.vue';
import DadosDoSeguro from './DadosDoSeguro.vue';
import DialogoAnexarPdf from './DialogoAnexarPdf.vue';
import FraseDoSeguro from './FraseDoSeguro.vue';
import HistoriaDoSeguro from './HistoriaDoSeguro.vue';
import RenovacaoDoSeguro from './RenovacaoDoSeguro.vue';
import DialogoDePrevia from './renovacao/DialogoDePrevia.vue';
import PalavrasSimples from './renovacao/PalavrasSimples.vue';

// #2897 — a gaveta do seguro: tudo de um seguro e o próximo passo dele (um só
// por vez, no rodapé: fica à vista também no celular). O passo da vez é o
// único botão azul (carteira/passoDoSeguro.js): com algo que não saiu ou um
// envio esperando, ele toma o lugar do passo de sempre, que fica ao lado como
// secundário; nenhum botão aparece duas vezes. O que ia sair sozinho e não
// saiu é dito no topo, logo abaixo da frase do seguro. "Corrigir" troca o
// conteúdo da mesma gaveta. Marcar como cancelado não pede confirmação: o aviso
// traz "Desfazer", sem prazo. "Abrir a renovação" passa a vez à gaveta da
// renovação (quem hospeda troca uma pela outra). `apoliceId` nulo = fechada.
const props = defineProps({
  apoliceId: { type: Number, default: null },
  fonte: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits([
  'fechar',
  'mudou',
  'abrirSegurado',
  'abrirRenovacao',
]);

const { t } = useI18n();
const tg = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.${chave}`, valores);
const textos = useTextosDoSeguro();
const aberto = useSeguroAberto(props.fonte, toRef(props, 'apoliceId'));
const { seguro } = aberto;

const corrigindo = ref(false);
const seguradoras = ref([]);
const erroAoSalvar = ref(false);
const aviso = ref({ texto: '', desfazer: null });
// Por que o próximo passo não dá para fazer agora (role="alert").
const alerta = ref('');
const idDoAlerta = useId();
const corpo = useTemplateRef('corpo');
const formulario = useTemplateRef('formulario');
const dialogoDoPdf = useTemplateRef('dialogoDoPdf');
const previaDaParcela = useTemplateRef('previaDaParcela');

const pronto = computed(() => aberto.estado.value === ESTADOS.PRONTO);
const tipo = computed(() => (seguro.value ? textos.tipo(seguro.value) : ''));
const primeiroNome = computed(
  () => seguro.value?.pessoa.name.split(' ')[0] ?? ''
);
const titulo = computed(() => {
  if (aberto.estado.value === ESTADOS.CARREGANDO) return tg('CARREGANDO');
  if (!pronto.value) return t('RELACIONAMENTOS_CARTEIRA.TITULO');
  return corrigindo.value
    ? t('RELACIONAMENTOS_CARTEIRA.CORRIGIR.TITULO', { tipo: tipo.value })
    : tg('TITULO', { tipo: tipo.value, seguradora: seguro.value.seguradora });
});
// A pessoa está mudando o texto em palavras simples: enviar espera o Salvar.
const alterandoPalavras = ref(false);
const passo = computed(() =>
  passoDoSeguro(seguro.value, props.agora, {
    alterandoPalavras: alterandoPalavras.value,
  })
);
// A ação já é um botão do rodapé (azul ou secundário)?
const noRodape = acao => [passo.value.azul, passo.value.depois].includes(acao);
const daConta = computed(() => ({
  cotaSozinha: props.fonte.cotaSozinha,
  tiposQueCota: props.fonte.tiposQueCota,
}));
const cotacao = computed(() => cotacaoDoCard(seguro.value, daConta.value));
// O que ia sair sozinho e o WhatsApp não deixou: o que foi e, no topo, o
// caminho ("Converse com <nome>."; o botão "Conversar" é o azul do rodapé).
const naoSaiu = computed(() => oQueNaoSaiu(seguro.value));
const oQueNaoSaiuEscrito = computed(() =>
  naoSaiu.value
    ? tg(`NAO_SAIU.${naoSaiu.value.id}`, { dias: naoSaiu.value.dias })
    : ''
);
const naoSaiuNoTopo = computed(() =>
  naoSaiu.value
    ? `${oQueNaoSaiuEscrito.value} ${tg('NAO_SAIU.CAMINHO', { nome: primeiroNome.value })}`
    : ''
);
const cancelado = computed(
  () => seloDoSeguro(seguro.value, props.agora) === SELOS.CANCELADO
);
const emRenovacao = computed(
  () => seloDoSeguro(seguro.value, props.agora) === SELOS.EM_RENOVACAO
);

const dizer = (texto, desfazer = null) => {
  aviso.value = { texto, desfazer };
  alerta.value = '';
};
const simular = (chave, valores) => useAlert(tg(`AVISOS.${chave}`, valores));
// A proposta oficial ou o resumo da cotação que saiu (um passo da história).
const verOQueSaiu = daHistoria =>
  daHistoria.acao === 'ver_resumo'
    ? useAlert(t('RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.ABRINDO_RESUMO'))
    : simular('ABRINDO_PROPOSTA');
const focarTitulo = async () => {
  await nextTick();
  corpo.value
    ?.closest('[role="dialog"]')
    ?.querySelector('[data-view-title]')
    ?.focus();
};

// Cada ação que muda o seguro: avisa quem abriu a gaveta (a lista e a ficha
// releem) e diz o que aconteceu, com o desfazer quando há.
const agir = async (acao, texto, desfazer = null) => {
  const certo = await acao();
  if (certo) emit('mudou');
  dizer(certo ? texto : tg('AVISOS.NAO_DEU'), certo ? desfazer : null);
  return certo;
};

const voltarAAtivo = () =>
  agir(aberto.voltarAAtivo, tg('AVISOS.VOLTOU_A_ATIVO'));
const marcarCancelado = () =>
  agir(aberto.cancelar, tg('AVISOS.CANCELADO'), () =>
    agir(aberto.voltarAAtivo, tg('AVISOS.DESFEITO'))
  );
const cotar = () => agir(aberto.cotar, '');

const abrirPdf = () => dialogoDoPdf.value?.abrir(seguro.value);
const aoGuardarPdf = ({ seguro: novo, apoliceNova }) => {
  aberto.receber(novo);
  emit('mudou');
  dizer(tg(apoliceNova ? 'AVISOS.APOLICE_NOVA' : 'AVISOS.PDF_GUARDADO'), () =>
    agir(aberto.desfazerPdf, tg('AVISOS.DESFEITO'))
  );
};

const abrirRenovacao = () => emit('abrirRenovacao', seguro.value.id);

// "Avisar <nome>": a mensagem da parcela em aberto passa pela conferência (como
// a proposta da renovação) e só sai no "Enviar". Quem não pode receber (regra
// de lista/quemFicaDeFora.js): o clique diz o motivo e a conferência não abre.
const mensagemDaParcela = computed(() =>
  seguro.value?.parcelaAbertaEm
    ? tg('PARCELA.MENSAGEM', {
        nome: primeiroNome.value,
        data: textos.diaMes(seguro.value.parcelaAbertaEm, props.agora),
        tipo: tipo.value,
      })
    : ''
);
const avisarDaParcela = () => {
  const motivo = motivoDeFora(seguro.value.pessoa);
  dizer('');
  if (motivo) {
    alerta.value = tg(`PARCELA.FORA.${motivo.toUpperCase()}`, {
      nome: primeiroNome.value,
    });
    return;
  }
  previaDaParcela.value?.abrir();
};
const enviarAvisoDaParcela = async () => {
  await agir(
    () => aberto.fazer('avisarDaParcela'),
    tg('PARCELA.ENVIADA', { nome: primeiroNome.value })
  );
  previaDaParcela.value?.fechar();
};

// "Seu seguro em palavras simples": salvar o texto alterado e enviar.
const salvarPalavras = texto =>
  agir(
    () => aberto.fazer('salvarPalavras', { texto }),
    t('RELACIONAMENTOS_CARTEIRA.PALAVRAS.AVISO_SALVO')
  );
const enviarPalavras = () =>
  agir(
    () => aberto.fazer('enviarPalavras'),
    t('RELACIONAMENTOS_CARTEIRA.PALAVRAS.AVISO_ENVIADO', {
      nome: seguro.value.pessoa.name,
    })
  );

const conversar = () =>
  simular('ABRINDO_CONVERSA', { nome: seguro.value.pessoa.name });

// O que cada botão do rodapé faz. A conversa e o PDF de verdade são de outras
// entregas: por ora, o aviso diz o que vai abrir.
const ACOES = {
  [PASSOS_DO_SEGURO.ABRIR_RENOVACAO]: abrirRenovacao,
  [PASSOS_DO_SEGURO.VER_PDF]: () =>
    simular('ABRINDO_PDF', { tipo: tipo.value }),
  [PASSOS_DO_SEGURO.ANEXAR_PDF]: abrirPdf,
  [PASSOS_DO_SEGURO.ANEXAR_APOLICE_NOVA]: abrirPdf,
  [PASSOS_DO_SEGURO.AVISAR]: avisarDaParcela,
  [PASSOS_DO_SEGURO.CONVERSAR_COM]: conversar,
  [PASSOS_DO_SEGURO.CONVERSAR]: conversar,
  [PASSOS_DO_SEGURO.ENVIAR_PALAVRAS]: enviarPalavras,
};
const fazer = acao => ACOES[acao]();
// "Conversar" e "Enviar a <nome>" já têm frase na casa (a da proposta e a do
// texto em palavras simples): o rodapé diz com as mesmas palavras.
const ROTULOS = {
  [PASSOS_DO_SEGURO.CONVERSAR]: () =>
    t('RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.CONVERSAR'),
  [PASSOS_DO_SEGURO.ENVIAR_PALAVRAS]: () =>
    t('RELACIONAMENTOS_CARTEIRA.PALAVRAS.ENVIAR_A', {
      nome: primeiroNome.value,
    }),
};
const rotuloDe = acao =>
  ROTULOS[acao]?.() ?? tg(`ACAO.${acao}`, { nome: primeiroNome.value });

const abrirCorrecao = async () => {
  erroAoSalvar.value = false;
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
// O rodapé tem o azul, um secundário e o "⋯"; o resto mora no "⋯"
// (carteira/rodapeDoSeguro.js).
const rodape = computed(() =>
  rodapeDoSeguro(passo.value, { cancelado: cancelado.value })
);
const DO_MENU = {
  [DO_RODAPE.CORRIGIR]: () => ({
    rotulo: tg('RODAPE.CORRIGIR'),
    icone: 'i-lucide-pencil',
    atributos: { 'data-carteira': 'corrigir-no-menu' },
    aoEscolher: abrirCorrecao,
  }),
  [DO_RODAPE.ANEXAR_OUTRO_PDF]: () => ({
    rotulo: tg('RODAPE.ANEXAR_OUTRO_PDF'),
    icone: 'i-lucide-paperclip',
    atributos: { 'data-carteira': 'anexar-outro-pdf' },
    aoEscolher: abrirPdf,
  }),
  [DO_RODAPE.VOLTAR_A_ATIVO]: () => ({
    rotulo: tg('RODAPE.VOLTAR_A_ATIVO'),
    icone: 'i-lucide-rotate-ccw',
    atributos: { 'data-carteira': 'voltar-a-ativo' },
    aoEscolher: voltarAAtivo,
  }),
  [DO_RODAPE.MARCAR_CANCELADO]: () => ({
    rotulo: tg('RODAPE.MARCAR_CANCELADO'),
    icone: 'i-lucide-circle-slash',
    atributos: { 'data-carteira': 'marcar-cancelado' },
    aoEscolher: marcarCancelado,
  }),
};
const itensDoMenu = computed(() =>
  rodape.value.menu.map(id => ({ id, ...DO_MENU[id]() }))
);
const aoEscolherNoMenu = id =>
  itensDoMenu.value.find(item => item.id === id)?.aoEscolher();

const sairDaCorrecao = () => {
  corrigindo.value = false;
  focarTitulo();
};
const salvarCorrecao = async dados => {
  erroAoSalvar.value = !(await aberto.corrigir(dados));
  if (erroAoSalvar.value) return;
  emit('mudou');
  sairDaCorrecao();
  const chave = cardNasceAmanha(seguro.value, props.agora)
    ? 'SALVO_CARD_AMANHA'
    : 'SALVO';
  dizer(t(`RELACIONAMENTOS_CARTEIRA.CORRIGIR.${chave}`));
};

watch(
  () => props.apoliceId,
  id => {
    corrigindo.value = false;
    alterandoPalavras.value = false;
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
    @fechar="emit('fechar')"
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
        data-relacionamentos="erro"
      >
        <ErroComTentarDeNovo :mensagem="tg('ERRO')" @tentar="aberto.carregar" />
      </div>
      <div
        v-else-if="aberto.estado.value === ESTADOS.NAO_ACHEI"
        data-carteira="seguro-nao-esta"
      >
        <VazioComUmBotao
          :frase="tg('NAO_ESTA_MAIS')"
          :botao="tg('VOLTAR_PARA_LISTA')"
          @acao="emit('fechar')"
        />
      </div>
      <CorrigirSeguro
        v-else-if="corrigindo"
        ref="formulario"
        :seguro="seguro"
        :seguradoras="seguradoras"
        @salvar="salvarCorrecao"
      />
      <template v-else>
        <FraseDoSeguro
          :seguro="seguro"
          :agora="agora"
          :da-conta="daConta"
          :nao-saiu="naoSaiuNoTopo"
        />
        <DadosDoSeguro
          :seguro="seguro"
          :agora="agora"
          @abrir-segurado="emit('abrirSegurado', $event)"
        />
        <RenovacaoDoSeguro
          v-if="seguro.renovacao"
          :renovacao="seguro.renovacao"
          :em-que-pe="textos.renovacao(seguro, daConta)"
          :nao-saiu="naoSaiu?.naRenovacao ? oQueNaoSaiuEscrito : ''"
          :mostra-abrir="!noRodape(PASSOS_DO_SEGURO.ABRIR_RENOVACAO)"
          :pode-cotar="cotacao === COTACAO.NAO_COMECOU && emRenovacao"
          :pedindo-cotacao="aberto.ocupado.value === 'cotar'"
          @abrir="abrirRenovacao"
          @cotar="cotar"
        />
        <PalavrasSimples
          v-if="seguro.palavras"
          v-model:alterando="alterandoPalavras"
          :seguro="seguro"
          :ocupado="aberto.ocupado.value"
          :agora="agora"
          :envia-no-rodape="noRodape(PASSOS_DO_SEGURO.ENVIAR_PALAVRAS)"
          @salvar="salvarPalavras"
          @enviar="enviarPalavras"
          @tentar="aberto.carregar"
        />
        <HistoriaDoSeguro
          :itens="aberto.historia.value"
          :estado="aberto.estadoDaHistoria.value"
          :numero="seguro.numero"
          :agora="agora"
          @tentar="aberto.carregarHistoria"
          @exportado="dizer(t('RELACIONAMENTOS_CARTEIRA.HISTORIA.BAIXADO'))"
          @ver-proposta="verOQueSaiu"
        />
      </template>
    </div>

    <template v-if="pronto" #rodape>
      <div class="flex flex-wrap items-center w-full gap-3">
        <template v-if="corrigindo">
          <p
            v-if="erroAoSalvar"
            role="alert"
            data-carteira="erro-correcao"
            class="m-0 text-base basis-full text-n-ruby-11"
          >
            {{ t('RELACIONAMENTOS_CARTEIRA.CORRIGIR.ERRO_AO_SALVAR') }}
          </p>
          <Button
            size="lg"
            class="flex-1 sm:flex-none"
            data-carteira="salvar-correcao"
            :is-loading="aberto.ocupado.value === 'corrigir'"
            :label="t('RELACIONAMENTOS_CARTEIRA.CORRIGIR.SALVAR')"
            @click="formulario?.tentarSalvar()"
          />
          <Button
            slate
            faded
            size="lg"
            class="flex-1 sm:flex-none"
            data-carteira="voltar-da-correcao"
            :label="t('RELACIONAMENTOS_CARTEIRA.CORRIGIR.VOLTAR')"
            @click="sairDaCorrecao"
          />
        </template>
        <template v-else>
          <AvisoComDesfazer
            class="basis-full"
            :texto="aviso.texto"
            :pode-desfazer="Boolean(aviso.desfazer)"
            :desfazendo="Boolean(aberto.ocupado.value)"
            @desfazer="aviso.desfazer?.()"
          />
          <p
            v-if="alerta"
            :id="idDoAlerta"
            role="alert"
            data-carteira="alerta-da-gaveta"
            class="m-0 text-base font-medium basis-full text-n-ruby-11"
          >
            {{ alerta }}
          </p>
          <div
            class="flex basis-full sm:basis-auto"
            :data-carteira="
              passo.azul === PASSOS_DO_SEGURO.AVISAR
                ? 'avisar-parcela'
                : undefined
            "
          >
            <Button
              size="lg"
              class="flex-1"
              data-carteira="gaveta-acao"
              :data-acao="passo.azul"
              :aria-describedby="alerta ? idDoAlerta : undefined"
              :is-loading="
                passo.azul === PASSOS_DO_SEGURO.ENVIAR_PALAVRAS &&
                aberto.ocupado.value === 'enviarPalavras'
              "
              :label="rotuloDe(passo.azul)"
              @click="fazer(passo.azul)"
            />
          </div>
          <!-- O secundário e o "⋯" andam juntos: se não couberem ao lado do
               azul, descem os dois para a linha de baixo. -->
          <div
            data-carteira="rodape-secundarios"
            class="flex flex-1 min-w-0 gap-3 sm:flex-none"
          >
            <Button
              v-if="rodape.secundario === DO_RODAPE.CORRIGIR"
              slate
              faded
              size="lg"
              class="flex-1 sm:flex-none"
              data-carteira="corrigir"
              :label="tg('RODAPE.CORRIGIR')"
              @click="abrirCorrecao"
            />
            <Button
              v-else
              slate
              faded
              size="lg"
              class="flex-1 sm:flex-none"
              data-carteira="gaveta-acao-secundaria"
              :data-acao="rodape.secundario"
              :label="rotuloDe(rodape.secundario)"
              @click="fazer(rodape.secundario)"
            />
            <div data-carteira="mais-do-seguro">
              <MenuMaisAcoes
                tamanho="lg"
                :rotulo="tg('RODAPE.MAIS')"
                :itens="itensDoMenu"
                @escolher="aoEscolherNoMenu"
              />
            </div>
          </div>
        </template>
      </div>
    </template>
  </GavetaLateral>
  <DialogoAnexarPdf
    ref="dialogoDoPdf"
    :fonte="fonte"
    @guardado="aoGuardarPdf"
  />
  <DialogoDePrevia
    ref="previaDaParcela"
    :titulo="tg('PARCELA.TITULO', { nome: primeiroNome })"
    :texto="mensagemDaParcela"
    :enviando="aberto.ocupado.value === 'avisarDaParcela'"
    @enviar="enviarAvisoDaParcela"
  />
</template>
