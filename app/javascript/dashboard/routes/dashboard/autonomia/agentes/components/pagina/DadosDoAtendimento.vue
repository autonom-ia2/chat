<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';

// #1479 (opção A) — os dois campos do atendimento, logo abaixo das instruções (GavetaInstrucoes). Só aparece com a
// flag agentes_enviar_local_e_contato. O telefone é o campo padrão do painel (CampoDeTelefone): o v-model fica
// vazio enquanto o número não é válido, então "digitou" vem do próprio campo (como no NovaConversaContatoNovo)
// para avisar "incompleto" em vez de salvar vazio calado. O aviso aparece quando a pessoa sai do campo ou tenta
// salvar (`conferir`).
const props = defineProps({
  nome: { type: String, required: true },
  conferir: { type: Boolean, default: false },
  bloqueado: { type: Boolean, default: false },
});

const endereco = defineModel('endereco', { type: String, default: '' });
const telefone = defineModel('telefone', { type: String, default: '' });

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.INSTRUCOES.ATENDIMENTO';
const base = `atendimento-${useId()}`;

const secao = ref(null);
const digitou = ref(Boolean(telefone.value));
const saiuDoTelefone = ref(false);

const incompleto = computed(() => digitou.value && !telefone.value);
const mostrarAviso = computed(
  () => incompleto.value && (saiuDoTelefone.value || props.conferir)
);

const aoDigitarTelefone = evento => {
  digitou.value = Boolean(String(evento.target?.value || '').trim());
};

// Salvar com o número incompleto: leva a pessoa ao campo, com o bloco inteiro (e o aviso) à vista.
const focarTelefone = () => {
  secao.value?.scrollIntoView?.({ block: 'nearest' });
  secao.value
    ?.querySelector('input[data-numero-do-telefone]')
    ?.focus({ preventScroll: true });
};

defineExpose({ incompleto, focarTelefone });
</script>

<template>
  <section
    ref="secao"
    data-dados-do-atendimento
    :aria-labelledby="`${base}-titulo`"
    class="flex flex-col gap-4 p-4 rounded-xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
  >
    <div class="flex flex-col gap-1">
      <h3
        :id="`${base}-titulo`"
        class="m-0 text-sm font-semibold text-n-slate-12"
      >
        {{ t(`${NS}.TITULO`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.DICA`, { nome }) }}
      </p>
    </div>
    <Input
      v-model="endereco"
      data-campo-endereco
      :label="t(`${NS}.ENDERECO`)"
      :placeholder="t(`${NS}.ENDERECO_EXEMPLO`)"
      :message="t(`${NS}.ENDERECO_DICA`, { nome })"
      :disabled="bloqueado"
      wrap-message
      autocomplete="street-address"
    />
    <div
      data-campo-telefone-atendimento
      @input="aoDigitarTelefone"
      @focusout="saiuDoTelefone = true"
    >
      <CampoDeTelefone
        v-model="telefone"
        :label="t(`${NS}.TELEFONE`)"
        :rotulo-do-pais="t(`${NS}.PAIS`)"
        :ajuda="t(`${NS}.TELEFONE_DICA`, { nome })"
        :erro="mostrarAviso ? t(`${NS}.TELEFONE_INCOMPLETO`) : ''"
      />
    </div>
  </section>
</template>
