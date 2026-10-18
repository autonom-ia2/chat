<script setup>
// Os produtos que vão (#1716): foto, nome, preço e o aviso do que acabou. Em
// vários e no carrossel, a ordem é a dos toques na gaveta; subir e descer
// trocam a posição (alvo de 44 px).
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import PrecoDoProduto from './PrecoDoProduto.vue';

const props = defineProps({
  // 'um' | 'varios' | 'carrossel'
  tipo: { type: String, required: true },
  produtos: { type: Array, required: true },
});
const emit = defineEmits(['mover', 'trocar']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.CONVERSA.PRODUTOS';
const emOrdem = () => props.tipo !== 'um' && props.produtos.length > 1;
const SETA =
  'grid rounded-lg place-items-center size-11 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-30';
</script>

<template>
  <section class="flex flex-col gap-2" data-produtos-escolhidos>
    <h4 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t(`${NS}.TITULO.${tipo}`) }}
    </h4>
    <ol class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="(produto, posicao) in produtos"
        :key="produto.id"
        class="flex items-center gap-3 p-2 border rounded-xl bg-n-solid-1"
        :class="produto.disponivel ? 'border-n-weak' : 'border-n-ruby-7'"
        :data-produto-escolhido="produto.id"
      >
        <span
          v-if="tipo !== 'um'"
          class="w-5 text-sm font-semibold text-center shrink-0 text-n-slate-11"
        >
          {{ posicao + 1 }}
        </span>
        <img
          v-if="produto.foto"
          :src="produto.foto"
          alt=""
          class="object-cover rounded-lg size-12 shrink-0 bg-n-slate-3"
        />
        <span
          v-else
          class="grid rounded-lg place-items-center size-12 shrink-0 bg-n-slate-3 text-n-slate-10"
          aria-hidden="true"
        >
          <span class="i-lucide-shopping-bag size-5" />
        </span>
        <span class="flex flex-col flex-1 min-w-0">
          <span class="text-sm font-medium break-words text-n-slate-12">
            {{ produto.nome }}
          </span>
          <PrecoDoProduto :produto="produto" class="text-xs text-n-slate-11" />
          <span
            v-if="!produto.disponivel"
            class="text-xs font-medium text-n-ruby-11"
            data-produto-acabou
          >
            {{ t(`${NS}.ACABOU`) }}
          </span>
        </span>
        <span v-if="emOrdem()" class="flex shrink-0">
          <button
            type="button"
            :class="SETA"
            :disabled="posicao === 0"
            :aria-label="t(`${NS}.SUBIR`, { nome: produto.nome })"
            data-subir
            @click="emit('mover', posicao, -1)"
          >
            <span class="i-lucide-arrow-up size-4" aria-hidden="true" />
          </button>
          <button
            type="button"
            :class="SETA"
            :disabled="posicao === produtos.length - 1"
            :aria-label="t(`${NS}.DESCER`, { nome: produto.nome })"
            data-descer
            @click="emit('mover', posicao, 1)"
          >
            <span class="i-lucide-arrow-down size-4" aria-hidden="true" />
          </button>
        </span>
      </li>
    </ol>
    <Button
      type="button"
      variant="outline"
      color="slate"
      icon="i-lucide-shopping-bag"
      class="self-start min-h-11"
      :label="t(`${NS}.TROCAR.${tipo}`)"
      data-trocar-produtos
      @click="emit('trocar')"
    />
  </section>
</template>
