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
import { cotaEsteSeguro } from '../../carteira/cotacaoDoCard';
import { cardNasceAmanha } from '../../carteira/formularioDoSeguro';
import {
  ACOES_DO_SEGURO,
  situacaoDoSeguro,
} from '../../carteira/situacaoDoSeguro';
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
// por vez, no rodapé: fica à vista também no celular). "Corrigir" troca o
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
const situacao = computed(() => situacaoDoSeguro(seguro.value, props.agora));
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
const verOQueSaiu = passo =>
  passo.acao === 'ver_resumo'
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

// O próximo passo do seguro. A conversa e o PDF de verdade são de outras
// entregas: por ora, o aviso diz o que vai abrir.
const PASSOS = {
  [ACOES_DO_SEGURO.ABRIR_RENOVACAO]: abrirRenovacao,
  [ACOES_DO_SEGURO.VER_PDF]: () => simular('ABRINDO_PDF', { tipo: tipo.value }),
  [ACOES_DO_SEGURO.ANEXAR_PDF]: abrirPdf,
  [ACOES_DO_SEGURO.ANEXAR_APOLICE_NOVA]: abrirPdf,
  [ACOES_DO_SEGURO.AVISAR]: avisarDaParcela,
  [ACOES_DO_SEGURO.CONVERSAR_COM]: conversar,
};
const proximoPasso = () => PASSOS[situacao.value.acao]();

const itensDoMenu = computed(() => [
  {
    id: 'anexar',
    rotulo: tg('RODAPE.ANEXAR_OUTRO_PDF'),
    icone: 'i-lucide-paperclip',
    atributos: { 'data-carteira': 'anexar-outro-pdf' },
  },
  cancelado.value
    ? {
        id: 'voltar',
        rotulo: tg('RODAPE.VOLTAR_A_ATIVO'),
        icone: 'i-lucide-rotate-ccw',
        atributos: { 'data-carteira': 'voltar-a-ativo' },
      }
    : {
        id: 'cancelar',
        rotulo: tg('RODAPE.MARCAR_CANCELADO'),
        icone: 'i-lucide-circle-slash',
        atributos: { 'data-carteira': 'marcar-cancelado' },
      },
]);
const aoEscolherNoMenu = id =>
  ({ anexar: abrirPdf, voltar: voltarAAtivo, cancelar: marcarCancelado })[id]();

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
        <FraseDoSeguro :seguro="seguro" :agora="agora" />
        <DadosDoSeguro
          :seguro="seguro"
          :agora="agora"
          @abrir-segurado="emit('abrirSegurado', $event)"
        />
        <RenovacaoDoSeguro
          v-if="seguro.renovacao"
          :renovacao="seguro.renovacao"
          :mostra-abrir="situacao.acao !== ACOES_DO_SEGURO.ABRIR_RENOVACAO"
          :pode-cotar="cotaEsteSeguro(seguro, fonte) && emRenovacao"
          :pedindo-cotacao="aberto.ocupado.value === 'cotar'"
          @abrir="abrirRenovacao"
          @cotar="cotar"
        />
        <PalavrasSimples
          v-if="seguro.palavras"
          :seguro="seguro"
          :ocupado="aberto.ocupado.value"
          :agora="agora"
          @salvar="salvarPalavras"
          @enviar="enviarPalavras"
          @tentar="aberto.carregar"
          @conversar="conversar"
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
              situacao.acao === ACOES_DO_SEGURO.AVISAR
                ? 'avisar-parcela'
                : undefined
            "
          >
            <Button
              size="lg"
              class="flex-1"
              data-carteira="gaveta-acao"
              :data-acao="situacao.acao"
              :aria-describedby="alerta ? idDoAlerta : undefined"
              :label="tg(`ACAO.${situacao.acao}`, { nome: primeiroNome })"
              @click="proximoPasso"
            />
          </div>
          <Button
            slate
            faded
            size="lg"
            class="flex-1 sm:flex-none"
            data-carteira="corrigir"
            :label="tg('RODAPE.CORRIGIR')"
            @click="abrirCorrecao"
          />
          <div data-carteira="mais-do-seguro">
            <MenuMaisAcoes
              tamanho="lg"
              :rotulo="tg('RODAPE.MAIS')"
              :itens="itensDoMenu"
              @escolher="aoEscolherNoMenu"
            />
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
