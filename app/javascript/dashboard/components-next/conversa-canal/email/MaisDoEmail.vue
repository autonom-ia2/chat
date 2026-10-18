<script setup>
// O "+" da resposta de e-mail (#1786), no lugar do clipe, como o do WhatsApp:
// "Documento" escolhe qualquer arquivo; "Fotos e vídeos" abre o seletor já filtrado
// em foto e vídeo. No e-mail os dois viram anexo; o filtro só ajuda a achar o arquivo.
// Arrastar arquivo para a caixa continua funcionando (o campo do Chatwoot fica lá).
// "Modelo de e-mail" aparece quando a conta tem modelo salvo em Campanhas: escolher
// põe o modelo embaixo do texto (decisão do Rodrigo, 18/10: "se o modelo está salvo,
// ele pode usar").
import { computed, nextTick, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import ModelosDeEmailAPI from 'dashboard/api/modelosDeEmail';
import EscolherModeloDoEmail from './EscolherModeloDoEmail.vue';
import { MODELO_DE_CAMPANHA } from './useConversaDeEmail';

const emit = defineEmits(['arquivos']);
const { t } = useI18n();

const ITENS = [
  {
    tipo: 'documento',
    chave: 'DOCUMENTO',
    icone: 'i-ph-file-text-fill',
    cor: 'text-n-iris-10',
    filtro: '',
  },
  {
    tipo: 'fotos',
    chave: 'FOTOS_E_VIDEOS',
    icone: 'i-ph-images-fill',
    cor: 'text-n-blue-10',
    filtro: 'image/*,video/*',
  },
];

const modelos = ref([]);
const carregando = ref(false);
const janela = useTemplateRef('janela');
onMounted(async () => {
  carregando.value = true;
  try {
    const { data } = await ModelosDeEmailAPI.listar();
    modelos.value = data.payload || [];
  } catch {
    modelos.value = [];
  } finally {
    carregando.value = false;
  }
});
const itens = computed(() =>
  modelos.value.length
    ? [
        ...ITENS,
        {
          tipo: 'modelo',
          chave: 'MODELO_DE_EMAIL',
          icone: 'i-ph-layout-fill',
          cor: 'text-n-teal-10',
          separado: true,
        },
      ]
    : ITENS
);

const aberto = ref(false);
const botao = useTemplateRef('botao');
const lista = useTemplateRef('lista');
const seletor = useTemplateRef('seletor');
const filtro = ref('');

const alternar = async () => {
  aberto.value = !aberto.value;
  if (!aberto.value) return;
  await nextTick();
  lista.value?.querySelector('[role=menuitem]')?.focus();
};
const escolher = async item => {
  aberto.value = false;
  if (item.tipo === 'modelo') {
    janela.value?.open();
    return;
  }
  filtro.value = item.filtro;
  await nextTick();
  seletor.value?.click();
};
const escolheu = evento => {
  const arquivos = [...(evento.target.files || [])];
  evento.target.value = '';
  if (arquivos.length) emit('arquivos', { arquivos, comoDocumento: false });
};
const mover = evento => {
  const itens = [...(lista.value?.querySelectorAll('[role=menuitem]') || [])];
  const atual = itens.indexOf(document.activeElement);
  const destino = { ArrowDown: atual + 1, ArrowUp: atual - 1 }[evento.key];
  if (destino === undefined) return;
  evento.preventDefault();
  itens[(destino + itens.length) % itens.length]?.focus();
};
</script>

<template>
  <div class="relative">
    <button
      ref="botao"
      type="button"
      :aria-label="t('CONVERSA_CANAL.EMAIL.ANEXAR')"
      :title="t('CONVERSA_CANAL.EMAIL.ANEXAR')"
      :aria-expanded="aberto"
      aria-haspopup="menu"
      data-mais-do-email
      @click="alternar"
    >
      <Icon
        icon="i-lucide-plus"
        class="size-[22px] transition-transform"
        :class="{ 'rotate-45': aberto }"
      />
    </button>
    <div
      v-if="aberto"
      ref="lista"
      v-on-click-outside="[() => (aberto = false), { ignore: [botao] }]"
      role="menu"
      class="absolute bottom-full start-0 mb-2 z-40 w-60 p-1.5 rounded-2xl bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak shadow-lg"
      @keydown.esc.prevent.stop="aberto = false"
      @keydown="mover"
    >
      <template v-for="item in itens" :key="item.tipo">
      <div v-if="item.separado" role="separator" class="my-1 h-px bg-n-weak" />
      <button
        type="button"
        role="menuitem"
        class="flex items-center gap-3 w-full min-h-11 px-3 rounded-xl text-[15px] text-n-slate-12 text-start outline-none hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1 focus-visible:ring-2 focus-visible:ring-n-brand"
        :data-item-do-mais="item.tipo"
        @click="escolher(item)"
      >
        <Icon :icon="item.icone" class="size-6" :class="item.cor" />
        {{ t(`CONVERSA_CANAL.EMAIL.${item.chave}`) }}
      </button>
      </template>
    </div>
    <input
      ref="seletor"
      type="file"
      multiple
      class="hidden"
      :accept="filtro || undefined"
      data-seletor-do-mais
      @change="escolheu"
    />
    <EscolherModeloDoEmail
      ref="janela"
      :modelos="modelos"
      :carregando="carregando"
      @escolher="id => emitter.emit(MODELO_DE_CAMPANHA, id)"
    />
  </div>
</template>
