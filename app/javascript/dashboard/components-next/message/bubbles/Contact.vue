<script setup>
import { computed, ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../provider.js';
import BaseAttachmentBubble from './BaseAttachment.vue';
import BaseBubble from './Base.vue';
import ContatoDoWhatsapp from '../../conversa-canal/midia/ContatoDoWhatsapp.vue';
import { usePele } from '../../conversa-canal/pele';
import { numeroParaConversar } from '../../conversa-canal/midia/contatos';
import { useAcoesDoContato } from '../../conversa-canal/midia/useAcoesDoContato';
import NovaConversaEntrada from '../../NovaConversa/NovaConversaEntrada.vue';

const { attachments, contentAttributes } = useMessageContext();
// #1702: com a pele do WhatsApp, o cartão de contato do app.
const pele = usePele();

const $store = useStore();
const { t } = useI18n();
// #1702: "Salvar contato" e "Conversar" da pele (também usados em "Ver todos").
const { buscarPorTelefone, abrirContato, avisarErro, salvar, paraConversar } =
  useAcoesDoContato();

const attachment = computed(() => {
  return attachments.value[0];
});

const phoneNumber = computed(() => {
  return attachment.value.fallbackTitle;
});

const contactName = computed(() => {
  const { meta } = attachment.value ?? {};
  const { firstName, lastName } = meta ?? {};
  return `${firstName ?? ''} ${lastName ?? ''}`.trim();
});

const formattedPhoneNumber = computed(() => {
  return phoneNumber.value.replace(/\s|-|[A-Za-z]/g, '');
});

const rawPhoneNumber = computed(() => {
  return phoneNumber.value.replace(/\D/g, '');
});

const isContactInfoResponse = computed(() => {
  return attachment.value?.meta?.isContactInfoResponse;
});

// Sem pele, exatamente como no main (a busca recebe o computed, como lá).
async function addContactAsInMain() {
  try {
    let contact = await buscarPorTelefone(rawPhoneNumber);
    if (!contact) {
      contact = await $store.dispatch('contacts/create', {
        name: contactName.value,
        phone_number: `+${rawPhoneNumber.value}`,
      });
      useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
    }
    abrirContato(contact.id);
  } catch (error) {
    avisarErro(error);
  }
}

function addContact() {
  if (!pele.value) return addContactAsInMain();
  return salvar(rawPhoneNumber.value, contactName.value);
}

// #1702: "Conversar", como no WhatsApp: a Nova conversa abre e recebe o contato assim
// que ele é achado ou criado. Contato que nunca falou com a caixa começa por modelo
// aprovado, e quem conduz isso é a própria Nova conversa.
// #1709: "Conversar" passa o waId do contato compartilhado (o número que tem WhatsApp).
const contactToTalk = ref(null);
async function talkToContact() {
  const id = await paraConversar(
    numeroParaConversar(phoneNumber.value, contentAttributes?.value),
    contactName.value
  );
  if (id) contactToTalk.value = id;
}

const temAcao = computed(
  () => formattedPhoneNumber.value && !isContactInfoResponse.value
);

const action = computed(() => ({
  label: t('CONVERSATION.SAVE_CONTACT'),
  onClick: addContact,
}));
</script>

<template>
  <BaseBubble
    v-if="pele"
    class="!p-[3px]"
    :data-bubble-name="temAcao ? 'contact-acao' : 'contact'"
  >
    <ContatoDoWhatsapp
      :nome="contactName"
      :telefone="phoneNumber"
      :acao="temAcao ? action : null"
    >
      <template v-if="temAcao" #conversar>
        <NovaConversaEntrada :contact-id="contactToTalk">
          <template #trigger>
            <button
              type="button"
              class="w-full h-10 text-[14px] font-medium text-[#1A6B42] dark:text-[#6FD07E] hover:bg-[#000]/[0.03] dark:hover:bg-white/[0.03]"
              data-conversar-com-contato
              @click="talkToContact"
            >
              {{ t('CONVERSA_CANAL.CONTATO.CONVERSAR') }}
            </button>
          </template>
        </NovaConversaEntrada>
      </template>
    </ContatoDoWhatsapp>
  </BaseBubble>
  <BaseAttachmentBubble
    v-else
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-[#D6409F]"
    sender-translation-key="CONVERSATION.SHARED_ATTACHMENT.CONTACT"
    :title="contactName"
    :content="phoneNumber"
    :action="temAcao ? action : null"
  />
</template>
