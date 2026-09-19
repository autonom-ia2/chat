<script setup>
import { computed, nextTick, ref, useAttrs, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useElementBounding, useWindowSize } from '@vueuse/core';
import { picoSearch } from '@chatwoot/pico-search';
import { DROPDOWN_SEARCH_THRESHOLD } from '../helper/filterHelper';
import DropdownContainer from 'next/dropdown-menu/base/DropdownContainer.vue';
import DropdownSection from 'next/dropdown-menu/base/DropdownSection.vue';
import DropdownBody from 'next/dropdown-menu/base/DropdownBody.vue';
import DropdownItem from 'next/dropdown-menu/base/DropdownItem.vue';

import Button from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

// [{label, icon, value}]
const props = defineProps({
  keyboardNavigation: {
    type: Boolean,
    default: false,
  },
  // Empty while an attribute the saved filter refers to no longer exists.
  options: {
    type: Array,
    default: () => [],
  },
  hideLabel: {
    type: Boolean,
    default: false,
  },
  hideIcon: {
    type: Boolean,
    default: false,
  },
  variant: {
    type: String,
    default: 'faded',
  },
  label: {
    type: String,
    default: null,
  },
});

const { t } = useI18n();
const selected = defineModel({
  type: [String, Number],
  required: true,
});

const vFocus = { mounted: el => el.focus() };

const triggerRef = ref(null);
const dropdownRef = ref(null);
const searchTerm = ref('');
const attrs = useAttrs();
const menuId = useId();
let keyboardTrigger;
let closeKeyboardMenu;

const keyboardName = () => ({
  'aria-label': attrs['aria-label'],
  'aria-labelledby': attrs['aria-labelledby'],
});

const onMenuKeydown = event => {
  if (!props.keyboardNavigation) return;
  const { key, target, currentTarget } = event;
  if (key === 'Escape' || key === 'Tab') {
    if (key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
    }
    closeKeyboardMenu();
    // Leave Tab's native default intact, starting from the trigger even with Teleport.
    keyboardTrigger?.focus();
    return;
  }
  const input = currentTarget.querySelector('input');
  if (['Enter', ' '].includes(key) && target !== input) {
    event.preventDefault();
    event.stopPropagation();
    if (target.matches('[role="option"]')) target.click();
    return;
  }
  if (target === input && key === 'Enter') event.preventDefault();
  if (target === input && ['Home', 'End', 'Enter', ' '].includes(key)) return;
  if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(key)) return;
  const options = [...currentTarget.querySelectorAll('[role="option"]')];
  const index = options.indexOf(target);
  let destination;
  if (key === 'Home') [destination] = options;
  if (key === 'End') destination = options.at(-1);
  if (key === 'ArrowDown') destination = options[index + 1] || options[0];
  if (key === 'ArrowUp')
    destination = options[index - 1] || input || options.at(-1);
  if (target === input && key === 'ArrowUp') destination = options.at(-1);
  event.preventDefault();
  event.stopPropagation();
  destination?.focus();
};

const showSearch = computed(
  () => props.options.length > DROPDOWN_SEARCH_THRESHOLD
);

const searchResults = computed(() => {
  // picoSearch throws on a whitespace-only query, which trims down to no search terms.
  const query = searchTerm.value.trim();
  if (!query) return props.options;
  // Section headers are not selectable, so they are dropped once a query narrows the list.
  const selectableOptions = props.options.filter(option => !option.disabled);
  return picoSearch(selectableOptions, query, ['label']);
});

const { top } = useElementBounding(triggerRef);
const { height } = useWindowSize();
const { height: dropdownHeight } = useElementBounding(dropdownRef);

const selectedOption = computed(() => {
  return props.options.find(o => o.value === selected.value) || {};
});

const iconToRender = computed(() => {
  if (props.hideIcon) return null;
  return selectedOption.value.icon || 'i-lucide-chevron-down';
});

const dropdownPosition = computed(() => {
  const DROPDOWN_MAX_HEIGHT = 340;
  // Get actual height if available or use default
  const menuHeight = dropdownHeight.value
    ? dropdownHeight.value + 20
    : DROPDOWN_MAX_HEIGHT;
  const spaceBelow = height.value - top.value;
  return spaceBelow < menuHeight ? 'bottom-0' : 'top-0';
});

