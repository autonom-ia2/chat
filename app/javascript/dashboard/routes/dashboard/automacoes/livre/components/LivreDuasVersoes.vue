<script setup>
// #3099 (F3 do épico #3095) — no painel "Alterar" do passo "Mandar mensagem" da Automação livre, abaixo do texto (e
// do modelo, quando há): "Testar duas versões desta mensagem". Ligado, a versão 2 é outro texto, com o mesmo "Pôr um
// dado" (LivreTexto, sem a ajuda que a versão 1 já mostra), e outro modelo aprovado quando o passo usa modelo para a conversa de 24 horas fechada
// (LivreModelo). Embaixo, o plano em frases e o "Alterar" (DuasVersoesRegra, no jeito da automação).
//
// A receita ganha `versoes` no passo: { texto: [...pedaços], modelo: { nome, idioma, variaveis } | null, criterio,
// divisao, espera }. Desligar tira a chave. O LivreAlterar põe esta peça no lugar do campo `versoes` do catálogo (peça
// `duas_versoes`) e só deixa salvar com a versão 2 pronta e diferente da 1 (versoesDoPasso.js). Quem sorteia a versão
// de cada pessoa e escolhe a melhor é o servidor (Autonomia::Automacao::DuasVersoes).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ToggleSwitch from 'dashboard/components-next/toggle-switch/ToggleSwitch.vue';
import DuasVersoesRegra from 'dashboard/components-next/CampaignJourney/DuasVersoesRegra.vue';
import { regraPadrao } from 'dashboard/components-next/CampaignJourney/duasVersoes';
import LivreTexto from './LivreTexto.vue';
import LivreModelo from './LivreModelo.vue';
import { versoesIguais } from '../versoesDoPasso';

const props = defineProps({
  // O passo "mensagem" inteiro: { id, tipo, texto, modelo?, versoes? }
  modelValue: { type: Object, required: true },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
  podeMedirCompras: { type: Boolean, default: true },
});
const emit = defineEmits(['update:modelValue']);

const NS = 'DUAS_VERSOES.AUTOMACAO';
const { t } = useI18n();

const versoes = computed(() => props.modelValue.versoes || null);
const ligado = computed(() => Boolean(versoes.value));
const comModelo = computed(() => Boolean(props.modelValue.modelo));
const iguais = computed(() => versoesIguais(props.modelValue));
const regra = computed(() => ({
  criterio: versoes.value?.criterio,
  divisao: versoes.value?.divisao,
  espera: versoes.value?.espera,
}));

const ligar = liga => {
  if (!liga) {
    const { versoes: _tirado, ...semVersoes } = props.modelValue;
    emit('update:modelValue', semVersoes);
    return;
  }
  emit('update:modelValue', {
    ...props.modelValue,
    versoes: { texto: [], modelo: null, ...regraPadrao() },
  });
};
const mudar = patch =>
  emit('update:modelValue', {
    ...props.modelValue,
    versoes: { ...versoes.value, ...patch },
  });
</script>

<template>
  <section
    class="flex flex-col gap-4 rounded-2xl border p-4"
    :class="ligado ? 'border-n-blue-7 bg-n-solid-1' : 'border-n-weak'"
    data-livre-duas-versoes
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
          <h3 class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('DUAS_VERSOES.MENSAGEM.TITULO') }}
          </h3>
          <p class="m-0 text-sm text-n-slate-11">
            {{
              ligado
                ? t('DUAS_VERSOES.MENSAGEM.AJUDA_LIGADO')
                : t(`${NS}.AJUDA_DESLIGADO`)
            }}
          </p>
        </div>
      </div>
      <ToggleSwitch
        :model-value="ligado"
        :label="t(`${NS}.LIGAR`)"
        data-ligar-duas-versoes
        @update:model-value="ligar"
      />
    </div>

    <template v-if="ligado">
      <LivreTexto
        :rotulo="t(`${NS}.TEXTO_2`)"
        :model-value="versoes.texto"
        sem-ajuda
        :catalogo="catalogo"
        :atributos-do="atributosDo"
        @update:model-value="texto => mudar({ texto })"
      />
      <LivreModelo
        v-if="comModelo"
        :rotulo="t(`${NS}.MODELO_2`)"
        :model-value="versoes.modelo"
        sem-ajuda
        da-segunda-versao
        :catalogo="catalogo"
        :atributos-do="atributosDo"
        @update:model-value="modelo => mudar({ modelo })"
      />
      <p
        v-if="iguais"
        role="status"
        class="m-0 rounded-xl bg-n-amber-2 px-4 py-3 text-sm text-n-amber-12"
        data-versoes-iguais
      >
        {{ t('DUAS_VERSOES.MENSAGEM.IGUAL') }}
      </p>
      <div class="border-t border-n-weak pt-4">
        <DuasVersoesRegra
          :regra="regra"
          na-automacao
          :pode-medir-compras="podeMedirCompras"
          @update="novaRegra => mudar(novaRegra)"
        />
      </div>
    </template>
  </section>
</template>
