<script setup>
// Janela "Encaminhar mensagem para" (#1702), como no WhatsApp Web: "✕" e título,
// busca com a borda verde, "Conversas recentes" com avatar, nome e a última linha,
// caixinha em cada linha (até 5) e, com alguém marcado, o rodapé com os nomes e o
// botão redondo de enviar. Cada destino volta com o seu resultado; fora da janela
// de 24 h o servidor não manda e diz por quê: a janela fica aberta só com os destinos
// que falharam marcados, e o motivo de cada um aparece nela. Teclado: o Tab fica
// dentro da janela e, ao fechar (✕, Esc, clique fora ou envio), o foco volta para
// onde estava ou, se aquilo sumiu, para a caixa de resposta.
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import CaixinhaDoWhatsapp from './CaixinhaDoWhatsapp.vue';
import { LIMITE_DE_DESTINOS } from './selecaoParaEncaminhar';
import { resumoDoEnvio } from './resultadoDoEncaminhar';

const props = defineProps({
  conversationId: { type: Number, required: true },
  messageIds: { type: Array, required: true },
});
const emit = defineEmits(['fechar', 'enviado']);
const { t } = useI18n();

const ESPERA_DA_BUSCA = 300;
const FOCAVEIS =
  'button:not([disabled]), input:not([disabled]), [href], [tabindex]:not([tabindex="-1"])';
// Ponto estável para o foco quando quem abriu a janela sumiu: a caixa de resposta.
const CAIXA_DE_RESPOSTA = '[data-conversa-da-pele] [contenteditable="true"]';

const termo = ref('');
const conversas = ref([]);
const carregando = ref(false);
const enviando = ref(false);
const escolhidas = ref([]);
const campo = ref(null);
const janela = ref(null);
// Destinos que falharam no último envio ({ id, nome, erro }) e se algum já foi.
const falhas = ref([]);
const algumJaFoi = ref(false);
let pedidoAtual = 0;
let focoAnterior = null;

const buscar = async () => {
  pedidoAtual += 1;
  const pedido = pedidoAtual;
  carregando.value = true;
  try {
    const { data } = await ConversaCanalAPI.destinosParaEncaminhar(
      termo.value.trim()
    );
    if (pedido === pedidoAtual) conversas.value = data.payload || [];
  } catch {
    if (pedido === pedidoAtual) conversas.value = [];
  } finally {
    if (pedido === pedidoAtual) carregando.value = false;
  }
};
// A busca adiada que venceria depois de a janela fechar não sai (o useDebounceFn
// não tem cancelar).
let fechada = false;
const buscarDepois = useDebounceFn(() => {
  if (!fechada) buscar();
}, ESPERA_DA_BUSCA);

const marcada = id => escolhidas.value.some(item => item.id === id);

const alternar = conversa => {
  if (marcada(conversa.id)) {
    escolhidas.value = escolhidas.value.filter(item => item.id !== conversa.id);
    return;
  }
  if (escolhidas.value.length >= LIMITE_DE_DESTINOS) {
    useAlert(
      t('CONVERSA_CANAL.ENCAMINHAR.LIMITE_DESTINOS', {
        limite: LIMITE_DE_DESTINOS,
      })
    );
    return;
  }
  escolhidas.value = [...escolhidas.value, conversa];
};

const nomesEscolhidos = computed(() =>
  escolhidas.value.map(item => item.nome).join(', ')
);

// Fechar depois de um envio parcial conta como enviado: o que foi não volta à seleção.
const fechar = () => {
  if (algumJaFoi.value) emit('enviado');
  else emit('fechar');
};

