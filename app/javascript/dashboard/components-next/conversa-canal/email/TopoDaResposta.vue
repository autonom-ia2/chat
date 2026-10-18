<script setup>
// Topo da caixa de resposta do e-mail (#1786): o tipo de resposta escrito por extenso
// (Responder, Responder a todos, Encaminhar ou Nota privada) num menu, e à direita
// Aumentar, Abrir em janela e Fechar. Na conversa de e-mail nova ele ocupa o lugar do
// alternador Responder / Mensagem Privada do Chatwoot.
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';
import {
  MODOS_DE_RESPOSTA,
  TAMANHOS,
  useEmailDaConversa,
} from './useConversaDeEmail';

const props = defineProps({
  modo: { type: String, default: MODOS_DE_RESPOSTA.TODOS },
});
const emit = defineEmits(['trocarModo']);

const { t } = useI18n();
const email = useEmailDaConversa();

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
  { modo: MODOS_DE_RESPOSTA.NOTA, chave: 'NOTA_PRIVADA', icone: 'i-lucide-lock' },
];
const atual = computed(
  () => MODOS.find(item => item.modo === props.modo) || MODOS[1]
);
const ehNota = computed(() => props.modo === MODOS_DE_RESPOSTA.NOTA);

const aberto = ref(false);
const menu = useTemplateRef('menu');
const botao = useTemplateRef('botao');
const alternar = async () => {
  aberto.value = !aberto.value;
  if (!aberto.value) return;
  await nextTick();
  menu.value?.querySelector('[aria-checked=true]')?.focus();
};
const escolher = modo => {
  aberto.value = false;
  botao.value?.focus();
  emit('trocarModo', modo);
};

const expandida = computed(() => email.tamanho.value === TAMANHOS.EXPANDIDA);
const emJanela = computed(() => email.tamanho.value === TAMANHOS.JANELA);

const ICONE =
  'grid place-content-center size-10 rounded-full text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <div
    class="flex items-center justify-between gap-2 min-h-14 ps-2 pe-2 pt-2"
    data-topo-da-resposta
  >
    <div class="relative flex items-center gap-2 min-w-0">
      <button
        ref="botao"
        type="button"
        class="inline-flex items-center gap-2 min-h-10 ps-3 pe-2 rounded-full text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-label="t('CONVERSA_CANAL.EMAIL.TIPO_DE_RESPOSTA')"
        :aria-expanded="aberto"
        aria-haspopup="menu"
        data-tipo-de-resposta
        @click="alternar"
      >
        <Icon :icon="atual.icone" class="size-[18px] text-n-slate-11" />
        {{ t(`CONVERSA_CANAL.EMAIL.${atual.chave}`) }}
        <Icon icon="i-lucide-chevron-down" class="size-4 text-n-slate-11" />
      </button>
      <span
        v-if="ehNota"
        class="truncate text-xs text-n-amber-11"
        data-aviso-da-nota
      >
        {{ t('CONVERSA_CANAL.EMAIL.SO_A_EQUIPE') }}
      </span>
      <ul
        v-if="aberto"
        ref="menu"
        v-on-click-outside="[() => (aberto = false), { ignore: [botao] }]"
        role="menu"
        class="reset-base list-none absolute top-full start-0 mt-1 z-40 w-60 py-1 rounded-xl bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak shadow-lg"
        @keydown.esc.prevent.stop="escolher(modo)"
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
            :data-tipo="item.modo"
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
    <div class="flex items-center gap-0.5 flex-shrink-0">
      <button
        type="button"
        :class="ICONE"
        :aria-label="
          expandida
            ? t('CONVERSA_CANAL.EMAIL.DIMINUIR')
            : t('CONVERSA_CANAL.EMAIL.AUMENTAR')
        "
        :title="
          expandida
            ? t('CONVERSA_CANAL.EMAIL.DIMINUIR')
            : t('CONVERSA_CANAL.EMAIL.AUMENTAR')
        "
        :aria-pressed="expandida"
        data-aumentar-resposta
        @click="email.alternarTamanho(TAMANHOS.EXPANDIDA)"
      >
        <Icon
          :icon="expandida ? 'i-lucide-minimize-2' : 'i-lucide-maximize-2'"
          class="size-[18px]"
        />
      </button>
      <button
        type="button"
        :class="[ICONE, 'hidden sm:grid']"
        :aria-label="
          emJanela
            ? t('CONVERSA_CANAL.EMAIL.VOLTAR_PARA_A_CONVERSA')
            : t('CONVERSA_CANAL.EMAIL.ABRIR_EM_JANELA')
        "
        :title="
          emJanela
            ? t('CONVERSA_CANAL.EMAIL.VOLTAR_PARA_A_CONVERSA')
            : t('CONVERSA_CANAL.EMAIL.ABRIR_EM_JANELA')
        "
        :aria-pressed="emJanela"
        data-janela-resposta
        @click="email.alternarTamanho(TAMANHOS.JANELA)"
      >
        <Icon
          :icon="
            emJanela ? 'i-lucide-panel-bottom' : 'i-lucide-picture-in-picture-2'
          "
          class="size-[18px]"
        />
      </button>
      <button
        type="button"
        :class="ICONE"
        :aria-label="t('CONVERSA_CANAL.EMAIL.FECHAR_RESPOSTA')"
        :title="t('CONVERSA_CANAL.EMAIL.FECHAR_RESPOSTA')"
        data-fechar-resposta
        @click="email.fecharResposta"
      >
        <Icon icon="i-lucide-x" class="size-[18px]" />
      </button>
    </div>
  </div>
</template>
