<script setup>
import { nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import CreateTrackedLinkDialog from './CreateTrackedLinkDialog.vue';

// Review story (#1011): the dialog opens by itself so each variant shows one
// state. Product copy is in pt_BR, the language the team reviews in.
useI18n().locale.value = 'pt_BR';

const inboxes = [
  { id: 38, name: 'WhatsApp Vendas' },
  { id: 41, name: 'WhatsApp Pós-venda' },
];
const tick = () =>
  new Promise(resolve => {
    setTimeout(resolve, 50);
  });
const type = async (selector, value) => {
  const field = document.querySelector(selector);
  field.value = value;
  field.dispatchEvent(new Event('input'));
  field.dispatchEvent(new Event('blur'));
  await nextTick();
};
const chooseInbox = async index => {
  document.querySelector('[role="combobox"]').click();
  await tick();
  document.querySelectorAll('[role="option"]')[index].click();
  await tick();
  document.activeElement?.blur();
};

// Function refs run on every render: open each dialog only once, after the
// teleported <dialog> is in the page.
const opened = new WeakSet();
const once = fill => dialog => {
  if (!dialog || opened.has(dialog)) return;
  opened.add(dialog);
  tick().then(() => fill(dialog));
};
const openQr = once(async dialog => {
  dialog.open();
  await tick();
  await type('dialog input[type="text"]', 'Panfleto Expo Viagem');
  await chooseInbox(0);
  await type('#tracked-link-message', 'Olá! Vi o panfleto na feira.');
  // Keyboard focus on the other card: focus ring, not the selected look.
  document.querySelector('input[value="website"]').focus();
});
const openWebsiteError = once(async dialog => {
  dialog.open();
  await tick();
  document.querySelector('input[value="website"]').click();
  await tick();
  await type('dialog input[type="text"]', 'LP Seguro Viagem');
  await type('#tracked-link-origins', 'http://placement.com.br');
});
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="Campaigns/TrackedLinks/CreateDialog"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="QR code">
      <div class="min-h-screen bg-n-background">
        <CreateTrackedLinkDialog :ref="openQr" :inboxes="inboxes" />
      </div>
    </Variant>
    <Variant title="Website · origin error">
      <div class="min-h-screen bg-n-background">
        <CreateTrackedLinkDialog :ref="openWebsiteError" :inboxes="inboxes" />
      </div>
    </Variant>
  </Story>
</template>
