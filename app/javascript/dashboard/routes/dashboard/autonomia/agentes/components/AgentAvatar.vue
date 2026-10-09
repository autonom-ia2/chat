<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({ agent: { type: Object, required: true } });
const color = computed(() => {
  if (props.agent.actuation === 'internal') return 'bg-n-iris-3 text-n-iris-11';
  if (props.agent.agent_type === 'insurance_quote')
    return 'bg-n-teal-3 text-n-teal-11';
  return 'bg-n-blue-3 text-n-blue-11';
});
</script>

<template>
  <span
    class="grid place-items-center size-[3.25rem] shrink-0 rounded-2xl overflow-hidden text-xl font-bold"
    :class="color"
    aria-hidden="true"
  >
    <Avatar
      v-if="agent.avatar_url"
      :name="agent.name"
      :src="agent.avatar_url"
      :size="52"
    />
    <span v-else>{{ agent.name.slice(0, 1).toLocaleUpperCase() }}</span>
  </span>
</template>
