<script setup>
import { computed, nextTick, onUnmounted, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import NovaConversaHeroi from './NovaConversaHeroi.vue';
import NovaConversaParaQuem from './NovaConversaParaQuem.vue';
import NovaConversaPorOnde from './NovaConversaPorOnde.vue';
import NovaConversaOndeEntra from './NovaConversaOndeEntra.vue';
import NovaConversaSemCanal from './NovaConversaSemCanal.vue';
import NovaConversaMensagem from './NovaConversaMensagem.vue';
import NovaConversaPrevia from './NovaConversaPrevia.vue';
import NovaConversaEnviada from './NovaConversaEnviada.vue';
import NovaConversaErro from './NovaConversaErro.vue';
import NovaConversaRodape from './NovaConversaRodape.vue';
import { useNovaConversaContato } from './useNovaConversaContato';
import { useNovaConversa } from './useNovaConversa';
import { useContinuarConversa } from './useContinuarConversa';
import { useFocoPreso } from './useFocoPreso';
import { useCriarMensagemPronta } from './useCriarMensagemPronta';
import {
  TELAS,
  TIPOS,
  linhaDoCanal,
  lugarDeOrigem,
  primeiroNome,
  telaDaGaveta,
} from './novaConversa';

// #1459 — "Nova conversa" numa gaveta lateral: para quem, por onde, a
// mensagem e, à direita, como a pessoa recebe. Uma tela, uma ação: Enviar.
// A interface pública é a mesma do ComposeConversation antigo (contactId,
// align, slot `trigger`, evento `close`), para a troca ser só o import.
const props = defineProps({
  contactId: { type: String, default: null },
  // A gaveta abre sempre do mesmo lado; `align` fica pela compatibilidade.
  // eslint-disable-next-line vue/no-unused-properties
  align: { type: String, default: 'end' },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const tituloId = `nova-conversa-titulo-${useId()}`;
const aberta = ref(false);
const raiz = ref(null);
const corpo = ref(null);
const blocoDaMensagem = ref(null);

const {
  contato,
  canais,
  canalId,
  canal,
  carregandoCanais,
  erroNosCanais,
  termo,
  resultados,
  buscando,
  erroNaBusca,
  criando,
  erroAoCriar,
  carregarCanais,
  escolherContato,
  usarContatoDaPagina,
  limparContato,
  mudarTermo,
  criarContato,
} = useNovaConversaContato();

// #1505 — o contato já tem conversa nesta caixa: continuar ou começar outra.
const continuar = useContinuarConversa({ contato, canal });
const {
  destino: escolha,
  existente: conversaExistente,
  carregando: carregandoConversa,
  erro: erroNaConversa,
  esperando: esperandoConversa,
  carregar: carregarConversa,
} = continuar;

const {
  form,
  tipo,
  destino: conversaDaMensagem,
  comAssinatura,
  assinatura,
  falta,
  previa,
  enviando,
  erro,
  enviada,
  limpar,
  enviar,
  enviarPronta,
} = useNovaConversa({ contato, canal, continuar });
const continuando = computed(() => Boolean(conversaDaMensagem.value));

const { prender, entrar, entrarSeLivre } = useFocoPreso(raiz, aberta);
const { podeCriar: podeCriarPronta, irCriar } = useCriarMensagemPronta();

const nome = computed(() => contato.value?.name || '');
const tela = computed(() =>
  telaDaGaveta({
    enviada: Boolean(enviada.value),
    contato: contato.value,
    carregandoCanais: carregandoCanais.value,
    erroNosCanais: erroNosCanais.value,
    canais: canais.value,
  })
);
const titulo = computed(() => {
  if (tela.value === TELAS.ENVIADA) {
    return enviada.value.nome
      ? t('NOVA_CONVERSA.ENVIADA.TITULO', { nome: enviada.value.nome })
      : t('NOVA_CONVERSA.ENVIADA.TITULO_SEM_NOME');
  }
  return nome.value
    ? t('NOVA_CONVERSA.TITULO', { nome: nome.value })
    : t('NOVA_CONVERSA.TITULO_SEM_CONTATO');
});
// A frase do cabeçalho acompanha o momento: procurar, escrever, ou nada.
const frase = computed(() => {
  if (tela.value === TELAS.SEM_CONTATO) return t('NOVA_CONVERSA.TEXTO_BUSCA');
  return tela.value === TELAS.ESCREVENDO ? t('NOVA_CONVERSA.TEXTO') : '';
});
const modoDoRodape = computed(() => {
  if (tela.value === TELAS.ENVIADA) return 'enviada';
  return tela.value === TELAS.ESCREVENDO ? 'enviar' : 'fechar';
});
const migalha = computed(() =>
  t(
    `NOVA_CONVERSA.MIGALHA.${lugarDeOrigem({
      rota: String(route.name || ''),
      comContato: Boolean(props.contactId),
    })}`
  )
);

const abrir = () => {
  aberta.value = true;
  // Mesmo sinal da tela antiga: desliga o arrastar-e-soltar da conversa.
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, true);
  // Busca de novo as caixas, para os modelos recém-aprovados aparecerem.
  store.dispatch('inboxes/get');
  if (props.contactId) usarContatoDaPagina(props.contactId);
};

const fechar = () => {
  if (!aberta.value) return;
  aberta.value = false;
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, false);
  if (enviada.value) {
    enviada.value = null;
    if (!props.contactId) limparContato();
  }
  emit('close');
};

const alternar = () => (aberta.value ? fechar() : abrir());

// A página trocou de contato com a gaveta aberta: a gaveta acompanha. Trocar
// de contato zera o que estava escrito (useNovaConversa).
watch(
  () => props.contactId,
  id => {
    if (!aberta.value) return;
    if (id) usarContatoDaPagina(id);
    else limparContato();
  }
);

// Quem usa a gaveta sumiu da tela com ela aberta: devolve o sinal, para o
// arrastar-e-soltar da conversa não ficar desligado.
onUnmounted(() => {
  if (aberta.value) emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, false);
});

