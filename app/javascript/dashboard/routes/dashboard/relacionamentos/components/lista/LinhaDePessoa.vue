<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import SegundaLinha from './SegundaLinha.vue';
import { segundaLinhaDaPessoa } from '../../lista/segundaLinhaDaPessoa';

// #2894 — uma pessoa na lista. Clicar no nome (ou Enter) abre a ficha: o botão
// do nome estica a área de clique pela linha toda; a caixa de marcar e o
// "Conversar" ficam por cima e não abrem a ficha. No desktop o "Conversar"
// fica sempre à vista, discreto (ninguém descobre um botão que só aparece no
// hover). No celular é um ícone.
const props = defineProps({
  pessoa: { type: Object, required: true },
  marcada: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir', 'alternar', 'conversar']);

const { t } = useI18n();

const partes = computed(() =>
  segundaLinhaDaPessoa(props.pessoa, props.agora, t)
);

const ehCliente = computed(() => props.pessoa.contact_type === 'customer');
</script>

<template>
  <li
    data-relacionamentos="linha"
    class="relative flex items-center min-w-0 gap-3 px-3 py-2 transition-colors group sm:px-5 hover:bg-n-alpha-1 focus-within:bg-n-alpha-1"
    :class="{ 'bg-n-alpha-1': marcada }"
  >
    <label
      class="relative z-10 flex items-center justify-center cursor-pointer size-11 shrink-0"
    >
      <span class="sr-only">
        {{ t('RELACIONAMENTOS.LISTA.LINHA.MARCAR', { nome: pessoa.name }) }}
      </span>
      <Checkbox
        data-relacionamentos="marcar"
        class="[&_input:checked:hover]:bg-n-brand"
        :model-value="marcada"
        @change="emit('alternar', pessoa)"
      />
    </label>
    <Avatar
      :name="pessoa.name"
      :src="pessoa.thumbnail"
      :size="40"
      rounded-full
    />
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
        <button
          type="button"
          class="min-w-0 max-w-full p-0 text-base font-semibold text-start truncate border-0 bg-transparent text-n-slate-12 after:absolute after:inset-0 focus-visible:outline-none focus-visible:after:outline focus-visible:after:outline-2 focus-visible:after:-outline-offset-2 focus-visible:after:outline-n-brand focus-visible:after:rounded-2xl"
          @click="emit('abrir', pessoa)"
        >
          {{ pessoa.name }}
        </button>
        <SeloDeEstado v-if="ehCliente" tom="cliente">
          {{ t('RELACIONAMENTOS.COMUM.SELO_CLIENTE') }}
        </SeloDeEstado>
        <SeloDeEstado v-if="pessoa.opted_out_at" tom="alerta">
          {{ t('RELACIONAMENTOS.COMUM.SELO_NAO_QUER_MENSAGENS') }}
        </SeloDeEstado>
      </div>
      <SegundaLinha :partes="partes" />
    </div>
    <Button
      slate
      faded
      class="relative z-10 hidden min-h-11 sm:inline-flex"
      :label="t('RELACIONAMENTOS.COMUM.CONVERSAR')"
      @click="emit('conversar', pessoa)"
    />
    <Button
      slate
      faded
      class="relative z-10 size-11 sm:hidden"
      icon="i-lucide-message-circle"
      :aria-label="
        t('RELACIONAMENTOS.LISTA.LINHA.CONVERSAR_COM', { nome: pessoa.name })
      "
      @click="emit('conversar', pessoa)"
    />
  </li>
</template>
