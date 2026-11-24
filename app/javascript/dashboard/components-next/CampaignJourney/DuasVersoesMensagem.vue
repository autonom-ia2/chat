<script setup>
// #3099 (F3 do épico #3095) — no passo Mensagem da Nova campanha, abaixo da mensagem do canal: "Testar duas versões".
// Desligado por padrão, numa linha só. Ligado, a versão 1 é a mensagem já escolhida acima e a pessoa monta a versão 2
// no jeito do canal: outro texto (WhatsApp API e SMS), outro modelo aprovado (WhatsApp Oficial) ou outro assunto
// (e-mail). Embaixo, o plano em frases com o "Alterar" (DuasVersoesRegra).
//
// Só a tela: recebe tudo por props e devolve o objeto inteiro em `update` (o `draft.duasVersoes` de campaignDraft).
// Não toca no passo de quando/agendamento (F5, #3101).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ToggleSwitch from 'dashboard/components-next/toggle-switch/ToggleSwitch.vue';
import SegundaVersaoTexto from './SegundaVersaoTexto.vue';
import SegundaVersaoModelo from './SegundaVersaoModelo.vue';
import SegundaVersaoAssunto from './SegundaVersaoAssunto.vue';
import DuasVersoesRegra from './DuasVersoesRegra.vue';
import { CAMPAIGN_CHANNELS } from './campaignChannels';
import { motivoDaSegunda } from './duasVersoes';

const props = defineProps({
  canal: { type: String, required: true },
  // { ligado, texto, templateId, assunto, criterio, divisao, espera }
  versoes: { type: Object, required: true },
  // A versão 1, do próprio rascunho: { texto, templateId, assunto }.
  primeira: { type: Object, default: () => ({}) },
  // Quantas pessoas vão receber (o "Vão receber", já sem o grupo de controle).
  publico: { type: Number, default: 0 },
  // O plano do teste contado pelo servidor (recipient_previews), quando já chegou.
  plano: { type: Object, default: null },
  podeMedirCompras: { type: Boolean, default: true },
  // WhatsApp Oficial: os modelos aprovados da caixa (SegundaVersaoModelo).
  modelos: { type: Array, default: () => [] },
  // E-mail: as ideias de assunto da IA, o remetente e o texto de prévia.
  sugestoesDeAssunto: { type: Array, default: () => [] },
  remetente: { type: String, default: '' },
  previaDoEmail: { type: String, default: '' },
  // Texto livre: as colunas do público, o primeiro cliente e os textos padrão (para a prévia).
  extraColumns: { type: Array, default: () => [] },
  sample: { type: Object, default: null },
  defaults: { type: Object, default: () => ({}) },
  // Quem chama liga depois de a pessoa tentar seguir sem a versão 2.
  mostrarFalta: { type: Boolean, default: false },
  // "Como escolher a melhor" já aberto (a revisão volta aqui pelo "Alterar" da regra).
  regraAberta: { type: Boolean, default: false },
});
const emit = defineEmits(['update', 'criarModelo']);

const NS = 'DUAS_VERSOES.MENSAGEM';
const { t } = useI18n();

const ehOficial = computed(
  () => props.canal === CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL
);
const ehEmail = computed(() => props.canal === CAMPAIGN_CHANNELS.EMAIL);
const motivo = computed(() =>
  motivoDaSegunda(props.canal, props.versoes, props.primeira)
);
// Igual à versão 1 é um problema (âmbar). A caixa ainda vazia é só o próximo passo: dica neutra, sem alarme. O
// "Continuar" fica desligado enquanto falta a versão 2, então não há tentativa de seguir para pintar de âmbar.
const aviso = computed(() => {
  if (motivo.value === 'IGUAL')
    return { texto: t(`${NS}.IGUAL`), problema: true };
  if (motivo.value === 'VAZIA' && props.mostrarFalta)
    return { texto: t(`${NS}.VAZIA`), problema: false };
  return null;
});
// No e-mail, a versão 1 foi montada no editor próprio e não aparece acima: a ajuda fala do e-mail e do assunto.
const ajuda = computed(() => {
  if (!props.versoes.ligado) return t(`${NS}.AJUDA_DESLIGADO`);
  return t(ehEmail.value ? `${NS}.AJUDA_LIGADO_EMAIL` : `${NS}.AJUDA_LIGADO`);
});
const regra = computed(() => ({
  criterio: props.versoes.criterio,
  divisao: props.versoes.divisao,
  espera: props.versoes.espera,
}));

const mudar = patch => emit('update', { ...props.versoes, ...patch });
</script>

<template>
  <section
    class="flex flex-col gap-4 rounded-2xl border bg-n-solid-1 p-4 shadow-sm sm:p-5"
    :class="versoes.ligado ? 'border-n-blue-7' : 'border-n-weak'"
    data-duas-versoes
  >
    <div class="flex items-start justify-between gap-3">
      <div class="flex min-w-0 items-start gap-3">
        <span
          class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-lucide-split size-5" />
        </span>
        <div class="flex min-w-0 flex-col gap-1">
          <h2 class="m-0 text-base font-semibold text-n-slate-12">
            {{ t(`${NS}.TITULO`) }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">
            {{ ajuda }}
          </p>
        </div>
      </div>
      <ToggleSwitch
        :model-value="versoes.ligado"
        :label="t(`${NS}.LIGAR`)"
        data-ligar-duas-versoes
        @update:model-value="ligado => mudar({ ligado })"
      />
    </div>

    <template v-if="versoes.ligado">
      <SegundaVersaoModelo
        v-if="ehOficial"
        :modelos="modelos"
        :primeira-id="primeira.templateId"
        :template-id="versoes.templateId"
        @update="templateId => mudar({ templateId })"
        @criar="emit('criarModelo')"
      />
      <SegundaVersaoAssunto
        v-else-if="ehEmail"
        :assunto="versoes.assunto"
        :primeira="primeira.assunto || ''"
        :sugestoes="sugestoesDeAssunto"
        :remetente="remetente"
        :previa="previaDoEmail"
        @update="assunto => mudar({ assunto })"
      />
      <SegundaVersaoTexto
        v-else
        :canal="canal"
        :texto="versoes.texto"
        :primeira="primeira.texto || ''"
        :extra-columns="extraColumns"
        :sample="sample"
        :defaults="defaults"
        @update="texto => mudar({ texto })"
      />

      <p
        v-if="aviso"
        role="status"
        class="m-0 flex items-start gap-2 rounded-xl px-4 py-3 text-sm"
        :class="
          aviso.problema
            ? 'bg-n-amber-2 text-n-amber-12'
            : 'bg-n-alpha-1 text-n-slate-11'
        "
        :data-aviso-da-2="aviso.problema ? 'problema' : 'dica'"
      >
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ aviso.texto }}
      </p>

      <div class="border-t border-n-weak pt-4">
        <DuasVersoesRegra
          :regra="regra"
          :publico="publico"
          :plano="plano"
          :pode-medir-compras="podeMedirCompras"
          :comeca-aberto="regraAberta"
          @update="novaRegra => mudar(novaRegra)"
        />
      </div>
    </template>
  </section>
</template>
