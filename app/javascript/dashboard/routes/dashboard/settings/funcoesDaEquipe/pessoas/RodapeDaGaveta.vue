<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// O rodapé da gaveta de pessoas (#2308, especificação 5.D; saiu de GavetaDaFuncao na rodada 9): a frase de cada
// pessoa que muda, o aviso do último salvar e os botões. "Foi salva" entra num role=status que já está na tela (o
// leitor de tela só anuncia o que muda nele); cada problema vem no seu parágrafo vermelho. Depois de um salvar com
// problema e nada mais pendente, "Cancelar" vira "Fechar". Se a gaveta virou só leitura com um aviso, Cancelar e
// Salvar somem e fica um só "Fechar" largo, que recebe o foco; a gaveta que já abre só leitura não chega a ter rodapé.
const props = defineProps({
  frases: { type: Array, default: () => [] },
  aviso: { type: Object, required: true },
  salvando: { type: Boolean, default: false },
  somenteLeitura: { type: Boolean, default: false },
  pendentes: { type: Number, default: 0 },
});

const emit = defineEmits(['fechar', 'salvar']);

const temAviso = computed(
  () => Boolean(props.aviso.salva) || props.aviso.problemas.length > 0
);
const rotuloDeSair = computed(() =>
  temAviso.value && !props.pendentes ? 'FECHAR' : 'CANCELAR'
);

const fecharSozinho = computed(() => props.somenteLeitura && temAviso.value);
const botaoFechar = ref(null);
watch(
  fecharSozinho,
  async agora => {
    if (!agora) return;
    await nextTick();
    botaoFechar.value?.$el.focus();
  },
  { immediate: true }
);
</script>

<template>
  <p
    v-for="frase in frases"
    :key="frase"
    data-frase-rodape
    class="m-0 text-sm text-n-slate-12"
  >
    {{ frase }}
  </p>
  <div data-status-gaveta role="status" :class="{ 'sr-only': !aviso.salva }">
    <p
      v-if="aviso.salva"
      data-salva-gaveta
      class="flex items-start gap-2 m-0 text-sm text-n-slate-12"
    >
      <span
        class="i-lucide-check size-4 mt-0.5 shrink-0 text-n-teal-11"
        aria-hidden="true"
      />
      {{ aviso.salva }}
    </p>
  </div>
  <p
    v-for="problema in aviso.problemas"
    :key="problema"
    data-erro-gaveta
    role="alert"
    class="m-0 text-sm font-medium text-n-ruby-11"
  >
    {{ problema }}
  </p>
  <div
    v-if="!somenteLeitura"
    class="flex flex-col gap-2 sm:flex-row sm:justify-end"
  >
    <Button
      data-cancelar
      :label="$t(`FUNCOES_EQUIPE.GAVETA.${rotuloDeSair}`)"
      slate
      faded
      :disabled="salvando"
      class="min-h-11 max-sm:w-full max-sm:!h-12"
      @click="emit('fechar')"
    />
    <Button
      data-salvar
      :label="$t(`FUNCOES_EQUIPE.GAVETA.${salvando ? 'SALVANDO' : 'SALVAR'}`)"
      :disabled="!pendentes || salvando"
      :is-loading="salvando"
      class="min-h-11 max-sm:w-full max-sm:!h-12"
      @click="emit('salvar')"
    />
  </div>
  <div v-else-if="fecharSozinho" class="flex flex-col sm:items-end">
    <Button
      ref="botaoFechar"
      data-fechar-gaveta
      :label="$t('FUNCOES_EQUIPE.GAVETA.FECHAR')"
      slate
      faded
      class="min-h-11 max-sm:w-full max-sm:!h-12"
      @click="emit('fechar')"
    />
  </div>
</template>
