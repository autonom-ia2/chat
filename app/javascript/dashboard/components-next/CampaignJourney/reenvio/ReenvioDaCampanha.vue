<script setup>
// #3101 — na revisão da campanha, depois de "Quando começa": mandar uma segunda mensagem, X dias depois, para quem não
// respondeu (ou não leu, no WhatsApp Oficial). Entra fechado, como as outras linhas da revisão (o resumo e "Alterar"):
// quem não mexe manda uma vez só, como hoje.
//
// A segunda mensagem passa pelo limite e pelo horário da conta, como qualquer mensagem de campanha. Quem respondeu,
// saiu da lista ou ficou bloqueado nesse meio-tempo não recebe.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/toggle-switch/ToggleSwitch.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TemplateVariableBindings from '../TemplateVariableBindings.vue';
import {
  DIAS_DO_REENVIO,
  MENSAGEM,
  comMudanca,
  faltaNoReenvio,
  mensagemDoCanal,
  modelosQueVao,
  quemPodeEscolher,
  reenvioNovo,
} from './reenvio';

const props = defineProps({
  // null = não manda de novo; senão { quem, dias, modeloId, ligacoes, texto, assunto } (reenvio.js).
  modelValue: { type: Object, default: null },
  // CAMPAIGN_CHANNELS da campanha.
  canal: { type: String, required: true },
  // WhatsApp Oficial: os outros modelos da caixa, como o passo 2 os oferece (ponte.opcoesDeModelo, sem o modelo da
  // primeira mensagem): [{ value, label, disabled, corpo, variaveis, ligacoes }]. `label` é o nome amigável;
  // `corpo` já vem preenchido com os dados da primeira pessoa do público (como "Como o cliente vê"); `variaveis` são as
  // do modelo (templateVariables, rotuladas pela ponte) e `ligacoes`, as que já vêm prontas: as do catálogo
  // (ponte.ligacoesIniciais) e as da primeira mensagem quando a variável tem o mesmo nome.
  modelos: { type: Array, default: () => [] },
  // De onde as variáveis podem vir, as mesmas do passo 2 (TemplateVariableBindings).
  colunas: { type: Array, default: () => [] },
  gruposDeCampos: { type: Array, default: () => [] },
  // Quantos caracteres cabem na segunda mensagem de texto (SMS e WhatsApp API).
  maximoDoTexto: { type: Number, default: 1000 },
});
const emit = defineEmits(['update:modelValue']);

const NS = 'REENVIO_HORARIO.REENVIO';
const NS_REVISAO = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW';
const { t } = useI18n();
const aberto = ref(false);
// O vermelho do modelo só depois de a pessoa passar pela escolha (não antes de ela mexer em nada).
const tocou = ref(false);
// Para ler o começo do modelo no resumo fechado.
const INICIO_DO_MODELO = 60;

const ligado = computed(() => Boolean(props.modelValue));
const tipo = computed(() => mensagemDoCanal(props.canal));
const opcoesDeQuem = computed(() => quemPodeEscolher(props.canal));
const modeloEscolhido = computed(() =>
  props.modelos.find(modelo => modelo.value === props.modelValue?.modeloId)
);
const falta = computed(() =>
  faltaNoReenvio(props.modelValue, props.canal, modeloEscolhido.value)
);
const opcoesDeModelo = computed(() =>
  props.modelos.map(({ value, label, disabled }) => ({
    value,
    label,
    disabled: Boolean(disabled),
  }))
);
// WhatsApp Oficial sem outro modelo que vá: não dá para mandar de novo, e o interruptor fica apagado com o motivo
// (como o melhor horário quando ninguém respondeu). Já ligado, ainda dá para desligar.
const semModelos = computed(
  () => tipo.value === MENSAGEM.MODELO && !modelosQueVao(props.modelos).length
);
const variaveisDoModelo = computed(() => modeloEscolhido.value?.variaveis || []);
// O que a pessoa recebe na segunda vez, no balão de exemplo.
const exemplo = computed(() => {
  if (tipo.value === MENSAGEM.MODELO) return modeloEscolhido.value?.corpo || '';
  if (tipo.value === MENSAGEM.TEXTO) return props.modelValue?.texto || '';
  return '';
});

const dias = computed(() => props.modelValue?.dias);
const quemTexto = computed(() =>
  t(`${NS}.QUEM_RESUMO.${(props.modelValue?.quem || '').toUpperCase()}`)
);
const resumo = computed(() =>
  ligado.value
    ? t(
        `${NS}.RESUMO_LIGADO`,
        { dias: dias.value, quem: quemTexto.value },
        dias.value
      )
    : t(`${NS}.RESUMO_DESLIGADO`)
);
// O começo do texto do modelo, cortado numa palavra; o nome amigável quando a página não mandou o corpo.
const detalheDoModelo = () => {
  const corpo = (modeloEscolhido.value?.corpo || '').trim();
  if (!corpo)
    return t(`${NS}.DETALHE_TEXTO`, { texto: modeloEscolhido.value?.label });
  if (corpo.length <= INICIO_DO_MODELO)
    return t(`${NS}.DETALHE_TEXTO`, { texto: corpo });
  const corte = corpo.slice(0, INICIO_DO_MODELO);
  const inicio = corte.slice(0, corte.lastIndexOf(' ')) || corte;
  return t(`${NS}.DETALHE_MODELO`, { inicio });
};
const detalhe = computed(() => {
  if (!ligado.value) return t(`${NS}.DETALHE_DESLIGADO`);
  if (falta.value) return t(`${NS}.FALTA.${falta.value}`);
  if (tipo.value === MENSAGEM.MODELO) return detalheDoModelo();
  if (tipo.value === MENSAGEM.ASSUNTO)
    return t(`${NS}.DETALHE_ASSUNTO`, { assunto: props.modelValue.assunto });
  return t(`${NS}.DETALHE_TEXTO`, { texto: props.modelValue.texto });
});

