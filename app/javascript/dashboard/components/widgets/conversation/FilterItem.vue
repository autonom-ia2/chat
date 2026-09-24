<script>
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

export default {
  components: { ChoiceSelect },
  props: {
    selectedValue: {
      type: String,
      required: true,
    },
    items: {
      type: Array,
      required: true,
    },
    type: {
      type: String,
      required: true,
    },
    pathPrefix: {
      type: String,
      required: true,
    },
  },
  emits: ['onChangeFilter'],
  data() {
    return {
      activeValue: this.selectedValue,
    };
  },
  computed: {
    choices() {
      return this.items.map(value => ({
        value,
        // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
        label: this.$t(`${this.pathPrefix}.${value}.TEXT`),
      }));
    },
    choiceLabel() {
      return this.type === 'status'
        ? this.$t('CHAT_LIST.CHAT_SORT.STATUS')
        : this.$t('CHAT_LIST.CHAT_SORT.ORDER_BY');
    },
  },
  methods: {
    onTabChange() {
      if (this.type === 'status') {
        this.$store.dispatch('setChatStatusFilter', this.activeValue);
      } else {
        this.$store.dispatch('setChatSortFilter', this.activeValue);
      }
      this.$emit('onChangeFilter', this.activeValue, this.type);
    },
  },
};
</script>

<template>
  <ChoiceSelect
    v-model="activeValue"
    :options="choices"
    :aria-label="choiceLabel"
    compact
    class="w-32 mx-1"
    @change="onTabChange()"
  />
</template>
