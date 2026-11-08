<script setup>
// Uma mensagem da conversa do Instagram com a cara do Direct (#2079). Recebida à
// esquerda, com a foto de 28 px só na última do grupo; nossa à direita, sem foto.
// Ao passar o mouse, "Responder", "Reagir" e "Mais opções" ao lado do balão, como no
// app; a reação fica no selo do canto de baixo do balão (#2113).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import { useMessageContext } from 'dashboard/components-next/message/provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import { ATTACHMENT_TYPES as A } from 'dashboard/components-next/message/constants';
import {
  useInstagramDaConversa,
  useSequenciaDoInstagram,
} from './useConversaDoInstagram';
import { BALOES, balaoDoInstagram } from './balaoDoInstagram';
import { cantosDoBalao, ladoDaMensagem } from './sequenciaDoInstagram';
import { RECEBIDO, ROTULO, SECUNDARIO } from './visualInstagram';
import TextoDoInstagram from './TextoDoInstagram.vue';
import MidiaDoInstagram from './MidiaDoInstagram.vue';
import AlbumDoInstagram from './AlbumDoInstagram.vue';
import VozDoInstagram from './VozDoInstagram.vue';
import CompartilhadoDoInstagram from './CompartilhadoDoInstagram.vue';
import ReacoesDoInstagram from './ReacoesDoInstagram.vue';
import BotaoDeReagir from '../BotaoDeReagir.vue';
import { reacoesDaMensagem } from '../reacoes';
import RotuloEditada from '../RotuloEditada.vue';
import { foiEditada } from '../marcasDaMensagem';
import { fornecerFuso } from '../pele';

// "Responder" segue a mesma regra do menu (quem só lê, nota, falha, caixa sem resposta).
// "Reagir" é o mesmo fluxo da reação do atendente do WhatsApp (useReacaoDoAtendente, no
// Message.vue): a linha só mostra o botão e devolve o emoji escolhido.
defineProps({
  podeResponder: { type: Boolean, default: false },
  podeReagir: { type: Boolean, default: false },
  reacaoAtual: { type: String, default: '' },
  reacaoBloqueada: { type: Boolean, default: false },
  reagindo: { type: Boolean, default: false },
});
const emit = defineEmits(['responder', 'menu', 'reagir']);

const { t } = useI18n();
const mensagem = useMessageContext();
const { contato, fuso } = useInstagramDaConversa();
// O "Editada" mostra a hora das versões anteriores no fuso da conta, como o horário da conversa.
fornecerFuso(fuso);
const sequencia = useSequenciaDoInstagram();

const dados = computed(() => ({
  id: mensagem.id.value,
  content: mensagem.content.value,
  attachments: mensagem.attachments.value || [],
  contentAttributes: mensagem.contentAttributes.value || {},
  messageType: mensagem.messageType.value,
  private: mensagem.isPrivate.value,
}));
const lado = computed(() => ladoDaMensagem(dados.value));
const enviada = computed(() => lado.value === 'direita');
const posicao = computed(
  () =>
    sequencia.value.get(dados.value.id) || {
      comAnterior: false,
      comProxima: false,
    }
);
const cantos = computed(() =>
  cantosDoBalao({ lado: lado.value, ...posicao.value })
);
const tipo = computed(() => balaoDoInstagram(dados.value));
const anexos = computed(() => dados.value.attachments);
// "Traduzir" do menu grava a tradução na mensagem: o balão mostra a tradução, com o
// "Ver original" embaixo, como no balão de sempre.
const { hasTranslations, translationContent } = useTranslations(
  mensagem.contentAttributes
);
const verOriginal = ref(false);
// Mensagem que o cliente apagou fica com o aviso de apagada: a tradução era do texto que saiu.
const texto = computed(() => {
  const traduzido =
    hasTranslations.value && !verOriginal.value && tipo.value !== BALOES.APAGADA
      ? translationContent.value
      : null;
  return (traduzido || dados.value.content || '').trim();
});
// O texto que vai junto da mídia (legenda, resposta ao story) vira um balão embaixo.
// Na menção em story e no story compartilhado o texto é do sistema ("mencionou você"),
// e o rótulo em cima já diz isso: fica de fora.
const STORY_SEM_TEXTO_DO_CLIENTE = [A.STORY_MENTION, A.IG_STORY];
const textoJunto = computed(
  () =>
    Boolean(texto.value) &&
    ![BALOES.TEXTO, BALOES.APAGADA, BALOES.POST].includes(tipo.value) &&
    !STORY_SEM_TEXTO_DO_CLIENTE.includes(
      dados.value.contentAttributes.imageType
    )
);
// O cliente editou a mensagem no Instagram (#2113): o texto já é o novo; "Editada" embaixo,
// como no app. Apagada não mostra (o texto que sai é o aviso).
const editada = computed(
  () =>
    tipo.value !== BALOES.APAGADA && foiEditada(dados.value.contentAttributes)
);
const temTraducao = computed(
  () =>
    hasTranslations.value && (tipo.value === BALOES.TEXTO || textoJunto.value)
);

// "Mais opções" pelo teclado não traz posição de mouse: o menu abre no botão.
const abrirMenu = evento => {
  if (evento.detail !== 0) {
    emit('menu', evento);
    return;
  }
  const { left, bottom } = evento.currentTarget.getBoundingClientRect();
  emit('menu', {
    type: evento.type,
    target: evento.currentTarget,
    pageX: left,
    pageY: bottom,
    preventDefault: () => evento.preventDefault(),
  });
};
const fotoDoContato = computed(
  () => !enviada.value && !posicao.value.comProxima
);
const reacoes = computed(() =>
  reacoesDaMensagem(dados.value.contentAttributes)
);