const enviar = async () => {
  if (enviando.value || !escolhidas.value.length) return;
  enviando.value = true;
  try {
    const { data } = await ConversaCanalAPI.encaminhar(
      props.conversationId,
      props.messageIds,
      escolhidas.value.map(item => item.id)
    );
    const resumo = resumoDoEnvio(data.payload, escolhidas.value);
    if (resumo.algumEnviado) {
      algumJaFoi.value = true;
      useAlert(t('CONVERSA_CANAL.ENCAMINHAR.ENVIADO', props.messageIds.length));
    }
    if (!resumo.falhas.length && resumo.algumEnviado) {
      falhas.value = [];
      emit('enviado');
      return;
    }
    if (!resumo.falhas.length) {
      useAlert(t('CONVERSA_CANAL.ENCAMINHAR.FALHOU'));
      return;
    }
    // Só os que falharam continuam marcados, para tentar de novo.
    const idsQueFalharam = resumo.falhas.map(falha => falha.id);
    escolhidas.value = escolhidas.value.filter(item =>
      idsQueFalharam.includes(item.id)
    );
    falhas.value = resumo.falhas;
  } catch (erro) {
    useAlert(
      erro?.response?.data?.error || t('CONVERSA_CANAL.ENCAMINHAR.FALHOU')
    );
  } finally {
    enviando.value = false;
  }
};

// Tab e Shift+Tab dão a volta dentro da janela, sem sair para a tela de trás.
const prenderTab = evento => {
  const focaveis = Array.from(janela.value?.querySelectorAll(FOCAVEIS) || []);
  if (!focaveis.length) return;
  const primeiro = focaveis[0];
  const ultimo = focaveis[focaveis.length - 1];
  const naPonta = evento.shiftKey ? primeiro : ultimo;
  if (document.activeElement !== naPonta) return;
  evento.preventDefault();
  (evento.shiftKey ? ultimo : primeiro).focus();
};

onMounted(async () => {
  focoAnterior = document.activeElement;
  buscar();
  await nextTick();
  campo.value?.focus();
});

