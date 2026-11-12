<script setup>
import { ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { quandoRelativo } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import CartaoDaSecao from './CartaoDaSecao.vue';
import FalhaDaParte from './FalhaDaParte.vue';

// #2894 — as notas: a caixa "Escreva uma nota" e a lista (quem e quando). Guardar
// só emite o texto; a caixa limpa quando a nota entra (`guardando` volta a falso
// sem erro). A nota nova aparece no topo porque a fonte a devolve primeiro.
// Quem só pode ver (`podeEscrever` falso) lê as notas e não tem a caixa.
// `falhou`: a leitura das notas não veio.
const props = defineProps({
  notas: { type: Array, required: true },
  guardando: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
  podeEscrever: { type: Boolean, default: true },
  falhou: { type: Boolean, default: false },
});
const emit = defineEmits(['guardar', 'tentar']);

const { t } = useI18n();
const idioma = useIdioma();
const texto = ref('');
const erro = ref('');
const caixa = ref(null);
const idDoErro = useId();

// Salvar nunca fica desligado por falta de texto: o clique diz o que falta e
// leva o foco à caixa. Quem trabalha (`guardando`) é o único motivo de espera.
const guardar = () => {
  if (props.guardando) return;
  const limpo = texto.value.trim();
  if (!limpo) {
    erro.value = t('RELACIONAMENTOS_FICHA.NOTAS.ESCREVA_ANTES');
    caixa.value?.focus();
    return;
  }
  erro.value = '';
  emit('guardar', limpo);
};
watch(texto, () => {
  erro.value = '';
});

// A tela chama depois de guardar com sucesso.
const limpar = () => {
  texto.value = '';
};
defineExpose({ limpar });

const ra = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.NOTAS.${chave}`, valores);

// Nota de quem já saiu da plataforma vem sem autor: só quando foi escrita.
const assinatura = nota => {
  const quando = quandoRelativo(nota.quando, props.agora, idioma.value);
  return nota.autor ? ra('POR', { autor: nota.autor, quando }) : quando;
};
</script>

<template>
  <CartaoDaSecao :titulo="ra('TITULO')" data-relacionamentos="notas">
    <form
      v-if="podeEscrever"
      class="flex flex-col gap-3 mb-5"
      @submit.prevent="guardar"
    >
      <textarea
        ref="caixa"
        v-model="texto"
        data-relacionamentos="nota-caixa"
        :aria-invalid="erro ? 'true' : undefined"
        :aria-describedby="idDoErro"
        rows="3"
        :aria-label="ra('CAMPO')"
        :placeholder="ra('CAMPO')"
        class="w-full p-3 text-base border-0 resize-y rounded-xl bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak placeholder:text-n-slate-10 focus:outline-n-brand"
      />
      <!-- Região de alerta fixa: nasce vazia e recebe o texto depois. -->
      <p
        :id="idDoErro"
        role="alert"
        data-relacionamentos="nota-erro"
        class="m-0 -mt-1 text-sm break-words text-n-ruby-11"
        :class="{ hidden: !erro }"
      >
        {{ erro }}
      </p>
      <Button
        data-relacionamentos="guardar-nota"
        type="submit"
        slate
        faded
        size="lg"
        class="self-end"
        :is-loading="guardando"
        :label="ra('GUARDAR')"
      />
    </form>
    <FalhaDaParte v-if="falhou" @tentar="emit('tentar')" />
    <p v-else-if="!notas.length" class="m-0 text-base text-n-slate-11">
      {{ ra('VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-4 p-0 m-0 list-none">
      <li
        v-for="nota in notas"
        :key="nota.id"
        data-relacionamentos="nota"
        class="pb-4 border-b border-n-weak last:border-b-0 last:pb-0"
      >
        <p class="m-0 text-base text-n-slate-12">{{ nota.texto }}</p>
        <p class="m-0 mt-1 text-sm text-n-slate-11">
          {{ assinatura(nota) }}
        </p>
      </li>
    </ul>
  </CartaoDaSecao>
</template>
