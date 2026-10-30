<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import EscolhaRadio from 'dashboard/routes/dashboard/autonomia/agentes/components/EscolhaRadio.vue';
import { useFormato } from '../card/useFormato';
import { useArquivarFunil } from './useArquivarFunil';
import { motivoDoErro } from './motivoDoErro';

// Arquivar o funil (#2095, passos 8 e 9). Pede o que fazer com os cards abertos ("Mover para outro funil" já
// marcado; "Guardar junto" diz o que para) e com as caixas de entrada que criam card nele ("Passar para outro
// funil" já marcado, apontando para o destino dos cards; "Deixar sem funil" avisa). Funil principal: escolhe o novo
// antes. Único funil ativo: não deixa. Tudo vai num pedido só; se falhar, nada muda.
const props = defineProps({
  carregarEtapas: { type: Function, required: true },
});
const emit = defineEmits(['arquivado', 'criarFunil']);

const { t, locale } = useI18n();
const formato = useFormato({ t, locale });
const dialogo = ref(null);
const enviando = ref(false);
const erro = ref('');
const estado = useArquivarFunil({ carregarEtapas: props.carregarEtapas });
const {
  funil,
  outros,
  previa,
  carregando,
  erroPrevia,
  erroEtapas,
  passo,
  novoPrincipal,
  destino,
  funilDestino,
  etapaDestino,
  etapasDestino,
  caixas,
  funilDasCaixas,
  abertos,
  caixasQueCriam,
  retornos,
  reunioes,
  pronto,
} = estado;

const opcoesDeFunil = computed(() =>
  outros.value.map(item => ({ value: item.id, label: item.name }))
);
const opcoesDeEtapa = computed(() =>
  etapasDestino.value.map(etapa => ({ value: etapa.id, label: etapa.name }))
);
const nomeDoFunil = id => outros.value.find(item => item.id === id)?.name || '';
const nomesDasCaixas = computed(() =>
  formato.juntar(caixasQueCriam.value.map(caixa => caixa.name))
);
const umaCaixa = computed(() => caixasQueCriam.value.length === 1);
// Caixa que também cria card em outro funil ativo continua criando lá (CardSyncer: o primeiro funil ativo ligado).
const comOutroFunil = computed(() =>
  caixasQueCriam.value.filter(caixa => caixa.other_pipelines?.length)
);
const avisoSemFunil = computed(() => {
  const sem = caixasQueCriam.value.filter(
    caixa => !caixa.other_pipelines?.length
  );
  const frases = comOutroFunil.value.map(caixa =>
    t('CRM_ARQUIVADOS.FUNIL.CAIXA_VAI_PARA_OUTRO', {
      caixa: caixa.name,
      funil: caixa.other_pipelines[0].name,
    })
  );
  if (sem.length)
    frases.unshift(
      t(
        sem.length === 1
          ? 'CRM_ARQUIVADOS.FUNIL.CAIXAS_SEM_FUNIL_UMA'
          : 'CRM_ARQUIVADOS.FUNIL.CAIXAS_SEM_FUNIL',
        { caixas: formato.juntar(sem.map(caixa => caixa.name)) }
      )
    );
  return frases.join(' ');
});

const titulo = computed(() => {
  if (passo.value === 'unico')
    return t('CRM_ARQUIVADOS.FUNIL.UNICO_TITULO', { funil: funil.value?.name });
  if (passo.value === 'principal')
    return t('CRM_ARQUIVADOS.FUNIL.PRINCIPAL_TITULO', {
      funil: funil.value?.name,
    });
  return t('CRM_ARQUIVADOS.FUNIL.TITULO', { funil: funil.value?.name });
});
const descricao = computed(() => {
  if (passo.value === 'unico') return t('CRM_ARQUIVADOS.FUNIL.UNICO_TEXTO');
  if (passo.value === 'principal')
    return t('CRM_ARQUIVADOS.FUNIL.PRINCIPAL_TEXTO');
  if (!previa.value) return '';
  return abertos.value
    ? t(
        'CRM_ARQUIVADOS.FUNIL.TEXTO_COM_CARDS',
        { count: abertos.value },
        abertos.value
      )
    : t('CRM_ARQUIVADOS.FUNIL.TEXTO_SEM_CARDS');
});

