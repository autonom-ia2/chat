<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import CampoDoAtributo from './CampoDoAtributo.vue';

// #3075 — os campos personalizados da conta na gaveta, com o controle do tipo
// de cada um. Os que aparecem na ficha (`campos` com `principal`) vêm primeiro;
// os outros ficam atrás de "Mais campos", que abre sozinho quando um deles tem
// erro. #3078 — tirado de CamposDaPessoa para a gaveta da empresa usar o mesmo.
// Não altera nada: cada mudança sobe por `mudar(chave, valor)`.
const props = defineProps({
  // ficha/atributos.js#camposDoRegistro.
  campos: { type: Array, required: true },
  // Os valores de agora e os de quando a gaveta abriu ({ chave: valor }).
  valores: { type: Object, required: true },
  iniciais: { type: Object, required: true },
  erros: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['mudar']);

const { t } = useI18n();
const maisAbertos = ref(false);
const idDosMais = useId();
const ra = chave => t(`RELACIONAMENTOS_FICHA.GAVETA.${chave}`);

const principais = computed(() =>
  props.campos.filter(campo => campo.principal)
);
const outros = computed(() => props.campos.filter(campo => !campo.principal));
const erroNosOutros = computed(() =>
  outros.value.some(campo => props.erros[`atributo:${campo.chave}`])
);
const abertos = computed(() => maisAbertos.value || erroNosOutros.value);
</script>

<template>
  <div
    data-relacionamentos="campos-da-conta"
    class="flex flex-col gap-5 pt-5 border-t border-n-weak"
  >
    <h3 class="m-0 text-base font-semibold text-n-slate-12">
      {{ ra('OUTRAS') }}
    </h3>
    <CampoDoAtributo
      v-for="campo in principais"
      :key="campo.chave"
      :campo="campo"
      :valor="valores[campo.chave] ?? ''"
      :valor-inicial="iniciais[campo.chave] ?? ''"
      :erro="erros[`atributo:${campo.chave}`]"
      @mudar="valor => emit('mudar', campo.chave, valor)"
    />
    <div v-if="outros.length" class="flex flex-col gap-5">
      <button
        type="button"
        data-relacionamentos="mais-campos"
        :aria-expanded="abertos ? 'true' : 'false'"
        :aria-controls="idDosMais"
        class="inline-flex items-center gap-2 p-0 text-base font-medium bg-transparent border-0 text-start min-h-11 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="maisAbertos = !maisAbertos"
      >
        {{
          t(
            'RELACIONAMENTOS_FICHA.GAVETA.MAIS_CAMPOS',
            { count: outros.length },
            outros.length
          )
        }}
        <span
          class="size-4 i-lucide-chevron-right rtl:rotate-180"
          :class="{ 'rotate-90 rtl:rotate-90': abertos }"
          aria-hidden="true"
        />
      </button>
      <div v-show="abertos" :id="idDosMais" class="flex flex-col gap-5">
        <CampoDoAtributo
          v-for="campo in outros"
          :key="campo.chave"
          :campo="campo"
          :valor="valores[campo.chave] ?? ''"
          :valor-inicial="iniciais[campo.chave] ?? ''"
          :erro="erros[`atributo:${campo.chave}`]"
          @mudar="valor => emit('mudar', campo.chave, valor)"
        />
      </div>
    </div>
  </div>
</template>
