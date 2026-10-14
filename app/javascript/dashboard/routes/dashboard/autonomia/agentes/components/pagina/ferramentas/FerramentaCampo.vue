<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #1301 — campo do assistente de ferramentas: rótulo, controle, erro, ajuda e exemplo. O exemplo
// só aparece com o campo vazio (banca do diretor de arte: repetir o valor parecia defeito). O slot
// recebe o aria-describedby já montado com o erro e a ajuda.
const props = defineProps({
  id: { type: String, required: true },
  rotulo: { type: String, required: true },
  opcional: { type: Boolean, default: false },
  erro: { type: String, default: '' },
  ajuda: { type: String, default: '' },
  exemplo: { type: String, default: '' },
  exemploMono: { type: Boolean, default: false },
  preenchido: { type: Boolean, default: false },
});

const { t } = useI18n();

// O espaço vem daqui: o Vue apaga o espaço entre <b> e <span> em linhas separadas, e depender do fim
// da string i18n deu "Exemplo:Use quando…".
const rotuloDoExemplo = computed(
  () => `${t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.EXEMPLO')} `
);

const descricao = computed(
  () =>
    [
      props.erro ? `${props.id}-erro` : '',
      props.ajuda ? `${props.id}-ajuda` : '',
    ]
      .filter(Boolean)
      .join(' ') || undefined
);
</script>

<template>
  <div class="flex flex-col min-w-0 gap-1.5">
    <label :for="id" class="text-sm font-semibold text-n-slate-12">
      {{ rotulo }}
      <span v-if="opcional" class="font-normal text-n-slate-11">
        {{ t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.OPCIONAL') }}
      </span>
    </label>
    <slot :descricao="descricao" :invalido="Boolean(erro)" />
    <p
      v-if="erro"
      :id="`${id}-erro`"
      data-erro-campo
      class="m-0 text-sm font-medium text-n-ruby-11"
    >
      {{ erro }}
    </p>
    <p v-if="ajuda" :id="`${id}-ajuda`" class="m-0 text-sm text-n-slate-11">
      {{ ajuda }}
    </p>
    <p
      v-if="exemplo && !preenchido"
      data-exemplo
      class="m-0 text-sm break-words text-n-slate-11"
    >
      <b class="font-semibold">{{ rotuloDoExemplo }}</b>
      <span :class="exemploMono ? 'font-mono' : ''">{{ exemplo }}</span>
    </p>
    <slot name="depois" />
  </div>
</template>