const opcoesDosCards = computed(() => {
  const param = retornos.value
    ? ` ${t('CRM_ARQUIVADOS.FUNIL.PARAM', { count: retornos.value }, retornos.value)}`
    : '';
  return [
    {
      valor: 'mover',
      titulo: t('CRM_ARQUIVADOS.FUNIL.MOVER'),
      texto: t('CRM_ARQUIVADOS.FUNIL.MOVER_TEXTO'),
    },
    {
      valor: 'guardar',
      titulo: t('CRM_ARQUIVADOS.FUNIL.GUARDAR'),
      texto: `${t('CRM_ARQUIVADOS.FUNIL.GUARDAR_TEXTO')}${param}`,
    },
  ];
});
// "Deixar sem funil": o texto diz o que acontece com as caixas que já criam card em outro funil, ou com a única.
const textoDoParar = computed(() => {
  if (comOutroFunil.value.length)
    return t('CRM_ARQUIVADOS.FUNIL.CAIXAS_PARAR_TEXTO_LIGADAS');
  if (umaCaixa.value) return t('CRM_ARQUIVADOS.FUNIL.CAIXAS_PARAR_TEXTO_UMA');
  return t('CRM_ARQUIVADOS.FUNIL.CAIXAS_PARAR_TEXTO');
});
const opcoesDasCaixas = computed(() => [
  {
    valor: 'passar',
    titulo: t('CRM_ARQUIVADOS.FUNIL.CAIXAS_PASSAR'),
    texto: t('CRM_ARQUIVADOS.FUNIL.CAIXAS_PASSAR_TEXTO'),
  },
  {
    valor: 'parar',
    titulo: t('CRM_ARQUIVADOS.FUNIL.CAIXAS_PARAR'),
    texto: textoDoParar.value,
  },
]);
const resumoDosCards = computed(() => {
  const etapa = etapasDestino.value.find(e => e.id === etapaDestino.value);
  if (!funilDestino.value || !etapa) return '';
  return t(
    'CRM_ARQUIVADOS.FUNIL.VAO_PARA',
    {
      count: abertos.value,
      funil: nomeDoFunil(funilDestino.value),
      etapa: etapa.name,
    },
    abertos.value
  );
});
const resumoDasCaixas = computed(() => {
  if (!funilDasCaixas.value) return '';
  return t('CRM_ARQUIVADOS.FUNIL.CAIXAS_ENTRAM', {
    caixas: nomesDasCaixas.value,
    funil: nomeDoFunil(funilDasCaixas.value),
    etapa: estado.primeiraEtapa(funilDasCaixas.value)?.name || '',
  });
});
const novoPrincipalNome = computed(() => nomeDoFunil(novoPrincipal.value));

const abrir = async ({ alvo, ativos }) => {
  erro.value = '';
  enviando.value = false;
  dialogo.value?.open();
  await estado.abrir({ alvo, ativos });
};
const fechar = () => dialogo.value?.close();

const confirmar = async () => {
  if (!pronto.value || enviando.value) return;
  enviando.value = true;
  erro.value = '';
  try {
    const { resposta, params } = await estado.arquivar();
    emit('arquivado', {
      funil: funil.value,
      resposta,
      abertos: abertos.value,
      moveu: Boolean(params.move_to_stage_id),
      guardou: Boolean(abertos.value) && !params.move_to_stage_id,
      funilDestino: params.move_to_stage_id ? funilDestino.value : null,
      nomeDoDestino: nomeDoFunil(funilDestino.value),
      caixas: caixasQueCriam.value.map(caixa => caixa.name),
      funilDasCaixas: params.inboxes_to_pipeline_id || null,
      nomeDoFunilDasCaixas: nomeDoFunil(params.inboxes_to_pipeline_id),
    });
    fechar();
  } catch (error) {
    // Arquivar em lotes (#2145): a recusa pode chegar depois de parte dos cards já ter ido para o destino.
    const levados = Number(error?.response?.data?.moved_count || 0);
    const motivo = motivoDoErro(t, error);
    erro.value = levados
      ? t(
          'CRM_ARQUIVADOS.FUNIL.ERRO_PARCIAL',
          { motivo, count: levados },
          levados
        )
      : t('CRM_ARQUIVADOS.FUNIL.ERRO', { motivo });
    if (levados) await estado.recarregarPrevia();
  } finally {
    enviando.value = false;
  }
};

