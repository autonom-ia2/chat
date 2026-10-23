<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { abaDoDesfecho, ehVenda, quemArquivou } from './textosDoArquivado';

// O "Próximo passo" do card arquivado (#2095, passo 5 do protótipo): diz que ele saiu do quadro, quem arquivou e
// onde estava, se a venda continua contando, para onde ele volta e se os retornos pararam. Quem pode arquivar vê
// Restaurar; quem não pode, a frase de quem pedir. O slot `depois` deixa outra parte acrescentar (Excluir de vez).
const props = defineProps({
  card: { type: Object, required: true },
  funil: { type: Object, default: null },
  formato: { type: Object, required: true },
  podeArquivar: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
  erro: { type: String, default: '' },
});
const emit = defineEmits(['restaurar']);

const { t } = useI18n();

// A última atividade 'archive' do card: quem, quando, por quê e quantos retornos pararam.
const arquivamento = computed(() =>
  (props.card.activities || []).find(item => item.event_type === 'archive')
);
const linha = computed(() => {
  const atividade = arquivamento.value;
  if (!atividade) return {};
  const payload = atividade.payload || {};
  let por = { type: 'system' };
  if (payload.by === 'ai') por = { type: 'ai' };
  else if (atividade.actor_type === 'user')
    por = { type: 'user', name: atividade.actor_name };
  return {
    archived_at: atividade.created_at,
    archived_by: por,
    archive_reason: payload.motivo,
  };
});
const quem = computed(() => quemArquivou(t, props.formato, linha.value));
const etapa = computed(() => props.card.stage?.name || '');
const desfecho = computed(
  () => props.card.metadata?.desfecho_arquivado || null
);
const venda = computed(() =>
  ehVenda(desfecho.value, props.funil) && !props.card.value_hidden
    ? props.formato.dinheiro(props.card.value_cents, props.card.currency)
    : ''
);
const aba = computed(() => abaDoDesfecho(t, desfecho.value, props.funil));
const retornosParados = computed(() =>
  Number(arquivamento.value?.payload?.lembretes_cancelados || 0)
);
</script>

<template>
  <section
    data-card-arquivado
    class="flex flex-col gap-3 rounded-2xl border-2 border-n-slate-6 bg-n-solid-1 px-4 py-3 shadow-sm sm:px-5"
  >
    <div class="flex items-start gap-3 sm:gap-4">
      <span
        class="grid size-10 shrink-0 place-items-center rounded-2xl bg-n-slate-3 text-n-slate-11 sm:size-12"
        aria-hidden="true"
      >
        <span class="i-lucide-archive size-5 sm:size-6" />
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1.5">
        <h3 class="mb-0 text-sm font-medium text-n-slate-11">
          {{ t('CRM_ARQUIVADOS.CARD.ROTULO') }}
        </h3>
        <p class="mb-0 text-lg font-semibold leading-snug text-n-slate-12">
          {{ t('CRM_ARQUIVADOS.CARD.FRASE') }}
        </p>
        <p
          v-if="venda"
          data-card-arquivado-venda
          class="mb-0 flex items-start gap-2 rounded-xl bg-n-teal-2 px-3 py-2 text-sm text-n-teal-11"
        >
          <span
            class="i-lucide-check mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ t('CRM_ARQUIVADOS.ARQUIVAR.VENDA', { valor: venda }) }}
        </p>
        <p
          v-if="quem || etapa"
          data-card-arquivado-quem
          class="mb-0 text-sm text-n-slate-11"
        >
          {{
            [quem, etapa ? t('CRM_ARQUIVADOS.CARD.ESTAVA_EM', { etapa }) : '']
              .filter(Boolean)
              .join('. ')
          }}
        </p>
        <p
          v-if="aba"
          data-card-arquivado-aba
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('CRM_ARQUIVADOS.CARD.VAI_PARA_A_LISTA', { aba }) }}
        </p>
        <p
          v-if="retornosParados"
          data-card-arquivado-retornos
          class="mb-0 text-sm text-n-slate-11"
        >
          {{
            t(
              'CRM_ARQUIVADOS.CARD.RETORNOS_PARARAM',
              { count: retornosParados },
              retornosParados
            )
          }}
        </p>
        <p
          v-if="erro"
          role="alert"
          class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
        >
          {{ erro }}
        </p>
        <div v-if="podeArquivar" class="pt-1">
          <Button
            data-card-restaurar
            :label="t('CRM_ARQUIVADOS.RESTAURAR')"
            icon="i-lucide-rotate-ccw"
            class="!min-h-11"
            :is-loading="ocupado"
            :disabled="ocupado"
            @click="emit('restaurar')"
          />
        </div>
        <p
          v-else
          data-sem-permissao
          class="mb-0 flex items-start gap-2 text-sm text-n-slate-11"
        >
          <span
            class="i-lucide-lock mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ t('CRM_ARQUIVADOS.SEM_PERMISSAO') }}
        </p>
        <slot name="depois" />
      </div>
    </div>
  </section>
</template>
