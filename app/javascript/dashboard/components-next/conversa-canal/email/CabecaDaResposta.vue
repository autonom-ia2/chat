<script setup>
// Cabeçalho da resposta na conversa de e-mail nova (#1786), como no leitor de e-mail:
// o tipo de resposta (Responder / Responder a todos / Encaminhar) num menu e os
// campos Para, Cc e Cco. "Para" sempre aparece (no Encaminhar ele vem vazio); Cc e
// Cco abrem num toque. Mesmo contrato do ReplyEmailHead (v-model dos três campos),
// então o envio é o de sempre.
import { computed, nextTick, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';
import { validEmailsByComma } from 'dashboard/components/widgets/conversation/helpers/emailHeadHelper';
import { MODOS_DE_RESPOSTA } from './useConversaDeEmail';

const props = defineProps({
  modo: { type: String, default: MODOS_DE_RESPOSTA.TODOS },
});
const emit = defineEmits(['trocarModo']);

const para = defineModel('toEmails', { type: String, default: '' });
const cc = defineModel('ccEmails', { type: String, default: '' });
const cco = defineModel('bccEmails', { type: String, default: '' });

const { t } = useI18n();

const MODOS = [
  {
    modo: MODOS_DE_RESPOSTA.RESPONDER,
    chave: 'RESPONDER',
    icone: 'i-lucide-reply',
  },
  {
    modo: MODOS_DE_RESPOSTA.TODOS,
    chave: 'RESPONDER_TODOS',
    icone: 'i-lucide-reply-all',
  },
  {
    modo: MODOS_DE_RESPOSTA.ENCAMINHAR,
    chave: 'ENCAMINHAR',
    icone: 'i-lucide-forward',
  },
];
const atual = computed(
  () => MODOS.find(item => item.modo === props.modo) || MODOS[1]
);

const menuAberto = ref(false);
const menu = useTemplateRef('menu');
const abrirMenu = async () => {
  menuAberto.value = !menuAberto.value;
  if (!menuAberto.value) return;
  await nextTick();
  menu.value?.querySelector('[role=menuitemradio]')?.focus();
};
const escolher = modo => {
  menuAberto.value = false;
  emit('trocarModo', modo);
};

const verCc = ref(Boolean(cc.value));
const verCco = ref(Boolean(cco.value));
watch(cc, valor => {
  if (valor) verCc.value = true;
});
watch(cco, valor => {
  if (valor) verCco.value = true;
});

const invalido = valor => !validEmailsByComma(valor);

const CAMPO =
  'flex-1 min-w-0 h-9 bg-transparent border-0 outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10 reset-base';
const LINHA =
  'flex items-center gap-2 min-h-10 px-1 border-b border-n-weak focus-within:border-n-brand';
const ROTULO = 'w-10 flex-shrink-0 text-sm text-n-slate-11';
const LINK =
  'min-h-9 px-2 rounded text-sm text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1';
</script>

<template>
  <div class="flex flex-col" data-cabeca-da-resposta>
    <div class="relative flex items-center gap-2 min-h-10">
      <button
        type="button"
        class="inline-flex items-center gap-1 h-9 px-2 rounded-lg text-n-slate-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-label="t('CONVERSA_CANAL.EMAIL.TIPO_DE_RESPOSTA')"
        :aria-expanded="menuAberto"
        aria-haspopup="menu"
        data-tipo-de-resposta
        @click="abrirMenu"
      >
        <Icon :icon="atual.icone" class="size-4" />
        <Icon icon="i-lucide-chevron-down" class="size-3.5" />
      </button>
      <span class="text-sm font-medium text-n-slate-12">
        {{ t(`CONVERSA_CANAL.EMAIL.${atual.chave}`) }}
      </span>
      <ul
        v-if="menuAberto"
        ref="menu"
        v-on-click-outside="() => (menuAberto = false)"
        role="menu"
        class="reset-base list-none absolute top-full mt-1 z-30 w-56 py-1 rounded-xl bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak shadow-lg"
        @keydown.esc.prevent="menuAberto = false"
      >
        <li
          v-for="item in MODOS"
          :key="item.modo"
          role="none"
          class="list-none"
        >
          <button
            type="button"
            role="menuitemradio"
            :aria-checked="item.modo === modo"
            class="flex items-center gap-3 w-full min-h-11 px-3 text-sm text-n-slate-12 hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1 outline-none"
            @click="escolher(item.modo)"
          >
            <Icon :icon="item.icone" class="size-4 text-n-slate-11" />
            <span class="flex-1 text-start">
              {{ t(`CONVERSA_CANAL.EMAIL.${item.chave}`) }}
            </span>
            <Icon
              v-if="item.modo === modo"
              icon="i-lucide-check"
              class="size-4 text-n-brand"
            />
          </button>
        </li>
      </ul>
    </div>

    <label :class="LINHA">
      <span :class="ROTULO">{{ t('CONVERSA_CANAL.EMAIL.PARA') }}</span>
      <input
        v-model="para"
        type="text"
        :class="CAMPO"
        :aria-invalid="invalido(para)"
        :placeholder="t('CONVERSA_CANAL.EMAIL.PARA_EXEMPLO')"
        data-campo-para
      />
      <button
        v-if="!verCc"
        type="button"
        :class="LINK"
        @click.prevent="verCc = true"
      >
        {{ t('CONVERSA_CANAL.EMAIL.CC') }}
      </button>
      <button
        v-if="!verCco"
        type="button"
        :class="LINK"
        @click.prevent="verCco = true"
      >
        {{ t('CONVERSA_CANAL.EMAIL.CCO') }}
      </button>
    </label>
    <label v-if="verCc" :class="LINHA">
      <span :class="ROTULO">{{ t('CONVERSA_CANAL.EMAIL.CC') }}</span>
      <input
        v-model="cc"
        type="text"
        :class="CAMPO"
        :aria-invalid="invalido(cc)"
        data-campo-cc
      />
    </label>
    <label v-if="verCco" :class="LINHA">
      <span :class="ROTULO">{{ t('CONVERSA_CANAL.EMAIL.CCO') }}</span>
      <input
        v-model="cco"
        type="text"
        :class="CAMPO"
        :aria-invalid="invalido(cco)"
        data-campo-cco
      />
    </label>
    <p
      v-if="invalido(para) || invalido(cc) || invalido(cco)"
      class="mt-1 text-xs text-n-ruby-11"
      role="alert"
    >
      {{ t('CONVERSA_CANAL.EMAIL.ENDERECO_INVALIDO') }}
    </p>
  </div>
</template>
