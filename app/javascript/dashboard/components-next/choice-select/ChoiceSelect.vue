<script setup>
// Escolha única do produto. Não usamos <select> nativo: a lista dele ignora o design
// system e muda de navegador para navegador. Teclado segue o padrão WAI-ARIA
// "select-only combobox" (dashboard/helper/choiceKeys.js). Portado do ChoiceSelect do Bio.
//
// A lista é um popover manual (Popover API): fica na camada do topo, acima de
// modal <dialog> e fora do corte de overflow das seções, e continua no DOM do
// componente — dentro do dialog, então não fica inerte. A posição é fixa,
// calculada do botão. Sem Popover API (jsdom), o v-show cuida da visibilidade.
import { computed, nextTick, ref, useId, useTemplateRef, watch } from 'vue';
import { onClickOutside, useEventListener } from '@vueuse/core';
import {
  choiceKeyAction,
  isChoiceList,
  sameChoice,
  typeaheadIndex,
} from 'dashboard/helper/choiceKeys';

const props = defineProps({
  // { value, label, disabled? }. value pode ser string, número, booleano ou null.
  options: { type: Array, default: () => [], validator: isChoiceList },
  // Alternativa a `options`, como <optgroup>: [{ label, options: [...] }].
  groups: {
    type: Array,
    default: () => [],
    validator: groups =>
      groups.every(
        group =>
          'label' in group &&
          Array.isArray(group.options) &&
          isChoiceList(group.options)
      ),
  },
  ariaLabel: { type: String, required: true },
  placeholder: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  invalid: { type: Boolean, default: false },
  // Altura menor (h-8, como o Input small) para barras de filtro; a área de
  // toque continua com 44 px. A largura, nos dois tamanhos, é a da maior opção
  // (como no select nativo), a menos que quem usa defina outra.
  compact: { type: Boolean, default: false },
});

// Como o @change do select nativo: só quando a escolha muda, já com o
// modelo atualizado.
const emit = defineEmits(['change']);

// String antes de Boolean: '' continua '' em vez de virar true.
const modelValue = defineModel({
  type: [String, Number, Boolean],
  default: '',
});

const TYPEAHEAD_MS = 600;
const LIST_MAX_HEIGHT = 320;
const OPTION_HEIGHT = 44;
const LIST_GAP = 4;
const VIEWPORT_MARGIN = 8;

const id = useId();
const listId = `${id}-list`;
const optionId = index => `${id}-option-${index}`;
const groupLabelId = index => `${id}-group-${index}`;

const root = useTemplateRef('root');
const trigger = useTemplateRef('trigger');
const list = useTemplateRef('list');

const isOpen = ref(false);
const active = ref(-1);
const listStyle = ref({});
const typed = { text: '', at: 0, from: -1 };

// Seções da lista: um grupo por <optgroup>, ou uma seção sem rótulo.
// `index` é a posição na lista achatada, usada pelo teclado.
const sections = computed(() => {
  let index = 0;
  const withIndex = options =>
    options.map(option => {
      const item = { option, index };
      index += 1;
      return item;
    });
  if (!props.groups.length)
    return [{ label: '', items: withIndex(props.options) }];
  return props.groups.map(group => ({
    label: group.label,
    items: withIndex(group.options),
  }));
});
const flatOptions = computed(() =>
  sections.value.flatMap(section => section.items.map(item => item.option))
);
const disabledFlags = computed(() =>
  flatOptions.value.map(option => Boolean(option.disabled))
);

const selected = computed(() =>
  flatOptions.value.findIndex(option =>
    sameChoice(option.value, modelValue.value)
  )
);
const selectedLabel = computed(
  () => flatOptions.value[selected.value]?.label ?? props.placeholder
);
// Todos os textos que o botão pode mostrar: medidos invisíveis na mesma célula,
// dão ao campo a largura do maior, estável como a do select nativo.
const medidas = computed(() =>
  [props.placeholder, ...flatOptions.value.map(option => option.label)].filter(
    Boolean
  )
);
// O <label> em volta, se houver: clicar nele com a lista aberta fecha pelo
// próprio botão (ativação do label), sem o clique-fora fechar antes e o botão
// reabrir em seguida.
const ownLabel = computed(() => root.value?.closest('label') ?? null);

