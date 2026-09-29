import { createStore } from 'vuex';
import axios from 'axios';
import Contacts from '../../contacts';
import types from '../../../mutation-types';
import contactList from './fixtures';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from '../../../../../shared/helpers/CustomErrors';
import { filterApiResponse } from './filterApiResponse';

const actionStore = createStore({
  modules: {
    contacts: {
      ...Contacts,
      state: () => ({
        records: Object.fromEntries(
          contactList.map(contact => [contact.id, contact])
        ),
        sortOrder: [],
        uiFlags: {},
      }),
    },
  },
});
const actions = Object.fromEntries(
  Object.entries(Contacts.actions).map(([name, action]) => [
    name,
    action.bind(actionStore),
  ])
);
const getters = { getContact: actionStore.getters['contacts/getContact'] };

const filterQueryData = {
  payload: [
    {
      attribute_key: 'email',
      filter_operator: 'contains',
      values: ['fayaz'],
      query_operator: null,
    },
  ],
};

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('sends correct mutations if API is success', async () => {
      axios.get.mockResolvedValue({
        data: { payload: contactList, meta: { count: 100, current_page: 1 } },
      });
      await actions.get({ commit, getters });
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetching: true }],
        [types.CLEAR_CONTACTS],
        [types.SET_CONTACTS, contactList],
        [types.SET_CONTACT_META, { count: 100, current_page: 1 }],
        [types.SET_CONTACT_UI_FLAG, { isFetching: false }],
      ]);
    });
    it('sends correct mutations if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.get({ commit, getters });
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetching: true }],
        [types.SET_CONTACT_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#show', () => {
    it('sends correct mutations if API is success', async () => {
      axios.get.mockResolvedValue({ data: { payload: contactList[0] } });
      await actions.show({ commit, getters }, { id: contactList[0].id });
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetchingItem: true }],
        [types.SET_CONTACT_ITEM, { ...contactList[0], custom_attributes: {} }],
        [types.SET_CONTACT_UI_FLAG, { isFetchingItem: false }],
      ]);
    });
    it('sends correct mutations if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.show({ commit, getters }, { id: contactList[0].id });
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetchingItem: true }],
        [types.SET_CONTACT_UI_FLAG, { isFetchingItem: false }],
      ]);
    });
  });

  describe('#active', () => {
    it('sends correct mutations if API is success', async () => {
      axios.get.mockResolvedValue({
        data: { payload: contactList, meta: { count: 100, current_page: 1 } },
      });
      await actions.active({ commit, getters });
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetching: true }],
        [types.CLEAR_CONTACTS],
        [types.SET_CONTACTS, contactList],
        [types.SET_CONTACT_META, { count: 100, current_page: 1 }],
        [types.SET_CONTACT_UI_FLAG, { isFetching: false }],
      ]);
    });
    it('sends correct mutations if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.active({ commit, getters });
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetching: true }],
        [types.SET_CONTACT_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#update', () => {
    it('sends correct mutations if API is success', async () => {
      axios.patch.mockResolvedValue({ data: { payload: contactList[0] } });
      await actions.update(
        { commit, getters },
        {
          id: contactList[0].id,
          name: contactList[0].name,
        }
      );
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isUpdating: true }],
        [
          types.SET_CONTACT_ITEM,
          {
            id: contactList[0].id,
            name: contactList[0].name,
            custom_attributes: contactList[0].custom_attributes || {},
          },
        ],
        [types.SET_CONTACT_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.update({ commit, getters }, contactList[0])
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isUpdating: true }],
        [types.SET_CONTACT_UI_FLAG, { isUpdating: false }],
      ]);
    });

    it('sends correct actions if duplicate contact is found', async () => {
      axios.patch.mockRejectedValue({
        response: {
          status: 422,
          data: {
            message: 'Incorrect header',
            attributes: ['email'],
          },
        },
      });
      await expect(
        actions.update(
          { commit, getters },
          {
            id: contactList[0].id,
            contactParams: contactList[0],
          }
        )
      ).rejects.toThrow(DuplicateContactException);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isUpdating: true }],
        [types.SET_CONTACT_UI_FLAG, { isUpdating: false }],
      ]);
    });

    it('preserves blank company_id when updating with form data', async () => {
      axios.patch.mockResolvedValue({ data: { payload: contactList[0] } });

      await actions.update(
        { commit, getters },
        {
          id: contactList[0].id,
          isFormData: true,
          name: contactList[0].name,
          companyId: '',
          avatar: 'avatar-file',
          additionalAttributes: {
            companyName: '',
            socialProfiles: {},
          },
        }
      );

      const lastPatchCall =
        axios.patch.mock.calls[axios.patch.mock.calls.length - 1];
      const formData = lastPatchCall[1];

      expect(formData).toBeInstanceOf(FormData);
      expect(formData.has('company_id')).toBe(true);
      expect(formData.get('company_id')).toBe('');
    });
  });

  describe('#create', () => {
    it('sends correct mutations if API is success', async () => {
      axios.post.mockResolvedValue({
        data: { payload: { contact: contactList[0] } },
      });
      await actions.create(
        { commit, getters },
        {
          contactParams: contactList[0],
        }
      );
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isCreating: true }],
        [types.SET_CONTACT_ITEM, contactList[0]],
        [types.SET_CONTACT_UI_FLAG, { isCreating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.create({ commit, getters }, contactList[0])
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isCreating: true }],
        [types.SET_CONTACT_UI_FLAG, { isCreating: false }],
      ]);
    });

    it('sends correct actions if email is already present', async () => {
      axios.post.mockRejectedValue({
        response: {
          data: {
            message: 'Email exists already',
          },
        },
      });
      await expect(
        actions.create(
          { commit, getters },
          {
            contactParams: contactList[0],
          }
        )
      ).rejects.toThrow(ExceptionWithMessage);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isCreating: true }],
        [types.SET_CONTACT_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#delete', () => {
    it('sends correct mutations if API is success', async () => {
      axios.delete.mockResolvedValue();
      await actions.delete({ commit, getters }, contactList[0].id);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isDeleting: true }],
        [types.SET_CONTACT_UI_FLAG, { isDeleting: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.delete({ commit, getters }, contactList[0].id)
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isDeleting: true }],
        [types.SET_CONTACT_UI_FLAG, { isDeleting: false }],
      ]);
    });
  });

  describe('#setContact', () => {
    it('returns correct mutations', () => {
      const data = { id: 1, name: 'john doe', availability_status: 'online' };
      actions.setContact({ commit, getters }, data);
      expect(commit.mock.calls).toEqual([[types.SET_CONTACT_ITEM, data]]);
    });
  });

  describe('#merge', () => {
    it('sends correct mutations if API is success', async () => {
      axios.post.mockResolvedValue({
        data: contactList[0],
      });
      await actions.merge({ commit, getters }, { childId: 0, parentId: 1 });
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isMerging: true }],
        [types.SET_CONTACT_ITEM, contactList[0]],
        [types.SET_CONTACT_UI_FLAG, { isMerging: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.merge({ commit, getters }, { childId: 0, parentId: 1 })
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isMerging: true }],
        [types.SET_CONTACT_UI_FLAG, { isMerging: false }],
      ]);
    });
  });

  describe('#deleteContactThroughConversations', () => {
    it('returns correct mutations', () => {
      actions.deleteContactThroughConversations(
        { commit, getters },
        contactList[0].id
      );
      expect(commit.mock.calls).toEqual([
        [types.DELETE_CONTACT, contactList[0].id],
        [types.CLEAR_CONTACT_CONVERSATIONS, contactList[0].id, { root: true }],
        [
          `contactConversations/${types.DELETE_CONTACT_CONVERSATION}`,
          contactList[0].id,
          { root: true },
        ],
      ]);
    });
  });

  describe('#updateContact', () => {
    it('sends correct mutations if API is success', async () => {
      axios.patch.mockResolvedValue({ data: { payload: contactList[0] } });
      await actions.updateContact({ commit, getters }, contactList[0]);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isUpdating: true }],
        [types.EDIT_CONTACT, contactList[0]],
        [types.SET_CONTACT_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.update({ commit, getters }, contactList[0])
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isUpdating: true }],
        [types.SET_CONTACT_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });
  describe('#deleteCustomAttributes', () => {
    it('sends correct mutations if API is success', async () => {
      axios.post.mockResolvedValue({ data: { payload: contactList[0] } });
      await actions.deleteCustomAttributes(
        { commit, getters },
        { id: 1, customAttributes: ['cloud-customer'] }
      );
      expect(commit.mock.calls).toEqual([
        [
          types.SET_CONTACT_ITEM,
          {
            id: 1,
            custom_attributes: Object.fromEntries(
              Object.entries(
                getters.getContact(1).custom_attributes || {}
              ).filter(([key]) => key !== 'cloud-customer')
            ),
          },
        ],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.deleteCustomAttributes(
          { commit, getters },
          { id: 1, customAttributes: ['cloud-customer'] }
        )
      ).rejects.toThrow(Error);
    });
  });

  describe('#fetchFilteredContacts', () => {
    it('fetches filtered conversations with a mock commit', async () => {
      axios.post.mockResolvedValue({
        data: filterApiResponse,
      });
      await actions.filter({ commit, getters }, filterQueryData);
      expect(commit).toHaveBeenCalledTimes(5);
      expect(commit.mock.calls).toEqual([
        ['SET_CONTACT_UI_FLAG', { isFetching: true }],
        ['CLEAR_CONTACTS'],
        ['SET_CONTACTS', filterApiResponse.payload],
        ['SET_CONTACT_META', filterApiResponse.meta],
        ['SET_CONTACT_UI_FLAG', { isFetching: false }],
      ]);
    });
  });

  describe('#setContactsFilter', () => {
    it('commits the correct mutation and sets filter state', () => {
      const filters = [
        {
          attribute_key: 'email',
          filter_operator: 'contains',
          values: ['fayaz'],
          query_operator: 'and',
        },
      ];
      actions.setContactFilters({ commit, getters }, filters);
      expect(commit.mock.calls).toEqual([[types.SET_CONTACT_FILTERS, filters]]);
    });
  });

  describe('#clearContactFilters', () => {
    it('commits the correct mutation and clears filter state', () => {
      actions.clearContactFilters({ commit, getters });
      expect(commit.mock.calls).toEqual([[types.CLEAR_CONTACT_FILTERS]]);
    });
  });

  describe('#deleteAvatar', () => {
    it('sends correct mutations if API is success', async () => {
      axios.delete.mockResolvedValue({ data: { payload: contactList[0] } });
      await actions.deleteAvatar({ commit, getters }, contactList[0].id);
      expect(commit.mock.calls).toEqual([
        [
          types.SET_CONTACT_ITEM,
          {
            id: contactList[0].id,
            thumbnail: contactList[0].thumbnail,
            avatar_url: contactList[0].avatar_url,
          },
        ],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.deleteAvatar({ commit, getters }, contactList[0].id)
      ).rejects.toThrow(Error);
    });
  });

  describe('#setOptOut', () => {
    it('marca a recusa e atualiza o contato', async () => {
      axios.post.mockResolvedValue({ data: { payload: contactList[0] } });
      await actions.setOptOut(
        { commit, getters },
        { id: contactList[0].id, optedOut: true }
      );
      expect(axios.post).toHaveBeenCalledWith(
        `/api/v1/contacts/${contactList[0].id}/opt_out`
      );
      expect(commit.mock.calls).toEqual([
        [
          types.SET_CONTACT_ITEM,
          {
            id: contactList[0].id,
            opted_out_at: contactList[0].opted_out_at,
            opt_out_source: contactList[0].opt_out_source,
          },
        ],
      ]);
    });
    it('desfaz a recusa e atualiza o contato', async () => {
      axios.delete.mockResolvedValue({ data: { payload: contactList[0] } });
      const result = await actions.setOptOut(
        { commit, getters },
        { id: contactList[0].id, optedOut: false }
      );
      expect(axios.delete).toHaveBeenCalledWith(
        `/api/v1/contacts/${contactList[0].id}/opt_out`
      );
      expect(commit.mock.calls).toEqual([
        [
          types.SET_CONTACT_ITEM,
          {
            id: contactList[0].id,
            opted_out_at: contactList[0].opted_out_at,
            opt_out_source: contactList[0].opt_out_source,
          },
        ],
      ]);
      expect(result).toEqual(contactList[0]);
    });
    it('repassa o erro sem mexer no contato', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.setOptOut(
          { commit, getters },
          { id: contactList[0].id, optedOut: true }
        )
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([]);
    });
    it('guarda a resposta do servidor no erro, para a tela mostrar a frase', async () => {
      const serverError = { response: { data: { error: 'Só a manual' } } };
      axios.delete.mockRejectedValue(serverError);
      await expect(
        actions.setOptOut(
          { commit, getters },
          { id: contactList[0].id, optedOut: false }
        )
      ).rejects.toMatchObject({ cause: serverError });
    });
  });

  describe('#initiateCall', () => {
    const contactId = 123;
    const inboxId = 456;

    it('sends correct mutations if API is success', async () => {
      const mockResponse = {
        data: {
          conversation_id: 789,
          status: 'initiated',
        },
      };
      axios.post.mockResolvedValue(mockResponse);

      const result = await actions.initiateCall(
        { commit, getters },
        { contactId, inboxId }
      );

      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isInitiatingCall: true }],
        [types.SET_CONTACT_UI_FLAG, { isInitiatingCall: false }],
      ]);
      expect(result).toEqual(mockResponse.data);
    });

    it('sends correct actions if API returns error with message', async () => {
      const errorMessage = 'Failed to initiate call';
      axios.post.mockRejectedValue({
        response: {
          data: {
            message: errorMessage,
          },
        },
      });

      await expect(
        actions.initiateCall({ commit, getters }, { contactId, inboxId })
      ).rejects.toThrow(ExceptionWithMessage);

      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isInitiatingCall: true }],
        [types.SET_CONTACT_UI_FLAG, { isInitiatingCall: false }],
      ]);
    });

    it('sends correct actions if API returns error with error field', async () => {
      const errorMessage = 'Call initiation error';
      axios.post.mockRejectedValue({
        response: {
          data: {
            error: errorMessage,
          },
        },
      });

      await expect(
        actions.initiateCall({ commit, getters }, { contactId, inboxId })
      ).rejects.toThrow(ExceptionWithMessage);

      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isInitiatingCall: true }],
        [types.SET_CONTACT_UI_FLAG, { isInitiatingCall: false }],
      ]);
    });

    it('sends correct actions if API returns generic error', async () => {
      axios.post.mockRejectedValue({ message: 'Network error' });

      await expect(
        actions.initiateCall({ commit, getters }, { contactId, inboxId })
      ).rejects.toThrow(Error);

      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isInitiatingCall: true }],
        [types.SET_CONTACT_UI_FLAG, { isInitiatingCall: false }],
      ]);
    });
  });

  describe('#fetchAttachments', () => {
    const attachments = [
      { id: 11, message_id: 21, file_type: 'image' },
      { id: 12, message_id: 22, file_type: 'file' },
    ];

    it('fetches and stores attachments on the contact record', async () => {
      axios.get.mockResolvedValue({ data: { payload: attachments } });
      const state = { records: { 1: { id: 1 } } };
      await actions.fetchAttachments({ commit, state }, 1);
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetchingAttachments: true }],
        [types.SET_CONTACT_ATTACHMENTS, { id: 1, data: attachments }],
        [types.SET_CONTACT_UI_FLAG, { isFetchingAttachments: false }],
      ]);
    });

    it('refetches even when attachments are already cached', async () => {
      axios.get.mockResolvedValue({ data: { payload: attachments } });
      const state = {
        records: { 1: { id: 1, attachments: [{ id: 99 }] } },
      };
      await actions.fetchAttachments({ commit, state }, 1);
      expect(axios.get).toHaveBeenCalled();
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetchingAttachments: true }],
        [types.SET_CONTACT_ATTACHMENTS, { id: 1, data: attachments }],
        [types.SET_CONTACT_UI_FLAG, { isFetchingAttachments: false }],
      ]);
    });

    it('clears the loading flag and rethrows when the API errors', async () => {
      axios.get.mockRejectedValue(new Error('Network error'));
      const state = { records: { 1: { id: 1 } } };
      await expect(
        actions.fetchAttachments({ commit, state }, 1)
      ).rejects.toThrow('Network error');
      expect(commit.mock.calls).toEqual([
        [types.SET_CONTACT_UI_FLAG, { isFetchingAttachments: true }],
        [types.SET_CONTACT_UI_FLAG, { isFetchingAttachments: false }],
      ]);
    });
  });
});
