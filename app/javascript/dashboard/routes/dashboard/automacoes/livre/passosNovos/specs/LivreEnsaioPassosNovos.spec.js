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

const conversaDoServidor = passos => ({
  conversa_id: 901,
  nome: 'Ana',
  entraria: true,
  ultima_atividade: new Date().toISOString(),
  passos,
});

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

  it('passo que ainda não salva: não chama o servidor e mostra a linha de exemplo', async () => {
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [
        novoPassoNovo('repetir_lista', 'p1', t),
        { id: 'p2', tipo: 'parar' },
      ],
    });
    await flushPromises();

    expect(AutomacoesAPI.ensaiar).not.toHaveBeenCalled();
    expect(tela.findAll('[data-ensaio-item]')).toHaveLength(2);
    expect(tela.find('[data-ensaio-passos]').text()).toContain(
      'REPETIR.ENSAIO'
    );
  });

  it('a pesquisa (#2936) ensaia pelo servidor, com a pergunta no balão', async () => {
    AutomacoesAPI.ensaiar.mockResolvedValueOnce({
      data: {
        conversas: [
          conversaDoServidor([
            {
              id: 'p1',
              tipo: 'pesquisa_nota',
              faria: 'pesquisa_nota',
              dados: {
                pergunta: 'De 0 a 10?',
                espera: { valor: 2, unidade: 'dias' },
              },
            },
          ]),
        ],
        outras: [],
      },
    });
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [novoPassoNovo('pesquisa_nota', 'p1', t)],
    });
    await flushPromises();

    expect(AutomacoesAPI.ensaiar).toHaveBeenCalledTimes(1);
    expect(tela.find('[data-ensaio-de-exemplo]').exists()).toBe(false);
    const passos = tela.find('[data-ensaio-passos]');
    expect(passos.text()).toContain('PESQUISA.ENSAIO');
    expect(passos.find('[data-balao]').text()).toBe('De 0 a 10?');
  });

  it('avisa no topo que o ensaio é de exemplo', async () => {
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [novoPassoNovo('usar_bloco', 'p1', t)],
    });
    await flushPromises();

    expect(tela.find('[data-ensaio-de-exemplo]').text()).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.ENSAIO_DE_EXEMPLO'
    );
  });

  it('o galho do passo novo diz o nome dele, sem "Se a IA escolher"', async () => {
    const aprovacao = {
      ...novoPassoNovo('pedir_aprovacao', 'p1', t),
      aprovado: [{ id: 'p2', tipo: 'parar' }],
    };
    AutomacoesAPI.ensaiar.mockResolvedValueOnce({
      data: {
        conversas: [
          conversaDoServidor([
            {
              id: 'p1',
              tipo: 'pedir_aprovacao',
              faria: 'pedir_aprovacao',
              dados: { para: ['Gerente Ana'] },
              ramos: [
                {
                  chave: 'aprovado',
                  fixo: true,
                  passos: [{ id: 'p2', tipo: 'parar', faria: 'parar' }],
                },
              ],
            },
          ]),
        ],
        outras: [],
      },
    });
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [aprovacao],
    });
    await flushPromises();

    const caminho = tela.find('[data-caminho]').text();
    expect(caminho).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.CAMINHO_NO_ENSAIO(AUTOMACAO_LIVRE.RAMOS.APROVADO)'
    );
    expect(caminho).not.toContain('SE_CAMINHO');
  });

  it('a busca do "Buscar em outro sistema" espera o OK de quem ensaia', async () => {
    const consulta = {
      ...novoPassoNovo('consultar', 'p1', t),
      fonte: { de: 'integracao', id: 'loja' },
      guardar: [{ nome: 'Status do pedido', caminho: 'pedido.status' }],
    };
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [consulta],
    });
    await flushPromises();

    expect(tela.find('[data-busca-resultado]').exists()).toBe(false);
    await tela.find('[data-busca-pedir]').trigger('click');
    await tela.find('[data-busca-sim]').trigger('click');
    await flushPromises();

    expect(tela.find('[data-busca-resultado]').text()).toContain(
      'Status do pedido'
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

  it('sem passo novo, não há aviso de exemplo', async () => {
    AutomacoesAPI.ensaiar.mockResolvedValueOnce({
      data: { conversas: [], outras: [] },
    });
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [{ id: 'p2', tipo: 'parar' }],
    });
    await flushPromises();

    expect(tela.find('[data-ensaio-de-exemplo]').exists()).toBe(false);
  });
});