// Coordenadas da lista (position: fixed), a partir do botão. Largura mínima é a
// do botão; opções mais longas alargam a lista até a borda da tela. A altura é
// limitada ao espaço do lado escolhido: a lista fixa não volta rolando a página,
// então o que passasse da tela ficaria inalcançável.
const place = () => {
  const rect = trigger.value?.getBoundingClientRect();
  if (!rect) return;
  const below = window.innerHeight - rect.bottom;
  const spaceBelow = below - LIST_GAP - VIEWPORT_MARGIN;
  const spaceAbove = rect.top - LIST_GAP - VIEWPORT_MARGIN;
  const needed = Math.min(
    LIST_MAX_HEIGHT,
    flatOptions.value.length * OPTION_HEIGHT
  );
  // Abre para cima só quando não cabe embaixo e há mais espaço em cima.
  const opensUpward = spaceBelow < needed && spaceAbove > spaceBelow;
  const space = opensUpward ? spaceAbove : spaceBelow;
  // Uma opção inteira no mínimo, mesmo em tela minúscula.
  const maxHeight = Math.max(OPTION_HEIGHT, Math.min(LIST_MAX_HEIGHT, space));
  // Em RTL a lista se alinha pela direita do botão e cresce para a esquerda.
  const rtl = getComputedStyle(trigger.value).direction === 'rtl';
  const horizontal = rtl
    ? {
        right: `${window.innerWidth - rect.right}px`,
        maxWidth: `${rect.right - VIEWPORT_MARGIN}px`,
      }
    : {
        left: `${rect.left}px`,
        maxWidth: `${window.innerWidth - rect.left - VIEWPORT_MARGIN}px`,
      };
  listStyle.value = {
    ...horizontal,
    minWidth: `${rect.width}px`,
    maxHeight: `${maxHeight}px`,
    ...(opensUpward
      ? { bottom: `${window.innerHeight - rect.top + LIST_GAP}px` }
      : { top: `${rect.bottom + LIST_GAP}px` }),
  };
};

const show = index => {
  place();
  active.value = index;
  isOpen.value = true;
};

function close(focus = true) {
  isOpen.value = false;
  active.value = -1;
  if (focus) trigger.value?.focus({ preventScroll: true });
}

const commit = (index, focus = true) => {
  const option = flatOptions.value[index];
  if (option?.disabled) return;
  close(focus);
  if (!option || sameChoice(option.value, modelValue.value)) return;
  modelValue.value = option.value;
  emit('change', option.value);
};

const toggle = () => {
  if (props.disabled) return;
  if (isOpen.value) close();
  else show(selected.value >= 0 ? selected.value : 0);
};

const onTypeahead = event => {
  const now = Date.now();
  if (now - typed.at > TYPEAHEAD_MS) {
    typed.text = '';
    typed.from = isOpen.value ? active.value : selected.value;
  }
  typed.text += event.key;
  typed.at = now;
  const typingStart = isOpen.value ? active.value : selected.value;
  const from = typed.text.length === 1 ? typingStart : typed.from;
  // Rótulo vazio nunca casa: a busca por digitação pula as desabilitadas.
  const match = typeaheadIndex(
    flatOptions.value.map(option => (option.disabled ? '' : option.label)),
    typed.text,
    from
  );
  if (match >= 0) {
    if (isOpen.value) active.value = match;
    else show(match);
  }
};

const onKeydown = event => {
  if (props.disabled) return;
  const isModified = event.ctrlKey || event.metaKey || event.altKey;
  const isSpaceInsideTyping =
    event.key === ' ' && typed.text && Date.now() - typed.at <= TYPEAHEAD_MS;
  if (
    (event.key.length === 1 && !isModified && event.key !== ' ') ||
    isSpaceInsideTyping
  ) {
    event.preventDefault();
    onTypeahead(event);
    return;
  }
  const action = choiceKeyAction({
    key: event.key,
    altKey: event.altKey,
    open: isOpen.value,
    active: active.value,
    selected: selected.value,
    count: flatOptions.value.length,
    disabled: disabledFlags.value,
  });
  if (action.type === 'none') return;
  if (action.type === 'commit' && action.keepDefault) {
    if (disabledFlags.value[action.active]) close(false);
    else commit(action.active, false);
    return;
  }
  event.preventDefault();
  if (action.type === 'open') show(action.active);
  else if (action.type === 'move') active.value = action.active;
  else if (action.type === 'commit' && disabledFlags.value[action.active])
    close();
  else if (action.type === 'commit') commit(action.active);
  else close();
};

const onBlur = event => {
  if (isOpen.value && !root.value?.contains(event.relatedTarget)) close(false);
};

watch([isOpen, active], async () => {
  if (!isOpen.value || active.value < 0) return;
  await nextTick();
  list.value
    ?.querySelector(`[id="${optionId(active.value)}"]`)
    ?.scrollIntoView({ block: 'nearest' });
});

watch(
  isOpen,
  open => {
    if (open) list.value?.showPopover?.();
    else list.value?.hidePopover?.();
  },
  { flush: 'post' }
);

