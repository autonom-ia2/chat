<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { quandoRelativo } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import CartaoDaSecao from './CartaoDaSecao.vue';

// #2894 — as notas: a caixa "Escreva uma nota" e a lista (quem e quando). Guardar
// só emite o texto; a caixa limpa quando a nota entra (`guardando` volta a falso
// sem erro). A nota nova aparece no topo porque a fonte a devolve primeiro.
const props = defineProps({
  notas: { type: Array, required: true },
  guardando: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['guardar']);

const { t } = useI18n();
const idioma = useIdioma();
const texto = ref('');

const guardar = () => {
  const limpo = texto.value.trim();
  if (limpo && !props.guardando) emit('guardar', limpo);
};

// A tela chama depois de guardar com sucesso.
const limpar = () => {
  texto.value = '';
};
defineExpose({ limpar });

const ra = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.NOTAS.${chave}`, valores);
</script>

<template>
  <CartaoDaSecao :titulo="ra('TITULO')" data-relacionamentos="notas">
    <form class="flex flex-col gap-3 mb-5" @submit.prevent="guardar">
      <textarea
        v-model="texto"
        data-relacionamentos="nota-caixa"
        rows="3"
        :aria-label="ra('CAMPO')"
        :placeholder="ra('CAMPO')"
        class="w-full p-3 text-base border-0 resize-y rounded-xl bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak placeholder:text-n-slate-10 focus:outline-n-brand"
      />
      <Button
        data-relacionamentos="guardar-nota"
        type="submit"
        slate
        faded
        class="self-end min-h-11"
        :is-loading="guardando"
        :disabled="!texto.trim()"
        :label="ra('GUARDAR')"
      />
    </form>
    <p v-if="!notas.length" class="m-0 text-base text-n-slate-11">
      {{ ra('VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-4 p-0 m-0 list-none">
      <li
        v-for="nota in notas"
        :key="nota.id"
        data-relacionamentos="nota"
        class="pb-4 border-b border-n-weak last:border-b-0 last:pb-0"
      >
        <p class="m-0 text-base text-n-slate-12">{{ nota.texto }}</p>
        <p class="m-0 mt-1 text-sm text-n-slate-11">
          {{
            ra('POR', {
              autor: nota.autor,
              quando: quandoRelativo(nota.quando, agora, idioma),
            })
          }}
        </p>
      </li>
    </ul>
  </CartaoDaSecao>
</template>
