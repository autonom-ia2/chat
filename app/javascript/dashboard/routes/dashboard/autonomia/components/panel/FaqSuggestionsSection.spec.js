import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { withFullI18n } from 'test-i18n';

import FaqSuggestionsSection from './FaqSuggestionsSection.vue';
import FaqSuggestionsAPI from 'dashboard/api/autonomia/faqSuggestions';
import { useAlert } from 'dashboard/composables';

withFullI18n();

vi.mock('dashboard/api/autonomia/faqSuggestions', () => ({
  default: { list: vi.fn(), approve: vi.fn(), ignore: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
}));

const dispatch = vi.fn().mockResolvedValue({});
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));

const suggestion = {
  id: 11,
  question: 'Qual o prazo de entrega?',
  answer: 'Até 5 dias úteis.',
  status: 'pending',
  conversation_display_id: 42,
};

const stubs = {
  NextButton: {
    props: ['label', 'disabled'],
    template:
      '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
  },
  Switch: {
    props: ['modelValue'],
    template:
      '<button class="toggle" :data-on="modelValue" @click="$emit(\'update:modelValue\', !modelValue)" />',
  },
  Spinner: true,
  Input: {
    props: ['modelValue'],
    template:
      '<input class="edit-question" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
  },
  TextArea: {
    props: ['modelValue'],
    template:
      '<textarea class="edit-answer" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
  },
};

const mountSection = (agent = { id: 3, config: { faq_suggestions: true } }) =>
  mount(FaqSuggestionsSection, { props: { agent }, global: { stubs } });

const buttonByText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text() === text);

describe('FaqSuggestionsSection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    FaqSuggestionsAPI.list.mockResolvedValue({
      data: { payload: [suggestion], meta: { pending_count: 1 } },
    });
    FaqSuggestionsAPI.approve.mockResolvedValue({ data: {} });
    FaqSuggestionsAPI.ignore.mockResolvedValue({ data: {} });
  });

  it('lists pending suggestions with a link to the conversation', async () => {
    const wrapper = mountSection();
    await flushPromises();

    expect(FaqSuggestionsAPI.list).toHaveBeenCalledWith(3, {
      status: 'pending',
    });
    expect(wrapper.text()).toContain('Qual o prazo de entrega?');
    expect(wrapper.find('[data-testid="faq-pending-count"]').text()).toBe('1');
    expect(wrapper.find('a').attributes('href')).toContain('/conversations/42');
  });

  it('approves a suggestion, removes it from the list and notifies the host', async () => {
    const wrapper = mountSection();
    await flushPromises();

    await buttonByText(wrapper, 'Approve').trigger('click');
    await flushPromises();

    expect(FaqSuggestionsAPI.approve).toHaveBeenCalledWith(3, 11, null);
    expect(wrapper.findAll('[data-testid="faq-suggestion"]')).toHaveLength(0);
    expect(wrapper.emitted('approved')).toBeTruthy();
    expect(useAlert).toHaveBeenCalledWith('Added to the knowledge base.');
  });

  it('sends the edited text when approving from the edit form', async () => {
    const wrapper = mountSection();
    await flushPromises();

    await buttonByText(wrapper, 'Edit and approve').trigger('click');
    await wrapper.find('textarea.edit-answer').setValue('Até 3 dias úteis.');
    await buttonByText(wrapper, 'Save and approve').trigger('click');
    await flushPromises();

    expect(FaqSuggestionsAPI.approve).toHaveBeenCalledWith(3, 11, {
      question: 'Qual o prazo de entrega?',
      answer: 'Até 3 dias úteis.',
    });
  });

  it('ignores a suggestion without emitting approved', async () => {
    const wrapper = mountSection();
    await flushPromises();

    await buttonByText(wrapper, 'Ignore').trigger('click');
    await flushPromises();

    expect(FaqSuggestionsAPI.ignore).toHaveBeenCalledWith(3, 11);
    expect(wrapper.emitted('approved')).toBeUndefined();
  });

  it('saves the generation toggle through the agent store', async () => {
    FaqSuggestionsAPI.list.mockResolvedValue({
      data: { payload: [], meta: { pending_count: 0 } },
    });
    const wrapper = mountSection({ id: 3, config: {} });
    await flushPromises();

    expect(wrapper.text()).toContain('Turn on generation');
    await wrapper.find('button.toggle').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 3,
      config: { faq_suggestions: true },
    });
  });
});
