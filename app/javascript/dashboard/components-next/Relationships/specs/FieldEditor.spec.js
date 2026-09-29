import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { setActivePinia, createPinia } from 'pinia';
import { useCompaniesStore } from 'dashboard/stores/companies';
import { createStore } from 'vuex';
import { mutations } from 'dashboard/store/modules/contacts/mutations';
import { getters } from 'dashboard/store/modules/contacts/getters';
import axios from 'axios';
import FieldEditor from '../FieldEditor.vue';

const context = vi.hoisted(() => ({ commit: null, store: null }));
vi.mock('axios', () => ({ default: { patch: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(31) }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => context.store,
}));

const mountField = (type = 'number', value = 0) => {
  context.store.commit('contacts/SET_CONTACT_ITEM', {
    id: 42,
    custom_attributes: { job_title: value, hidden: 'keep' },
  });
  context.commit.mockClear();
  return mount(FieldEditor, {
    props: {
      definition: {
        id: 7,
        attribute_key: 'job_title',
        attribute_display_name: 'Cargo',
        attribute_display_type: type,
        attribute_description: 'Função',
      },
      record: {
        id: 42,
        customAttributes: { job_title: value, hidden: 'keep' },
      },
      entity: 'contact',
    },
  });
};
const click = async (wrapper, text) =>
  wrapper
    .findAll('button')
    .find(button => button.text().includes(text))
    .trigger('click');

beforeEach(() => {
  vi.clearAllMocks();
  setActivePinia(createPinia());
  context.store = createStore({
    modules: {
      contacts: {
        namespaced: true,
        state: () => ({ records: {}, sortOrder: [] }),
        getters,
        mutations,
      },
    },
  });
  context.commit = vi.spyOn(context.store, 'commit');
});
it('sends only the confirmed field, preserves zero, and announces success after the response', async () => {
  let resolve;
  axios.patch.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = mountField();
  await click(wrapper, 'RELATIONSHIPS.EDIT');
  await wrapper.find('input').setValue('0');
  await click(wrapper, 'RELATIONSHIPS.SAVE');
  expect(wrapper.find('[role="status"]').exists()).toBe(false);
  expect(axios.patch).toHaveBeenCalledWith(
    '/api/v1/accounts/31/relationships/contact/42/values',
    { field: { key: 'job_title', value: 0, previous: 0 } }
  );
  resolve({ data: { custom_attributes: { job_title: 0, hidden: 'keep' } } });
  await flushPromises();
  expect(wrapper.find('[role="status"]').text()).toBe('RELATIONSHIPS.SAVED');
  expect(context.commit).toHaveBeenCalledWith('contacts/SET_CONTACT_ITEM', {
    id: 42,
    custom_attributes: { job_title: 0, hidden: 'keep' },
  });
});
it('retains the draft on failure and never announces saved', async () => {
  axios.patch.mockRejectedValue({ response: { status: 422 } });
  const wrapper = mountField();
  await click(wrapper, 'RELATIONSHIPS.EDIT');
  await wrapper.find('input').setValue('12');
  await click(wrapper, 'RELATIONSHIPS.SAVE');
  await flushPromises();
  expect(wrapper.find('input').element.value).toBe('12');
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(context.commit).not.toHaveBeenCalled();
});
it('ignores an old response after switching records', async () => {
  let resolve;
  axios.patch.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = mountField('checkbox', false);
  await click(wrapper, 'RELATIONSHIPS.EDIT');
  await click(wrapper, 'RELATIONSHIPS.SAVE');
  expect(axios.patch.mock.calls[0][1].field.value).toBe(false);
  await wrapper.setProps({ record: { id: 43, customAttributes: {} } });
  resolve({ data: { custom_attributes: { job_title: false } } });
  await flushPromises();
  expect(context.commit).not.toHaveBeenCalled();
  expect(wrapper.find('[role="status"]').exists()).toBe(false);
});
it('keeps date-only values unchanged', async () => {
  axios.patch.mockResolvedValue({
    data: { custom_attributes: { job_title: '2026-09-29' } },
  });
  const wrapper = mountField('date', '2026-09-29');
  await click(wrapper, 'RELATIONSHIPS.EDIT');
  expect(wrapper.find('input').element.value).toBe('2026-09-29');
  await click(wrapper, 'RELATIONSHIPS.SAVE');
  expect(axios.patch.mock.calls[0][1].field.value).toBe('2026-09-29');
});

