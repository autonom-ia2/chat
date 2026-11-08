<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2696 — o pedido em uma frase, no topo da porta. A IA da conta lê a frase e
// a página preenche "O quê?", "Onde?" e os ajustes; a pessoa confere antes de
// tocar em "Achar empresas". Quem interpreta é só a IA (pela fonte, API ou
// demonstração). Erro ou "não entendi": os campos ficam como estão, e a
// frase abaixo do campo diz o que fazer. Nada falha calado. `ocupado` sobe
// para a página, que trava "O quê?" e "Onde?" enquanto a IA responde: a
// resposta nunca passa por cima do que a pessoa escreveu nesse meio-tempo.
const props = defineProps({
  interpretar: { type: Function, required: true },
});
const emit = defineEmits(['entendeu']);

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.PORTA.FRASE';
// O mesmo teto do servidor (SearchInterpreter::MAX_TEXT).
const MAX_LETRAS = 300;

const texto = ref('');
const ocupado = defineModel('ocupado', { type: Boolean, default: false });
const resultado = ref(null);

const vazio = computed(() => !texto.value.trim());
const AVISOS = {
  confira: { tom: 'text-n-teal-11', icone: 'i-lucide-circle-check' },
  nao_entendeu: { tom: 'text-n-amber-11', icone: 'i-lucide-triangle-alert' },
  erro: { tom: 'text-n-ruby-11', icone: 'i-lucide-circle-alert' },
  sem_ia: { tom: 'text-n-ruby-11', icone: 'i-lucide-circle-alert' },
};
const aviso = computed(() =>
  resultado.value
    ? {
        ...AVISOS[resultado.value.tipo],
        texto: t(`${NS}.${resultado.value.tipo.toUpperCase()}`),
      }
    : null
);

const preencher = async () => {
  if (vazio.value || ocupado.value) return;
  ocupado.value = true;
  resultado.value = null;
  try {
    const entendido = await props.interpretar(texto.value.trim());
    if (entendido.entendeu) {
      emit('entendeu', entendido);
      resultado.value = { tipo: 'confira', ficouDeFora: entendido.ficouDeFora };
    } else {
      resultado.value = { tipo: 'nao_entendeu' };
    }
  } catch (erro) {
    resultado.value = {
      tipo:
        erro?.codigo === 'prospecting.interpret.ai_not_configured'
          ? 'sem_ia'
          : 'erro',
    };
  } finally {
    ocupado.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-1.5" data-frase>
    <label for="achar-frase" class="text-sm font-semibold text-n-slate-11">
      {{ $t(`${NS}.ROTULO`) }}
    </label>
    <div class="flex flex-col gap-2 md:flex-row">
      <input
        id="achar-frase"
        v-model="texto"
        type="text"
        autocomplete="off"
        :maxlength="MAX_LETRAS"
        :placeholder="$t(`${NS}.PLACEHOLDER`)"
        aria-describedby="achar-frase-aviso"
        class="flex-1 w-full !h-12 px-3 text-base border outline-none !mb-0 rounded-xl border-n-slate-6 bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-blue-9"
        data-campo-frase
        @keydown.enter.prevent="preencher"
      />
      <Button
        type="button"
        faded
        :label="ocupado ? $t(`${NS}.BOTAO_OCUPADO`) : $t(`${NS}.BOTAO`)"
        :is-loading="ocupado"
        :disabled="vazio || ocupado"
        icon="i-lucide-sparkles"
        class="!min-h-12 !rounded-xl !px-5 !text-base"
        data-preencher
        @click="preencher"
      />
    </div>
    <div id="achar-frase-aviso" aria-live="polite">
      <p
        v-if="aviso"
        class="flex items-start gap-1.5 m-0 text-sm"
        :class="aviso.tom"
        data-aviso-frase
      >
        <span :class="aviso.icone" class="size-4 mt-0.5 shrink-0" />
        <span>
          {{ aviso.texto }}
          <span
            v-if="resultado.ficouDeFora"
            class="block text-n-slate-11"
            data-ficou-de-fora
          >
            {{ resultado.ficouDeFora }}
          </span>
        </span>
      </p>
    </div>
  </div>
</template>
