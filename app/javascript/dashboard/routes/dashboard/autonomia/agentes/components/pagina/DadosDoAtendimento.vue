<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import { MAX_ENDERECO } from '../../composables/useDadosDoAtendimento';

// #1479 (opção B) — os dois campos do atendimento, dentro da GavetaAtendimento (bloco "Endereço e telefone" da
// página). Só com a flag agentes_enviar_local_e_contato. O telefone é o campo padrão do painel (CampoDeTelefone): o v-model fica
// vazio enquanto o número não é válido, então "digitou" vem do próprio campo (como no NovaConversaContatoNovo)
// para avisar "incompleto" em vez de salvar vazio calado. O aviso aparece quando a pessoa sai do campo ou tenta
// salvar (`conferir`). `erroDoTelefone`: a explicação do servidor quando ele recusou o número.
const props = defineProps({
  nome: { type: String, required: true },
  conferir: { type: Boolean, default: false },
  bloqueado: { type: Boolean, default: false },
  erroDoTelefone: { type: String, default: '' },
});

const endereco = defineModel('endereco', { type: String, default: '' });
const telefone = defineModel('telefone', { type: String, default: '' });

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.ATENDIMENTO.CAMPOS';

const secao = ref(null);
const digitou = ref(Boolean(telefone.value));
const saiuDoTelefone = ref(false);

const incompleto = computed(() => digitou.value && !telefone.value);
const mostrarAviso = computed(
  () => incompleto.value && (saiuDoTelefone.value || props.conferir)
);
const erro = computed(() =>
  mostrarAviso.value ? t(`${NS}.TELEFONE_INCOMPLETO`) : props.erroDoTelefone
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
  <div ref="secao" data-dados-do-atendimento class="flex flex-col gap-5">
    <Input
      v-model="endereco"
      data-campo-endereco
      :label="t(`${NS}.ENDERECO`)"
      :placeholder="t(`${NS}.ENDERECO_EXEMPLO`)"
      :message="t(`${NS}.ENDERECO_DICA`, { nome })"
      :disabled="bloqueado"
      :maxlength="MAX_ENDERECO"
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
        :erro="erro"
      />
    </div>
  </div>
</template>
