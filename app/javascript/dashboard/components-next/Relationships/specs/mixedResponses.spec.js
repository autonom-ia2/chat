import { mount, flushPromises } from '@vue/test-utils';
import { computed } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import store from 'dashboard/store';
import { useCompaniesStore } from 'dashboard/stores/companies';
import FieldEditor from '../FieldEditor.vue';

vi.mock('dashboard/store', async () => {
  const { createStore } = await import('vuex');
  const { default: contacts } = await import(
    'dashboard/store/modules/contacts'
  );
  return {
    default: createStore({
      state: () => ({ user: 1, account: 31 }),
      getters: {
        getCurrentUserID: state => state.user,
        getCurrentAccountId: state => state.account,
      },
      mutations: {
        CLEAR_USER: state => {
          state.user = null;
        },
        user: (state, value) => {
          state.user = value;
        },
        account: (state, value) => {
          state.account = value;
        },
      },
      modules: {
        contacts: {
          ...contacts,
          state: () => ({ records: {}, sortOrder: [], uiFlags: {} }),
        },
      },
    }),
  };
});
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: computed(() => store.state.account) }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const previousClient = window.axios;
let requests;
let server;
let companies;
let wrappers;
const response = () => ({
  id: 42,
  name: 'Server name',
  custom_attributes: { ...server },
});
const deferred = snapshot =>
  new Promise(resolve => {
    requests.push(() => resolve(snapshot));
  });
const record = entity =>
  entity === 'contact'
    ? store.getters['contacts/getContact'](42)
    : companies.getRecord(42);
const attributes = entity =>
  record(entity).custom_attributes || record(entity).customAttributes;
const legacy = (entity, patch) =>
  entity === 'contact'
    ? store.dispatch('contacts/update', { id: 42, ...patch })
    : companies.update({ id: 42, ...patch });
const remove = (entity, keys) =>
  entity === 'contact'
    ? store.dispatch('contacts/deleteCustomAttributes', {
        id: 42,
        customAttributes: keys,
      })
    : companies.deleteCustomAttributes({ id: 42, customAttributes: keys });
const show = entity =>
  entity === 'contact'
    ? store.dispatch('contacts/show', { id: 42 })
    : companies.show(42);
const resolveRequest = async index => {
  requests[index]();
  await flushPromises();
};
const edit = async (entity, key, value) => {
  const wrapper = mount(FieldEditor, {
    props: {
      entity,
      record: record(entity),
      definition: {
        id: key,
        attribute_key: key,
        attribute_display_name: key,
        attribute_display_type: 'text',
      },
    },
  });
  wrappers.push(wrapper);
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.EDIT')
    .trigger('click');
  await wrapper.find('input').setValue(value);
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.SAVE')
    .trigger('click');
};

beforeEach(() => {
  setActivePinia(createPinia());
  companies = useCompaniesStore();
  wrappers = [];
  requests = [];
  server = { a: 'old A', b: 'old B' };
  window.history.replaceState({}, '', '/app/accounts/31/contacts/42');
  store.commit('account', 31);
  store.commit('user', 1);
  store.commit('contacts/SET_CONTACT_ITEM', response());
  companies.upsertCompanyRecord({
    id: 42,
    name: 'Server name',
    customAttributes: { ...server },
  });
  window.axios = {
    patch: vi.fn((url, payload) => {
      if (payload.field) {
        if (payload.field.value === null) delete server[payload.field.key];
        else server[payload.field.key] = payload.field.value;
        return deferred({ data: { custom_attributes: { ...server } } });
      }
      Object.assign(server, (payload.company || payload).custom_attributes);
      return deferred({ data: { payload: response() } });
    }),
    post: vi.fn((url, payload) => {
      payload.custom_attributes.forEach(key => delete server[key]);
      return deferred({ data: { payload: response() } });
    }),
    get: vi.fn(() => deferred({ data: { payload: response() } })),
  };
});
afterEach(() => {
  wrappers.forEach(wrapper => wrapper.unmount());
  window.axios = previousClient;
});

