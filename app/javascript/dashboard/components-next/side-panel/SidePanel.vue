<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { onKeyStroke, useScrollLock } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import { useModalFocus } from 'dashboard/composables/useModalFocus';

const props = defineProps({
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  width: {
    type: String,
    default: 'xl',
    validator: value =>
      ['md', 'lg', 'xl', '2xl', '3xl', 'audience'].includes(value),
  },
  closeOnClickOutside: {
    type: Boolean,
    default: true,
  },
  panelTestId: {
    type: String,
    default: '',
  },
  backdropTestId: {
    type: String,
    default: '',
  },
});

// `afterLeave` fires once the slide-out transition finishes, so consumers
// mounted with v-if can wait for it before unmounting the panel.
const emit = defineEmits(['close', 'afterLeave']);

const MAX_WIDTH_CLASSES = {
  md: 'max-w-md',
  lg: 'max-w-lg',
  xl: 'max-w-xl',
  '2xl': 'max-w-2xl',
  '3xl': 'max-w-3xl',
  audience: 'sm:w-[37rem]',
};

const isOpen = ref(false);
const panelRef = ref(null);
const isScrollLocked = useScrollLock(document.body);
const { activate, deactivate } = useModalFocus({ container: panelRef });

let previousActiveElement = null;
let restorePending = false;

const maxWidthClass = computed(() => MAX_WIDTH_CLASSES[props.width]);

const open = () => {
  if (isOpen.value) return;
  previousActiveElement =
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
  restorePending = true;
  isOpen.value = true;
};

// Locking the page and moving focus both force layout. Doing that in the frame the panel mounts
// in delays the slide by a frame, so it waits until the panel has arrived.
const onAfterEnter = () => {
  if (!isOpen.value) return;

  isScrollLocked.value = true;
  const initialFocus =
    panelRef.value?.querySelector('[data-autofocus]') || panelRef.value;
  initialFocus?.focus({ preventScroll: true });
  activate();
};

const close = () => {
  if (!isOpen.value) return;

  deactivate();
  isOpen.value = false;
  isScrollLocked.value = false;
  emit('close');
};

const restoreFocus = () => {
  if (!restorePending) return;

  restorePending = false;
  const trigger = previousActiveElement;
  previousActiveElement = null;
  if (trigger?.isConnected) trigger.focus();
};

const onAfterLeave = () => {
  restoreFocus();
  emit('afterLeave');
};

const onOverlayClick = () => {
  if (props.closeOnClickOutside) close();
};

onKeyStroke('Escape', event => {
  if (!isOpen.value) return;
  // A dialog opened on top of the panel (e.g. the editor's link prompt) handles Escape itself.
  if (document.querySelector('dialog[open]')) return;

  event.preventDefault();
  close();
});

onBeforeUnmount(() => {
  deactivate();
  isScrollLocked.value = false;
  restoreFocus();
});

defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection to="body">
    <Transition
      enter-active-class="transition-opacity duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-200 ease-in"
      leave-to-class="opacity-0"
    >
      <div
        v-if="isOpen"
        class="fixed inset-0 z-50 bg-n-alpha-black1"
        role="presentation"
        :data-test="backdropTestId || undefined"
        @click="onOverlayClick"
      />
    </Transition>
    <Transition
      enter-active-class="transition-transform duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]"
      enter-from-class="translate-x-[calc(100%+0.75rem)] rtl:translate-x-[calc(-100%-0.75rem)]"
      leave-active-class="transition-transform duration-200 ease-in"
      leave-to-class="translate-x-[calc(100%+0.75rem)] rtl:translate-x-[calc(-100%-0.75rem)]"
      @after-enter="onAfterEnter"
      @after-leave="onAfterLeave"
    >
      <aside
        v-if="isOpen"
        ref="panelRef"
        role="dialog"
        aria-modal="true"
        :aria-label="title"
        :data-test="panelTestId || undefined"
        :data-testid="panelTestId || undefined"
        tabindex="-1"
        class="fixed z-50 flex flex-col w-[calc(100%-1.5rem)] overflow-hidden rounded-xl shadow-lg outline outline-1 outline-n-container inset-y-3 end-3 bg-n-solid-1 will-change-transform"
        :class="maxWidthClass"
      >
        <header
          class="flex justify-between flex-shrink-0 gap-4 px-6 py-5 border-b border-n-weak"
          :class="$slots.header ? 'items-start' : 'items-center'"
        >
          <slot name="header">
            <div class="min-w-0">
              <h3 class="text-base font-medium truncate text-n-slate-12">
                {{ title }}
              </h3>
              <p v-if="description" class="mt-1 mb-0 text-sm text-n-slate-11">
                {{ description }}
              </p>
            </div>
          </slot>
          <div class="flex items-center gap-1 shrink-0 -me-2">
            <slot name="header-actions" />
            <slot name="close">
              <Button
                ghost
                slate
                sm
                icon="i-lucide-x"
                :aria-label="$t('GENERAL.CLOSE')"
                @click="close"
              />
            </slot>
          </div>
        </header>
        <div class="flex-1 min-h-0 px-6 py-5 overflow-y-auto">
          <slot />
        </div>
        <footer
          v-if="$slots.footer"
          class="flex-shrink-0 px-6 py-4 border-t border-n-weak"
        >
          <slot name="footer" />
        </footer>
      </aside>
    </Transition>
  </TeleportWithDirection>
</template>
