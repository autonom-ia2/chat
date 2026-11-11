<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { formatarMes } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import BotaoCopiar from './BotaoCopiar.vue';
import MenuMais from './MenuMais.vue';

// #2894 — o cabeçalho da ficha da pessoa: quem é, desde quando é cliente, como
// falar com ela, e as ações. Só "Conversar" é preenchido.
const props = defineProps({
  pessoa: { type: Object, required: true },
  marcandoCliente: { type: Boolean, default: false },
});
const emit = defineEmits([
  'conversar',
  'novoCard',
  'lembrete',
  'marcarCliente',
  'abrirEmpresa',
  'maisAcao',
]);

const { t } = useI18n();
const idioma = useIdioma();

const ehCliente = computed(() => props.pessoa.contact_type === 'customer');
const clienteDesde = computed(() =>
  props.pessoa.customer_since
    ? t('RELACIONAMENTOS_FICHA.CABECALHO.CLIENTE_DESDE', {
        data: formatarMes(props.pessoa.customer_since, idioma.value),
      })
    : t('RELACIONAMENTOS.COMUM.SELO_CLIENTE')
);
const empresa = computed(
  () => props.pessoa.additional_attributes?.company_name || ''
);
</script>

<template>
  <header
    data-relacionamentos="cabecalho"
    class="flex flex-col gap-6 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:p-8 lg:flex-row lg:items-start lg:justify-between"
  >
    <div class="flex min-w-0 gap-4 md:gap-6">
      <Avatar
        :name="pessoa.name"
        :src="pessoa.thumbnail"
        :size="88"
        rounded-full
        class="shrink-0"
      />
      <div class="flex flex-col min-w-0 gap-2">
        <h1
          class="m-0 text-3xl font-bold leading-tight tracking-tight break-words md:text-4xl text-n-slate-12"
        >
          {{ pessoa.name }}
        </h1>
        <div class="flex flex-wrap items-center gap-2">
          <SeloDeEstado v-if="ehCliente" tom="cliente">
            {{ clienteDesde }}
          </SeloDeEstado>
          <Button
            v-else
            data-relacionamentos="marcar-cliente"
            slate
            ghost
            size="sm"
            class="min-h-11"
            :is-loading="marcandoCliente"
            :label="t('RELACIONAMENTOS_FICHA.CABECALHO.MARCAR_CLIENTE')"
            @click="emit('marcarCliente')"
          />
        </div>
        <div
          v-if="pessoa.phone_number"
          class="flex items-center gap-1 text-base text-n-slate-12"
        >
          <span class="tabular-nums">{{ pessoa.phone_number }}</span>
          <BotaoCopiar
            :valor="pessoa.phone_number"
            :item="t('RELACIONAMENTOS_FICHA.CABECALHO.ITEM_TELEFONE')"
          />
        </div>
        <p v-if="pessoa.email" class="m-0 text-base break-all text-n-slate-11">
          {{ pessoa.email }}
        </p>
        <button
          v-if="empresa && pessoa.company_id"
          type="button"
          data-relacionamentos="empresa-da-pessoa"
          class="self-start text-base font-medium text-start text-n-blue-11 hover:underline min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('abrirEmpresa', pessoa.company_id)"
        >
          {{ empresa }}
        </button>
        <p v-else-if="empresa" class="m-0 text-base text-n-slate-11">
          {{ empresa }}
        </p>
        <ul
          v-if="pessoa.labels?.length"
          :aria-label="t('RELACIONAMENTOS_FICHA.CABECALHO.ETIQUETAS')"
          class="flex flex-wrap gap-2 p-0 m-0 list-none"
        >
          <li
            v-for="etiqueta in pessoa.labels"
            :key="etiqueta"
            class="px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-iris-3 text-n-iris-11"
          >
            {{ etiqueta }}
          </li>
        </ul>
      </div>
    </div>
    <div
      role="group"
      :aria-label="
        t('RELACIONAMENTOS_FICHA.CABECALHO.ACOES', { nome: pessoa.name })
      "
      class="flex flex-wrap items-center gap-3 shrink-0"
    >
      <Button
        data-relacionamentos="conversar"
        size="lg"
        class="!min-h-12 !rounded-xl"
        icon="i-lucide-message-circle"
        :label="t('RELACIONAMENTOS.COMUM.CONVERSAR')"
        @click="emit('conversar')"
      />
      <Button
        slate
        faded
        class="min-h-11"
        :label="t('RELACIONAMENTOS_FICHA.ACOES.NOVO_CARD')"
        @click="emit('novoCard')"
      />
      <Button
        slate
        faded
        class="min-h-11"
        :label="t('RELACIONAMENTOS_FICHA.ACOES.LEMBRETE')"
        @click="emit('lembrete')"
      />
      <MenuMais @acao="escolha => emit('maisAcao', escolha)" />
    </div>
  </header>
</template>
