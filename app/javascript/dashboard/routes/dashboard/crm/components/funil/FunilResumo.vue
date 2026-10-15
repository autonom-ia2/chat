<script setup>
import { computed } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import FunilResumoCartao from './FunilResumoCartao.vue';
import FunilCartaoVendas from './FunilCartaoVendas.vue';
import FunilCartaoQuandoUsar from './FunilCartaoQuandoUsar.vue';
import { rotuloDoTempo, tempoDoLembrete } from './lembretesAtender';

// #1384 — Editar: o funil inteiro em frases, cada parte com "Alterar". O que
// falta aparece em âmbar, com um botão só.
const props = defineProps({
  etapas: { type: Array, required: true },
  semFrase: { type: Array, default: () => [] },
  quandoUsar: { type: String, default: '' },
  venda: { type: Boolean, default: true },
  meta: { type: [String, Number], default: '' },
  dinheiro: { type: Function, required: true },
  comRetorno: { type: Boolean, default: false },
  retorno: { type: Object, default: null },
  caixas: { type: Array, default: () => [] },
  anuncios: { type: Array, default: () => [] },
  arquivando: { type: Boolean, default: false },
  juntar: { type: Function, required: true },
  // #1498 — o nome dos dois desfechos, para "Para que serve".
  sucesso: { type: String, default: '' },
  fracasso: { type: String, default: '' },
  // #1498 — lembretes de Atender ligados e o modelo do funil.
  lembretesAtender: { type: Object, default: null },
  modelo: { type: String, default: '' },
});

defineEmits(['abrir', 'criar', 'arquivar']);

const { t } = useI18n();

const primeira = computed(() => props.etapas[0]?.name || '');
// #1498 — o que os lembretes de Atender fazem, numa frase.
const fraseAtender = computed(() => {
  const ligados = props.lembretesAtender || {};
  if (props.modelo === 'COBRANCA')
    return ligados.payment
      ? 'CRM_FUNIL.RESUMO.COBRAR_LEMBRETES'
      : 'CRM_FUNIL.RESUMO.ATENDER_SEM_LEMBRETES';
  if (ligados.progress && ligados.resolved_check)
    return 'CRM_FUNIL.RESUMO.ATENDER_LEMBRETES';
  if (ligados.progress) return 'CRM_FUNIL.RESUMO.ATENDER_SO_ANDAMENTO';
  if (ligados.resolved_check) return 'CRM_FUNIL.RESUMO.ATENDER_SO_RESOLVEU';
  return 'CRM_FUNIL.RESUMO.ATENDER_SEM_LEMBRETES';
});
// #1589 — o tempo escolhido de cada lembrete entra na frase do resumo.
const temposAtender = computed(() => ({
  andamento: t(
    rotuloDoTempo(tempoDoLembrete(props.lembretesAtender, 'progress'))
  ),
  resolveu: t(
    rotuloDoTempo(tempoDoLembrete(props.lembretesAtender, 'resolved_check'))
  ),
  sucesso: props.sucesso,
}));
const ultima = computed(() => props.etapas.at(-1)?.name || '');
const nomesSemFrase = computed(() =>
  props.semFrase.map(etapa => etapa.name.trim() || '…')
);
</script>

