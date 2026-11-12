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
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../../comum/EsqueletoDeLista.vue';
import VazioComUmBotao from '../../comum/VazioComUmBotao.vue';
import GavetaLateral from '../../ficha/GavetaLateral.vue';
import {
  COTACAO,
  FIM,
  cotacaoDoCard,
  fimDaRenovacao,
} from '../../../carteira/cotacaoDoCard';
import { PASSOS, passoDaVez } from '../../../carteira/passoDaVez';
import { useSeguroAberto } from '../../../carteira/useSeguroAberto';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import { ESTADOS_DA_FICHA as ESTADOS } from '../../../ficha/useEstadoDaFicha';
import AvisoComDesfazer from '../AvisoComDesfazer.vue';
import DialogoAnexarPdf from '../DialogoAnexarPdf.vue';
import BlocoDaCotacao from './BlocoDaCotacao.vue';
import BlocoDoSeguroNoCard from './BlocoDoSeguroNoCard.vue';
import DialogoMotivo from './DialogoMotivo.vue';
import PreviaDaProposta from './PreviaDaProposta.vue';

// #2897 — a renovação de um seguro, do começo ao fim, numa gaveta
// (`?renovacao=<id do seguro>`): em que pé está, o seguro, a cotação e como
// terminou. Um botão azul por vez, no rodapé: o do passo da vez
// (carteira/passoDaVez.js: cotar, enviar, pôr o telefone, conversar…); depois
// de as opções saírem, o azul é "Renovou". "Renovou" e "Não renovou" estão
// sempre no rodapé e não pedem confirmação: o aviso traz "Desfazer", sem prazo.
// Com a proposta saindo sozinha, nada aqui pede clique: a gaveta só mostra o
// que já saiu. `seguroId` nulo = fechada.
const props = defineProps({
  seguroId: { type: Number, default: null },
  fonte: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['fechar', 'mudou', 'abrirSegurado']);

const { t } = useI18n();
const router = useRouter();
const tk = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.CARD.${chave}`, valores);
const tg = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.${chave}`, valores);
const ca = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.${chave}`, valores);
const textos = useTextosDoSeguro();
const aberto = useSeguroAberto(props.fonte, toRef(props, 'seguroId'));
const { seguro } = aberto;

const aviso = ref({ texto: '', desfazer: null });
const corpo = useTemplateRef('corpo');
const previa = useTemplateRef('previa');
const blocoDaCotacao = useTemplateRef('blocoDaCotacao');
// A pessoa resolveu escrever os dados que faltam sem esperar a resposta que o
// agente pediu.
const preenchendo = ref(false);
const dialogoDoMotivo = useTemplateRef('dialogoDoMotivo');
const dialogoDoPdf = useTemplateRef('dialogoDoPdf');

const carregando = computed(() => aberto.estado.value === ESTADOS.CARREGANDO);
const temRenovacao = computed(
  () =>
    aberto.estado.value === ESTADOS.PRONTO && Boolean(seguro.value?.renovacao)
);
const naoEsta = computed(
  () =>
    aberto.estado.value === ESTADOS.NAO_ACHEI ||
    (aberto.estado.value === ESTADOS.PRONTO && !seguro.value?.renovacao)
);
const tipo = computed(() => (seguro.value ? textos.tipo(seguro.value) : ''));
const primeiroNome = computed(
  () => seguro.value?.pessoa.name.split(' ')[0] ?? ''
);
const titulo = computed(() => {
  if (carregando.value) return tk('CARREGANDO');
  return temRenovacao.value
    ? tk('TITULO', { tipo: tipo.value })
    : t('RELACIONAMENTOS_CARTEIRA.GAVETA.RENOVACAO.TITULO');
});
const fim = computed(() => fimDaRenovacao(seguro.value?.renovacao));
const daConta = computed(() => ({
  cotaSozinha: props.fonte.cotaSozinha,
  tiposQueCota: props.fonte.tiposQueCota,
}));
const cotacao = computed(() => cotacaoDoCard(seguro.value, daConta.value));
// O título: a etapa e a cotação dizem a mesma coisa (carteira/tituloDaRenovacao).
const emQuePe = computed(() => textos.renovacao(seguro.value, daConta.value));
const passo = computed(() =>
  passoDaVez(seguro.value?.renovacao, cotacao.value, {
    preenchendo: preenchendo.value,
  })
);
// A apólice nova chega sozinha quando o seguro veio do Agger.
const chegaSozinha = computed(() => seguro.value?.origem.tipo === 'agger');
const nomeDoMotivo = motivo =>
  t(`RELACIONAMENTOS_CARTEIRA.MOTIVOS.${motivo.toUpperCase()}`);
const comoTerminou = computed(() => {
  if (fim.value === FIM.RENOVOU) {
    return tk(chegaSozinha.value ? 'RENOVOU_AGGER' : 'RENOVOU_FALTA');
  }
  const { motivo, motivoEscrito } = seguro.value;
  return motivo
    ? tk('NAO_RENOVOU_MOTIVO', {
        motivo: motivoEscrito || nomeDoMotivo(motivo),
      })
    : emQuePe.value;
});

const dizer = (texto, desfazer = null) => {
  aviso.value = { texto, desfazer };
};
const focarTitulo = async () => {
  await nextTick();
  corpo.value
    ?.closest('[role="dialog"]')
    ?.querySelector('[data-view-title]')
    ?.focus();
};

// Cada ação que muda a renovação: avisa quem abriu a gaveta (a lista e a ficha
// releem) e diz o que aconteceu, com o desfazer quando há.
const agir = async (nome, dados, texto = '', desfazer = null) => {
  const certo = await aberto.fazer(nome, dados);
  if (certo) emit('mudou');
  dizer(certo ? texto : tg('AVISOS.NAO_DEU'), certo ? desfazer : null);
  return certo;
};
const desfazer = () =>
  agir('desfazerDesfecho', undefined, tg('AVISOS.DESFEITO'));

const enviar = async () => {
  const { name } = seguro.value.pessoa;
  await agir(
    'enviarProposta',
    undefined,
    tk('PROPOSTA_ENVIADA', { nome: name })
  );
  previa.value?.fechar();
};
const renovou = () =>
  agir('renovou', undefined, tk('RENOVACAO_MARCADA'), desfazer);
const naoRenovou = escolha =>
  agir(
    'naoRenovou',
    escolha,
    tk('NAO_RENOVOU_MOTIVO', {
      motivo: escolha.texto || nomeDoMotivo(escolha.motivo),
    }),
    desfazer
  );

const aoGuardarPdf = ({ seguro: novo }) => {
  aberto.receber(novo);
  emit('mudou');
  dizer(tg('AVISOS.APOLICE_NOVA'));
};

// O PDF, a conversa e o CRM de verdade são de outras entregas: por ora, o
// aviso diz o que vai abrir.
const simular = texto => useAlert(texto);
const verProposta = () =>
  simular(
    seguro.value.renovacao.proposta?.oficial
      ? tg('AVISOS.ABRINDO_PROPOSTA')
      : t('RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.ABRINDO_RESUMO')
  );
const abrirPessoa = () =>
  emit('abrirSegurado', { tipo: 'pessoa', id: seguro.value.pessoa.id });
const entrarNoAgger = () =>
  router.push({ name: 'relacionamentos_trazer', query: { como: 'agger' } });
const conversar = () =>
  simular(tg('AVISOS.ABRINDO_CONVERSA', { nome: seguro.value.pessoa.name }));

// O botão azul de cada passo. "Renovou" já está no rodapé (fica azul quando é a
// vez dele) e "Pedir a proposta desta" fica ao lado da seguradora escolhida.
const BOTOES = {
  [PASSOS.COTAR_AGORA]: () => ({
    marca: 'cotar-agora',
    rotulo: tg('RENOVACAO.COTAR_AGORA'),
    ocupado: 'cotar',
    aoClicar: () => agir('cotar'),
  }),
  [PASSOS.COTAR_DE_NOVO]: () => ({
    marca: 'cotar-de-novo',
    rotulo: ca('COTAR_DE_NOVO'),
    ocupado: 'cotar',
    aoClicar: () => agir('cotar'),
  }),
  [PASSOS.COTAR_COM_DADOS]: () => ({
    marca: 'cotar-com-dado',
    rotulo: ca('COTAR_COM_DADOS'),
    ocupado: 'cotarComDados',
    aoClicar: () => blocoDaCotacao.value?.cotarComOsDados(),
  }),
  [PASSOS.ENTRAR_NO_AGGER]: () => ({
    marca: 'entrar-no-agger',
    rotulo: ca('ENTRAR_NO_AGGER'),
    aoClicar: entrarNoAgger,
  }),
  [PASSOS.ANEXAR_PROPOSTA]: () => ({
    marca: 'anexar-proposta',
    rotulo: ca('ANEXAR_PROPOSTA'),
    ocupado: 'anexarProposta',
    aoClicar: () => agir('anexarProposta'),
  }),
  [PASSOS.ENVIAR]: () => ({
    marca: 'enviar-ao-cliente',
    rotulo: ca('ENVIAR_A', { nome: primeiroNome.value }),
    aoClicar: () => previa.value?.abrir(),
  }),
  [PASSOS.ENVIAR_RESUMO]: () => ({
    marca: 'enviar-ao-cliente',
    rotulo: ca('ENVIAR_O_RESUMO'),
    aoClicar: () => previa.value?.abrir(),
  }),
  [PASSOS.POR_TELEFONE]: () => ({
    marca: 'por-o-telefone',
    rotulo: ca('POR_O_TELEFONE'),
    aoClicar: abrirPessoa,
  }),
  [PASSOS.CONVERSAR]: () => ({
    marca: 'conversar-sobre-a-proposta',
    rotulo: ca('CONVERSAR'),
    aoClicar: conversar,
  }),
};
const botaoDoPasso = computed(() => BOTOES[passo.value?.id]?.() ?? null);
const renovouEAVez = computed(() => passo.value?.id === PASSOS.RENOVOU);

watch(
  () => props.seguroId,
  id => {
    dizer('');
    preenchendo.value = false;
    if (id) aberto.carregar();
  },
  { immediate: true }
);
// Saiu de "o agente já perguntou" (cotou, chegou a resposta): a escolha de
// preencher não vale para a próxima vez.
watch(cotacao, estado => {
  if (estado !== COTACAO.FALTOU_PERGUNTADO) preenchendo.value = false;
});
// A gaveta que já nasce aberta (o endereço trouxe `?renovacao=`) não passa pelo
// "abrir": o foco vai ao título por aqui.
onMounted(() => {
  if (props.seguroId) focarTitulo();
});
</script>

<template>
  <GavetaLateral
    marca="gaveta-da-renovacao"
    largura="sm:w-[32rem]"
    :aberta="Boolean(seguroId)"
    :titulo="titulo"
    @fechar="emit('fechar')"
  >
    <div ref="corpo" data-carteira="card-renovacao" class="flex flex-col gap-8">
      <EsqueletoDeLista
        v-if="carregando"
        :linhas="5"
        data-carteira="carregando"
      />
      <div
        v-else-if="aberto.estado.value === ESTADOS.ERRO"
        data-relacionamentos="erro"
      >
        <ErroComTentarDeNovo :mensagem="tk('ERRO')" @tentar="aberto.carregar" />
      </div>
      <div v-else-if="naoEsta" data-carteira="renovacao-nao-esta">
        <VazioComUmBotao
          :frase="tk('NAO_ESTA_MAIS')"
          :botao="tk('VOLTAR')"
          @acao="emit('fechar')"
        />
      </div>
      <template v-else>
        <div class="flex flex-col items-start gap-2">
          <Button
            link
            size="lg"
            data-carteira="pessoa-da-renovacao"
            :label="seguro.pessoa.name"
            @click="abrirPessoa"
          />
          <p
            v-if="!fim"
            data-carteira="situacao-da-renovacao"
            class="m-0 text-xl font-semibold leading-snug text-balance text-n-slate-12"
          >
            {{ emQuePe }}
          </p>
          <p
            v-else
            data-carteira="como-terminou"
            class="m-0 text-xl font-semibold leading-snug text-balance text-n-slate-12"
          >
            {{ comoTerminou }}
          </p>
          <p data-carteira="quem-cuida" class="m-0 text-base text-n-slate-11">
            {{ tg('RENOVACAO.QUEM_CUIDA', { nome: seguro.renovacao.cuida }) }}
          </p>
        </div>
        <BlocoDoSeguroNoCard
          :seguro="seguro"
          :agora="agora"
          @ver-apolice="simular(tg('AVISOS.ABRINDO_PDF', { tipo }))"
        />
        <BlocoDaCotacao
          ref="blocoDaCotacao"
          :seguro="seguro"
          :da-conta="daConta"
          :escolhida="passo?.seguradora ?? ''"
          :preenchendo="preenchendo"
          :ocupado="aberto.ocupado.value"
          :agora="agora"
          @fazer="agir"
          @ver-proposta="verProposta"
          @preencher="preenchendo = true"
        />
        <div>
          <Button
            link
            size="lg"
            icon="i-lucide-external-link"
            data-carteira="abrir-no-crm"
            :label="tk('ABRIR_NO_CRM')"
            @click="simular(tk('ABRINDO_NO_CRM'))"
          />
        </div>
      </template>
    </div>

    <template v-if="temRenovacao" #rodape>
      <div class="flex flex-wrap items-center w-full gap-3">
        <AvisoComDesfazer
          class="basis-full"
          :texto="aviso.texto"
          :pode-desfazer="Boolean(aviso.desfazer)"
          :desfazendo="aberto.ocupado.value === 'desfazerDesfecho'"
          @desfazer="aviso.desfazer?.()"
        />
        <template v-if="!fim">
          <!-- Com o botão do passo são três: o azul ocupa a linha de cima e
               "Renovou" e "Não renovou" dividem a de baixo, em qualquer
               largura (nenhum deles fica sozinho numa linha). -->
          <Button
            v-if="botaoDoPasso"
            size="lg"
            class="basis-full"
            :data-carteira="botaoDoPasso.marca"
            :is-loading="
              Boolean(botaoDoPasso.ocupado) &&
              aberto.ocupado.value === botaoDoPasso.ocupado
            "
            :label="botaoDoPasso.rotulo"
            @click="botaoDoPasso.aoClicar"
          />
          <div data-carteira="desfechos" class="flex gap-3 basis-full">
            <Button
              size="lg"
              class="flex-1"
              :class="{ 'sm:flex-none': !botaoDoPasso }"
              :slate="!renovouEAVez"
              :faded="!renovouEAVez"
              data-carteira="renovou"
              :is-loading="aberto.ocupado.value === 'renovou'"
              :label="tk('RENOVOU')"
              @click="renovou"
            />
            <Button
              slate
              faded
              size="lg"
              class="flex-1"
              :class="{ 'sm:flex-none': !botaoDoPasso }"
              data-carteira="nao-renovou"
              :label="tk('NAO_RENOVOU')"
              @click="dialogoDoMotivo?.abrir()"
            />
          </div>
        </template>
        <Button
          v-else-if="fim === FIM.RENOVOU && !chegaSozinha"
          size="lg"
          class="basis-full sm:basis-auto"
          data-carteira="anexar-apolice-nova"
          :label="tg('ACAO.ANEXAR_APOLICE_NOVA')"
          @click="dialogoDoPdf?.abrir(seguro)"
        />
      </div>
    </template>
  </GavetaLateral>
  <PreviaDaProposta
    ref="previa"
    :seguro="seguro"
    :enviando="aberto.ocupado.value === 'enviarProposta'"
    @enviar="enviar"
  />
  <DialogoMotivo ref="dialogoDoMotivo" @escolher="naoRenovou" />
  <DialogoAnexarPdf
    ref="dialogoDoPdf"
    :fonte="fonte"
    @guardado="aoGuardarPdf"
  />
</template>