it('merges only confirmed keys with two real contact store editors and reversed responses', async () => {
  const first = mountField('text', 'before');
  const second = mount(FieldEditor, {
    props: {
      ...first.props(),
      definition: {
        ...first.props('definition'),
        id: 8,
        attribute_key: 'other',
      },
    },
  });
  const replies = [];
  axios.patch.mockImplementation(
    () =>
      new Promise(resolve => {
        replies.push(resolve);
      })
  );
  await click(first, 'RELATIONSHIPS.EDIT');
  await first.find('input').setValue('A');
  await click(first, 'RELATIONSHIPS.SAVE');
  await click(second, 'RELATIONSHIPS.EDIT');
  await second.find('input').setValue('B');
  await click(second, 'RELATIONSHIPS.SAVE');
  replies[1]({ data: { custom_attributes: { job_title: 'A', other: 'B' } } });
  await flushPromises();
  replies[0]({ data: { custom_attributes: { job_title: 'A' } } });
  await flushPromises();
  expect(
    context.store.getters['contacts/getContact'](42).custom_attributes
  ).toEqual({ job_title: 'A', other: 'B', hidden: 'keep' });
  first.unmount();
  second.unmount();
});
it('locks the submitted draft while saving and ignores a response after unmount', async () => {
  let reply;
  axios.patch.mockImplementation(
    () =>
      new Promise(resolve => {
        reply = resolve;
      })
  );
  const wrapper = mountField('text', 'before');
  await click(wrapper, 'RELATIONSHIPS.EDIT');
  await click(wrapper, 'RELATIONSHIPS.SAVE');
  expect(wrapper.find('input').element.disabled).toBe(true);
  wrapper.unmount();
  reply({ data: {} });
  await flushPromises();
  expect(context.commit).not.toHaveBeenCalled();
});
it('renders only HTTP links as clickable and provides compact copy/edit/clear actions', async () => {
  const wrapper = mountField('link', 'https://example.test/path');
  await wrapper.setProps({ compact: true });
  expect(wrapper.find('a').attributes('rel')).toBe('noopener noreferrer');
  expect(wrapper.find('button[aria-label="RELATIONSHIPS.COPY"]').exists()).toBe(
    true
  );
  expect(
    wrapper.find('button[aria-label="RELATIONSHIPS.CLEAR"]').exists()
  ).toBe(true);
  await wrapper.setProps({
    record: {
      id: 42,
      customAttributes: { job_title: ['javascript', 'alert(1)'].join(':') },
    },
  });
  expect(wrapper.find('a').exists()).toBe(false);
  wrapper.unmount();
});

it('preserves two confirmed keys in the real company store with reversed responses', async () => {
  const companies = useCompaniesStore();
  companies.records = [{ id: 51, customAttributes: { hidden: 'keep' } }];
  const base = {
    record: companies.getRecord(51),
    entity: 'company',
    definition: {
      id: 21,
      attribute_key: 'a',
      attribute_display_name: 'A',
      attribute_display_type: 'text',
    },
  };
  const first = mount(FieldEditor, { props: base });
  const second = mount(FieldEditor, {
    props: {
      ...base,
      definition: { ...base.definition, id: 22, attribute_key: 'b' },
    },
  });
  const replies = [];
  axios.patch.mockImplementation(
    () =>
      new Promise(resolve => {
        replies.push(resolve);
      })
  );
  await click(first, 'RELATIONSHIPS.EDIT');
  await first.find('input').setValue('A');
  await click(first, 'RELATIONSHIPS.SAVE');
  await click(second, 'RELATIONSHIPS.EDIT');
  await second.find('input').setValue('B');
  await click(second, 'RELATIONSHIPS.SAVE');
  replies[1]({ data: { custom_attributes: { a: 'A', b: 'B' } } });
  await flushPromises();
  replies[0]({ data: { custom_attributes: { a: 'A' } } });
  await flushPromises();
  expect(companies.getRecord(51).customAttributes).toEqual({
    a: 'A',
    b: 'B',
    hidden: 'keep',
  });
  first.unmount();
  second.unmount();
});

it('preserves a local draft when a different field updates the same record prop', async () => {
  const wrapper = mountField('text', 'original');
  await click(wrapper, 'RELATIONSHIPS.EDIT');
  await wrapper.find('input').setValue('local draft');
  await wrapper.setProps({
    record: {
      id: 42,
      customAttributes: { job_title: 'original', other: 'confirmed elsewhere' },
    },
  });
  expect(wrapper.find('input').element.value).toBe('local draft');
  wrapper.unmount();
});

// Match the dashboard bootstrap: feature requests use the configured global client.
const originalDashboardClient = window.axios;
beforeEach(() => {
  window.axios = axios;
});
afterEach(() => {
  window.axios = originalDashboardClient;
});