// Rolar a página ou uma seção com a lista aberta fecha, como o select nativo
// (capture pega a rolagem das seções internas); assim a lista nunca fica
// solta, apontando para um botão que saiu da vista. A rolagem da própria lista
// não conta. Redimensionar só reposiciona.
const openWindow = () => (isOpen.value ? window : null);
useEventListener(
  openWindow,
  'scroll',
  event => {
    if (!list.value?.contains(event.target)) close(false);
  },
  { capture: true, passive: true }
);
useEventListener(openWindow, 'resize', place, { passive: true });

onClickOutside(
  root,
  () => {
    if (isOpen.value) close(false);
  },
  { ignore: [list, ownLabel] }
);
</script>

<template>
  <div ref="root" class="grid grid-cols-[minmax(0,1fr)]">
    <!-- Grid de uma célula: o botão e as medidas invisíveis ocupam a mesma
         célula, e a coluna fica com a largura da maior (minmax(0, 1fr): cabe
         numa largura definida por quem usa e preenche a linha num formulário). -->
    <span
      v-for="(medida, indice) in medidas"
      :key="indice"
      data-medida
      aria-hidden="true"
      class="invisible h-0 overflow-hidden whitespace-nowrap pl-3 pr-9 text-sm [grid-area:1/1]"
    >
      {{ medida }}
    </span>
    <button
      ref="trigger"
      type="button"
      role="combobox"
      :aria-label="ariaLabel"
      aria-haspopup="listbox"
      :aria-expanded="isOpen"
      :aria-controls="listId"
      :aria-activedescendant="
        isOpen && active >= 0 ? optionId(active) : undefined
      "
      :aria-invalid="invalid || undefined"
      :disabled="disabled"
      class="relative flex items-center justify-between w-full gap-2 [grid-area:1/1] rounded-lg text-start font-normal bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 focus-visible:outline-2 disabled:cursor-not-allowed disabled:opacity-60 before:absolute before:inset-x-0"
      :class="[
        // Altura dos campos do design system (h-10; compacto h-8). O
        // pseudo-elemento leva a área de toque a 44 px nos dois.
        compact
          ? 'h-8 px-3 text-sm before:-inset-y-1.5'
          : 'h-10 px-3 text-sm before:-inset-y-0.5',
        invalid
          ? 'outline-n-ruby-9 focus-visible:outline-n-ruby-9'
          : 'outline-n-weak hover:enabled:outline-n-slate-6 focus-visible:outline-n-brand',
      ]"
      @click="toggle"
      @keydown="onKeydown"
      @blur="onBlur"
    >
      <span class="truncate">{{ selectedLabel }}</span>
      <span
        class="flex-shrink-0 size-4 text-n-slate-11"
        :class="isOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        aria-hidden="true"
      />
    </button>
    <ul
      v-show="isOpen"
      :id="listId"
      ref="list"
      role="listbox"
      :aria-label="ariaLabel"
      tabindex="-1"
      popover="manual"
      class="fixed z-50 px-0 py-1 m-0 overflow-y-auto border-0 rounded-lg shadow-lg inset-auto max-h-80 bg-n-solid-2 text-n-slate-12 outline outline-1 outline-n-container"
      :style="listStyle"
      @pointerdown.prevent
      @click.prevent
    >
      <li
        v-for="(section, sectionIndex) in sections"
        :key="sectionIndex"
        role="none"
      >
        <div
          v-if="section.label"
          :id="groupLabelId(sectionIndex)"
          class="px-3 pt-2 pb-1 text-xs font-medium text-n-slate-10"
        >
          {{ section.label }}
        </div>
        <ul
          :role="section.label ? 'group' : 'none'"
          :aria-labelledby="
            section.label ? groupLabelId(sectionIndex) : undefined
          "
          class="p-0 m-0 list-none"
        >
          <li
            v-for="{ option, index } in section.items"
            :id="optionId(index)"
            :key="index"
            role="option"
            :aria-selected="index === selected"
            :aria-disabled="option.disabled || undefined"
            class="flex items-center justify-between gap-2 px-3 text-sm min-h-11"
            :class="{
              'bg-n-alpha-2': index === active,
              'font-medium': index === selected,
              'cursor-pointer text-n-slate-12': !option.disabled,
              'cursor-not-allowed text-n-slate-10': option.disabled,
            }"
            @pointerdown.prevent
            @pointermove="active = index"
            @click="commit(index)"
          >
            <span class="truncate">{{ option.label }}</span>
            <span
              v-if="index === selected"
              class="flex-shrink-0 i-lucide-check size-4 text-n-slate-11"
              aria-hidden="true"
            />
          </li>
        </ul>
      </li>
    </ul>
  </div>
</template>
