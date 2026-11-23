<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CartaoDaSecao from './CartaoDaSecao.vue';
import CartaoDoArquivo from './CartaoDoArquivo.vue';
import FalhaDaParte from './FalhaDaParte.vue';

// #2894 — o que foi trocado nas conversas. #3113: grade de miniaturas que abrem ao tocar (CartaoDoArquivo), as mais
// novas primeiro; "Ver mais N" mostra o resto. `falhou`: a leitura não veio.
const props = defineProps({
  arquivos: { type: Array, required: true },
  agora: { type: Number, default: () => Date.now() },
  falhou: { type: Boolean, default: false },
});
const emit = defineEmits(['tentar']);

// Duas fileiras na tela larga (4 por fileira), quatro no celular e no tablet (2 por fileira): sempre fileira cheia.
const VISIVEIS = 8;

const { t } = useI18n();
const ra = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.ARQUIVOS.${chave}`, valores);
const todos = ref(false);
const cartao = ref(null);

// Recolher encolhe a seção de uma vez: a tela volta ao título, e a pessoa não cai no bloco de baixo.
const alternar = () => {
  todos.value = !todos.value;
  if (!todos.value) cartao.value?.$el?.scrollIntoView?.({ block: 'start' });
};

const mostrados = computed(() =>
  todos.value ? props.arquivos : props.arquivos.slice(0, VISIVEIS)
);
const sobram = computed(() => props.arquivos.length > VISIVEIS);
// O servidor manda até 50: o botão diz quantos faltam aparecer, nunca um total que pode ser maior.
const restantes = computed(() => props.arquivos.length - VISIVEIS);
</script>

<template>
  <CartaoDaSecao
    ref="cartao"
    :titulo="ra('TITULO')"
    data-relacionamentos="arquivos"
  >
    <FalhaDaParte v-if="falhou" @tentar="emit('tentar')" />
    <p v-else-if="!arquivos.length" class="m-0 text-base text-n-slate-11">
      {{ ra('VAZIO') }}
    </p>
    <template v-else>
      <ul
        class="grid grid-cols-2 p-0 m-0 list-none gap-x-3 gap-y-5 lg:grid-cols-4"
      >
        <li v-for="arquivo in mostrados" :key="arquivo.id" class="min-w-0">
          <CartaoDoArquivo :arquivo="arquivo" :agora="agora" />
        </li>
      </ul>
      <Button
        v-if="sobram"
        data-relacionamentos="ver-todos-os-arquivos"
        slate
        faded
        class="!h-11 w-full mt-5"
        :aria-expanded="todos"
        :label="
          todos
            ? ra('MOSTRAR_MENOS')
            : t(
                'RELACIONAMENTOS_FICHA.ARQUIVOS.VER_MAIS',
                { n: restantes },
                restantes
              )
        "
        @click="alternar"
      />
    </template>
  </CartaoDaSecao>
</template>
