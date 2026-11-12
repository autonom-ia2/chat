<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { P } from './passosNovos';
import { blocosDaConta } from './adaptadorFalso';

// #2933 — Usar outra automação: os blocos da conta (automações sem gatilho
// próprio), cada um com o que faz em uma frase. Escolhido, a tela mostra os
// passos de dentro. Mudar o bloco muda em todas as automações que usam ele.
const props = defineProps({
  modelValue: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const B = `${P}.BLOCO`;

const route = useRoute();
const router = useRouter();

const blocos = computed(() => blocosDaConta(t));
// Sem bloco na conta: o caminho é marcar uma automação como bloco, na lista.
const irParaLista = () =>
  router.push({
    name: 'automacoes_lista',
    params: { accountId: route.params.accountId },
  });
const escolhido = computed(() =>
  blocos.value.find(bloco => bloco.id === props.modelValue.bloco_id)
);
const escolher = id =>
  emit('update:modelValue', { ...props.modelValue, bloco_id: id });

// Começar pronto: o primeiro bloco já vem escolhido.
onMounted(() => {
  if (props.modelValue.bloco_id == null && blocos.value.length)
    escolher(blocos.value[0].id);
});
</script>

<template>
  <div class="flex flex-col gap-5" data-passo-novo="usar_bloco">
    <div
      v-if="!blocos.length"
      data-bloco-vazio
      class="flex flex-col items-start gap-3 p-4 rounded-2xl bg-n-alpha-2"
    >
      <p class="mb-0 text-[0.9375rem] text-n-slate-12">
        {{ $t(`${B}.VAZIO`) }}
      </p>
      <Button
        :label="$t(`${B}.VAZIO_BOTAO`)"
        icon="i-lucide-list"
        class="min-h-11"
        @click="irParaLista"
      />
    </div>
    <fieldset v-else class="flex flex-col gap-2">
      <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
        {{ $t(`${B}.QUAL`) }}
      </legend>
      <button
        v-for="bloco in blocos"
        :key="bloco.id"
        type="button"
        :data-bloco="bloco.id"
        :aria-pressed="bloco.id === modelValue.bloco_id"
        class="flex items-start w-full gap-3 p-4 border text-start rounded-2xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          bloco.id === modelValue.bloco_id
            ? 'border-n-blue-8 bg-n-blue-2'
            : 'border-n-weak bg-n-solid-1 hover:border-n-blue-7'
        "
        @click="escolher(bloco.id)"
      >
        <span
          class="grid mt-0.5 rounded-full place-items-center size-6 shrink-0"
          :class="
            bloco.id === modelValue.bloco_id
              ? 'bg-n-blue-9 text-white'
              : 'border border-n-slate-7'
          "
          aria-hidden="true"
        >
          <span
            v-if="bloco.id === modelValue.bloco_id"
            class="i-lucide-check size-4"
          />
        </span>
        <span class="flex flex-col flex-1 min-w-0 gap-1">
          <span class="text-base font-semibold text-n-slate-12">
            {{ bloco.nome }}
          </span>
          <span class="text-sm text-n-slate-11">{{ bloco.frase }}</span>
        </span>
      </button>
    </fieldset>

    <div
      v-if="escolhido"
      data-bloco-dentro
      class="flex flex-col gap-2 p-4 rounded-2xl bg-n-alpha-2"
    >
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ $t(`${B}.O_QUE_FAZ`) }}
      </p>
      <ol
        class="flex flex-col gap-1.5 m-0 text-[0.9375rem] ps-5 text-n-slate-12"
      >
        <li v-for="(dentro, i) in escolhido.passos" :key="i">{{ dentro }}</li>
      </ol>
    </div>

    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${B}.MUDA_EM_TODAS`) }}</p>
  </div>
</template>