const updateSelected = newValue => {
  selected.value = newValue;
  if (props.keyboardNavigation) nextTick(() => keyboardTrigger?.focus());
};

const toggleDropdown = async (toggle, event) => {
  searchTerm.value = '';
  if (props.keyboardNavigation) {
    keyboardTrigger = event?.currentTarget || document.activeElement;
    closeKeyboardMenu = toggle;
  }
  toggle();
  if (!props.keyboardNavigation) return;
  await nextTick();
  const menu = dropdownRef.value?.$el;
  const initialFocus =
    menu?.querySelector('[aria-selected="true"]') ||
    menu?.querySelector('[role="option"]') ||
    menu?.querySelector('input, [role="listbox"]');
  initialFocus?.focus();
};
const keyboardAttrs = (isOpen, toggle) =>
  props.keyboardNavigation
    ? {
        ...keyboardName(),
        'aria-haspopup': 'listbox',
        'aria-expanded': isOpen,
        'aria-controls': isOpen ? menuId : undefined,
        onKeydown: event => {
          if (!['Enter', ' ', 'ArrowDown', 'ArrowUp'].includes(event.key))
            return;
          event.preventDefault();
          event.stopPropagation();
          if (!isOpen) toggleDropdown(toggle, event);
        },
      }
    : {};
</script>

<template>
  <DropdownContainer>
    <template #trigger="{ toggle, isOpen }">
      <slot
        name="trigger"
        :toggle="event => toggleDropdown(toggle, event)"
        :keyboard-attrs="keyboardAttrs(isOpen, toggle)"
        :expanded="isOpen"
      >
        <Button
          ref="triggerRef"
          v-bind="keyboardAttrs(isOpen, toggle)"
          type="button"
          sm
          slate
          :variant
          :icon="iconToRender"
          :trailing-icon="selectedOption.icon ? false : true"
          :label="label || (hideLabel ? null : selectedOption.label)"
          @click="toggleDropdown(toggle, $event)"
        />
      </slot>
    </template>
    <DropdownBody
      ref="dropdownRef"
      class="min-w-56 z-50"
      :class="dropdownPosition"
      strong
      @keydown="onMenuKeydown"
    >
      <div v-if="showSearch" class="relative">
        <Icon class="absolute size-4 left-2 top-2" icon="i-lucide-search" />
        <input
          v-model="searchTerm"
          v-focus
          class="w-full p-1.5 pl-8 rounded-lg text-n-slate-11 bg-n-alpha-1"
          :placeholder="t('COMBOBOX.SEARCH_PLACEHOLDER')"
          :aria-label="
            keyboardNavigation ? t('COMBOBOX.SEARCH_PLACEHOLDER') : undefined
          "
        />
      </div>
      <DropdownSection
        :id="keyboardNavigation ? menuId : undefined"
        class="[&>ul]:max-h-72"
        v-bind="keyboardNavigation ? keyboardName() : {}"
        :role="keyboardNavigation ? 'listbox' : undefined"
        :tabindex="keyboardNavigation ? -1 : undefined"
      >
        <template v-for="option in searchResults" :key="option.value">
          <li
            v-if="option.disabled"
            class="px-2 py-1.5 text-xs font-medium text-n-slate-10 select-none"
          >
            {{ option.label }}
          </li>
          <DropdownItem
            v-else
            :label="option.label"
            :icon="option.icon"
            :click="
              keyboardNavigation ? () => updateSelected(option.value) : null
            "
            :type="keyboardNavigation ? 'button' : undefined"
            :class="{ 'focus-visible:bg-n-alpha-2': keyboardNavigation }"
            :role="keyboardNavigation ? 'option' : undefined"
            :aria-selected="
              keyboardNavigation ? option.value === selected : undefined
            "
            @click="!keyboardNavigation && updateSelected(option.value)"
          />
        </template>
        <DropdownItem v-if="!searchResults.length" disabled>
          {{
            searchTerm
              ? t('COMBOBOX.EMPTY_SEARCH_RESULTS', { searchTerm })
              : t('COMBOBOX.EMPTY_STATE')
          }}
        </DropdownItem>
      </DropdownSection>
    </DropdownBody>
  </DropdownContainer>
</template>
