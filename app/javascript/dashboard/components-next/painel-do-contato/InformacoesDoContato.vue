<script setup>
// #2138 — "Outras informações": só os campos do contato com definição e valor
// (os internos do WhatsApp já saíram em useListasDoContato), um por linha. Não
// reaproveita o CustomAttributes do painel antigo: ele lista também os vazios,
// arrasta, mostra "Mostrar todos os atributos" e "Configurar campos", e avisa
// com "Atributo atualizado". Quem só vê usa o FieldEditor em leitura; quem
// edita (contact_manage), o mesmo CustomAttribute de sempre, gravando pelo
// contacts/update, que vale em toda conta.
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CustomAttribute from 'dashboard/components/CustomAttribute.vue';
import FieldEditor from 'dashboard/components-next/Relationships/FieldEditor.vue';

const props = defineProps({
  definicoes: { type: Array, required: true },
  contact: { type: Object, required: true },
  podeEditar: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();

const valorDe = chave => props.contact.custom_attributes?.[chave] ?? '';

const gravar = async acao => {
  try {
    await acao();
    useAlert(t('PAINEL_DO_CONTATO.INFORMACOES.SALVO'));
  } catch {
    useAlert(t('PAINEL_DO_CONTATO.INFORMACOES.ERRO'));
  }
};

const atualizar = (chave, valor) =>
  gravar(() =>
    store.dispatch('contacts/update', {
      id: props.contact.id,
      customAttributes: { [chave]: valor },
    })
  );

const apagar = chave =>
  gravar(() =>
    store.dispatch('contacts/deleteCustomAttributes', {
      id: props.contact.id,
      customAttributes: [chave],
    })
  );

const copiar = async valor => {
  await copyTextToClipboard(valor);
  useAlert(t('PAINEL_DO_CONTATO.INFORMACOES.COPIADO'));
};
</script>

<template>
  <ul class="flex flex-col p-0 pb-4 m-0 list-none divide-y divide-n-weak">
    <li v-for="definicao in definicoes" :key="definicao.id">
      <CustomAttribute
        v-if="podeEditar"
        :attribute-key="definicao.attribute_key"
        :attribute-type="definicao.attribute_display_type"
        :values="definicao.attribute_values"
        :label="definicao.attribute_display_name"
        :description="definicao.attribute_description"
        :value="valorDe(definicao.attribute_key)"
        :attribute-regex="definicao.regex_pattern"
        :regex-cue="definicao.regex_cue"
        :contact-id="contact.id"
        show-actions
        @update="atualizar"
        @delete="apagar"
        @copy="copiar"
      />
      <FieldEditor
        v-else
        compact
        read-only
        :definition="definicao"
        :record="contact"
        entity="contact"
      />
    </li>
  </ul>
</template>
