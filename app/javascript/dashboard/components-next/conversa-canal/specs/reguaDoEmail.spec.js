// #1809 — a régua do "Aa" do e-mail e o aviso de assinatura.
import { mount } from '@vue/test-utils';
import { getFormattingForEditor } from 'dashboard/helper/editorHelper';
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
  // A régua do e-mail, como o editor monta, sem o que o e-mail tira: com o ✨ (copiloto da
  // Autonom.ia disponível, #1872) e sem ele (getFormattingForEditor tira o 'copilot').
  const comIa = getFormattingForEditor('Channel::Email', true).menu.filter(
    botao => !FORA_DA_REGUA.includes(botao)
  );
  const regua = getFormattingForEditor('Channel::Email', false).menu.filter(
    botao => !FORA_DA_REGUA.includes(botao)
  );
  const fios = botoes =>
    [
      ...(botoes[0] === 'copilot' ? ['strong'] : []),
      'link',
      'bulletList',
      'undo',
    ]
      .map(botao => `:nth-child(${botoes.indexOf(botao) + 1})`)
      .join(',');

  it('não tem o botão de imagem: o "+" da barra de baixo já anexa', () => {
    expect(FORA_DA_REGUA).toContain('imageUpload');
    expect(regua).not.toContain('imageUpload');
  });

  it('o ✨ fica na régua (o editor só o mostra com a IA do cliente disponível)', () => {
    expect(FORA_DA_REGUA).not.toContain('copilot');
    expect(comIa[0]).toBe('copilot');
    expect(regua).not.toContain('copilot');
  });

  it('sem o ✨, os fios separam negrito… | link | listas | desfazer', () => {
    expect(FORMATACAO_FIXA).toContain(
      `.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(${fios(regua)})]:before:w-px`
    );
  });

  it('com o ✨, um fio depois dele e os outros um botão adiante', () => {
    expect(fios(comIa)).toBe(
      ':nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8)'
    );
    expect(FORMATACAO_FIXA).toContain(
      `.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(${fios(comIa)})]:before:w-px`
    );
    // O fio tem o mesmo desenho nas duas réguas.
    const desenho = seletor =>
      FORMATACAO_FIXA.split(' ')
        .filter(classe => classe.includes(seletor))
        .map(classe => classe.slice(classe.indexOf(')]:') + 3));
    expect(desenho('menubar:has(.ProseMirror-copilot)')).toEqual(
      desenho('menubar:not(:has(.ProseMirror-copilot))')
    );
    expect(desenho('menubar:has(.ProseMirror-copilot)')).toHaveLength(9);
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