it.each(['contact', 'company'])(
  '%s: legacy then new, reversed responses preserve both partial server writes and live native fields',
  async entity => {
    const old = legacy(entity, { customAttributes: { a: 'A' } });
    await edit(entity, 'b', 'B');
    await resolveRequest(1);
    if (entity === 'contact')
      store.commit('contacts/SET_CONTACT_ITEM', {
        id: 42,
        name: 'New native name',
      });
    else companies.getRecord(42).name = 'New native name';
    await resolveRequest(0);
    await old;
    expect(server).toEqual({ a: 'A', b: 'B' });
    expect(attributes(entity)).toEqual(server);
    expect(record(entity).name).toBe('New native name');
  }
);
it.each(['contact', 'company'])(
  '%s: new then legacy, reversed responses preserve both keys',
  async entity => {
    await edit(entity, 'a', 'A');
    const pending = legacy(entity, { customAttributes: { b: 'B' } });
    await resolveRequest(1);
    await resolveRequest(0);
    await pending;
    expect(attributes(entity)).toEqual(server);
  }
);
it.each(['contact', 'company'])(
  '%s: deletion removes only its keys and a delayed show cannot resurrect them or undo a saved value',
  async entity => {
    const read = show(entity);
    const deletion = remove(entity, ['a']);
    await edit(entity, 'b', 'B');
    await resolveRequest(2);
    await resolveRequest(1);
    await resolveRequest(0);
    await Promise.all([read, deletion]);
    expect(server).toEqual({ b: 'B' });
    expect(attributes(entity)).toEqual(server);
  }
);
it.each(['contact', 'company'])(
  '%s: a stale deletion response cannot erase a later confirmed replacement',
  async entity => {
    const deletion = remove(entity, ['a']);
    await edit(entity, 'a', 'replacement');
    await resolveRequest(1);
    await resolveRequest(0);
    await deletion;
    expect(attributes(entity)).toEqual(server);
  }
);
it.each(['contact', 'company'])(
  '%s: older write cannot overwrite the same key confirmed by the newer writer',
  async entity => {
    await edit(entity, 'a', 'A');
    const pending = legacy(entity, { customAttributes: { a: 'new A' } });
    await resolveRequest(1);
    await resolveRequest(0);
    await pending;
    expect(attributes(entity)).toEqual(server);
  }
);
it.each(['contact', 'company'])(
  '%s: native updates do not replay custom attributes',
  async entity => {
    const pending = legacy(entity, { name: 'Native' });
    await edit(entity, 'a', 'A');
    await resolveRequest(1);
    await resolveRequest(0);
    await pending;
    expect(attributes(entity)).toEqual(server);
  }
);
it.each(['contact', 'company'])(
  '%s: ignores pending updates and deletes after account changes and logout',
  async entity => {
    const update = legacy(entity, { customAttributes: { a: 'A' } });
    const deletion = remove(entity, ['b']);
    store.commit('account', 32);
    store.commit('account', 31);
    store.commit('CLEAR_USER');
    store.commit('user', 1);
    await resolveRequest(1);
    await resolveRequest(0);
    await Promise.all([update, deletion]);
    expect(attributes(entity)).toEqual({ a: 'old A', b: 'old B' });
  }
);

it.each(['contact', 'company'])(
  '%s: a failed newer write does not suppress an older successful confirmation',
  async entity => {
    await edit(entity, 'a', 'A');
    window.axios.patch.mockRejectedValueOnce(new Error('offline'));
    await expect(
      legacy(entity, { customAttributes: { a: 'failed' } })
    ).rejects.toThrow();
    await resolveRequest(0);
    expect(attributes(entity)).toEqual(server);
  }
);

it.each(['contact', 'company'])(
  '%s: avatar confirmations preserve a value saved while upload was pending',
  async entity => {
    window.axios.patch.mockImplementationOnce(() =>
      deferred({
        data: {
          payload: {
            ...response(),
            thumbnail: 'new-avatar',
            avatar_url: 'new-avatar',
          },
        },
      })
    );
    const pending = legacy(entity, {
      avatar: new File(['avatar'], 'avatar.png', { type: 'image/png' }),
      ...(entity === 'contact' && { isFormData: true }),
    });
    await edit(entity, 'a', 'A');
    await resolveRequest(1);
    await resolveRequest(0);
    await pending;
    expect(attributes(entity)).toEqual(server);
    expect(
      entity === 'contact' ? record(entity).thumbnail : record(entity).avatarUrl
    ).toBe('new-avatar');
  }
);

it('preserves the native company link response while a custom value is saved', async () => {
  window.axios.patch.mockImplementationOnce(() =>
    deferred({
      data: {
        payload: {
          ...response(),
          company_id: 7,
          company: { id: 7, name: 'Linked company' },
        },
      },
    })
  );
  const pending = legacy('contact', { companyId: 7 });
  await edit('contact', 'a', 'A');
  await resolveRequest(1);
  await resolveRequest(0);
  await pending;
  expect(attributes('contact')).toEqual(server);
  expect(record('contact').company).toEqual({ id: 7, name: 'Linked company' });
  expect(record('contact').company_id).toBe(7);
});
