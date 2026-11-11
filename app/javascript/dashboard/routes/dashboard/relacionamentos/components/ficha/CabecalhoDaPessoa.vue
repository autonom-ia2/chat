<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { formatarMes } from '../../ficha/formatos';
import { formatarTelefone } from '../../lista/telefone';
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
    class="flex flex-col w-full min-w-0 gap-6 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:p-8 lg:flex-row lg:items-start lg:justify-between"
  >
    <div class="flex w-full min-w-0 gap-4 md:gap-6">
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
        <div class="flex flex-col min-w-0 gap-1">
          <div
            v-if="pessoa.phone_number"
            data-contato="telefone"
            class="flex items-center min-w-0 gap-2 text-base text-n-slate-12"
          >
            <span
              class="i-lucide-phone size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            <span class="tabular-nums">
              {{ formatarTelefone(pessoa.phone_number) }}
            </span>
            <BotaoCopiar
              class="-my-2"
              :valor="pessoa.phone_number"
              :item="t('RELACIONAMENTOS_FICHA.CABECALHO.ITEM_TELEFONE')"
            />
          </div>
          <div
            v-if="pessoa.email"
            data-contato="email"
            class="flex items-center min-w-0 gap-2 text-base text-n-slate-11"
          >
            <span
              class="i-lucide-mail size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            <span class="min-w-0 break-all" :title="pessoa.email">
              {{ pessoa.email }}
            </span>
          </div>
          <div
            v-if="empresa"
            data-contato="empresa"
            class="flex items-center min-w-0 gap-2 text-base text-n-slate-11"
          >
            <span
              class="i-lucide-building-2 size-4 shrink-0 text-n-slate-10"
              aria-hidden="true"
            />
            <button
              v-if="pessoa.company_id"
              type="button"
              data-relacionamentos="empresa-da-pessoa"
              class="p-0 -my-2 font-medium bg-transparent border-0 min-w-0 text-start text-n-blue-11 hover:underline min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="emit('abrirEmpresa', pessoa.company_id)"
            >
              {{ empresa }}
            </button>
            <span v-else class="min-w-0 break-words">{{ empresa }}</span>
          </div>
        </div>
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
      class="flex flex-col w-full min-w-0 gap-3 lg:w-auto lg:flex-row lg:items-center lg:shrink-0"
    >
      <Button
        data-relacionamentos="conversar"
        size="lg"
        class="w-full lg:w-auto !min-h-12 !rounded-xl"
        icon="i-lucide-message-circle"
        :label="t('RELACIONAMENTOS.COMUM.CONVERSAR')"
        @click="emit('conversar')"
      />
      <div
        data-relacionamentos="acoes-secundarias"
        class="grid grid-cols-[1fr_1fr_auto] items-center gap-3 lg:flex"
      >
        <Button
          slate
          faded
          class="w-full min-h-11"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.NOVO_CARD')"
          @click="emit('novoCard')"
        />
        <Button
          slate
          faded
          class="w-full min-h-11"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.LEMBRETE')"
          @click="emit('lembrete')"
        />
        <MenuMais @acao="escolha => emit('maisAcao', escolha)" />
      </div>
    </div>
  </header>
</template>
