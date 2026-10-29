import axios from 'axios';
import { actions } from '../../customRole';
import * as types from '../../../mutation-types';
import { customRoleList } from './fixtures';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#getCustomRole', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({ data: customRoleList });
      await actions.getCustomRole({ commit });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { fetchingList: true }],
        [types.default.SET_CUSTOM_ROLE, customRoleList],
        [
          types.default.SET_CUSTOM_ROLE_UI_FLAG,
          { fetchingList: false, fetchingListFailed: false },
        ],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.getCustomRole({ commit });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { fetchingList: true }],
        [
          types.default.SET_CUSTOM_ROLE_UI_FLAG,
          { fetchingList: false, fetchingListFailed: true },
        ],
      ]);
    });
  });

  describe('#createCustomRole', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({ data: customRoleList[0] });
      await actions.createCustomRole({ commit }, customRoleList[0]);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { creatingItem: true }],
        [types.default.ADD_CUSTOM_ROLE, customRoleList[0]],
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { creatingItem: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.createCustomRole({ commit })).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { creatingItem: true }],
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { creatingItem: false }],
      ]);
    });
  });

  // #2185: o editor mostra o nome repetido ao lado do campo.
  it('keeps the refused fields on the error', async () => {
    axios.post.mockRejectedValue({
      response: {
        data: { message: 'Name has already been taken', attributes: ['name'] },
      },
    });
    await expect(
      actions.createCustomRole({ commit }, customRoleList[0])
    ).rejects.toMatchObject({ attributes: ['name'] });
  });

  describe('#updateCustomRole', () => {
    it('sends correct actions if API is success', async () => {
      axios.patch.mockResolvedValue({ data: customRoleList[0] });
      await actions.updateCustomRole(
        { commit },
        { id: 1, ...customRoleList[0] }
      );
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { updatingItem: true }],
        [types.default.EDIT_CUSTOM_ROLE, customRoleList[0]],
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { updatingItem: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.updateCustomRole({ commit }, { id: 1 })
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { updatingItem: true }],
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { updatingItem: false }],
      ]);
    });
  });

  // #2308: a conversa guiada separa o 401 (alcance, flag, a própria função) pelo status e pelo código do corpo.
  it.each([
    ['createCustomRole', 'post', customRoleList[0]],
    ['updateCustomRole', 'patch', { id: 1, ...customRoleList[0] }],
  ])('%s keeps status and code of a 401', async (acao, metodo, dados) => {
    axios[metodo].mockRejectedValue({
      response: { status: 401, data: { error: 'out_of_reach' } },
    });
    await expect(actions[acao]({ commit }, dados)).rejects.toMatchObject({
      status: 401,
      code: 'out_of_reach',
      attributes: [],
    });
  });

  describe('#deleteCustomRole', () => {
    // #2185: com gente na função, o destino delas vai junto.
    it('sends where the people go', async () => {
      axios.delete.mockResolvedValue({});
      await actions.deleteCustomRole(
        { commit },
        { id: 1, destinationRoleId: 'none' }
      );
      expect(axios.delete).toHaveBeenLastCalledWith(
        expect.stringContaining('/custom_roles/1'),
        { params: { destination_role_id: 'none' } }
      );
    });
    it('sends correct actions if API is success', async () => {
      axios.delete.mockResolvedValue({ data: customRoleList[0] });
      await actions.deleteCustomRole({ commit }, { id: 1 });
      expect(axios.delete).toHaveBeenLastCalledWith(expect.any(String), {
        params: {},
      });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { deletingItem: true }],
        [types.default.DELETE_CUSTOM_ROLE, 1],
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { deletingItem: true }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.deleteCustomRole({ commit }, { id: 1 })
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { deletingItem: true }],
        [types.default.SET_CUSTOM_ROLE_UI_FLAG, { deletingItem: true }],
      ]);
    });
    // A lista usa o código para abrir a pergunta do destino quando o servidor acha gente na função.
    it('keeps the error code from the server', async () => {
      axios.delete.mockRejectedValue({
        response: {
          data: { error: 'destination_required', message: 'Has people' },
        },
      });
      await expect(
        actions.deleteCustomRole({ commit }, { id: 1 })
      ).rejects.toMatchObject({
        message: 'Has people',
        code: 'destination_required',
      });
    });
  });
});