<template>
  <!-- #1498 — Vender ou Atender sempre à vista, no topo. -->
  <FunilCartaoVendas
    :venda="venda"
    :meta="meta"
    :dinheiro="dinheiro"
    :sucesso="sucesso"
    :fracasso="fracasso"
    @alterar="$emit('abrir', 'sales')"
  />
  <FunilResumoCartao
    parte="stages"
    icone="i-lucide-columns-3"
    :titulo="$t('CRM_FUNIL.ETAPAS.ROTULO')"
    :falta="semFrase.length > 0"
    @alterar="$emit('abrir', 'stages')"
  >
    <I18nT keypath="CRM_FUNIL.RESUMO.ETAPAS" tag="span" scope="global">
      <template #etapas>
        <strong class="font-semibold">
          {{
            $t('CRM_FUNIL.CONFIRA.ETAPAS', { n: etapas.length }, etapas.length)
          }}
        </strong>
      </template>
      <template #primeira>
        <strong class="font-semibold">{{ primeira }}</strong>
      </template>
      <template #ultima>
        <strong class="font-semibold">{{ ultima }}</strong>
      </template>
    </I18nT>
    <template v-if="semFrase.length" #extra>
      <div
        data-resumo-falta
        class="mt-2 flex flex-col items-start gap-3 rounded-xl border border-dashed border-n-amber-8 bg-n-amber-2 p-3 sm:flex-row sm:items-center"
      >
        <I18nT
          keypath="CRM_FUNIL.RESUMO.FALTA_FRASE"
          tag="span"
          scope="global"
          :plural="semFrase.length"
          class="min-w-0 text-[0.9375rem] text-n-slate-12 sm:flex-1"
        >
          <template #nomes>
            <strong class="font-semibold">{{ juntar(nomesSemFrase) }}</strong>
          </template>
        </I18nT>
        <Button
          data-resumo-sugerir
          :label="$t('CRM_FUNIL.ETAPAS.CRIAR_IA')"
          icon="i-lucide-sparkles"
          amber
          class="!min-h-11"
          @click="$emit('criar', semFrase[0])"
        />
      </div>
    </template>
  </FunilResumoCartao>
  <FunilCartaoQuandoUsar
    :texto="quandoUsar"
    @alterar="$emit('abrir', 'about')"
  />
  <FunilResumoCartao
    v-if="comRetorno"
    parte="returns"
    icone="i-lucide-bell-ring"
    tom="bg-n-iris-3 text-n-iris-11"
    :titulo="$t('CRM_FUNIL.RETORNO.ROTULO')"
    @alterar="$emit('abrir', 'returns')"
  >
    <template v-if="!retorno">{{ $t('CRM_FUNIL.CARREGANDO') }}</template>
    <template v-else-if="!venda">
      {{ $t(fraseAtender, temposAtender) }}
    </template>
    <I18nT
      v-else-if="retorno.enabled"
      :keypath="
        retorno.mode === 'ai_reminder'
          ? 'CRM_FUNIL.RESUMO.RETORNO_EQUIPE'
          : 'CRM_FUNIL.RESUMO.RETORNO'
      "
      tag="span"
      scope="global"
    >
      <template #vezes>
        <strong class="font-semibold">
          {{
            $t(
              'CRM_FUNIL.RESUMO.ATE_VEZES',
              { n: retorno.maxTouches },
              retorno.maxTouches
            )
          }}
        </strong>
      </template>
    </I18nT>
    <template v-else>{{ $t('CRM_FUNIL.RESUMO.RETORNO_DESLIGADO') }}</template>
  </FunilResumoCartao>
  <FunilResumoCartao
    parte="inboxes"
    icone="i-lucide-inbox"
    tom="bg-n-teal-3 text-n-teal-11"
    :titulo="$t('CRM_FUNIL.CAIXAS.ROTULO')"
    @alterar="$emit('abrir', 'inboxes')"
  >
    <I18nT
      v-if="caixas.length"
      keypath="CRM_FUNIL.RESUMO.CAIXAS"
      tag="span"
      scope="global"
    >
      <template #nomes>
        <strong class="font-semibold">{{ juntar(caixas) }}</strong>
      </template>
    </I18nT>
    <template v-else>{{ $t('CRM_FUNIL.RESUMO.CAIXAS_NENHUMA') }}</template>
  </FunilResumoCartao>
  <FunilResumoCartao
    v-if="venda"
    parte="ads"
    icone="i-lucide-megaphone"
    tom="bg-n-ruby-3 text-n-ruby-11"
    :titulo="$t('CRM_FUNIL.ANUNCIOS.ROTULO')"
    @alterar="$emit('abrir', 'ads')"
  >
    <I18nT
      v-if="anuncios.length"
      keypath="CRM_FUNIL.RESUMO.ANUNCIOS"
      tag="span"
      scope="global"
    >
      <template #quem>
        <strong class="font-semibold">{{ juntar(anuncios) }}</strong>
      </template>
    </I18nT>
    <template v-else>{{ $t('CRM_FUNIL.RESUMO.ANUNCIOS_DESLIGADO') }}</template>
  </FunilResumoCartao>
  <div
    data-pipeline-archive
    class="mt-2 flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-5"
  >
    <p class="mb-0 min-w-0 flex-1 text-sm text-n-slate-11">
      {{ $t('CRM_KANBAN.PIPELINE_DRAWER.ARCHIVE_HINT') }}
    </p>
    <Button
      :label="$t('CRM_KANBAN.PIPELINE_DRAWER.ARCHIVE')"
      icon="i-lucide-archive"
      ruby
      ghost
      class="!min-h-11 shrink-0"
      :is-loading="arquivando"
      @click="$emit('arquivar')"
    />
  </div>
</template>