const mudar = mudanca =>
  emit('update:modelValue', comMudanca(props.modelValue, mudanca));
// Ligado, já vem pronto: o texto (SMS e WhatsApp API) ou o assunto (e-mail) de exemplo, que a pessoa pode mudar.
const alternar = novo => {
  tocou.value = false;
  emit(
    'update:modelValue',
    novo
      ? reenvioNovo({
          texto:
            tipo.value === MENSAGEM.TEXTO ? t(`${NS}.TEXTO_EXEMPLO`) : '',
          assunto:
            tipo.value === MENSAGEM.ASSUNTO ? t(`${NS}.ASSUNTO_EXEMPLO`) : '',
        })
      : null
  );
};
// Trocar de modelo traz as ligações que já vêm prontas para ele.
const escolherModelo = modeloId => {
  const modelo = props.modelos.find(item => item.value === modeloId);
  mudar({ modeloId, ligacoes: { ...(modelo?.ligacoes || {}) } });
};
const ligar = (chave, ligacao) =>
  mudar({
    ligacoes: { ...(props.modelValue?.ligacoes || {}), [chave]: ligacao },
  });

// As pílulas levam `border-solid`: o _base.scss tira a borda de todo <button>, e sem ela a opção não escolhida não
// parece um botão.
const classeDaPilula = escolhida =>
  escolhida
    ? 'border-n-blue-8 bg-n-blue-2 text-n-blue-11'
    : 'border-n-slate-6 text-n-slate-12 hover:bg-n-alpha-1';
</script>

