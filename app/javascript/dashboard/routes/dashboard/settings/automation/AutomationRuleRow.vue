<script setup>
import { computed } from 'vue';
import { messageStamp } from 'shared/helpers/timeHelper';
import { formatDelay } from 'dashboard/helper/automationHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import { BaseTableRow, BaseTableCell } from 'dashboard/components-next/table';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useSaidaExterna } from './saidaExterna';

const props = defineProps({
  automation: {
    type: Object,
    required: true,
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle', 'edit', 'delete', 'clone']);

const canManage = useCanManage('automation_manage');
// #2448: sem integration_manage, a regra com webhook ou transcrição por e-mail não liga, não desliga e não é copiada.
const { travada } = useSaidaExterna();
const saidaTravada = computed(() => travada(props.automation.actions));

const readableDate = date => messageStamp(new Date(date), 'LLL d, yyyy');
const readableDateWithTime = date =>
  messageStamp(new Date(date), 'LLL d, yyyy hh:mm a');

const automationActive = computed({
  get: () => props.automation.active,
  set: active => {
    const { id, name } = props.automation;
    emit('toggle', {
      id,
      name,
      status: !active,
    });
  },
});
</script>

<template>
  <BaseTableRow :item="automation">
    <template #default>
      <BaseTableCell class="max-w-0 w-full">
        <div class="flex items-center gap-2 min-w-0">
          <span class="text-body-main text-n-slate-12 truncate">
            {{ automation.name }}
          </span>
          <span
            v-if="automation.execution_delay"
            class="text-xs px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11 whitespace-nowrap flex-shrink-0"
          >
            {{
              $t('AUTOMATION.LIST.DELAY_BADGE', {
                delay: formatDelay(automation.execution_delay),
              })
            }}
          </span>
          <div class="w-px h-3 rounded-lg bg-n-weak flex-shrink-0" />
          <span class="text-body-main text-n-slate-11 truncate">
            {{ automation.description }}
          </span>
        </div>
        <p
          v-if="canManage && saidaTravada"
          class="mt-1 text-sm text-n-amber-11"
        >
          {{ $t('AUTOMATION.EXTERNAL_ACTIONS_LOCKED') }}
        </p>
      </BaseTableCell>

      <BaseTableCell>
        <ToggleSwitch
          v-model="automationActive"
          :disabled="!canManage || saidaTravada"
        />
      </BaseTableCell>

      <BaseTableCell :title="readableDateWithTime(automation.created_on)">
        <span class="text-body-main text-n-slate-12 whitespace-nowrap">
          {{ readableDate(automation.created_on) }}
        </span>
      </BaseTableCell>

      <BaseTableCell align="end">
        <div v-if="canManage" class="flex gap-3 justify-end flex-shrink-0">
          <Button
            v-tooltip.top="$t('AUTOMATION.FORM.EDIT')"
            icon="i-woot-edit-pen"
            slate
            sm
            :is-loading="loading"
            @click="$emit('edit', automation)"
          />
          <Button
            v-tooltip.top="$t('AUTOMATION.CLONE.TOOLTIP')"
            icon="i-woot-clone"
            sm
            slate
            :disabled="saidaTravada"
            :is-loading="loading"
            @click="$emit('clone', automation)"
          />
          <Button
            v-tooltip.top="$t('AUTOMATION.FORM.DELETE')"
            :is-loading="loading"
            icon="i-woot-bin"
            slate
            sm
            class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
            @click="$emit('delete', automation)"
          />
        </div>
      </BaseTableCell>
    </template>
  </BaseTableRow>
</template>
