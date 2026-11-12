import { flushPromises, mount } from '@vue/test-utils';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import LivreEnsaio from '../../components/LivreEnsaio.vue';
import { comPassosNovos, novoPassoNovo } from '../passosNovos';

// Protótipo #2931–#2936 — o Ensaiar com um passo novo: o servidor ainda não
// conhece o passo, então o ensaio vem do adaptador falso, com as conversas de
// exemplo e a linha do passo novo. Sem passo novo, segue a API de sempre.
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t, locale: { value: 'pt_BR' } }),
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { ensaiar: vi.fn() },
}));

const CATALOGO = comPassosNovos(
  {
    gatilhos: [],
    operadores: [],
    unidades: [],
    valores: [],
    passos: [{ tipo: 'parar', grupo: 'CONTROLE', frase: 'PARAR', campos: [] }],
  },
  true
);

const montar = receita =>
  mount(LivreEnsaio, {
    props: { automacaoId: 5, receita, catalogo: CATALOGO, rascunho: true },
    global: { mocks: { $t: t } },
  });

describe('LivreEnsaio com passo novo', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Element.prototype.scrollIntoView = vi.fn();
    window.matchMedia = vi.fn(() => ({ matches: false }));
  });

  it('não chama o servidor e mostra a linha do passo novo', async () => {
    const pesquisa = novoPassoNovo('pesquisa_nota', 'p1', t);
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [pesquisa, { id: 'p2', tipo: 'parar' }],
    });
    await flushPromises();

    expect(AutomacoesAPI.ensaiar).not.toHaveBeenCalled();
    expect(tela.findAll('[data-ensaio-item]')).toHaveLength(2);
    const passos = tela.find('[data-ensaio-passos]');
    expect(passos.text()).toContain('PESQUISA.ENSAIO');
    expect(passos.find('[data-balao]').text()).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.PESQUISA.PERGUNTA_PADRAO'
    );
  });

  it('sem passo novo, ensaia pelo servidor', async () => {
    AutomacoesAPI.ensaiar.mockResolvedValueOnce({
      data: { conversas: [], outras: [] },
    });
    montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [{ id: 'p2', tipo: 'parar' }],
    });
    await flushPromises();

    expect(AutomacoesAPI.ensaiar).toHaveBeenCalledTimes(1);
  });
});