<template>
  <div class="border-t border-n-weak py-4" data-reenvio>
    <div
      v-if="!aberto"
      class="flex items-start justify-between gap-3"
      data-resumo
    >
      <div class="flex min-w-0 flex-col gap-1">
        <p class="m-0 text-xs font-semibold uppercase text-n-slate-11">
          {{ t(`${NS}.TITULO`) }}
        </p>
        <p class="m-0 break-words text-sm font-semibold text-n-slate-12">
          {{ resumo }}
        </p>
        <p
          class="m-0 line-clamp-2 break-words text-xs"
          :class="falta ? 'text-n-ruby-11' : 'text-n-slate-11'"
          data-reenvio-detalhe
        >
          {{ detalhe }}
        </p>
      </div>
      <Button
        :label="t(`${NS_REVISAO}.CHANGE`)"
        :aria-label="
          t(`${NS_REVISAO}.CHANGE_ARIA`, { block: t(`${NS}.TITULO`) })
        "
        variant="ghost"
        size="sm"
        class="!min-h-11 shrink-0"
        data-alterar
        @click="aberto = true"
      />
    </div>

    <fieldset v-else class="m-0 flex flex-col gap-4 border-0 p-0">
      <legend class="mb-2 text-xs font-semibold uppercase text-n-slate-11">
        {{ t(`${NS}.TITULO`) }}
      </legend>

      <div class="flex items-start justify-between gap-3">
        <div class="flex min-w-0 flex-col gap-1">
          <p class="m-0 text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.LIGAR`) }}
          </p>
          <p
            id="reenvio-ligar-ajuda"
            class="m-0 text-xs text-n-slate-11"
            data-reenvio-ligar-ajuda
          >
            {{ semModelos ? t(`${NS}.SEM_MODELOS`) : t(`${NS}.LIGAR_AJUDA`) }}
          </p>
        </div>
        <ToggleSwitch
          :model-value="ligado"
          :label="t(`${NS}.LIGAR`)"
          :disabled="semModelos && !ligado"
          described-by="reenvio-ligar-ajuda"
          data-reenvio-ligar
          @update:model-value="alternar"
        />
      </div>

      <template v-if="ligado">
        <div v-if="opcoesDeQuem.length > 1" class="flex flex-col gap-2">
          <p id="reenvio-quem" class="m-0 text-sm text-n-slate-12">
            {{ t(`${NS}.QUEM`) }}
          </p>
          <div
            class="flex flex-wrap gap-2"
            role="radiogroup"
            aria-labelledby="reenvio-quem"
          >
            <button
              v-for="quem in opcoesDeQuem"
              :key="quem"
              type="button"
              role="radio"
              :aria-checked="modelValue.quem === quem"
              :data-quem="quem"
              class="flex min-h-11 flex-col items-start justify-center rounded-xl border border-solid px-4 py-1.5 text-start text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :class="classeDaPilula(modelValue.quem === quem)"
              @click="mudar({ quem })"
            >
              <span>{{ t(`${NS}.QUEM_OPCAO.${quem.toUpperCase()}`) }}</span>
              <span class="text-xs font-normal text-n-slate-11">
                {{ t(`${NS}.QUEM_AJUDA.${quem.toUpperCase()}`) }}
              </span>
            </button>
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <p id="reenvio-dias" class="m-0 text-sm text-n-slate-12">
            {{ t(`${NS}.DEPOIS_DE`) }}
          </p>
          <div
            class="flex flex-wrap gap-2"
            role="radiogroup"
            aria-labelledby="reenvio-dias"
          >
            <button
              v-for="opcao in DIAS_DO_REENVIO"
              :key="opcao"
              type="button"
              role="radio"
              :aria-checked="modelValue.dias === opcao"
              :data-dias="opcao"
              class="min-h-11 rounded-xl border border-solid px-4 text-sm font-medium tabular-nums focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :class="classeDaPilula(modelValue.dias === opcao)"
              @click="mudar({ dias: opcao })"
            >
              {{ t(`${NS}.DIAS`, { n: opcao }, opcao) }}
            </button>
          </div>
        </div>

        <div class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-4">
          <p class="m-0 text-sm font-medium text-n-slate-12">
            {{
              tipo === MENSAGEM.ASSUNTO
                ? t(`${NS}.SEGUNDO_EMAIL`)
                : t(`${NS}.SEGUNDA_MENSAGEM`)
            }}
          </p>
          <template v-if="tipo === MENSAGEM.MODELO">
            <p class="m-0 text-xs text-n-slate-11">
              {{ t(`${NS}.MODELO_AJUDA`) }}
            </p>
            <div @focusout="tocou = true">
              <ChoiceSelect
                :model-value="modelValue.modeloId ?? ''"
                :options="opcoesDeModelo"
                :placeholder="t(`${NS}.MODELO_ESCOLHER`)"
                :aria-label="t(`${NS}.MODELO_LABEL`)"
                :invalid="tocou && falta === 'SEM_MODELO'"
                :disabled="semModelos"
                data-reenvio-modelo
                @update:model-value="escolherModelo"
              />
            </div>
            <!-- As variáveis do segundo modelo, como no passo 2: já vêm ligadas às da primeira mensagem e às do
                 catálogo; a pessoa só escolhe o que sobrou. A mensagem sai dias depois, sem ela por perto. -->
            <TemplateVariableBindings
              v-if="variaveisDoModelo.length"
              :variables="variaveisDoModelo"
              :bindings="modelValue.ligacoes || {}"
              :columns="colunas"
              :extra-groups="gruposDeCampos"
              data-reenvio-ligacoes
              @bind="ligar"
            />
          </template>
          <template v-else-if="tipo === MENSAGEM.TEXTO">
            <p class="m-0 text-xs text-n-slate-11">
              {{ t(`${NS}.TEXTO_AJUDA`) }}
            </p>
            <TextArea
              :model-value="modelValue.texto"
              :placeholder="t(`${NS}.TEXTO_EXEMPLO`)"
              :max-length="maximoDoTexto"
              show-character-count
              auto-height
              min-height="5rem"
              data-reenvio-texto
              @update:model-value="texto => mudar({ texto })"
            />
          </template>
          <template v-else-if="tipo === MENSAGEM.ASSUNTO">
            <p class="m-0 text-xs text-n-slate-11">
              {{ t(`${NS}.ASSUNTO_AJUDA`) }}
            </p>
            <Input
              :model-value="modelValue.assunto"
              :label="t(`${NS}.ASSUNTO_LABEL`)"
              :placeholder="t(`${NS}.ASSUNTO_EXEMPLO`)"
              custom-input-class="!h-11"
              data-reenvio-assunto
              @update:model-value="assunto => mudar({ assunto })"
            />
          </template>

          <div
            v-if="exemplo"
            class="mt-1 rounded-2xl bg-n-teal-2 p-3"
            data-reenvio-exemplo
          >
            <p class="m-0 mb-1 text-xs text-n-slate-11">
              {{ t(`${NS}.COMO_CHEGA`) }}
            </p>
            <p
              class="m-0 max-w-sm whitespace-pre-wrap break-words rounded-2xl rounded-tl-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm"
            >
              {{ exemplo }}
            </p>
          </div>
        </div>

        <p
          class="m-0 flex items-start gap-2 text-xs text-n-slate-11"
          data-reenvio-regras
        >
          <span
            class="i-lucide-shield-check mt-0.5 size-3.5 shrink-0"
            aria-hidden="true"
          />
          {{ t(`${NS}.REGRAS`) }}
        </p>
      </template>

      <Button
        :label="t(`${NS}.PRONTO`)"
        variant="outline"
        color="slate"
        size="sm"
        class="!min-h-11 self-start"
        data-reenvio-pronto
        @click="aberto = false"
      />
    </fieldset>
  </div>
</template>
