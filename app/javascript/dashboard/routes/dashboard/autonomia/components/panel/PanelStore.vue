<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import StorePublicationPanel from '../../../financial/components/StorePublicationPanel.vue';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
});
const agentGetter = useMapGetter('autonomiaAgents/getRecord');
const agent = computed(() => agentGetter.value(Number(props.agentId)));
const target = computed(() => ({ agentId: props.agentId }));
</script>

<template>
  <StorePublicationPanel :target="target" :default-name="agent?.name || ''" />
</template>
