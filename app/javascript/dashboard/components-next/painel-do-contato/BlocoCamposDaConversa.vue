<script setup>
// #2538 — os campos da conversa (atributos personalizados de conversa), como o
// bloco "Informação da conversa" do painel antigo: todos os definidos, inclusive
// os vazios. É aqui que quem atende vê o que uma automação (o passo "extrair")
// ou outra pessoa preencheu. Edita com a mesma permissão de antes: quem opera a
// conversa (#1800); quem só lê vê o valor, sem os botões de editar. Grava pelo
// updateCustomAttributes, como o CustomAttributes do painel antigo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CustomAttribute from 'dashboard/components/CustomAttribute.vue';
import BlocoDoPainel from './BlocoDoPainel.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  podeOperar: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const definicoes = computed(() =>
  getters['attributes/getAttributesByModel'].value('conversation_attribute')
);
const valores = computed(() => props.conversation.custom_attributes || {});
const valorDe = chave => valores.value[chave] ?? '';

const gravar = async customAttributes => {
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: props.conversation.id,
      customAttributes,
    });
    useAlert(t('PAINEL_DO_CONTATO.CAMPOS_DA_CONVERSA.SALVO'));
  } catch {
    useAlert(t('PAINEL_DO_CONTATO.CAMPOS_DA_CONVERSA.ERRO'));
  }
};

// Quem só lê não tem os botões (show-actions); a gravação confere de novo.
const atualizar = (chave, valor) =>
  props.podeOperar && gravar({ ...valores.value, [chave]: valor });

const apagar = chave =>
  props.podeOperar &&
  gravar(
    Object.fromEntries(
      Object.entries(valores.value).filter(([key]) => key !== chave)
    )
  );

const copiar = async valor => {
  await copyTextToClipboard(valor);
  useAlert(t('PAINEL_DO_CONTATO.CAMPOS_DA_CONVERSA.COPIADO'));
};
</script>

<template>
  <BlocoDoPainel
    v-if="definicoes.length"
    :titulo="t('PAINEL_DO_CONTATO.CAMPOS_DA_CONVERSA.TITULO')"
    data-test-id="bloco-campos-da-conversa"
  >
    <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
      <li v-for="definicao in definicoes" :key="definicao.id">
        <CustomAttribute
          :attribute-key="definicao.attribute_key"
          :attribute-type="definicao.attribute_display_type"
          :values="definicao.attribute_values"
          :label="definicao.attribute_display_name"
          :description="definicao.attribute_description"
          :value="valorDe(definicao.attribute_key)"
          :attribute-regex="definicao.regex_pattern"
          :regex-cue="definicao.regex_cue"
          :show-actions="podeOperar"
          @update="atualizar"
          @delete="apagar"
          @copy="copiar"
        />
      </li>
    </ul>
  </BlocoDoPainel>
</template>
