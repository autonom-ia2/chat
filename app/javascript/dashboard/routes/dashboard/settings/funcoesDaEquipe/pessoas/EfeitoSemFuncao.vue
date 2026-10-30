<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useSemFuncao } from '../useSemFuncao';
import DiffDeAcesso from './DiffDeAcesso.vue';

// A linha âmbar de quem vai ficar sem função (#2308, especificação 5.D): o primeiro ganho e a perda que mais importa
// (porPeso: conversas, vendas, contatos, o resto) numa frase, e "Ver tudo o que muda" abre o mesmo diff do apagar. Tirar alguém da função não é restringir: sem função,
// a pessoa costuma ver mais. Um ganho que só o administrador daria (os valores em R$) sempre aparece na frase: o
// servidor deixa, mas quem tira precisa ver.
const props = defineProps({
  permissions: { type: Array, default: () => [] },
});

const { t } = useI18n();
const { efeitoDe } = useSemFuncao();
const id = useId();
const tudo = ref(false);

const FRASE = {
  ganhoEPerda: 'PASSA_E_DEIXA',
  ganho: 'SO_PASSA',
  perda: 'SO_DEIXA',
  nada: 'NADA',
};
const efeito = computed(() => efeitoDe(props.permissions));
const frase = computed(() => {
  const { forma, ganho, perda, tambem } = efeito.value;
  return [
    t(`FUNCOES_EQUIPE.EFEITO.${FRASE[forma]}`, { ganho, perda }),
    ...tambem,
  ].join(' ');
});
</script>

<template>
  <div data-efeito class="flex flex-col gap-2">
    <p class="flex items-start gap-1.5 m-0 text-sm text-n-slate-12">
      <span
        class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <span>
        {{ frase }}
        <button
          type="button"
          data-ver-tudo
          :aria-expanded="tudo"
          :aria-controls="`${id}-tudo`"
          class="inline-flex items-center px-1 -mx-1 font-semibold underline rounded min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="tudo = !tudo"
        >
          {{ $t('FUNCOES_EQUIPE.EFEITO.VER_TUDO') }}
        </button>
      </span>
    </p>
    <DiffDeAcesso
      v-show="tudo"
      :id="`${id}-tudo`"
      :ganha="efeito.ganha"
      :perde="efeito.perde"
    />
  </div>
</template>
