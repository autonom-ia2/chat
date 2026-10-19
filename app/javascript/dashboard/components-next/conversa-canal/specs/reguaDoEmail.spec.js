// #1809 — a régua do "Aa" do e-mail e o aviso de assinatura.
import { mount } from '@vue/test-utils';
import { FORMATTING } from 'dashboard/constants/editor';
import {
  FORA_DA_REGUA,
  FORMATACAO_FIXA,
  REGUA_SO_NO_AA,
} from '../email/visualEmail';
import AvisoDeAssinatura from '../email/AvisoDeAssinatura.vue';

const estado = vi.hoisted(() => ({ dispatch: vi.fn(), resolve: vi.fn() }));

vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: estado.resolve, push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: estado.dispatch }),
}));

describe('régua do e-mail (#1809)', () => {
  // A régua do e-mail, como o editor monta, sem o que o e-mail tira.
  const regua = FORMATTING['Channel::Email'].menu.filter(
    botao => !FORA_DA_REGUA.includes(botao)
  );

  it('não tem o botão de imagem: o "+" da barra de baixo já anexa', () => {
    expect(FORA_DA_REGUA).toContain('imageUpload');
    expect(regua).not.toContain('imageUpload');
  });

  it('não tem o ✨ do Captain, que não usamos', () => {
    expect(regua).not.toContain('copilot');
  });

  it('os fios separam negrito… | link | listas | desfazer', () => {
    const inicioDosGrupos = ['link', 'bulletList', 'undo'].map(
      botao => regua.indexOf(botao) + 1
    );
    const filhos = inicioDosGrupos.map(n => `:nth-child(${n})`).join(',');
    expect(FORMATACAO_FIXA).toContain(`:is(${filhos})]:before:w-px`);
  });

  it('botão que o ProseMirror esconde (listas dentro de lista) fica no lugar, apagado e sem clique', () => {
    const icone =
      "[&_.popover-prosemirror-menu_.ProseMirror-menuitem>.ProseMirror-icon[style*='none']]";
    expect(FORMATACAO_FIXA).toContain(`${icone}:!flex`);
    expect(FORMATACAO_FIXA).toContain(`${icone}:!opacity-40`);
    expect(FORMATACAO_FIXA).toContain(`${icone}:!pointer-events-none`);
  });

  // Contrato do seletor (a classe da barra do ProseMirror); o efeito na tela é conferido no navegador.
  it('com o "Aa" desligado, a classe esconde a barra flutuante do ProseMirror', () => {
    expect(REGUA_SO_NO_AA).toBe(
      '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!hidden'
    );
  });
});

describe('AvisoDeAssinatura (#1809)', () => {
  beforeEach(() => {
    estado.dispatch.mockReset();
    estado.resolve
      .mockReset()
      .mockReturnValue({ href: '/app/accounts/1/profile/settings' });
  });

  const montar = () =>
    mount(AvisoDeAssinatura, { global: { stubs: { Icon: true } } });

  it('"Criar assinatura" abre o perfil numa aba nova, sem sair da tela (e do rascunho)', () => {
    const link = montar().find('[data-criar-assinatura]');
    expect(link.element.tagName).toBe('A');
    expect(link.attributes('href')).toBe('/app/accounts/1/profile/settings');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toContain('noopener');
    expect(estado.resolve).toHaveBeenCalledWith({
      name: 'profile_settings_index',
    });
  });

  it('ao voltar para a aba depois de criar, relê o perfil uma vez', async () => {
    const wrapper = montar();
    window.dispatchEvent(new Event('focus'));
    expect(estado.dispatch).not.toHaveBeenCalled();
    await wrapper.find('[data-criar-assinatura]').trigger('click');
    window.dispatchEvent(new Event('focus'));
    expect(estado.dispatch).toHaveBeenCalledWith('validityCheck');
    window.dispatchEvent(new Event('focus'));
    expect(estado.dispatch).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
});
