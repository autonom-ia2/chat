<script setup>
// "Confira e envie" do carrossel de fotos (#1716): cada cartão com a foto, o
// que foi preenchido e "Alterar" (botão explícito, alvo de 44 px).
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  // cartoesDoModelo(template)
  cartoes: { type: Array, required: true },
  // { [indice]: { imagem, campos } }
  valores: { type: Object, required: true },
});
const emit = defineEmits(['alterar']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.CONVERSA.CONFIRA';
const resumo = valor => Object.values(valor?.campos || {}).join(' · ');
</script>

<template>
  <section class="flex flex-col gap-2" data-cartoes-escolhidos>
    <h4 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t(`${NS}.CARTOES`, { n: cartoes.length }) }}
    </h4>
    <ol class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="cartao in cartoes"
        :key="cartao.indice"
        class="flex items-center gap-3 p-2 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <img
          :src="valores[cartao.indice]?.imagem"
          alt=""
          class="object-cover rounded-lg size-12 shrink-0 bg-n-slate-3"
        />
        <span class="flex-1 min-w-0 text-sm break-words text-n-slate-12">
          <strong class="block">
            {{ t(`${NS}.CARTAO_N`, { n: cartao.indice + 1 }) }}
          </strong>
          <span class="text-xs text-n-slate-11">
            {{ resumo(valores[cartao.indice]) }}
          </span>
        </span>
        <Button
          type="button"
          variant="link"
          color="slate"
          class="min-h-11"
          :label="t(`${NS}.ALTERAR`)"
          :aria-label="t(`${NS}.ALTERAR_N`, { n: cartao.indice + 1 })"
          :data-alterar-cartao="cartao.indice"
          @click="emit('alterar', cartao.indice)"
        />
      </li>
    </ol>
  </section>
</template>
