<script>
import PageHeader from '../../SettingsSubPageHeader.vue';
import BandwidthSms from './BandwidthSms.vue';
import Twilio from './Twilio.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

export default {
  components: {
    PageHeader,
    Twilio,
    BandwidthSms,
    ChoiceSelect,
  },
  data() {
    return {
      provider: 'twilio',
    };
  },
  computed: {
    providerChoices() {
      return [
        {
          value: 'twilio',
          label: this.$t('INBOX_MGMT.ADD.SMS.PROVIDERS.TWILIO'),
        },
        {
          value: '360dialog',
          label: this.$t('INBOX_MGMT.ADD.SMS.PROVIDERS.BANDWIDTH'),
        },
      ];
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.SMS.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.SMS.DESC')"
    />
    <div class="flex-shrink-0 flex-grow-0">
      <label>
        {{ $t('INBOX_MGMT.ADD.SMS.PROVIDERS.LABEL') }}
        <ChoiceSelect
          v-model="provider"
          :options="providerChoices"
          :aria-label="$t('INBOX_MGMT.ADD.SMS.PROVIDERS.LABEL')"
          class="w-full mb-4"
        />
      </label>
    </div>
    <Twilio v-if="provider === 'twilio'" type="sms" />
    <BandwidthSms v-else />
  </div>
</template>
