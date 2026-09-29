import { recordRequest } from 'dashboard/components-next/Relationships/confirmedValues';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import snakecaseKeys from 'snakecase-keys';
import AccountActionsAPI from '../../../api/accountActions';
import ContactAPI from '../../../api/contacts';
import AnalyticsHelper from '../../../helper/AnalyticsHelper';
import { CONTACTS_EVENTS } from '../../../helper/AnalyticsHelper/events';
import types from '../../mutation-types';

const buildContactFormData = contactParams => {
  const formData = new FormData();
  const { additional_attributes = {}, ...contactProperties } = contactParams;
  Object.keys(contactProperties).forEach(key => {
    const value = contactProperties[key];
    const shouldAppendBlankCompanyId =
      key === 'company_id' && value !== undefined;

    if (value || shouldAppendBlankCompanyId) {
      formData.append(key, value ?? '');
    }
  });
  const { social_profiles, ...additionalAttributesProperties } =
    additional_attributes;
  Object.keys(additionalAttributesProperties).forEach(key => {
    formData.append(
      `additional_attributes[${key}]`,
      additionalAttributesProperties[key]
    );
  });
  Object.keys(social_profiles || {}).forEach(key => {
    formData.append(
      `additional_attributes[social_profiles][${key}]`,
      social_profiles[key]
    );
  });
  return formData;
};

export const handleContactOperationErrors = error => {
  if (error.response?.status === 422) {
    const exception = new DuplicateContactException(
      error.response.data.attributes
    );
    exception.message = error.response.data.message || exception.message;
    throw exception;
  } else if (error.response?.data?.message) {
    throw new ExceptionWithMessage(error.response.data.message);
  } else {
    throw new Error(error);
  }
};

