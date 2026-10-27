import { flushPromises, mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import { withFullI18n } from '../../../../../../../../vitest.i18n';
import MetaAdsComments from '../components/comentarios/MetaAdsComments.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const i18n = withFullI18n('en');
const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.COMMENTS';
const said = key => i18n.global.t(`${KEY}.${key}`);

const comment = (id, minutes = 30) => ({
  id,
  author: { name: null, username: `p${id}`, is_page: false },
  text: `comentário ${id}`,
  created_time: new Date(Date.now() - minutes * 60000).toISOString(),
  hidden: false,
  can_reply: true,
  can_hide: true,
  can_delete: true,
  can_reply_private: true,
  private_reply_expired: false,
  private_reply: null,
  replies: [],
});

const ready = comments => ({
  status: 'ready',
  account: { username: 'loja' },
  comments,
  total: comments.length,
  next_cursor: null,
});

const adaptador = data => ({
  listar: vi.fn().mockResolvedValue(data),
  mais: vi.fn(),
  responder: vi.fn(),
  ocultar: vi.fn(),
  apagar: vi.fn(),
  privado: vi.fn(),
  entrar: vi.fn(),
});

const refused = (status, code) =>
  Object.assign(new Error(code), {
    response: { status, data: { error: code } },
  });

let wrapper;
const mountShell = async abas => {
  wrapper = mount(MetaAdsComments, {
    props: { adId: '120', abas, canManage: true },
    global: { stubs: { Spinner: true, Dialog: true } },
  });
  await flushPromises();
  return wrapper;
};

// A casca dos comentários (#2196): o motivo que o servidor dá vira o aviso certo, e "Ver mais" nunca junta a página
// de uma aba na outra.
describe('MetaAdsComments (#2196)', () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => wrapper?.unmount());

  it('says why a private reply was refused and reads the tab again', async () => {
    const ig = adaptador(ready([comment('1')]));
    ig.privado.mockRejectedValue(refused(422, 'private_reply_done'));
    const shell = await mountShell([{ key: 'INSTAGRAM', adaptador: ig }]);

    await shell
      .findComponent({ name: 'MetaAdsCommentRow' })
      .props('acoes')
      .privado(comment('1'), 'Oi');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(said('ERRORS.PRIVATE_REPLY_DONE'));
    expect(ig.listar).toHaveBeenCalledTimes(2);
  });

  it('falls back to the generic message for an unknown code', async () => {
    const ig = adaptador(ready([comment('1')]));
    ig.ocultar.mockRejectedValue(refused(422, 'something_new'));
    const shell = await mountShell([{ key: 'INSTAGRAM', adaptador: ig }]);

    await shell
      .findComponent({ name: 'MetaAdsCommentRow' })
      .props('acoes')
      .ocultar(comment('1'), true);

    expect(useAlert).toHaveBeenCalledWith(said('MANAGE_ERROR'));
  });

  it('asks for an administrator when the login is refused with 403', async () => {
    const ig = adaptador({ ...ready([]), status: 'needs_login' });
    ig.entrar.mockRejectedValue(refused(403, 'forbidden'));
    const shell = await mountShell([{ key: 'INSTAGRAM', adaptador: ig }]);

    await shell
      .find('[data-ad-comments-action="needs_login"]')
      .trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(said('LOGIN_ADMIN'));
  });

  it('says why there is no private reply for someone outside the Instagram inbox', async () => {
    const outsider = {
      ...comment('1'),
      can_reply_private: false,
      private_reply_not_member: true,
    };
    const shell = await mountShell([
      { key: 'INSTAGRAM', adaptador: adaptador(ready([outsider])) },
    ]);

    expect(shell.find('[data-ad-comment-private]').exists()).toBe(false);
    expect(shell.find('[data-ad-comment-private-not-member]').text()).toBe(
      said('PRIVATE_NOT_MEMBER')
    );
  });

  it('says when Instagram did not confirm the private reply and lets the manager release it', async () => {
    const pending = {
      ...comment('1'),
      can_reply_private: false,
      private_reply: {
        sent_at: new Date().toISOString(),
        confirmed: false,
        can_release: true,
      },
    };
    const ig = adaptador(ready([pending]));
    ig.liberar = vi.fn().mockResolvedValue({ id: '1' });
    const shell = await mountShell([{ key: 'INSTAGRAM', adaptador: ig }]);

    expect(shell.find('[data-ad-comment-private-sent]').text()).toContain(
      said('PRIVATE_UNCONFIRMED')
    );
    await shell.find('[data-ad-comment-private-release]').trigger('click');
    await flushPromises();

    expect(ig.liberar).toHaveBeenCalledWith('120', '1');
    expect(useAlert).toHaveBeenCalledWith(said('PRIVATE_RELEASED'));
  });

  it('keeps the next page in the tab that asked for it when the tab changes meanwhile', async () => {
    const many = ['1', '2', '3'].map(id => comment(id));
    const ig = adaptador({ ...ready(many), next_cursor: 'C2' });
    const fb = adaptador(ready([comment('f1')]));
    let release;
    ig.mais.mockReturnValue(
      new Promise(resolve => {
        release = resolve;
      })
    );
    const shell = await mountShell([
      { key: 'INSTAGRAM', adaptador: ig },
      { key: 'FACEBOOK', adaptador: fb },
    ]);

    await shell.find('[data-ad-comments-more]').trigger('click');
    await shell.find('[data-ad-comments-tab="FACEBOOK"]').trigger('click');
    release({ comments: [comment('4')], next_cursor: null });
    await flushPromises();

    expect(
      shell
        .findAll('[data-comment-id]')
        .map(row => row.attributes('data-comment-id'))
    ).toEqual(['f1']);
    await shell.find('[data-ad-comments-tab="INSTAGRAM"]').trigger('click');
    await shell.find('[data-ad-comments-more]').trigger('click');
    expect(shell.find('[data-comment-id="4"]').exists()).toBe(true);
    expect(ig.mais).toHaveBeenCalledTimes(1);
  });
});