const cancelar = () => {
  limpar();
  erro.value = '';
  if (!props.contactId) limparContato();
  fechar();
};

const mandar = () => enviar(() => blocoDaMensagem.value?.montar() ?? null);

const abrirConversa = () => {
  const { contaId, id } = enviada.value;
  fechar();
  router.push(`/app/accounts/${contaId}/conversations/${id}`);
};

// Na página do próprio contato, o cadastro já está atrás da gaveta: só fecha.
// De qualquer outro lugar, leva até lá.
const completarCadastro = () => {
  const id = contato.value?.id;
  const jaNaPagina = String(route.params.contactId || '') === String(id);
  fechar();
  if (jaNaPagina || !id) return;
  router.push({
    name: 'contacts_edit',
    params: { accountId: route.params.accountId, contactId: id },
  });
};

const criarPronta = () => {
  const caixaId = canal.value?.id;
  fechar();
  irCriar(caixaId);
};

const aoTeclar = evento => {
  prender(evento);
  // Enter sozinho só quebra a linha; Ctrl/Cmd+Enter envia.
  if (evento.key === 'Enter' && (evento.metaKey || evento.ctrlKey)) {
    evento.preventDefault();
    if (!enviada.value) mandar();
  }
};

// O que muda a tela inteira (enviou, ou deu erro) leva a rolagem ao topo; a
// confirmação recebe o foco, para o leitor de tela anunciar.
watch([enviada, erro], async ([foi]) => {
  await nextTick();
  if (corpo.value) corpo.value.scrollTop = 0;
  if (foi) entrar();
});

// Os canais chegam depois de a gaveta abrir. Quando chegam, o foco vai para
// onde a pessoa vai agir (o campo da mensagem, ou a primeira opção).
watch(carregandoCanais, carregando => {
  if (!carregando && aberta.value) entrarSeLivre();
});

// Um seletor aberto por cima da gaveta (mensagem pronta do Twilio, sugestão
// de e-mail) trata o próprio Esc; a gaveta não fecha por baixo dele.
const SOBREPOSTOS =
  '[data-popover-content], dialog.ProseMirror-prompt-backdrop';

useKeyboardEvents({
  Escape: {
    action: evento => {
      if (!aberta.value || evento.target?.closest?.(SOBREPOSTOS)) return;
      fechar();
    },
    allowOnFocusedInput: true,
  },
});

// A gaveta cobre o canto do lançador do Guia; sinaliza que está aberta.
useFixedPanelPresence(aberta);
</script>