// Quem abriu a janela pode ter sumido (o envio fecha o modo seleção): aí o foco vai
// para a caixa de resposta, que reaparece no mesmo ciclo, e não cai no body.
onBeforeUnmount(() => {
  fechada = true;
  if (focoAnterior?.isConnected) {
    focoAnterior.focus();
    return;
  }
  nextTick(() => document.querySelector(CAIXA_DE_RESPOSTA)?.focus());
});
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-[#000]/40"
      data-janela-de-encaminhar
      @click.self="fechar"
      @keydown.esc.stop="fechar"
    >
      <div
        ref="janela"
        role="dialog"
        aria-modal="true"
        aria-labelledby="titulo-encaminhar"
        class="flex flex-col w-full max-w-[520px] max-h-[min(720px,90vh)] overflow-hidden rounded-2xl bg-white dark:bg-[#161717] text-[#0A0A0A] dark:text-[#FAFAFA] shadow-[0_17px_50px_rgba(11,20,26,0.19),0_12px_15px_rgba(11,20,26,0.24)]"
        @keydown.tab="prenderTab"
      >
        <div class="flex items-center gap-4 px-4 pt-4 pb-2">
          <button
            type="button"
            class="grid place-content-center size-11 rounded-full text-[#54656F] dark:text-[#AEBAC1] hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5"
            :aria-label="t('CONVERSA_CANAL.ENCAMINHAR.FECHAR')"
            @click="fechar"
          >
            <Icon icon="i-ph-x" class="size-6" />
          </button>
          <h2 id="titulo-encaminhar" class="text-[19px] leading-6 font-medium">
            {{ t('CONVERSA_CANAL.ENCAMINHAR.TITULO') }}
          </h2>
        </div>

        <div class="px-4 py-2">
          <label
            class="flex items-center gap-3 h-11 px-4 rounded-full border-2 border-[#1DAA61] bg-white dark:bg-[#242626] focus-within:outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-[#1DAA61]"
          >
            <Icon
              icon="i-ph-magnifying-glass"
              class="size-5 shrink-0 text-[#54656F] dark:text-[#AEBAC1]"
            />
            <input
              ref="campo"
              v-model="termo"
              type="search"
              class="flex-1 min-w-0 !mb-0 !p-0 !border-0 !bg-transparent !shadow-none !outline-none text-[15px] placeholder:text-[#667781] dark:placeholder:text-[#8696A0]"
              :placeholder="t('CONVERSA_CANAL.ENCAMINHAR.BUSCAR')"
              :aria-label="t('CONVERSA_CANAL.ENCAMINHAR.BUSCAR')"
              @input="buscarDepois"
            />
          </label>
        </div>

        <div class="flex-1 min-h-[240px] overflow-y-auto pb-2">
          <p
            class="px-6 pt-3 pb-2 text-[15px] text-[#008069] dark:text-[#21C063]"
          >
            {{ t('CONVERSA_CANAL.ENCAMINHAR.RECENTES') }}
          </p>
          <p
            v-if="carregando && !conversas.length"
            class="px-6 py-4 text-sm text-[#667781] dark:text-[#8696A0]"
          >
            {{ t('CONVERSA_CANAL.ENCAMINHAR.CARREGANDO') }}
          </p>
          <p
            v-else-if="!conversas.length"
            class="px-6 py-4 text-sm text-[#667781] dark:text-[#8696A0]"
          >
            {{ t('CONVERSA_CANAL.ENCAMINHAR.NADA') }}
          </p>
          <ul v-else class="list-none m-0 p-0">
            <li v-for="conversa in conversas" :key="conversa.id">
              <button
                type="button"
                role="checkbox"
                class="flex items-center gap-4 w-full min-h-[72px] px-6 text-start hover:bg-[#0A0A0A]/[0.04] dark:hover:bg-white/[0.04] focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-[#1DAA61]"
                :aria-checked="marcada(conversa.id)"
                data-destino
                @click="alternar(conversa)"
              >
                <CaixinhaDoWhatsapp :marcada="marcada(conversa.id)" />
                <Avatar
                  :name="conversa.nome"
                  :src="conversa.avatar || ''"
                  :size="49"
                  rounded-full
                />
                <span
                  class="flex flex-col flex-1 min-w-0 py-3 border-b border-[#000]/[0.06] dark:border-white/[0.06]"
                >
                  <span class="text-[17px] leading-[21px] truncate">
                    {{ conversa.nome }}
                  </span>
                  <span
                    class="text-sm leading-5 truncate text-[#667781] dark:text-[#8696A0]"
                  >
                    {{ conversa.ultima_linha || conversa.caixa }}
                  </span>
                </span>
              </button>
            </li>
          </ul>
        </div>

        <div
          v-if="falhas.length"
          role="alert"
          class="px-6 py-3 text-sm bg-[#FDECEA] dark:bg-[#3A1D1D] text-[#8B1A10] dark:text-[#F5B7B1]"
          data-falhas-do-encaminhar
        >
          <p class="m-0 font-medium">
            {{ t('CONVERSA_CANAL.ENCAMINHAR.NAO_FOI') }}
          </p>
          <ul class="m-0 mt-1 ps-4 list-disc">
            <li v-for="falha in falhas" :key="falha.id">
              {{ t('CONVERSA_CANAL.ENCAMINHAR.DESTINO_FALHOU', falha) }}
            </li>
          </ul>
        </div>

        <div
          v-if="escolhidas.length"
          class="flex items-center gap-4 min-h-[72px] ltr:pl-6 ltr:pr-4 rtl:pr-6 rtl:pl-4 bg-[#F7F5F3] dark:bg-[#1D1F1F]"
          data-rodape-de-encaminhar
        >
          <span
            class="flex-1 min-w-0 truncate text-[15px] text-[#3B4A54] dark:text-[#D1D7DB]"
          >
            {{ nomesEscolhidos }}
          </span>
          <button
            type="button"
            class="grid place-content-center size-[52px] shrink-0 rounded-full bg-[#1DAA61] text-white hover:bg-[#1A9956] disabled:opacity-60"
            :disabled="enviando"
            :aria-label="t('CONVERSA_CANAL.ENCAMINHAR.ENVIAR')"
            data-enviar-encaminhamento
            @click="enviar"
          >
            <Icon icon="i-ph-paper-plane-right-fill" class="size-6" />
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