export const actions = {
  search: async (
    { commit },
    { search, page, sortAttr, label, append = false }
  ) => {
    commit(types.SET_CONTACT_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload, meta },
      } = await ContactAPI.search(search, page, sortAttr, label);
      if (!append) {
        commit(types.CLEAR_CONTACTS);
      }
      commit(append ? types.APPEND_CONTACTS : types.SET_CONTACTS, payload);
      commit(types.SET_CONTACT_META, meta);
      commit(types.SET_CONTACT_UI_FLAG, { isFetching: false });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isFetching: false });
    }
  },

  get: async ({ commit }, { page = 1, sortAttr, label } = {}) => {
    commit(types.SET_CONTACT_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload, meta },
      } = await ContactAPI.get(page, sortAttr, label);
      commit(types.CLEAR_CONTACTS);
      commit(types.SET_CONTACTS, payload);
      commit(types.SET_CONTACT_META, meta);
      commit(types.SET_CONTACT_UI_FLAG, { isFetching: false });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isFetching: false });
    }
  },

  active: async ({ commit }, { page = 1, sortAttr } = {}) => {
    commit(types.SET_CONTACT_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload, meta },
      } = await ContactAPI.active(page, sortAttr);
      commit(types.CLEAR_CONTACTS);
      commit(types.SET_CONTACTS, payload);
      commit(types.SET_CONTACT_META, meta);
      commit(types.SET_CONTACT_UI_FLAG, { isFetching: false });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isFetching: false });
    }
  },

  async show({ commit, getters }, { id }) {
    const request = recordRequest(
      this,
      ContactAPI.accountIdFromRoute,
      'contact',
      id
    );
    commit(types.SET_CONTACT_UI_FLAG, { isFetchingItem: true });
    try {
      const response = await ContactAPI.show(id);
      if (request.valid())
        commit(types.SET_CONTACT_ITEM, {
          ...response.data.payload,
          custom_attributes: request.mergeRead(
            response.data.payload.custom_attributes,
            getters.getContact(id).custom_attributes
          ),
        });
      commit(types.SET_CONTACT_UI_FLAG, {
        isFetchingItem: false,
      });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, {
        isFetchingItem: false,
      });
    }
  },

  fetchAttachments: async ({ commit }, id) => {
    commit(types.SET_CONTACT_UI_FLAG, { isFetchingAttachments: true });
    try {
      const response = await ContactAPI.getAttachments(id);
      commit(types.SET_CONTACT_ATTACHMENTS, {
        id,
        data: response.data.payload,
      });
    } finally {
      commit(types.SET_CONTACT_UI_FLAG, { isFetchingAttachments: false });
    }
  },

  async update(
    { commit, getters },
    { id, isFormData = false, ...contactParams }
  ) {
    const { avatar, customAttributes, ...paramsToDecamelize } = contactParams;
    const decamelizedContactParams = {
      ...snakecaseKeys(paramsToDecamelize, { deep: true }),
      ...(customAttributes && { custom_attributes: customAttributes }),
      ...(avatar && { avatar }),
    };
    const request = recordRequest(
      this,
      ContactAPI.accountIdFromRoute,
      'contact',
      id
    );
    const confirm = request.write(
      Object.keys(decamelizedContactParams.custom_attributes || {})
    );
    commit(types.SET_CONTACT_UI_FLAG, { isUpdating: true });
    try {
      const response = await ContactAPI.update(
        id,
        isFormData
          ? buildContactFormData(decamelizedContactParams)
          : decamelizedContactParams
      );
      if (request.valid()) {
        const payload = response.data.payload;
        const patch = Object.fromEntries(
          Object.keys(decamelizedContactParams)
            .filter(
              key => key !== 'custom_attributes' && Object.hasOwn(payload, key)
            )
            .map(key => [key, payload[key]])
        );
        if (avatar) {
          patch.thumbnail = payload.thumbnail;
          patch.avatar_url = payload.avatar_url;
        }
        // Native company selection also returns the resolved company object.
        if (Object.hasOwn(decamelizedContactParams, 'company_id'))
          patch.company = payload.company;
        commit(types.SET_CONTACT_ITEM, {
          id: payload.id,
          ...patch,
          custom_attributes: confirm(
            getters.getContact(id).custom_attributes,
            payload.custom_attributes
          ),
        });
      }
      commit(types.SET_CONTACT_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isUpdating: false });
      handleContactOperationErrors(error);
    }
  },

  create: async ({ commit }, { isFormData = false, ...contactParams }) => {
    const decamelizedContactParams = snakecaseKeys(contactParams, {
      deep: true,
    });
    commit(types.SET_CONTACT_UI_FLAG, { isCreating: true });
    try {
      const response = await ContactAPI.create(
        isFormData
          ? buildContactFormData(decamelizedContactParams)
          : decamelizedContactParams
      );

      AnalyticsHelper.track(CONTACTS_EVENTS.CREATE_CONTACT);
      commit(types.SET_CONTACT_ITEM, response.data.payload.contact);
      commit(types.SET_CONTACT_UI_FLAG, { isCreating: false });
      return response.data.payload.contact;
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isCreating: false });
      return handleContactOperationErrors(error);
    }
  },

  import: async ({ commit }, file) => {
    commit(types.SET_CONTACT_UI_FLAG, { isImporting: true });
    try {
      await ContactAPI.importContacts(file);
      commit(types.SET_CONTACT_UI_FLAG, { isImporting: false });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isImporting: false });
      if (error.response?.data?.message) {
        throw new ExceptionWithMessage(error.response.data.message);
      }
    }
  },

  export: async ({ commit }, { payload, label }) => {
    commit(types.SET_CONTACT_UI_FLAG, { isExporting: true });
    try {
      await ContactAPI.exportContacts({ payload, label });

      commit(types.SET_CONTACT_UI_FLAG, { isExporting: false });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isExporting: false });
      if (error.response?.data?.message) {
        throw new Error(error.response.data.message);
      } else {
        throw new Error(error);
      }
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_CONTACT_UI_FLAG, { isDeleting: true });
    try {
      await ContactAPI.delete(id);
      commit(types.SET_CONTACT_UI_FLAG, { isDeleting: false });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isDeleting: false });
      if (error.response?.data?.message) {
        throw new Error(error.response.data.message);
      } else {
        throw new Error(error);
      }
    }
  },

  async deleteCustomAttributes({ commit, getters }, { id, customAttributes }) {
    const request = recordRequest(
      this,
      ContactAPI.accountIdFromRoute,
      'contact',
      id
    );
    const confirm = request.write(customAttributes);
    try {
      await ContactAPI.destroyCustomAttributes(id, customAttributes);
      if (request.valid())
        commit(types.SET_CONTACT_ITEM, {
          id,
          custom_attributes: confirm(getters.getContact(id).custom_attributes),
        });
    } catch (error) {
      throw new Error(error);
    }
  },

  async deleteAvatar({ commit }, id) {
    const request = recordRequest(
      this,
      ContactAPI.accountIdFromRoute,
      'contact',
      id
    );
    try {
      const response = await ContactAPI.destroyAvatar(id);
      if (request.valid())
        commit(types.SET_CONTACT_ITEM, {
          id,
          thumbnail: response.data.payload.thumbnail,
          avatar_url: response.data.payload.avatar_url,
        });
    } catch (error) {
      throw new Error(error);
    }
  },

  async setOptOut({ commit }, { id, optedOut }) {
    const request = recordRequest(
      this,
      ContactAPI.accountIdFromRoute,
      'contact',
      id
    );
    try {
      const response = optedOut
        ? await ContactAPI.markOptOut(id)
        : await ContactAPI.removeOptOut(id);
      if (request.valid())
        commit(types.SET_CONTACT_ITEM, {
          id,
          opted_out_at: response.data.payload.opted_out_at,
          opt_out_source: response.data.payload.opt_out_source,
        });
      return response.data.payload;
    } catch (error) {
      // A resposta fica em `cause`: a tela mostra a frase que o servidor mandou.
      throw new Error(error, { cause: error });
    }
  },

  fetchContactableInbox: async ({ commit }, id) => {
    commit(types.SET_CONTACT_UI_FLAG, { isFetchingInboxes: true });
    try {
      const response = await ContactAPI.getContactableInboxes(id);
      const contact = {
        id: Number(id),
        contact_inboxes: response.data.payload,
      };
      commit(types.SET_CONTACT_ITEM, contact);
    } catch (error) {
      if (error.response?.data?.message) {
        throw new ExceptionWithMessage(error.response.data.message);
      } else {
        throw new Error(error);
      }
    } finally {
      commit(types.SET_CONTACT_UI_FLAG, { isFetchingInboxes: false });
    }
  },

  updatePresence: ({ commit }, data) => {
    commit(types.UPDATE_CONTACTS_PRESENCE, data);
  },

  setContact({ commit }, data) {
    commit(types.SET_CONTACT_ITEM, data);
  },

  merge: async ({ commit }, { childId, parentId }) => {
    commit(types.SET_CONTACT_UI_FLAG, { isMerging: true });
    try {
      const response = await AccountActionsAPI.merge(parentId, childId);
      commit(types.SET_CONTACT_ITEM, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CONTACT_UI_FLAG, { isMerging: false });
    }
  },

  deleteContactThroughConversations: ({ commit }, id) => {
    commit(types.DELETE_CONTACT, id);
    commit(types.CLEAR_CONTACT_CONVERSATIONS, id, { root: true });
    commit(`contactConversations/${types.DELETE_CONTACT_CONVERSATION}`, id, {
      root: true,
    });
  },

  updateContact: async ({ commit }, updateObj) => {
    commit(types.SET_CONTACT_UI_FLAG, { isUpdating: true });
    try {
      commit(types.EDIT_CONTACT, updateObj);
      commit(types.SET_CONTACT_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isUpdating: false });
    }
  },

  filter: async (
    { commit },
    { page = 1, sortAttr, queryPayload, resetState = true } = {}
  ) => {
    commit(types.SET_CONTACT_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload, meta },
      } = await ContactAPI.filter(page, sortAttr, queryPayload);
      if (resetState) {
        commit(types.CLEAR_CONTACTS);
        commit(types.SET_CONTACTS, payload);
        commit(types.SET_CONTACT_META, meta);
        commit(types.SET_CONTACT_UI_FLAG, { isFetching: false });
      }
      return payload;
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isFetching: false });
    }
    return [];
  },

  setContactFilters({ commit }, data) {
    commit(types.SET_CONTACT_FILTERS, data);
  },

  clearContactFilters({ commit }) {
    commit(types.CLEAR_CONTACT_FILTERS);
  },

  initiateCall: async ({ commit }, { contactId, inboxId, conversationId }) => {
    commit(types.SET_CONTACT_UI_FLAG, { isInitiatingCall: true });
    try {
      const response = await ContactAPI.initiateCall(
        contactId,
        inboxId,
        conversationId
      );
      commit(types.SET_CONTACT_UI_FLAG, { isInitiatingCall: false });
      return response.data;
    } catch (error) {
      commit(types.SET_CONTACT_UI_FLAG, { isInitiatingCall: false });
      if (error.response?.data?.message) {
        throw new ExceptionWithMessage(error.response.data.message);
      } else if (error.response?.data?.error) {
        throw new ExceptionWithMessage(error.response.data.error);
      } else {
        throw new Error(error);
      }
    }
  },
};
