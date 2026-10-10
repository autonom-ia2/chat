<script setup>
import { computed, onBeforeUnmount, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAutoGrowTextarea } from '../../composables/useAutoGrowTextarea';
import AgenteBotao from './AgenteBotao.vue';

// #1181 — campo de conversa do módulo (Conte, Mudar conversando e teste). Enter manda e Shift+Enter
// quebra a linha. Arquivos são sempre opcionais: o clipe só aparece com `anexar`, e nada impede de
// mandar só texto. No teste (`soImagens`) só entram fotos, que vão como data-url e nunca para a base
// real (protótipo T04: "o teste não grava arquivo na base real").
const props = defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  anexar: { type: Boolean, default: false },
  soImagens: { type: Boolean, default: false },
  enviando: { type: Boolean, default: false },
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'enviar']);

const { t } = useI18n();
const campoId = `compositor-${useId()}`;
const campo = ref(null);
const seletor = ref(null);
const anexos = ref([]);
let proximoId = 0;

const texto = computed({
  get: () => props.modelValue,
  set: valor => emit('update:modelValue', valor),
});
useAutoGrowTextarea(campo, texto);

const ehImagem = arquivo => (arquivo.type || '').startsWith('image/');

const juntar = lista => {
  const novos = Array.from(lista || [])
    .filter(arquivo => !props.soImagens || ehImagem(arquivo))
    .map(arquivo => {
      proximoId += 1;
      return {
        id: proximoId,
        arquivo,
        previa: ehImagem(arquivo) ? URL.createObjectURL(arquivo) : null,
      };
    });
  anexos.value = [...anexos.value, ...novos];
};

const soltar = anexo => {
  if (anexo.previa) URL.revokeObjectURL(anexo.previa);
};

const remover = id => {
  const anexo = anexos.value.find(item => item.id === id);
  if (anexo) soltar(anexo);
  anexos.value = anexos.value.filter(item => item.id !== id);
};

onBeforeUnmount(() => anexos.value.forEach(soltar));

const temAlgo = computed(
  () => Boolean((props.modelValue || '').trim()) || anexos.value.length > 0
);

const enviar = () => {
  if (!temAlgo.value || props.enviando || props.desabilitado) return;
  emit('enviar', {
    texto: (props.modelValue || '').trim(),
    anexos: anexos.value.map(item => item.arquivo),
  });
  anexos.value.forEach(soltar);
  anexos.value = [];
};

const aoTeclar = evento => {
  if (evento.key !== 'Enter' || evento.shiftKey || evento.isComposing) return;
  evento.preventDefault();
  enviar();
};

const aoEscolher = evento => {
  juntar(evento.target.files);
  evento.target.value = '';
};
</script>

<template>
  <form
    class="flex flex-col gap-2 p-2 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-slate-7"
    @submit.prevent="enviar"
  >
    <ul
      v-if="anexos.length"
      :aria-label="t('AGENTS.JORNADA.COMPOSITOR.ANEXOS')"
      class="flex flex-wrap gap-2 p-0 m-0 list-none"
    >
      <li
        v-for="anexo in anexos"
        :key="anexo.id"
        class="flex items-center gap-2 py-1 ps-1 pe-0 rounded-xl bg-n-slate-2 ring-1 ring-inset ring-n-weak max-w-64"
      >
        <img
          v-if="anexo.previa"
          :src="anexo.previa"
          :alt="anexo.arquivo.name"
          class="object-cover rounded-lg size-10 shrink-0"
        />
        <span
          v-else
          class="grid rounded-lg place-items-center size-10 shrink-0 bg-n-slate-3 text-n-slate-11"
        >
          <span class="i-lucide-file-text size-5" aria-hidden="true" />
        </span>
        <span class="text-sm truncate text-n-slate-12">
          {{ anexo.arquivo.name }}
        </span>
        <button
          type="button"
          :aria-label="
            t('AGENTS.JORNADA.COMPOSITOR.REMOVER', { nome: anexo.arquivo.name })
          "
          class="grid rounded-lg place-items-center size-11 shrink-0 text-n-slate-11 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="remover(anexo.id)"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </li>
    </ul>
    <div class="flex items-end gap-2">
      <template v-if="anexar">
        <button
          type="button"
          data-anexar
          :disabled="desabilitado"
          :aria-label="
            soImagens
              ? t('AGENTS.JORNADA.COMPOSITOR.ANEXAR_FOTO')
              : t('AGENTS.JORNADA.COMPOSITOR.ANEXAR')
          "
          class="grid rounded-xl place-items-center size-11 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11 disabled:opacity-50"
          @click="seletor?.click()"
        >
          <span class="i-lucide-paperclip size-5" aria-hidden="true" />
        </button>
        <input
          ref="seletor"
          type="file"
          multiple
          class="hidden"
          :accept="soImagens ? 'image/*' : undefined"
          @change="aoEscolher"
        />
      </template>
      <label :for="campoId" class="sr-only">
        {{ placeholder || t('AGENTS.JORNADA.COMPOSITOR.ESCREVA') }}
      </label>
      <textarea
        :id="campoId"
        ref="campo"
        v-model="texto"
        rows="1"
        :disabled="desabilitado"
        :placeholder="placeholder || t('AGENTS.JORNADA.COMPOSITOR.ESCREVA')"
        class="flex-1 min-w-0 px-2 py-2.5 text-base leading-relaxed bg-transparent border-0 outline-none resize-none !mb-0 min-h-11 max-h-48 overflow-y-auto text-n-slate-12 placeholder:text-n-slate-10"
        @keydown="aoTeclar"
      />
      <AgenteBotao
        type="submit"
        data-enviar
        :carregando="enviando"
        :inativo="!temAlgo || desabilitado"
      >
        {{ t('AGENTS.JORNADA.COMPOSITOR.ENVIAR') }}
      </AgenteBotao>
    </div>
  </form>
</template>
