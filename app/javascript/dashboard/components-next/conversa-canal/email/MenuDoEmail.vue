<script setup>
// "⋮" no cabeçalho de cada e-mail (#1786), como no leitor de e-mail: Responder a todos
// e Encaminhar a partir deste e-mail. O Responder fica à vista, ao lado.
import { nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';

const emit = defineEmits(['escolher']);
const { t } = useI18n();

const ITENS = [
  { modo: 'todos', chave: 'RESPONDER_TODOS', icone: 'i-lucide-reply-all' },
  { modo: 'encaminhar', chave: 'ENCAMINHAR', icone: 'i-lucide-forward' },
];

const aberto = ref(false);
const lista = useTemplateRef('lista');
const botao = useTemplateRef('botao');
const alternar = async () => {
  aberto.value = !aberto.value;
  if (!aberto.value) return;
  await nextTick();
  lista.value?.querySelector('[role=menuitem]')?.focus();
};
const fechar = () => {
  aberto.value = false;
  botao.value?.focus();
};
const escolher = modo => {
  aberto.value = false;
  emit('escolher', modo);
};
</script>

<template>
  <div class="relative">
    <button
      ref="botao"
      type="button"
      class="grid place-content-center size-9 rounded-full text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-label="t('CONVERSA_CANAL.EMAIL.MAIS_OPCOES')"
      :title="t('CONVERSA_CANAL.EMAIL.MAIS_OPCOES')"
      :aria-expanded="aberto"
      aria-haspopup="menu"
      data-menu-do-email
      @click="alternar"
    >
      <Icon icon="i-lucide-ellipsis-vertical" class="size-4" />
    </button>
    <ul
      v-if="aberto"
      ref="lista"
      v-on-click-outside="[() => (aberto = false), { ignore: [botao] }]"
      role="menu"
      class="reset-base list-none absolute end-0 top-full mt-1 z-30 w-56 py-1 rounded-xl bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak shadow-lg"
      @keydown.esc.prevent="fechar"
    >
      <li v-for="item in ITENS" :key="item.modo" role="none" class="list-none">
        <button
          type="button"
          role="menuitem"
          class="flex items-center gap-3 w-full min-h-11 px-3 text-sm text-n-slate-12 hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1 outline-none"
          :data-item-do-menu="item.modo"
          @click="escolher(item.modo)"
        >
          <Icon :icon="item.icone" class="size-4 text-n-slate-11" />
          {{ t(`CONVERSA_CANAL.EMAIL.${item.chave}`) }}
        </button>
      </li>
    </ul>
  </div>
</template>