<template>
  <span class="inline-flex" @click="alternar">
    <slot name="trigger" :is-open="aberta" :toggle="alternar" />
  </span>

  <TeleportWithDirection to="body">
    <transition
      enter-active-class="transition-opacity duration-200 ease-out"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-150 ease-in"
      leave-to-class="opacity-0"
    >
      <div
        v-if="aberta"
        data-nova-conversa-fundo
        aria-hidden="true"
        class="fixed inset-0 z-40 bg-n-alpha-black1"
        @click="fechar"
      />
    </transition>
    <transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
      leave-active-class="transition duration-150 ease-in"
      leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
    >
      <div
        v-if="aberta"
        ref="raiz"
        data-nova-conversa-gaveta
        role="dialog"
        aria-modal="true"
        :aria-labelledby="tituloId"
        class="fixed inset-y-0 z-50 flex h-full w-[72rem] max-w-full flex-col overflow-hidden bg-n-solid-1 shadow-2xl ltr:right-0 rtl:left-0"
        @keydown="aoTeclar"
      >
        <NovaConversaHeroi
          :titulo-id="tituloId"
          :migalha="migalha"
          :titulo="titulo"
          :texto="frase"
          @fechar="fechar"
        />

        <div ref="corpo" class="min-h-0 flex-1 overflow-y-auto">
          <NovaConversaEnviada
            v-if="tela === TELAS.ENVIADA"
            :texto="enviada.texto"
            :email="enviada.email"
            :assunto="enviada.assunto"
            :chave-do-canal="enviada.chaveDoCanal"
            :caixa="enviada.caixa"
            :endereco="enviada.endereco"
            :numero="enviada.numero"
          />
          <div
            v-else
            class="grid min-h-full grid-cols-[minmax(0,1fr)]"
            :class="{
              'lg:grid-cols-[minmax(0,1fr)_26rem]': tela === TELAS.ESCREVENDO,
            }"
          >
            <main
              class="flex min-w-0 flex-col gap-6 px-5 py-7 sm:px-8"
              :class="{
                'mx-auto w-full max-w-3xl': tela !== TELAS.ESCREVENDO,
              }"
            >
              <NovaConversaErro v-if="erro" :texto="erro" />

              <NovaConversaParaQuem
                v-if="!contactId"
                :contato="contato"
                :termo="termo"
                :resultados="resultados"
                :buscando="buscando"
                :erro-na-busca="erroNaBusca"
                :criando="criando"
                :erro-ao-criar="erroAoCriar"
                @buscar="mudarTermo"
                @escolher="escolherContato"
                @criar="criarContato"
                @alterar="limparContato"
              />

              <NovaConversaSemCanal
                v-if="tela === TELAS.SEM_CANAL"
                :nome="primeiroNome(nome)"
                @completar="completarCadastro"
              />
              <NovaConversaPorOnde
                v-else-if="contato"
                v-model="canalId"
                :canais="canais"
                :carregando="carregandoCanais"
                :erro="erroNosCanais"
                @tentar="carregarCanais"
              />

              <NovaConversaOndeEntra
                v-if="canal && conversaExistente"
                v-model="escolha"
                :conversa="conversaExistente"
                :carregando="continuando && carregandoConversa"
                :erro="continuando && erroNaConversa"
                @tentar="carregarConversa"
              />

              <NovaConversaMensagem
                v-if="canal && !esperandoConversa"
                ref="blocoDaMensagem"
                :key="`${canal.id}-${tipo}`"
                v-model:modo="form.modo"
                v-model:mensagem="form.mensagem"
                v-model:assunto="form.assunto"
                v-model:cc="form.cc"
                v-model:bcc="form.bcc"
                v-model:anexos="form.anexos"
                v-model:modelo="form.modelo"
                :canal="canal"
                :tipo="tipo"
                :assinatura="assinatura"
                :com-assinatura="comAssinatura"
                :pode-criar-pronta="podeCriarPronta"
                :continuando="continuando"
                @update:campos-prontos="form.camposProntos = $event"
                @update:texto-do-modelo="form.textoDoModelo = $event"
                @enviar-pronta="enviarPronta"
                @criar-pronta="criarPronta"
              />
            </main>

            <aside
              v-if="tela === TELAS.ESCREVENDO"
              class="min-w-0 border-t border-n-weak bg-n-alpha-1 px-5 py-7 sm:px-8 lg:border-s lg:border-t-0 lg:px-5"
            >
              <NovaConversaPrevia
                :nome="nome"
                :email="tipo === TIPOS.EMAIL"
                :texto="previa"
                :assunto="continuando ? '' : form.assunto"
                :remetente="canal?.name || ''"
                :endereco-do-remetente="linhaDoCanal(canal)"
              />
            </aside>
          </div>
        </div>

        <NovaConversaRodape
          :modo="modoDoRodape"
          :falta="falta"
          :enviando="enviando"
          @cancelar="cancelar"
          @enviar="mandar"
          @abrir="abrirConversa"
          @fechar="fechar"
        />
      </div>
    </transition>
  </TeleportWithDirection>
</template>
