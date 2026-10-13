<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #1423 — uma parte do card numa frase, no padrão do FunilResumoCartao:
// ícone com a cor da parte, rótulo pequeno, a frase com o dado em negrito e o
// botão cinza. O ícone fica na linha do rótulo e a frase usa a largura toda:
// os quatro cartões do resumo cabem lado a lado, dois por linha, sem rolar. "Alterar" quando a parte tem edição, "Ver" quando é só leitura.
// Com `alerta`, borda e ícone vermelhos, como o "erro" do PassagemCartao.
const props = defineProps({
  parte: { type: String, required: true },
  icone: { type: String, required: true },
  tom: { type: String, default: 'bg-n-blue-3 text-n-blue-11' },
  titulo: { type: String, required: true },
  acao: {
    type: String,
    default: 'alterar',
    validator: valor => ['alterar', 'ver', 'marcar', ''].includes(valor),
  },
  alerta: { type: Boolean, default: false },
  // Nome da parte que o botão abre, quando não é o título (leitor de tela).
  rotuloAcao: { type: String, default: '' },
});

defineEmits(['abrir']);

const { t } = useI18n();
// "Marcar" quando a parte ainda está vazia e dá para criar (a reunião).
const ACAO = {
  alterar: {
    rotulo: 'ALTERAR',
    aria: 'ALTERAR_PARTE',
    icone: 'i-lucide-pencil',
  },
  ver: { rotulo: 'VER', aria: 'VER_PARTE', icone: 'i-lucide-eye' },
  marcar: {
    rotulo: 'MARCAR',
    aria: 'MARCAR_PARTE',
    icone: 'i-lucide-calendar-plus',
  },
};
const botao = computed(() => ACAO[props.acao] || ACAO.alterar);
</script>

<template>
  <article
    :data-card-parte="parte"
    class="flex min-w-0 flex-col gap-1 rounded-2xl border bg-n-solid-1 px-4 py-3 shadow-sm transition"
    :class="
      alerta
        ? 'border-n-ruby-8'
        : 'border-n-weak hover:border-n-slate-7 focus-within:border-n-blue-8 focus-within:shadow-md'
    "
  >
    <div class="flex min-h-11 items-center gap-3">
      <span
        class="grid size-9 shrink-0 place-items-center rounded-xl"
        :class="alerta ? 'bg-n-ruby-3 text-n-ruby-11' : tom"
        aria-hidden="true"
      >
        <span class="size-5" :class="icone" />
      </span>
      <h3 class="mb-0 min-w-0 flex-1 text-sm font-medium text-n-slate-11">
        <slot name="titulo">{{ titulo }}</slot>
      </h3>
      <slot name="botao" />
      <Button
        v-if="acao"
        :data-card-abrir="parte"
        :label="t(`CRM_CARD.${botao.rotulo}`)"
        :aria-label="
          t(`CRM_CARD.${botao.aria}`, { parte: rotuloAcao || titulo })
        "
        :icon="botao.icone"
        slate
        faded
        class="!min-h-11 shrink-0"
        @click="$emit('abrir')"
      />
    </div>
    <div class="text-base leading-normal text-n-slate-12">
      <slot />
    </div>
    <slot name="extra" />
  </article>
</template>
