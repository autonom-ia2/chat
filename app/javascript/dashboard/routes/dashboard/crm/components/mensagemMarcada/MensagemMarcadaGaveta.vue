<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import PreviaMoldura from '../funil/previas/PreviaMoldura.vue';
import PreviaWhatsapp from 'dashboard/components-next/whatsapp-preview/PreviaWhatsapp.vue';
import NovaConversaCartao from 'dashboard/components-next/NovaConversa/NovaConversaCartao.vue';
import { nomeLegivel } from 'dashboard/components-next/NovaConversa/novaConversa';
import CardHeroi from '../card/CardHeroi.vue';
import CardRodape from '../card/CardRodape.vue';
import { useFocoPreso } from '../card/useFocoPreso';
import { formatarDia, minutosDoDia } from '../calendario/tempoNaConta';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import PassoParaQuem from './PassoParaQuem.vue';
import PassoQuando from './PassoQuando.vue';
import PassoMensagem from './PassoMensagem.vue';
import MensagemMarcadaConfirmar from './MensagemMarcadaConfirmar.vue';
import { PASSOS, useMensagemMarcada } from './useMensagemMarcada';

// #1590 — "Mensagem marcada" na gaveta da casa: topo escuro, uma decisão por
// passo à esquerda (o que já foi decidido vira frase com "Alterar") e, à
// direita, o balão do WhatsApp como o cliente vai ver, com o dia e a hora.
// Para quem → Quando → O que dizer → Confira. Abre pelo "+ Novo" do
// calendário (com o dia clicado) e, com `card`, pelo negócio (pula o
// "Para quem"). Vai para o body: aberta de dentro do card, fica por cima dele.
const props = defineProps({
  show: { type: Boolean, default: false },
  dia: { type: String, default: '' },
  card: { type: Object, default: null },
  // As caixas da conta que a tela já carregou.
  caixas: { type: Array, default: () => [] },
});
const emit = defineEmits(['close', 'salvou', 'abrirNegocio']);

const { t, locale } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();
const fuso = computed(() => fusoDaConta(currentAccount.value));
const idioma = computed(() => locale.value.replace('_', '-'));
const gavetaId = `mensagem-marcada-${useId()}`;
const M = 'CRM_MENSAGEM_MARCADA';

const m = useMensagemMarcada({
  store,
  fuso,
  caixasDaTela: computed(() => props.caixas),
});
const passoMensagem = ref(null);
const montada = ref(null);
const corpo = ref(null);

const comecar = () => {
  m.reiniciar({ dia: props.dia > m.hoje() ? props.dia : '' });
  montada.value = null;
  if (props.card) m.escolherAlvo(props.card);
};
watch(
  () => props.show,
  aberta => {
    if (aberta) {
      store.dispatch('inboxes/get');
      comecar();
    }
  },
  { immediate: true }
);

const fechar = () => emit('close');
const numero = computed(() => PASSOS.indexOf(m.passo.value) + 1);
const pronto = computed(() => Boolean(m.feita.value));

