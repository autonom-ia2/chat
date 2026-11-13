<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import LivreDuracao from '../components/LivreDuracao.vue';
import LivreModelo from '../components/LivreModelo.vue';
import LivreQuem from './LivreQuem.vue';
import { DURACOES, P } from './passosNovos';
import { horariosLivres } from './adaptadorFalso';

// #2935 — Marcar reunião pela conversa: na agenda de quem, quanto tempo, o que
// dizer antes dos horários e quanto esperar a resposta. A prévia mostra a
// mensagem com os 3 próximos horários livres, como o cliente vai ver. A IA de
// decidir entende a resposta; nada de lista de palavras. Com a janela de 24 h
// fechada, vai o modelo aprovado escolhido, ou nada (como no passo mensagem).
const props = defineProps({
  modelValue: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  opcoes: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const R = `${P}.REUNIAO`;

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });

const duracoes = computed(() =>
  DURACOES.map(minutos => ({
    value: minutos,
    label: t(`${R}.MINUTOS`, { n: minutos }),
  }))
);
const horarios = computed(() => horariosLivres(t));
</script>

<template>
  <div class="flex flex-col gap-5" data-passo-novo="marcar_reuniao">
    <LivreQuem
      :rotulo="$t(`${R}.COM`)"
      :model-value="modelValue.com"
      :opcoes="opcoes"
      sem-time
      @update:model-value="com => mudar({ com })"
    />
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${R}.DURACAO`) }}
      </span>
      <ChoiceSelect
        data-reuniao-duracao
        :model-value="modelValue.duracao"
        :aria-label="$t(`${R}.DURACAO`)"
        :options="duracoes"
        @update:model-value="duracao => mudar({ duracao })"
      />
    </div>
    <TextArea
      data-reuniao-convite
      :model-value="modelValue.convite || ''"
      :label="$t(`${R}.CONVITE`)"
      :max-length="300"
      @update:model-value="convite => mudar({ convite })"
    />

    <figure
      data-reuniao-previa
      class="flex flex-col gap-2 p-4 m-0 rounded-2xl bg-n-alpha-2"
    >
      <figcaption class="text-sm font-medium text-n-slate-11">
        {{ $t(`${R}.COMO_O_CLIENTE_VE`) }}
      </figcaption>
      <div
        class="flex flex-col self-start w-full max-w-xs gap-2 p-3 shadow-sm rounded-2xl rounded-ss-sm bg-n-teal-3"
      >
        <p class="mb-0 text-[0.9375rem] text-n-slate-12 whitespace-pre-line">
          {{ modelValue.convite }}
        </p>
        <ul class="flex flex-col gap-1.5 p-0 m-0 list-none">
          <li
            v-for="horario in horarios"
            :key="horario"
            class="flex items-center justify-center px-3 text-[0.9375rem] font-medium rounded-xl min-h-11 bg-n-solid-1 text-n-blue-11"
          >
            {{ horario }}
          </li>
        </ul>
      </div>
      <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${R}.SEM_BOTOES`) }}</p>
    </figure>

    <LivreModelo
      :rotulo="$t('AUTOMACAO_LIVRE.CAMPOS.MODELO')"
      :model-value="modelValue.modelo || null"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="modelo => mudar({ modelo })"
    />

    <LivreDuracao
      :rotulo="$t(`${R}.ESPERA`)"
      :model-value="modelValue.espera"
      :unidades="catalogo.unidades"
      @update:model-value="espera => mudar({ espera })"
    />
    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${R}.COMO_FUNCIONA`) }}</p>
  </div>
</template>
