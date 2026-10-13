<script setup>
import { computed } from 'vue';
import { conferirConteudo } from '../helpers/conteudo';

// O que costuma fazer o WhatsApp recusar, conferido antes de enviar. Ao vivo:
// muda enquanto a pessoa corrige.
const props = defineProps({
  conteudo: { type: Object, required: true },
  contexto: { type: Object, default: () => ({}) },
});

const itens = computed(() => conferirConteudo(props.conteudo, props.contexto));
const problemas = computed(() => itens.value.filter(item => !item.ok).length);
</script>

<template>
  <section
    data-conferencia
    class="flex flex-col gap-3 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <h3 class="m-0 text-base font-semibold text-n-slate-12">
      {{ $t('MODELOS_WHATSAPP.CONFERENCIA.TITULO') }}
    </h3>
    <p
      class="mb-0 text-sm"
      :class="problemas ? 'text-n-ruby-11' : 'text-n-teal-11'"
      role="status"
    >
      {{
        problemas
          ? $t('MODELOS_WHATSAPP.CONFERENCIA.FALTA', { n: problemas }, problemas)
          : $t('MODELOS_WHATSAPP.CONFERENCIA.TUDO_CERTO')
      }}
    </p>
    <ul class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="item in itens"
        :key="item.chave"
        :data-item="item.chave"
        :data-ok="item.ok"
        class="flex items-start gap-2.5 text-[0.9375rem]"
        :class="item.ok ? 'text-n-slate-11' : 'text-n-ruby-11 font-medium'"
      >
        <span
          class="mt-0.5 size-5 shrink-0"
          :class="
            item.ok
              ? 'i-lucide-circle-check text-n-teal-10'
              : 'i-lucide-circle-x text-n-ruby-10'
          "
          aria-hidden="true"
        />
        <span>
          <span class="sr-only">
            {{
              item.ok
                ? $t('MODELOS_WHATSAPP.CONFERENCIA.OK')
                : $t('MODELOS_WHATSAPP.CONFERENCIA.CORRIGIR')
            }}
          </span>
          {{ $t(`MODELOS_WHATSAPP.CONFERENCIA.ITENS.${item.chave}`, item.params || {}) }}
        </span>
      </li>
    </ul>
  </section>
</template>
