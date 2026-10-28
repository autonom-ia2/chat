<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { recursos } from './ligarPassos';

// Fim do passo a passo (#2338): o que já funciona e, para cada recurso que ainda não funciona, o que falta e um
// botão que leva direto ao passo certo. A mesma lista fica na aba Conexão depois.
const props = defineProps({
  estado: { type: Object, required: true },
});
const emit = defineEmits(['abrir', 'numeros', 'vendas', 'painel']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.LIGAR.PRONTO';
const lista = computed(() => recursos(props.estado));

const resolver = falta => {
  // PROTÓTIPO: no PR final, NUMEROS abre o login da Página (read_insights).
  if (falta === 'NUMEROS') emit('numeros');
  else if (falta === 'VENDAS') emit('vendas');
  else if (falta === 'PERMISSAO') emit('abrir', 'FACEBOOK');
  else emit('abrir', falta);
};
</script>

<template>
  <div data-ligar-pronto class="flex flex-col gap-5">
    <span
      class="flex items-center justify-center size-12 rounded-xl bg-n-teal-3 text-n-teal-11"
      aria-hidden="true"
    >
      <span class="i-lucide-party-popper size-6" />
    </span>
    <div class="flex flex-col gap-2">
      <h2 class="m-0 text-xl font-semibold text-n-slate-12">
        {{ $t(`${KEY}.TITLE`) }}
      </h2>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ $t(`${KEY}.TEXT`) }}
      </p>
    </div>
    <ul
      class="flex flex-col p-0 m-0 list-none border border-solid divide-y rounded-xl border-n-weak divide-n-weak"
    >
      <li
        v-for="item in lista"
        :key="item.chave"
        :data-ligar-recurso="item.chave"
        :data-ligar-falta="item.falta || undefined"
        class="flex flex-wrap items-center gap-3 px-4 py-3"
      >
        <span
          class="flex-none size-5"
          :class="
            item.falta
              ? 'i-lucide-circle-dashed text-n-amber-11'
              : 'i-lucide-circle-check text-n-teal-11'
          "
          aria-hidden="true"
        />
        <span class="flex flex-col flex-1 min-w-[12rem]">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t(`${KEY}.RECURSOS.${item.chave}`) }}
          </span>
          <span
            class="text-xs"
            :class="item.falta ? 'text-n-amber-11' : 'text-n-slate-11'"
          >
            {{
              item.falta
                ? $t(`${KEY}.FALTA.${item.falta}`)
                : $t(`${KEY}.FUNCIONA`)
            }}
          </span>
        </span>
        <Button
          v-if="item.falta"
          size="sm"
          variant="faded"
          class="!min-h-11"
          :label="$t(`${KEY}.RESOLVER.${item.falta}`)"
          @click="resolver(item.falta)"
        />
      </li>
    </ul>
    <Button
      data-ligar-ver-painel
      class="self-start !min-h-11"
      :label="$t(`${KEY}.SEE_PANEL`)"
      @click="emit('painel')"
    />
  </div>
</template>
