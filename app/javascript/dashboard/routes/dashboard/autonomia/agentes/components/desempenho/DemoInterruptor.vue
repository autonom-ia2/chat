<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { SITUACOES } from '../../utils/desempenhoFonte';

// #2226 v2 (desenho §7, frente D) — o interruptor do protótipo: de onde vêm os números (vida real
// ou demonstração), se a demonstração tem anúncios (estados b e a da origem) e a situação da tabela
// 2.11. Some quando os números vêm da API. Cada escolha vai para o endereço (?fonte, ?anuncio,
// ?estado), para dar link de cada variante; quem guarda o endereço é a página.
const props = defineProps({
  // meta.fonte do painel na tela: 'vida_real' | 'demo' | 'api'.
  fonte: { type: String, required: true },
  anuncios: { type: Boolean, default: true },
  situacao: { type: String, default: '' },
  // Sem o arquivo da vida real nesta máquina, a escolha fica visível, mas desligada.
  vidaRealDisponivel: { type: Boolean, default: true },
});

const emit = defineEmits(['trocar']);

const { t } = useI18n();
const NS = 'AGENTS.DESEMPENHO2.D.DEMO';
const id = useId();
const NORMAL = 'normal';

const visivel = computed(() => props.fonte !== 'api');
const ehDemo = computed(() => props.fonte === 'demo');

const opcoesDeFonte = computed(() => [
  {
    value: 'vida_real',
    label: t(`${NS}.FONTE_VIDA_REAL`),
    disabled: !props.vidaRealDisponivel,
    hint: props.vidaRealDisponivel ? undefined : t(`${NS}.SEM_VIDA_REAL`),
  },
  { value: 'demo', label: t(`${NS}.FONTE_DEMO`) },
]);
const opcoesDeAnuncio = computed(() => [
  { value: '1', label: t(`${NS}.COM_ANUNCIOS`) },
  { value: '0', label: t(`${NS}.SEM_ANUNCIOS`) },
]);
const opcoesDeSituacao = computed(() => [
  { value: NORMAL, label: t(`${NS}.NORMAL`) },
  ...SITUACOES.map(situacao => ({
    value: situacao,
    label: t(`${NS}.SITUACAO_${situacao.toUpperCase()}`),
  })),
]);

const fonteEscolhida = computed({
  get: () => props.fonte,
  set: valor => emit('trocar', { fonte: valor }),
});
const anuncioEscolhido = computed({
  get: () => (props.anuncios ? '1' : '0'),
  set: valor => emit('trocar', { anuncio: valor }),
});
const situacaoEscolhida = computed({
  get: () => props.situacao || NORMAL,
  set: valor =>
    emit('trocar', { estado: valor === NORMAL ? undefined : valor }),
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <section
    v-if="visivel"
    data-demo
    :aria-labelledby="`${id}-titulo`"
    class="flex flex-col gap-3 p-4 border border-dashed rounded-2xl border-n-slate-7 bg-n-slate-2 dark:bg-n-slate-3"
  >
    <header class="flex flex-col gap-0.5">
      <h2
        :id="`${id}-titulo`"
        class="m-0 text-sm font-semibold text-n-slate-12"
      >
        {{ t(`${NS}.TITULO`) }}
      </h2>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t(ehDemo ? `${NS}.TEXTO_DEMO` : `${NS}.TEXTO_VIDA_REAL`) }}
      </p>
    </header>
    <div class="grid gap-3 sm:grid-cols-3">
      <label
        :for="`${id}-fonte`"
        class="flex flex-col gap-1 text-xs font-semibold text-n-slate-11"
      >
        {{ t(`${NS}.FONTE`) }}
        <ChoiceSelect
          v-model="fonteEscolhida"
          data-demo-fonte
          :trigger-id="`${id}-fonte`"
          :options="opcoesDeFonte"
          :aria-label="t(`${NS}.FONTE`)"
        />
      </label>
      <label
        v-if="ehDemo"
        :for="`${id}-anuncio`"
        class="flex flex-col gap-1 text-xs font-semibold text-n-slate-11"
      >
        {{ t(`${NS}.ANUNCIOS`) }}
        <ChoiceSelect
          v-model="anuncioEscolhido"
          data-demo-anuncio
          :trigger-id="`${id}-anuncio`"
          :options="opcoesDeAnuncio"
          :aria-label="t(`${NS}.ANUNCIOS`)"
        />
      </label>
      <label
        :for="`${id}-situacao`"
        class="flex flex-col gap-1 text-xs font-semibold text-n-slate-11"
      >
        {{ t(`${NS}.SITUACAO`) }}
        <ChoiceSelect
          v-model="situacaoEscolhida"
          data-demo-situacao
          :trigger-id="`${id}-situacao`"
          :options="opcoesDeSituacao"
          :aria-label="t(`${NS}.SITUACAO`)"
        />
      </label>
    </div>
  </section>
</template>
