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
  default: { ensaiar: vi.fn(), get: vi.fn(), testarConsulta: vi.fn() },
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

  it('avisa no topo que o ensaio é de exemplo', async () => {
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [novoPassoNovo('marcar_reuniao', 'p1', t)],
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

  // #2932–#2934: os três com motor ensaiam no servidor, sem a faixa de exemplo.
  const conversaCom = passos => ({
    data: {
      conversas: [{ conversa_id: 1, nome: 'Ana', entraria: true, passos }],
      outras: [],
    },
  });

  it('os passos com motor ensaiam no servidor, com o galho pelo nome', async () => {
    AutomacoesAPI.ensaiar.mockResolvedValueOnce(
      conversaCom([
        {
          id: 'p1',
          tipo: 'repetir_lista',
          faria: 'repetir_lista',
          dados: { total: 2, primeiros: ['Ana', 'Bruno'], fora_do_teto: 3 },
          ramos: [
            {
              chave: 'cada',
              passos: [
                { id: 'c1', tipo: 'parar', faria: 'catalogo', dados: {} },
              ],
            },
          ],
        },
      ])
    );
    const lista = {
      ...novoPassoNovo('repetir_lista', 'p1', t),
      cada: [{ id: 'c1', tipo: 'parar' }],
    };
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [lista],
    });
    await flushPromises();

    expect(AutomacoesAPI.ensaiar).toHaveBeenCalledTimes(1);
    expect(tela.find('[data-ensaio-de-exemplo]').exists()).toBe(false);
    const passos = tela.find('[data-ensaio-passos]').text();
    expect(passos).toContain('REPETIR.ENSAIO(2,');
    expect(passos).toContain('REPETIR.ENSAIO_FORA_DO_TETO(3)');
    expect(tela.find('[data-caminho]').text()).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.CAMINHO_NO_ENSAIO(AUTOMACAO_LIVRE.RAMOS.CADA)'
    );
  });

  it('a busca do "Buscar em outro sistema" só sai com o OK de quem ensaia', async () => {
    const consulta = {
      ...novoPassoNovo('consultar', 'p1', t),
      fonte: { de: 'endereco', url: 'https://loja.exemplo.com/pedido' },
      guardar: [{ nome: 'Status do pedido', caminho: 'pedido.status' }],
    };
    AutomacoesAPI.ensaiar.mockResolvedValueOnce(
      conversaCom([
        {
          id: 'p1',
          tipo: 'consultar',
          faria: 'consultar',
          dados: { guardaria: ['Status do pedido'] },
        },
      ])
    );
    AutomacoesAPI.testarConsulta.mockResolvedValueOnce({
      data: {
        ok: true,
        dados: [
          { caminho: 'pedido.status', valor: 'enviado', rotulo: 'Status' },
        ],
      },
    });
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [consulta],
    });
    await flushPromises();

    expect(AutomacoesAPI.testarConsulta).not.toHaveBeenCalled();
    await tela.find('[data-busca-pedir]').trigger('click');
    await tela.find('[data-busca-sim]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.testarConsulta).toHaveBeenCalledWith(consulta.fonte);
    expect(tela.find('[data-busca-resultado]').text()).toContain('enviado');
  });

  it('o passo de dentro do bloco sai em frase pela receita do bloco', async () => {
    AutomacoesAPI.get.mockResolvedValueOnce({
      data: {
        automacoes: [
          {
            id: 9,
            nome: 'Boas-vindas',
            bloco: true,
            versao: { receita: { passos: [{ id: 'p1', tipo: 'parar' }] } },
          },
        ],
      },
    });
    AutomacoesAPI.ensaiar.mockResolvedValueOnce(
      conversaCom([
        {
          id: 'p1',
          tipo: 'usar_bloco',
          faria: 'usar_bloco',
          dados: { nome: 'Boas-vindas' },
          ramos: [
            {
              chave: 'dentro',
              passos: [
                {
                  bloco: 9,
                  id: 'p1',
                  tipo: 'parar',
                  faria: 'parar',
                  dados: {},
                },
              ],
            },
          ],
        },
      ])
    );
    const tela = montar({
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [{ ...novoPassoNovo('usar_bloco', 'p1', t), bloco_id: 9 }],
    });
    await flushPromises();

    const itens = tela
      .findAll('[data-ensaio-passos] li')
      .map(item => item.text());
    expect(itens.join(' ')).toContain('BLOCO.ENSAIO_DE_VERDADE(Boas-vindas)');
    expect(itens.join(' ')).toContain('PARAR');
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
