import { ref } from 'vue';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import { useEditorLivre } from '../useEditorLivre';

// #2530 — Pelo endereço, a automação nova abre antes de o pacote do idioma
// chegar. O nome padrão segue o idioma da tela; o que a pessoa escreve fica.
const idioma = ref('en');
const TEXTOS = {
  en: { 'AUTOMACAO_LIVRE.EDITOR.NOVA': 'New automation' },
  pt_BR: { 'AUTOMACAO_LIVRE.EDITOR.NOVA': 'Nova automação' },
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: chave => TEXTOS[idioma.value][chave] || chave }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { create: vi.fn() },
}));

describe('useEditorLivre — nome da nova', () => {
  beforeEach(() => {
    idioma.value = 'en';
    vi.clearAllMocks();
  });

  it('o nome padrão acompanha o idioma que chega depois', async () => {
    const editor = useEditorLivre();
    await editor.carregar(null);
    expect(editor.nome.value).toBe('New automation');

    idioma.value = 'pt_BR';

    expect(editor.nome.value).toBe('Nova automação');
  });

  it('o nome que a pessoa escreveu não muda com o idioma e é o que salva', async () => {
    AutomacoesAPI.create.mockResolvedValueOnce({
      data: { id: 1, nome: 'Boas-vindas', versao: null },
    });
    const editor = useEditorLivre();
    await editor.carregar(null);

    editor.nome.value = 'Boas-vindas';
    idioma.value = 'pt_BR';
    await editor.guardar();

    expect(editor.nome.value).toBe('Boas-vindas');
    expect(AutomacoesAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({ nome: 'Boas-vindas' })
    );
  });

  it('a nova sem nome escrito salva com o padrão no idioma da tela', async () => {
    AutomacoesAPI.create.mockResolvedValueOnce({
      data: { id: 1, nome: 'Nova automação', versao: null },
    });
    const editor = useEditorLivre();
    await editor.carregar(null);
    idioma.value = 'pt_BR';
    await editor.guardar();

    expect(AutomacoesAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({ nome: 'Nova automação' })
    );
  });
});
