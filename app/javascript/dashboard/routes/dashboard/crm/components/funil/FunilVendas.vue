<script setup>
import Input from 'dashboard/components-next/input/Input.vue';
import FunilTipo from './FunilTipo.vue';
import { TIPOS, tipoDaVenda } from './funil';
import { useCrmPermissions } from '../../composables/useCrmPermissions';

// #1384 — se o funil conta como venda, a meta do mês e o nome do resultado.
// #1498 — "conta como venda" virou a pergunta do tipo (Vender ou Atender),
// a mesma da criação. Atender não tem meta.
defineProps({
  padraoSucesso: { type: String, required: true },
  padraoFracasso: { type: String, required: true },
  // #1876 — símbolo da moeda do funil (R$, US$, €…).
  moeda: { type: String, required: true },
});

const venda = defineModel('venda', { type: Boolean, default: true });
const meta = defineModel('meta', { type: [String, Number], default: '' });
const sucesso = defineModel('sucesso', { type: String, default: '' });
const fracasso = defineModel('fracasso', { type: String, default: '' });
// #2075 — a meta do mês é dinheiro: sem a chave de valores o campo não aparece (o servidor guarda a que existe).
const { canSeeSalesValues } = useCrmPermissions();
</script>

<template>
  <div data-pipeline-outcome class="flex flex-col gap-5">
    <FunilTipo
      compacto
      :tipo="tipoDaVenda(venda)"
      @escolher="venda = TIPOS.find(item => item.chave === $event).venda"
    />

    <label
      v-if="venda && canSeeSalesValues"
      class="flex flex-col gap-1 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
    >
      <span class="text-base font-semibold text-n-slate-12">
        {{ $t('CRM_FUNIL.VENDAS.META') }}
      </span>
      <span class="text-[0.9375rem] text-n-slate-11">
        {{ $t('CRM_FUNIL.VENDAS.META_AJUDA') }}
      </span>
      <span
        class="mt-2 flex min-h-12 max-w-xs items-center rounded-xl border border-n-weak bg-n-solid-1 focus-within:outline focus-within:outline-2 focus-within:outline-n-brand"
      >
        <span class="pe-2 ps-4 text-base text-n-slate-11">
          {{ moeda }}
        </span>
        <input
          v-model="meta"
          type="number"
          min="0"
          step="100"
          inputmode="decimal"
          class="reset-base !mb-0 min-w-0 flex-1 border-0 bg-transparent py-2.5 pe-4 text-lg font-semibold text-n-slate-12 outline-none placeholder:font-normal placeholder:text-n-slate-10"
          :placeholder="$t('CRM_FUNIL.VENDAS.META_EXEMPLO')"
        />
      </span>
    </label>

    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
    >
      <div>
        <h4 class="mb-1 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_FUNIL.VENDAS.NOMES') }}
        </h4>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{
            $t('CRM_FUNIL.VENDAS.NOMES_AJUDA', {
              sucesso: padraoSucesso,
              fracasso: padraoFracasso,
            })
          }}
        </p>
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <Input
          v-model="sucesso"
          :label="$t('CRM_FUNIL.VENDAS.SUCESSO')"
          :placeholder="padraoSucesso"
          custom-input-class="!h-12 !rounded-xl !bg-n-solid-1 !px-4 !text-base shadow-sm"
        />
        <Input
          v-model="fracasso"
          :label="$t('CRM_FUNIL.VENDAS.FRACASSO')"
          :placeholder="padraoFracasso"
          custom-input-class="!h-12 !rounded-xl !bg-n-solid-1 !px-4 !text-base shadow-sm"
        />
      </div>
    </section>
  </div>
</template>
