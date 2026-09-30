<script setup>
import { ref } from 'vue';
import RelationshipMedia from './RelationshipMedia.vue';
defineProps({ contactId: { type: Number, required: true } });
const expanded = ref(false);
</script>

<template>
  <RelationshipMedia
    :contact-id="contactId"
    :expanded="expanded"
    @expand="expanded = true"
    @collapse="expanded = false"
  />
</template>
