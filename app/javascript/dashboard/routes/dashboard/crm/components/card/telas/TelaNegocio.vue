<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CampoValor from '../campos/CampoValor.vue';
import CampoUrgencia from '../campos/CampoUrgencia.vue';
import CampoFecharAte from '../campos/CampoFecharAte.vue';
import CrmCardCustomFields from '../../CrmCardCustomFields.vue';

// #1423 — o negócio: nome, observações, quanto vale (moeda por escolha),
// urgência em quatro botões, e em "Mais detalhes" quanto pede atenção (0 a
// 100) e quando deve fechar. As informações extras do card salvam uma a uma,
// como hoje (CF-01). Sem permissão, tudo fica só para ler.
const props = defineProps({
  card: { type: Object, required: true },
  podeGerenciar: { type: Boolean, default: false },
});
const titulo = defineModel('titulo', { type: String, default: '' });
const descricao = defineModel('descricao', { type: String, default: '' });
const valor = defineModel('valor', { type: [String, Number], default: '' });
const moeda = defineModel('moeda', { type: String, default: 'BRL' });
const urgencia = defineModel('urgencia', { type: String, default: 'medium' });
const atencao = defineModel('atencao', { type: [String, Number], default: 0 });
const fecharAte = defineModel('fecharAte', { type: String, default: '' });

const { t } = useI18n();
const N = 'CRM_CARD.NEGOCIO';
const maisAberto = ref(Boolean(Number(atencao.value) || fecharAte.value));
const somenteLeitura = computed(() => !props.podeGerenciar);
// O aviso de nome vazio só aparece depois que a pessoa mexe no campo.
const mexeuNoNome = ref(false);
const faltaNome = computed(() => mexeuNoNome.value && !titulo.value.trim());
</script>

<template>
  <section class="flex flex-col gap-5" data-tela="negocio">
    <p
      v-if="somenteLeitura"
      class="mb-0 rounded-xl bg-n-alpha-2 p-3 text-sm text-n-slate-11"
    >
      {{ t('CRM_CARD.SO_LEITURA') }}
    </p>
    <Input
      v-model="titulo"
      data-negocio-titulo
      :readonly="somenteLeitura"
      :label="t(`${N}.NOME`)"
      :placeholder="t(`${N}.TITULO_EXEMPLO`)"
      :message="faltaNome ? t(`${N}.TITULO_FALTA`) : ''"
      :message-type="faltaNome ? 'error' : 'info'"
      @update:model-value="mexeuNoNome = true"
    />
    <TextArea
      v-model="descricao"
      :label="t(`${N}.OBSERVACOES`)"
      :placeholder="t(`${N}.OBSERVACOES_EXEMPLO`)"
      :disabled="somenteLeitura"
      :max-length="5000"
      auto-height
      min-height="6rem"
    />
    <CampoValor
      v-model:valor="valor"
      v-model:moeda="moeda"
      :somente-leitura="somenteLeitura"
    />
    <CampoUrgencia v-model="urgencia" :somente-leitura="somenteLeitura" />

    <details
      class="group rounded-2xl border border-n-weak bg-n-solid-1"
      :open="maisAberto"
      @toggle="maisAberto = $event.currentTarget.open"
    >
      <summary
        class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 rounded-2xl px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 [&::-webkit-details-marker]:hidden"
      >
        {{ t(`${N}.MAIS`) }}
        <span
          class="i-lucide-chevron-down size-4 text-n-slate-10 transition-transform group-open:rotate-180"
          aria-hidden="true"
        />
      </summary>
      <div class="flex flex-col gap-5 border-t border-n-weak p-4">
        <Input
          v-model="atencao"
          type="number"
          min="0"
          max="100"
          :readonly="somenteLeitura"
          :label="t(`${N}.ATENCAO`)"
          :message="t(`${N}.ATENCAO_DICA`)"
          class="max-w-[22rem]"
        />
        <CampoFecharAte v-model="fecharAte" :somente-leitura="somenteLeitura" />
      </div>
    </details>

    <CrmCardCustomFields :card="card" :can-manage="podeGerenciar" />
  </section>
</template>
