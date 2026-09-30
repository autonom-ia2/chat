<script setup>
import RelationshipMedia from './RelationshipMedia.vue';
defineProps({
  companyId: { type: Number, required: true },
  expanded: { type: Boolean, default: false },
});
</script>

<template>
  <RelationshipMedia :company-id="companyId" :expanded="expanded" />
</template>