// A citação de quem respondeu: rótulo em cima e a mensagem citada esmaecida.
const citada = computed(() => mensagem.inReplyTo?.value || null);
const rotuloDaCitacao = computed(() =>
  enviada.value
    ? t('CONVERSA_CANAL.INSTAGRAM.VOCE_RESPONDEU')
    : t('CONVERSA_CANAL.INSTAGRAM.RESPONDEU_A_VOCE')
);
const textoCitado = computed(() => {
  const citacao = citada.value;
  if (!citacao) return '';
  return (
    (citacao.content || '').trim() ||
    t('CONVERSA_CANAL.INSTAGRAM.MENSAGEM_VAZIA')
  );
});
</script>

<template>
  <div
    class="group/instagram group/linha flex w-full items-end gap-2"
    :class="[
      enviada ? 'flex-row-reverse' : 'flex-row',
      posicao.comProxima ? 'mb-0.5' : 'mb-2',
    ]"
  >
    <div v-if="!enviada" class="w-7 shrink-0">
      <Avatar
        v-if="fotoDoContato"
        :src="contato?.thumbnail || ''"
        :name="contato?.name || ''"
        :size="28"
        rounded-full
      />
    </div>
    <div
      class="flex min-w-0 flex-col gap-0.5"
      :class="enviada ? 'items-end' : 'items-start'"
      @contextmenu="emit('menu', $event)"
    >
      <!-- O selo encosta no último balão: o "Ver original" fica fora, embaixo dele. -->
      <div
        class="relative flex min-w-0 flex-col gap-0.5"
        :class="[
          enviada ? 'items-end' : 'items-start',
          { 'pb-[18px]': reacoes.length },
        ]"
        data-baloes-do-instagram
      >
        <template v-if="citada">
          <span :class="ROTULO" class="mt-1">{{ rotuloDaCitacao }}</span>
          <div
            class="max-w-[300px] truncate rounded-[18px] px-3 py-2 text-[13px] leading-4 opacity-60"
            :class="[RECEBIDO]"
          >
            {{ textoCitado }}
          </div>
        </template>
        <TextoDoInstagram
          v-if="tipo === BALOES.TEXTO"
          :texto="texto"
          :enviada="enviada"
          :cantos="cantos"
        />
        <div
          v-else-if="tipo === BALOES.APAGADA"
          class="rounded-[18px] border border-[#DBDFE4] dark:border-[#363636] px-3 py-2 text-[15px] leading-5 italic"
          :class="SECUNDARIO"
        >
          {{ texto }}
        </div>
        <MidiaDoInstagram
          v-else-if="
            tipo === BALOES.MIDIA ||
            tipo === BALOES.REEL ||
            tipo === BALOES.FIGURINHA
          "
          :anexo="anexos[0]"
          :cantos="cantos"
          :figurinha="tipo === BALOES.FIGURINHA"
        />
        <AlbumDoInstagram
          v-else-if="tipo === BALOES.ALBUM"
          :anexos="anexos"
          :cantos="cantos"
        />
        <VozDoInstagram
          v-else-if="tipo === BALOES.VOZ"
          :anexo="anexos[0]"
          :enviada="enviada"
          :cantos="cantos"
        />
        <CompartilhadoDoInstagram
          v-else-if="tipo === BALOES.POST || tipo === BALOES.STORY"
          :tipo="tipo"
          :mensagem="dados"
          :enviada="enviada"
        />
        <TextoDoInstagram
          v-if="textoJunto"
          :texto="texto"
          :enviada="enviada"
          :cantos="cantos"
        />
        <ReacoesDoInstagram
          v-if="reacoes.length"
          :reacoes="reacoes"
          :enviada="enviada"
        />
      </div>
      <span
        v-if="editada"
        :class="ROTULO"
        class="px-3"
        data-editada-do-instagram
      >
        <RotuloEditada
          :atributos="dados.contentAttributes"
          :abrir-no-inicio="!enviada"
        />
      </span>
      <TranslationToggle
        v-if="temTraducao"
        class="px-3"
        :showing-original="verOriginal"
        @toggle="verOriginal = !verOriginal"
      />
    </div>
    <div
      class="flex shrink-0 items-center gap-2 self-center opacity-0 transition-opacity group-hover/instagram:opacity-100 focus-within:opacity-100"
      :class="enviada ? 'flex-row-reverse' : 'flex-row'"
    >
      <button
        v-if="podeResponder"
        type="button"
        class="flex size-6 shrink-0 items-center justify-center p-0"
        :aria-label="t('CONVERSA_CANAL.INSTAGRAM.RESPONDER')"
        @click="emit('responder')"
      >
        <span class="i-ph-arrow-bend-up-left size-4" />
      </button>
      <BotaoDeReagir
        v-if="podeReagir"
        class="-my-2"
        :mensagem-id="dados.id"
        :atual="reacaoAtual"
        :bloqueado="reacaoBloqueada"
        :enviando="reagindo"
        :dica-bloqueado="t('CONVERSA_CANAL.INSTAGRAM.REAGIR_FORA_DA_JANELA')"
        @reagir="emit('reagir', $event)"
      />
      <button
        type="button"
        class="flex size-6 shrink-0 items-center justify-center p-0"
        :aria-label="t('CONVERSA_CANAL.INSTAGRAM.MAIS_OPCOES')"
        @click="abrirMenu"
      >
        <span class="i-ph-dots-three-vertical-bold size-4" />
      </button>
    </div>
  </div>
</template>
