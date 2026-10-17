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
import NovaConversaEntrada from '../../NovaConversa/NovaConversaEntrada.vue';

import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';

const { attachments, contentAttributes } = useMessageContext();
// #1702: com a pele do WhatsApp, o cartão de contato do app.
const pele = usePele();

const $store = useStore();
const { t } = useI18n();

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

function getContactObject(digits = rawPhoneNumber.value) {
  const contactItem = {
    name: contactName.value,
    phone_number: `+${digits}`,
  };
  return contactItem;
}

async function filterContactByNumber(searchCandidate) {
  const query = {
    attribute_key: 'phone_number',
    filter_operator: 'equal_to',
    values: [searchCandidate],
    attribute_model: 'standard',
    custom_attribute_type: '',
  };

  const queryPayload = { payload: [query] };
  const contacts = await $store.dispatch('contacts/filter', {
    queryPayload,
    resetState: false,
  });
  return contacts.shift();
}

function openContactNewTab(contactId) {
  const accountId = window.location.pathname.split('/')[3];
  const url = `/app/accounts/${accountId}/contacts/${contactId}`;
  window.open(url, '_blank');
}

const onlyDigits = text =>
  Array.from(text || '')
    .filter(char => char >= '0' && char <= '9')
    .join('');

// Cadastro sem nome de verdade: vazio ou o próprio telefone no lugar do nome.
const lacksName = (contact, digits) =>
  !contact.name?.trim() || onlyDigits(contact.name) === digits;

// Procura o contato pelo telefone com "+" (como ele é gravado) e cria se não existir.
// #1702: achou sem nome de verdade e o cartão traz o nome? Completa o cadastro; nome
// que alguém já deu ao contato não é trocado.
// #1709: "Conversar" passa o waId do contato compartilhado (o número que tem WhatsApp).
async function findOrCreateContact(digits = rawPhoneNumber.value) {
  const contact = await filterContactByNumber(`+${digits}`);
  if (!contact) {
    const created = await $store.dispatch(
      'contacts/create',
      getContactObject(digits)
    );
    useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
    return created;
  }
  if (contactName.value && lacksName(contact, digits)) {
    await $store.dispatch('contacts/update', {
      id: contact.id,
      name: contactName.value,
    });
    useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
  }
  return contact;
}

function alertContactError(error) {
  if (error instanceof DuplicateContactException) {
    if (error.data.includes('phone_number')) {
      useAlert(t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
    }
  } else if (error instanceof ExceptionWithMessage) {
    useAlert(error.data);
  } else {
    useAlert(t('CONTACT_FORM.ERROR_MESSAGE'));
  }
}

// Sem pele, exatamente como no main (a busca recebe o computed, como lá).
async function addContactAsInMain() {
  let contact = await filterContactByNumber(rawPhoneNumber);
  if (!contact) {
    contact = await $store.dispatch('contacts/create', getContactObject());
    useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
  }
  return contact;
}

async function addContact() {
  try {
    const contact = pele.value
      ? await findOrCreateContact()
      : await addContactAsInMain();
    openContactNewTab(contact.id);
  } catch (error) {
    alertContactError(error);
  }
}

// #1702: "Conversar", como no WhatsApp: a Nova conversa abre e recebe o contato assim
// que ele é achado ou criado. Contato que nunca falou com a caixa começa por modelo
// aprovado, e quem conduz isso é a própria Nova conversa.
const contactToTalk = ref(null);
async function talkToContact() {
  try {
    const contact = await findOrCreateContact(
      numeroParaConversar(phoneNumber.value, contentAttributes?.value)
    );
    contactToTalk.value = String(contact.id);
  } catch (error) {
    alertContactError(error);
  }
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