defineExpose({ abrir, fechar });
</script>

<template>
  <Dialog
    ref="dialogo"
    data-arquivar-funil
    :data-passo="passo"
    type="alert"
    :title="titulo"
    :description="descricao"
    width="lg"
    overflow-y-auto
    :close-on-outside-click="false"
  >
    <div class="flex flex-col gap-4">
      <div v-if="carregando" aria-busy="true" class="flex flex-col gap-2">
        <span class="sr-only">{{ t('CRM_ARQUIVADOS.CARREGANDO') }}</span>
        <div class="h-12 animate-pulse rounded-xl bg-n-alpha-2" />
        <div class="h-12 animate-pulse rounded-xl bg-n-alpha-2" />
      </div>
      <p
        v-else-if="erroPrevia"
        role="alert"
        class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{
          t('CRM_ARQUIVADOS.FUNIL.ERRO_PREVIA', {
            motivo: motivoDoErro(t, erroPrevia),
          })
        }}
      </p>

      <template v-else-if="passo === 'principal'">
        <label class="flex flex-col gap-1 text-sm font-medium text-n-slate-12">
          {{ t('CRM_ARQUIVADOS.FUNIL.NOVO_PRINCIPAL') }}
          <ChoiceSelect
            v-model="novoPrincipal"
            data-funil-novo-principal
            :options="opcoesDeFunil"
            :aria-label="t('CRM_ARQUIVADOS.FUNIL.NOVO_PRINCIPAL')"
            :placeholder="t('CRM_ARQUIVADOS.ESCOLHA')"
            class="w-full"
          />
        </label>
      </template>

      <template v-else-if="passo === 'escolha' && previa">
        <p
          v-if="novoPrincipal"
          data-funil-principal-nota
          class="mb-0 flex items-start gap-2 rounded-xl bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
        >
          <span
            class="i-lucide-star mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{
            t('CRM_ARQUIVADOS.FUNIL.VIRA_PRINCIPAL', {
              funil: novoPrincipalNome,
            })
          }}
        </p>

        <section v-if="abertos" data-funil-cards class="flex flex-col gap-2">
          <p class="mb-0 text-sm font-semibold text-n-slate-12">
            {{ t('CRM_ARQUIVADOS.FUNIL.O_QUE_FAZER') }}
          </p>
          <EscolhaRadio
            v-model="destino"
            :rotulo="t('CRM_ARQUIVADOS.FUNIL.O_QUE_FAZER')"
            :opcoes="opcoesDosCards"
          />
          <div
            v-if="destino === 'mover'"
            data-funil-destino
            class="grid gap-3 rounded-xl bg-n-alpha-1 p-3 sm:grid-cols-2"
          >
            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
            >
              {{ t('CRM_ARQUIVADOS.FUNIL.FUNIL') }}
              <ChoiceSelect
                :model-value="funilDestino"
                :options="opcoesDeFunil"
                :aria-label="t('CRM_ARQUIVADOS.FUNIL.FUNIL')"
                class="w-full"
                @update:model-value="estado.escolherDestino"
              />
            </label>
            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
            >
              {{ t('CRM_ARQUIVADOS.FUNIL.ETAPA') }}
              <ChoiceSelect
                v-model="etapaDestino"
                :options="opcoesDeEtapa"
                :aria-label="t('CRM_ARQUIVADOS.FUNIL.ETAPA')"
                :placeholder="t('CRM_ARQUIVADOS.ESCOLHA')"
                class="w-full"
              />
            </label>
            <p
              v-if="resumoDosCards"
              data-funil-resumo
              class="mb-0 text-sm text-n-slate-11 sm:col-span-2"
            >
              {{ resumoDosCards }}
            </p>
          </div>
          <p
            v-else-if="reunioes"
            data-funil-reunioes
            class="mb-0 flex items-start gap-2 rounded-xl bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
          >
            <span
              class="i-lucide-calendar mt-0.5 size-4 shrink-0"
              aria-hidden="true"
            />
            {{
              t('CRM_ARQUIVADOS.FUNIL.REUNIOES', { count: reunioes }, reunioes)
            }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CRM_ARQUIVADOS.FUNIL.JA_ARQUIVADOS') }}
          </p>
        </section>

        <section
          v-if="caixasQueCriam.length"
          data-funil-caixas
          class="flex flex-col gap-2"
        >
          <p class="mb-0 text-sm font-semibold text-n-slate-12">
            {{
              t(
                umaCaixa
                  ? 'CRM_ARQUIVADOS.FUNIL.CAIXAS_UMA'
                  : 'CRM_ARQUIVADOS.FUNIL.CAIXAS_VARIAS',
                { caixas: nomesDasCaixas }
              )
            }}
          </p>
          <EscolhaRadio
            v-model="caixas"
            :rotulo="t('CRM_ARQUIVADOS.FUNIL.CAIXAS_ROTULO')"
            :opcoes="opcoesDasCaixas"
          />
          <div
            v-if="caixas === 'passar'"
            class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-3"
          >
            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
            >
              {{ t('CRM_ARQUIVADOS.FUNIL.CAIXAS_DESTINO') }}
              <ChoiceSelect
                :model-value="funilDasCaixas"
                data-funil-caixas-destino
                :options="opcoesDeFunil"
                :aria-label="t('CRM_ARQUIVADOS.FUNIL.CAIXAS_DESTINO')"
                class="w-full"
                @update:model-value="estado.escolherFunilDasCaixas"
              />
            </label>
            <p
              v-if="resumoDasCaixas"
              data-funil-caixas-resumo
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ resumoDasCaixas }}
            </p>
          </div>
          <p
            v-else
            data-funil-caixas-aviso
            class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
          >
            <span
              class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0"
              aria-hidden="true"
            />
            {{ avisoSemFunil }}
          </p>
        </section>
      </template>

      <p
        v-if="erroEtapas"
        role="alert"
        data-funil-erro-etapas
        class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{
          t('CRM_ARQUIVADOS.FUNIL.ERRO_ETAPAS', {
            motivo: motivoDoErro(t, erroEtapas),
          })
        }}
      </p>
      <p
        v-if="erro"
        role="alert"
        data-funil-erro
        class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{ erro }}
      </p>
    </div>
    <template #footer>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          type="button"
          :label="t('CRM_ARQUIVADOS.CANCELAR')"
          slate
          faded
          class="!min-h-11"
          :disabled="enviando"
          @click="fechar"
        />
        <Button
          v-if="passo === 'unico'"
          type="button"
          :label="t('CRM_ARQUIVADOS.FUNIL.CRIAR_FUNIL')"
          icon="i-lucide-plus"
          class="!min-h-11"
          @click="
            fechar();
            emit('criarFunil');
          "
        />
        <Button
          v-else-if="passo === 'principal'"
          type="button"
          data-funil-continuar
          :label="t('CRM_ARQUIVADOS.FUNIL.CONTINUAR')"
          class="!min-h-11"
          :disabled="!novoPrincipal || carregando"
          @click="estado.continuarComPrincipal"
        />
        <Button
          v-else
          type="button"
          data-funil-confirmar
          :label="t('CRM_ARQUIVADOS.FUNIL.BOTAO')"
          icon="i-lucide-archive"
          ruby
          class="!min-h-11"
          :is-loading="enviando"
          :disabled="!pronto || enviando"
          @click="confirmar"
        />
      </div>
    </template>
  </Dialog>
</template>
