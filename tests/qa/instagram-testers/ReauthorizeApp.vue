<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import Reauthorize from 'dashboard/routes/dashboard/settings/inbox/channels/instagram/Reauthorize.vue';
const store = useStore();
const inbox = computed(() => store.getters['inboxes/getInbox'](9101));
</script>

<template>
  <main class="w-full min-w-0 bg-n-background text-n-slate-12">
    <Reauthorize :inbox="inbox" />
  </main>
</template>
