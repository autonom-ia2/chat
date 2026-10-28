<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

// O diálogo da casa (#2308, especificação 9), uma anatomia só: quadrado de 44 px com ícone por tipo, título,
// explicação, risco opcional e o rodapé (à direita no computador; empilhado, na largura toda, no celular).
// Cuidado = âmbar com ação azul; destrutivo = ruby com ação vermelha. O <dialog> modal deixa o resto inerte (foco
// preso); o botão seguro tem o foco inicial e responde ao Esc; ao fechar, o foco volta a quem abriu.
const props = defineProps({
  tipo: {
    type: String,
    default: 'cuidado',
    validator: valor => ['cuidado', 'destrutivo'].includes(valor),
  },
  icone: { type: String, default: '' },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  risco: { type: String, default: '' },
  seguro: { type: String, required: true },
  acao: { type: String, required: true },
  // Mesmo rótulo, só o estado muda (especificação 9): "Mover as pessoas e apagar" espera o destino.
  acaoDesabilitada: { type: Boolean, default: false },
});

const emit = defineEmits(['seguro', 'acao']);

const id = useId();
const dialogo = ref(null);
const botaoSeguro = ref(null);
let gatilho = null;

const destrutivo = computed(() => props.tipo === 'destrutivo');
const iconeDoTipo = computed(
  () =>
    props.icone ||
    (destrutivo.value ? 'i-lucide-trash-2' : 'i-lucide-triangle-alert')
);

const abrir = async () => {
  gatilho = document.activeElement;
  dialogo.value?.showModal?.();
  await nextTick();
  botaoSeguro.value?.$el?.focus();
};

const escolher = evento => {
  dialogo.value?.close?.();
  gatilho?.focus?.();
  gatilho = null;
  if (evento === 'acao') emit('acao');
  else emit('seguro');
};

// O Esc dispara "cancel" no <dialog>: vira a ação segura.
const aoCancelar = evento => {
  evento.preventDefault();
  escolher('seguro');
};

defineExpose({ abrir });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogo"
      :aria-labelledby="`${id}-titulo`"
      :aria-describedby="`${id}-texto`"
      class="w-full p-0 bg-transparent max-w-md rounded-2xl shadow-xl backdrop:bg-n-alpha-black1 max-sm:m-0 max-sm:mt-auto max-sm:max-w-none max-sm:rounded-b-none"
      @cancel="aoCancelar"
    >
      <div
        class="flex flex-col gap-4 p-6 rounded-2xl max-sm:rounded-b-none bg-n-solid-1"
      >
        <span
          class="grid place-items-center size-11 rounded-xl"
          :class="
            destrutivo
              ? 'bg-n-ruby-3 text-n-ruby-11'
              : 'bg-n-amber-3 text-n-amber-11'
          "
        >
          <span class="size-5" :class="iconeDoTipo" aria-hidden="true" />
        </span>
        <h2
          :id="`${id}-titulo`"
          class="m-0 text-lg font-semibold leading-snug text-n-slate-12"
        >
          {{ titulo }}
        </h2>
        <div :id="`${id}-texto`" class="flex flex-col gap-2">
          <p v-if="texto" class="m-0 text-[0.9375rem] text-n-slate-11">
            {{ texto }}
          </p>
          <p
            v-if="risco"
            data-risco
            class="flex items-start gap-2 m-0 text-sm text-n-slate-12"
          >
            <span
              class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
              aria-hidden="true"
            />
            {{ risco }}
          </p>
          <slot />
        </div>
        <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Button
            ref="botaoSeguro"
            data-seguro
            type="button"
            :label="seguro"
            slate
            faded
            class="max-sm:w-full max-sm:!h-12 min-h-11"
            @click="escolher('seguro')"
          />
          <Button
            data-acao
            type="button"
            :label="acao"
            :color="destrutivo ? 'ruby' : 'blue'"
            :disabled="acaoDesabilitada"
            class="max-sm:w-full max-sm:!h-12 min-h-11"
            @click="escolher('acao')"
          />
        </div>
      </div>
    </dialog>
  </TeleportWithDirection>
</template>
