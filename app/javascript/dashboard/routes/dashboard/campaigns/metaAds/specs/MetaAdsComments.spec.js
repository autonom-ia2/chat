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
const mountShell = async (abas, extra = {}) => {
  wrapper = mount(MetaAdsComments, {
    props: { adId: '120', abas, canManage: true, ...extra },
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

  it('says the reason in the words of its own network on the Facebook tab (#2197)', async () => {
    const fb = adaptador(ready([comment('1')]));
    fb.ocultar.mockRejectedValue(refused(422, 'meta_unavailable'));
    const shell = await mountShell([{ key: 'FACEBOOK', adaptador: fb }]);

    await shell
      .findComponent({ name: 'MetaAdsCommentRow' })
      .props('acoes')
      .ocultar(comment('1'), true);
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      said('FACEBOOK.ERRORS.META_UNAVAILABLE')
    );
    expect(said('FACEBOOK.ERRORS.META_UNAVAILABLE')).toContain('Facebook');
  });

  it('shows a photo-only comment with the photo label, not as an empty line (#2197)', async () => {
    const fb = adaptador(
      ready([{ ...comment('1'), text: null, attachment: 'photo' }])
    );
    const shell = await mountShell([{ key: 'FACEBOOK', adaptador: fb }]);

    expect(shell.find('[data-ad-comment-attachment]').text()).toBe(
      said('ATTACHMENT_PHOTO')
    );
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

  // #2359 (decisão A): sem a caixa do Messenger da Página, ninguém lê; o botão de conectar é de quem cria caixas.
  describe('Facebook Page inbox (#2359)', () => {
    const fbWith = status =>
      adaptador({ status, comments: [], total: 0, next_cursor: null });

    it('without the Page inbox, offers to connect it to whoever can create inboxes', async () => {
      const fb = fbWith('no_inbox');
      const shell = await mountShell([{ key: 'FACEBOOK', adaptador: fb }], {
        canCreateInbox: true,
      });

      const card = shell.find('[data-ad-comments-state="no_inbox"]');
      expect(card.text()).toContain(said('FACEBOOK.NO_INBOX_TITLE'));
      expect(card.text()).toContain(said('FACEBOOK.NO_INBOX'));
      expect(card.text()).not.toContain(said('FACEBOOK.NO_INBOX_ASK'));
      await card.find('[data-ad-comments-action="no_inbox"]').trigger('click');

      expect(fb.entrar).toHaveBeenCalledWith('no_inbox', '120');
    });

    it('without the Page inbox and without inbox permission, says who can connect it', async () => {
      const shell = await mountShell(
        [{ key: 'FACEBOOK', adaptador: fbWith('no_inbox') }],
        { canCreateInbox: false }
      );

      const card = shell.find('[data-ad-comments-state="no_inbox"]');
      expect(card.text()).toContain(said('FACEBOOK.NO_INBOX_ASK'));
      expect(card.find('[data-ad-comments-action]').exists()).toBe(false);
    });

    it('a refusal for the Page inbox says why and reads the tab again', async () => {
      const fb = adaptador(ready([comment('1')]));
      fb.ocultar.mockRejectedValue(refused(403, 'not_inbox_member'));
      const shell = await mountShell([{ key: 'FACEBOOK', adaptador: fb }]);

      await shell
        .findComponent({ name: 'MetaAdsCommentRow' })
        .props('acoes')
        .ocultar(comment('1'), true);
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith(
        said('FACEBOOK.ERRORS.NOT_INBOX_MEMBER')
      );
      expect(fb.listar).toHaveBeenCalledTimes(2);
    });

    it('outside the Page inbox, explains it without any button', async () => {
      const shell = await mountShell(
        [{ key: 'FACEBOOK', adaptador: fbWith('not_inbox_member') }],
        { canCreateInbox: true }
      );

      const card = shell.find('[data-ad-comments-state="not_inbox_member"]');
      expect(card.text()).toContain(said('FACEBOOK.NOT_INBOX_MEMBER_TITLE'));
      expect(card.text()).toContain(said('FACEBOOK.NOT_INBOX_MEMBER'));
      expect(card.find('[data-ad-comments-action]').exists()).toBe(false);
    });
  });

  // #2358: no Instagram, ver e agir pedem ver a caixa; o servidor manda `not_inbox_member` no lugar da lista.
  it('says the comments stay with the Instagram team for someone outside the inbox', async () => {
    const ig = adaptador({ ...ready([]), status: 'not_inbox_member' });
    const shell = await mountShell([{ key: 'INSTAGRAM', adaptador: ig }]);

    const card = shell.find('[data-ad-comments-state="not_inbox_member"]');
    expect(card.text()).toContain(said('INSTAGRAM.NOT_INBOX_MEMBER_TITLE'));
    expect(card.text()).toContain('@loja');
    expect(card.find('[data-ad-comments-action]').exists()).toBe(false);
    expect(shell.find('[data-ad-comments-list]').exists()).toBe(false);
  });

  it('reads the tab again when an action is refused for someone outside the inbox', async () => {
    const ig = adaptador(ready([comment('1')]));
    ig.responder.mockRejectedValue(refused(403, 'not_inbox_member'));
    const shell = await mountShell([{ key: 'INSTAGRAM', adaptador: ig }]);

    await shell
      .findComponent({ name: 'MetaAdsCommentRow' })
      .props('acoes')
      .responder(comment('1'), 'Oi');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(said('ERRORS.NOT_INBOX_MEMBER'));
    expect(ig.listar).toHaveBeenCalledTimes(2);
  });

  // #2358: o botão de entrar só aparece para quem chega ao fim do caminho; os outros leem a quem pedir.
  it('hides the login button and says whom to ask when the tab says this person cannot log in', async () => {
    const ig = adaptador({ ...ready([]), status: 'needs_login' });
    const podeEntrar = vi.fn().mockReturnValue(false);
    const shell = await mountShell([
      { key: 'INSTAGRAM', adaptador: ig, podeEntrar },
    ]);

    expect(podeEntrar).toHaveBeenCalledWith('needs_login');
    expect(shell.find('[data-ad-comments-action]').exists()).toBe(false);
    expect(shell.find('[data-ad-comments-ask]').text()).toBe(
      said('INSTAGRAM.NEEDS_LOGIN_ASK')
    );
  });

  it('keeps the login button for whoever manages the ads on a tab without podeEntrar (Facebook)', async () => {
    const fb = adaptador({ ...ready([]), status: 'needs_login' });
    const shell = await mountShell([{ key: 'FACEBOOK', adaptador: fb }]);

    expect(shell.find('[data-ad-comments-action="needs_login"]').exists()).toBe(
      true
    );
    expect(shell.find('[data-ad-comments-ask]').exists()).toBe(false);
  });

  it('shows the connect button when the tab says this person can create the inbox', async () => {
    const ig = adaptador({ ...ready([]), status: 'not_connected' });
    const shell = await mountShell([
      { key: 'INSTAGRAM', adaptador: ig, podeEntrar: () => true },
    ]);

    expect(
      shell.find('[data-ad-comments-action="not_connected"]').exists()
    ).toBe(true);
    expect(shell.find('[data-ad-comments-ask]').exists()).toBe(false);
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
