<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { timeZoneOptions } from 'dashboard/routes/dashboard/settings/inbox/helpers/businessHour';
import CrmServiceSchedulesAPI from 'dashboard/api/crmServiceSchedules';

const props = defineProps({
  ownerType: { type: String, required: true }, // 'Inbox' | 'User'
  ownerId: { type: Number, required: true },
  ownerName: { type: String, default: '' },
  schedule: { type: Object, default: null }, // existing payload row or null
  // #1619: calendário novo abre no fuso da conta (fusoDaConta), não num fuso fixo.
  defaultTimezone: { type: String, default: '' },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();

const DAY_KEYS = [
  'SUNDAY',
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
];
const DEFAULT_BLOCK = { start: '09:00', end: '18:00' };

const toTime = minutes =>
  `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(
    minutes % 60
  ).padStart(2, '0')}`;
// Estrito: só "H:mm"/"HH:mm" válido (0..1439, e "24:00"=1440 = fim do dia). Qualquer outra coisa
// (vazio, NaN, "25:61") -> NaN, que a validação rejeita (evita gravar minuto nulo/lixo no backend).
const toMinutes = time => {
  const match = /^(\d{1,2}):(\d{2})$/.exec(String(time ?? '').trim());
  if (!match) return NaN;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (minutes > 59 || hours > 24 || (hours === 24 && minutes !== 0)) return NaN;
  return hours * 60 + minutes;
};

const hydrateDays = () => {
  const days = Array.from({ length: 7 }, () => []);
  (props.schedule?.blocks || []).forEach(block => {
    days[block.day_of_week]?.push({
      start: toTime(block.start_minute),
      end: toTime(block.end_minute),
    });
  });
  days.forEach(blocks =>
    blocks.sort((a, b) => toMinutes(a.start) - toMinutes(b.start))
  );
  return days;
};

const timezone = ref(
  props.schedule?.timezone || props.defaultTimezone || 'America/Sao_Paulo'
);
const enabled = ref(props.schedule?.enabled ?? true);
const days = reactive(hydrateDays());
const isSaving = ref(false);

const tzOptions = timeZoneOptions();

const title = computed(() =>
  props.ownerType === 'Inbox'
    ? t('CRM_SLA.SCHEDULES.EDITOR.INBOX_TITLE', { name: props.ownerName })
    : t('CRM_SLA.SCHEDULES.EDITOR.AGENT_TITLE', { name: props.ownerName })
);

const isBlockInvalid = block => {
  const start = toMinutes(block.start);
  const end = toMinutes(block.end);
  return (
    !Number.isFinite(start) ||
    !Number.isFinite(end) ||
    start < 0 ||
    end > 1440 ||
    end <= start
  );
};
const dayHasInvalidBlock = dayIndex => days[dayIndex].some(isBlockInvalid);
const hasInvalidBlocks = computed(() =>
  days.some(blocks => blocks.some(isBlockInvalid))
);

const toggleDay = (dayIndex, isOn) => {
  days[dayIndex] = isOn ? [{ ...DEFAULT_BLOCK }] : [];
};

const addBlock = dayIndex => {
  const lastBlock = days[dayIndex][days[dayIndex].length - 1];
  if (!lastBlock) {
    days[dayIndex].push({ ...DEFAULT_BLOCK });
    return;
  }
  const start = Math.min(toMinutes(lastBlock.end), 1378);
  days[dayIndex].push({ start: toTime(start), end: toTime(start + 60) });
};

const removeBlock = (dayIndex, blockIndex) => {
  days[dayIndex].splice(blockIndex, 1);
};

const onSave = async () => {
  if (hasInvalidBlocks.value || !timezone.value) return;

  isSaving.value = true;
  try {
    const blocks = days.flatMap((dayBlocks, dayOfWeek) =>
      dayBlocks.map(block => ({
        day_of_week: dayOfWeek,
        start_minute: toMinutes(block.start),
        end_minute: toMinutes(block.end),
      }))
    );
    const response = await CrmServiceSchedulesAPI.create({
      service_schedule: {
        owner_type: props.ownerType,
        owner_id: props.ownerId,
        timezone: timezone.value,
        enabled: enabled.value,
        blocks,
      },
    });
    useAlert(t('CRM_SLA.SCHEDULES.EDITOR.API.SAVE_SUCCESS'));
    emit('saved', response.data.payload);
  } catch (error) {
    useAlert(t('CRM_SLA.SCHEDULES.EDITOR.API.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[100] flex items-center justify-center bg-n-alpha-black2 p-6"
      @click.self="emit('close')"
    >
      <div
        class="flex w-full max-w-2xl max-h-[85vh] flex-col gap-4 overflow-y-auto rounded-xl bg-n-solid-1 p-5 shadow-lg"
      >
        <div class="flex items-center justify-between gap-2">
          <h3 class="text-base font-medium text-n-slate-12">{{ title }}</h3>
          <Button
            ghost
            slate
            sm
            icon="i-lucide-x"
            type="button"
            @click="emit('close')"
          />
        </div>

        <div class="grid gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM_SLA.SCHEDULES.EDITOR.TIMEZONE_LABEL') }}
          </label>
          <ComboBox v-model="timezone" :options="tzOptions" />
        </div>

        <div class="flex items-center justify-between gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('CRM_SLA.SCHEDULES.EDITOR.ENABLED_LABEL') }}
          </span>
          <Switch v-model="enabled" />
        </div>

        <div class="flex flex-col divide-y divide-n-weak">
          <div
            v-for="(dayKey, dayIndex) in DAY_KEYS"
            :key="dayKey"
            class="flex items-start gap-3 py-2.5"
          >
            <div class="flex w-36 flex-shrink-0 items-center gap-2 pt-1">
              <Switch
                :model-value="days[dayIndex].length > 0"
                @update:model-value="toggleDay(dayIndex, $event)"
              />
              <span class="text-sm text-n-slate-12">
                {{ t(`CRM_SLA.SCHEDULES.EDITOR.DAYS.${dayKey}`) }}
              </span>
            </div>
            <div class="flex min-w-0 flex-1 flex-col gap-1.5">
              <span
                v-if="!days[dayIndex].length"
                class="pt-1 text-sm text-n-slate-10"
              >
                {{ t('CRM_SLA.SCHEDULES.EDITOR.NO_BLOCKS') }}
              </span>
              <template v-else>
                <div
                  v-for="(block, blockIndex) in days[dayIndex]"
                  :key="blockIndex"
                  class="flex items-center gap-1.5"
                >
                  <input
                    v-model="block.start"
                    type="time"
                    :aria-label="t('CRM_SLA.SCHEDULES.EDITOR.START_LABEL')"
                    class="reset-base !mb-0 h-8 rounded-lg border-0 bg-n-alpha-black2 px-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                  />
                  <span class="text-sm text-n-slate-10" aria-hidden="true">{{
                    t('CRM_SLA.SCHEDULES.EDITOR.RANGE_SEPARATOR')
                  }}</span>
                  <input
                    v-model="block.end"
                    type="time"
                    :aria-label="t('CRM_SLA.SCHEDULES.EDITOR.END_LABEL')"
                    class="reset-base !mb-0 h-8 rounded-lg border-0 bg-n-alpha-black2 px-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                    :class="{ '!outline-n-ruby-9': isBlockInvalid(block) }"
                  />
                  <Button
                    ghost
                    slate
                    sm
                    icon="i-lucide-x"
                    type="button"
                    :title="t('CRM_SLA.SCHEDULES.EDITOR.REMOVE_BLOCK')"
                    @click="removeBlock(dayIndex, blockIndex)"
                  />
                  <Button
                    v-if="blockIndex === days[dayIndex].length - 1"
                    ghost
                    slate
                    sm
                    icon="i-lucide-plus"
                    type="button"
                    :title="t('CRM_SLA.SCHEDULES.EDITOR.ADD_BLOCK')"
                    @click="addBlock(dayIndex)"
                  />
                </div>
                <p
                  v-if="dayHasInvalidBlock(dayIndex)"
                  class="mb-0 text-xs text-n-ruby-9"
                >
                  {{ t('CRM_SLA.SCHEDULES.EDITOR.BLOCK_INVALID') }}
                </p>
              </template>
            </div>
          </div>
        </div>

        <div class="flex items-center justify-end gap-2">
          <Button
            faded
            slate
            type="button"
            :label="t('CRM_SLA.SCHEDULES.EDITOR.CANCEL')"
            @click="emit('close')"
          />
          <Button
            type="button"
            :label="t('CRM_SLA.SCHEDULES.EDITOR.SAVE')"
            :is-loading="isSaving"
            :disabled="hasInvalidBlocks || !timezone"
            @click="onSave"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