const quandoEmFrase = computed(() => {
  const { dia, hora } = m.quando.value;
  if (!dia) return '';
  let nomeDoDia = formatarDia(dia, idioma.value, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
  if (dia === m.hoje()) nomeDoDia = t(`${M}.QUANDO.HOJE_FRASE`);
  if (dia === m.amanha()) nomeDoDia = t(`${M}.QUANDO.AMANHA_FRASE`);
  return hora ? t(`${M}.QUANDO.FRASE`, { dia: nomeDoDia, hora }) : nomeDoDia;
});

const heroi = computed(() => {
  const nome = m.alvo.value?.primeiroNome || '';
  if (pronto.value)
    return {
      titulo: t(`${M}.PRONTO.TITULO`, { nome }),
      texto: t(`${M}.PRONTO.TEXTO`, { quando: quandoEmFrase.value }),
    };
  const chave = m.passo.value.toUpperCase().replace('-', '_');
  return {
    titulo: t(`${M}.${chave}.TITULO`, { nome }),
    texto: t(`${M}.PASSO_DE`, { numero: numero.value, total: PASSOS.length }),
  };
});

const passou = nome =>
  pronto.value || PASSOS.indexOf(m.passo.value) > PASSOS.indexOf(nome);

const fechadaPeloCard = computed(() => Boolean(props.card));
// De onde a pessoa veio: o calendário, ou o card (pelo nome do cliente).
const migalha = computed(() => [
  fechadaPeloCard.value
    ? props.card.contact?.name || props.card.title
    : t(`${M}.MIGALHA`),
]);

const textoDaPrevia = computed(() => m.textoQueSai.value);
const PALAVRAS_DO_RESUMO = 6;
const inicioDoTexto = computed(() => {
  const palavras = m.textoQueSai.value.split(' ').filter(Boolean);
  const inicio = palavras.slice(0, PALAVRAS_DO_RESUMO).join(' ');
  return palavras.length > PALAVRAS_DO_RESUMO ? `${inicio}…` : inicio;
});
const avancar = () => {
  if (m.passo.value === 'mensagem' && m.soPronta.value)
    montada.value = passoMensagem.value?.montar() ?? null;
  m.avancar();
};
const marcar = async () => {
  const foi = await m.criar({
    titulo: t(`${M}.TITULO_LEMBRETE`, { nome: m.alvo.value.nome }),
    montada: montada.value,
  });
  if (foi) emit('salvou');
};

const voltar = () => {
  const indice = PASSOS.indexOf(m.passo.value);
  if (indice <= 0 || (indice === 1 && fechadaPeloCard.value)) {
    fechar();
    return;
  }
  m.voltarPara(PASSOS[indice - 1]);
};

const rodape = computed(() => {
  if (pronto.value)
    return {
      secundaria: fechadaPeloCard.value
        ? null
        : {
            rotulo: t(`${M}.PRONTO.ABRIR_NEGOCIO`),
            acao: () => emit('abrirNegocio', m.alvo.value.cardId),
          },
      principal: { rotulo: t(`${M}.PRONTO.FECHAR`), acao: fechar },
    };
  const confirmar = m.passo.value === 'confirmar';
  const primeiro =
    m.passo.value === 'para-quem' ||
    (m.passo.value === 'quando' && fechadaPeloCard.value);
  return {
    falta: m.faltaNoPasso.value ? t(`${M}.FALTA.${m.faltaNoPasso.value}`) : '',
    secundaria: {
      rotulo: primeiro ? t(`${M}.CANCELAR`) : t(`${M}.VOLTAR`),
      acao: voltar,
    },
    principal:
      m.passo.value === 'para-quem'
        ? null
        : {
            rotulo: confirmar ? t(`${M}.MARCAR`) : t(`${M}.CONTINUAR`),
            icone: confirmar ? 'i-lucide-check' : 'i-lucide-arrow-right',
            depois: !confirmar,
            acao: confirmar ? marcar : avancar,
            carregando: m.salvando.value,
            desabilitado: Boolean(m.faltaNoPasso.value) || m.salvando.value,
          },
  };
});

const raiz = ref(null);
const { prender } = useFocoPreso({ raiz, mostrar: computed(() => props.show) });
watch([m.passo, m.feita], async () => {
  await nextTick();
  if (corpo.value) corpo.value.scrollTop = 0;
  raiz.value?.querySelector('[data-foco]')?.focus();
});
</script>

<template>
  <TeleportWithDirection to="body">
    <transition
      enter-active-class="transition-opacity duration-200 ease-out"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-150 ease-in"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        aria-hidden="true"
        class="fixed inset-0 z-[55] bg-n-alpha-black1 backdrop-blur-[1px]"
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
        v-if="show"
        ref="raiz"
        data-mensagem-marcada
        :data-passo-atual="pronto ? 'pronto' : m.passo.value"
        role="dialog"
        aria-modal="true"
        :aria-labelledby="`${gavetaId}-titulo`"
        tabindex="-1"
        class="fixed inset-y-0 z-[60] flex h-full w-[72rem] max-w-full flex-col overflow-hidden bg-n-solid-1 shadow-2xl outline-none ltr:right-0 rtl:left-0"
        @keydown="prender"
        @keydown.esc.stop="fechar"
      >
        <CardHeroi
          :rotulo="t(`${M}.ROTULO`)"
          icone="i-lucide-send"
          :titulo="heroi.titulo"
          :texto="heroi.texto"
          :migalha="migalha"
          :titulo-id="`${gavetaId}-titulo`"
          :texto-id="`${gavetaId}-texto`"
          @fechar="fechar"
        />
        <div ref="corpo" class="min-h-0 flex-1 overflow-y-auto">
          <div
            class="grid min-h-full grid-cols-[minmax(0,1fr)] lg:grid-cols-[minmax(0,1fr)_26rem]"
          >
            <main class="flex min-w-0 flex-col gap-4 px-5 py-6 sm:px-8">
              <div
                v-if="pronto"
                data-mensagem-pronta
                class="flex items-start gap-4 rounded-2xl border border-n-teal-6 bg-n-teal-2 p-4"
              >
                <span
                  class="grid size-11 shrink-0 place-items-center rounded-full bg-n-teal-9 text-white"
                  aria-hidden="true"
                >
                  <span class="i-lucide-check size-6" />
                </span>
                <span class="flex flex-col gap-1">
                  <span class="text-base font-semibold text-n-slate-12">
                    {{ t(`${M}.PRONTO.FRASE`, { quando: quandoEmFrase }) }}
                  </span>
                  <span class="text-sm text-n-slate-11">
                    {{ t(`${M}.PRONTO.ONDE`) }}
                  </span>
                </span>
              </div>

              <NovaConversaCartao
                v-if="passou('para-quem') && m.alvo.value"
                data-resumo="para-quem"
                icone="i-lucide-user-round"
                tom="bg-n-teal-3 text-n-teal-11"
                :titulo="t(`${M}.PARA_QUEM.RESUMO`)"
                :sem-alterar="pronto || fechadaPeloCard"
                @alterar="m.voltarPara('para-quem')"
              >
                <strong class="font-semibold">{{ m.alvo.value.nome }}</strong>
                <span v-if="m.alvo.value.negocio">
                  {{
                    `\u00A0${t(`${M}.PARA_QUEM.NEGOCIO`, { negocio: m.alvo.value.negocio })}`
                  }}
                </span>
              </NovaConversaCartao>
              <NovaConversaCartao
                v-if="passou('quando')"
                data-resumo="quando"
                icone="i-lucide-calendar-clock"
                :titulo="t(`${M}.QUANDO.RESUMO`)"
                :sem-alterar="pronto"
                @alterar="m.voltarPara('quando')"
              >
                <strong class="font-semibold first-letter:uppercase">
                  {{ quandoEmFrase }}
                </strong>
              </NovaConversaCartao>
              <NovaConversaCartao
                v-if="passou('mensagem')"
                data-resumo="mensagem"
                icone="i-lucide-message-square-text"
                tom="bg-n-iris-3 text-n-iris-11"
                :titulo="t(`${M}.MENSAGEM.RESUMO`)"
                :sem-alterar="pronto"
                @alterar="m.voltarPara('mensagem')"
              >
                <template v-if="m.soPronta.value && m.mensagem.value.modelo">
                  {{ t(`${M}.MENSAGEM.RESUMO_PRONTA`) }}
                  <strong class="font-semibold">
                    {{ nomeLegivel(m.mensagem.value.modelo.name) }}
                  </strong>
                </template>
                <template v-else>
                  {{
                    t(`${M}.MENSAGEM.RESUMO_TEXTO`, { inicio: inicioDoTexto })
                  }}
                </template>
              </NovaConversaCartao>

              <template v-if="!pronto">
                <PassoParaQuem
                  v-if="m.passo.value === 'para-quem'"
                  :para-alvo="m.paraAlvo"
                  @escolher="m.escolherAlvo"
                  @abrir-negocio="id => emit('abrirNegocio', id)"
                />
                <PassoQuando
                  v-else-if="m.passo.value === 'quando'"
                  v-model="m.quando.value"
                  :hoje="m.hoje()"
                  :agora-minutos="minutosDoDia(new Date(), fuso)"
                  :fuso="fuso"
                  :no-passado="m.noPassado.value"
                />
                <PassoMensagem
                  v-else-if="m.passo.value === 'mensagem'"
                  ref="passoMensagem"
                  v-model="m.mensagem.value"
                  :nome="m.alvo.value?.primeiroNome || ''"
                  :carregando="m.carregandoJanela.value"
                  :erro="m.erroNaJanela.value"
                  :so-pronta="m.soPronta.value"
                  :pelo-celular="m.peloCelular.value"
                  :modelos="m.modelos.value"
                  @tentar="m.carregarJanela"
                  @update:texto-do-modelo="m.textoDoModelo.value = $event"
                  @update:campos-prontos="m.camposProntos.value = $event"
                />
                <MensagemMarcadaConfirmar
                  v-else
                  v-model="m.anotacao.value"
                  :alvo="m.alvo.value"
                  :pelo-celular="m.peloCelular.value"
                  :erro="m.erro.value"
                />
              </template>
            </main>
            <aside
              data-mensagem-previa
              class="min-w-0 border-t border-n-weak bg-n-alpha-1 px-5 py-7 sm:px-8 lg:border-s lg:border-t-0 lg:px-6"
            >
              <PreviaMoldura
                class="lg:sticky lg:top-7"
                :titulo="
                  m.alvo.value
                    ? t(`${M}.PREVIA.TITULO`, {
                        nome: m.alvo.value.primeiroNome,
                      })
                    : t(`${M}.PREVIA.TITULO_SEM_NOME`)
                "
                :texto="t(`${M}.PREVIA.TEXTO`)"
              >
                <PreviaWhatsapp
                  :texto="textoDaPrevia"
                  :nome-do-remetente="m.alvo.value?.caixaNome || ''"
                  :fantasma="t(`${M}.PREVIA.FANTASMA`)"
                  :hora="m.quando.value.hora || t(`${M}.PREVIA.SEM_HORA`)"
                >
                  <template #cabecalho>
                    {{ quandoEmFrase || t(`${M}.PREVIA.SEM_DIA`) }}
                  </template>
                </PreviaWhatsapp>
              </PreviaMoldura>
            </aside>
          </div>
        </div>
        <CardRodape :rodape="rodape" :ocupado="m.salvando.value" />
      </div>
    </transition>
  </TeleportWithDirection>
</template>
