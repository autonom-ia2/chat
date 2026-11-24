import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import GavetaDeFiltros from '../../components/lista/GavetaDeFiltros.vue';
import LinhaDaCondicao from '../../components/lista/LinhaDaCondicao.vue';
import { FILTROS_VAZIOS } from '../../lista/filtros';
import { OPERADORES, TIPOS } from '../../lista/informacoes';

// #3168 — "Por outra informação" na gaveta "Mais filtros", com o texto de
// verdade em pt_BR.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./teleportFalso')).TeleportFalso,
}));

withFullI18n('pt_BR');

const marca = nome => `[data-relacionamentos="${nome}"]`;
const montar = (props = {}) =>
  mount(GavetaDeFiltros, {
    props: {
      aberta: true,
      comCondicoes: true,
      opcoes: { empresas: [], etiquetas: [], cidades: [] },
      ...props,
    },
    attachTo: document.body,
  });
const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);
const escolherNome = async (w, indice = 0) => {
  const linha = w.findAllComponents(LinhaDaCondicao)[indice];
  linha.vm.$emit('mudar', {
    ...linha.props('condicao'),
    chave: 'name',
    tipo: TIPOS.TEXTO,
    modelo: 'standard',
    como: OPERADORES.TEM,
    valor: '',
  });
  await w.vm.$nextTick();
};

describe('GavetaDeFiltros com "Por outra informação"', () => {
  it('começa só com o título, a ajuda e "+ Escolher uma informação"', () => {
    const w = montar();
    const secao = w.get(marca('por-outra-informacao'));
    expect(secao.text()).toContain('Por outra informação');
    expect(secao.text()).toContain(
      'Escolha uma informação e o que ela precisa ter.'
    );
    expect(w.findAll(marca('linha-da-condicao'))).toHaveLength(0);
    expect(w.find(marca('juntar-condicoes')).exists()).toBe(false);
    w.unmount();
  });

  it('não aparece na aba Empresas (sem `comCondicoes`)', () => {
    const w = montar({ comCondicoes: false, deEmpresas: true });
    expect(w.find(marca('por-outra-informacao')).exists()).toBe(false);
    w.unmount();
  });

  it('cada toque cria uma linha; com duas, aparece a escolha de juntar', async () => {
    const w = montar();
    await w.get(marca('escolher-informacao')).trigger('click');
    expect(w.findAll(marca('linha-da-condicao'))).toHaveLength(1);
    await w.get(marca('escolher-informacao')).trigger('click');
    expect(w.findAll(marca('linha-da-condicao'))).toHaveLength(2);
    expect(w.get(marca('por-outra-informacao')).text()).toContain(
      'Das informações abaixo, mostrar quem tem:'
    );
    const juntar = w.get(marca('juntar-condicoes'));
    expect(juntar.findAll('[role="radio"]').map(r => r.text())).toEqual([
      'Tudo isso',
      'Pelo menos uma',
    ]);
    await w.get(marca('tirar-condicao')).trigger('click');
    expect(w.findAll(marca('linha-da-condicao'))).toHaveLength(1);
    w.unmount();
  });

  it('depois da lixeira o foco vai para a linha seguinte ou para "Escolher"', async () => {
    const w = montar();
    await w.get(marca('escolher-informacao')).trigger('click');
    await w.get(marca('escolher-informacao')).trigger('click');
    await w.findAll(marca('tirar-condicao'))[0].trigger('click');
    await flushPromises();
    const informacao = w.get(
      `${marca('linha-da-condicao')} ${marca('informacao-da-condicao')} button`
    );
    expect(document.activeElement).toBe(informacao.element);
    await w.get(marca('tirar-condicao')).trigger('click');
    await flushPromises();
    expect(document.activeElement).toBe(
      w.get(marca('escolher-informacao')).element
    );
    w.unmount();
  });

  it('"Bloqueada" não pergunta "Como": vai direto a Sim | Não', async () => {
    const w = montar();
    await w.get(marca('escolher-informacao')).trigger('click');
    const linha = w.findAllComponents(LinhaDaCondicao)[0];
    linha.vm.$emit('mudar', {
      ...linha.props('condicao'),
      chave: 'blocked',
      tipo: TIPOS.SIM_NAO,
      modelo: 'standard',
      como: OPERADORES.IGUAL,
      valor: true,
    });
    await w.vm.$nextTick();
    expect(w.find(marca('como-da-condicao')).exists()).toBe(false);
    expect(
      w
        .get(marca('valor-da-condicao'))
        .findAll('[role="radio"]')
        .map(r => r.text())
    ).toEqual(['Sim', 'Não']);
    w.unmount();
  });

  it('falta o valor: mostra o erro na linha e não aplica', async () => {
    const w = montar();
    await w.get(marca('escolher-informacao')).trigger('click');
    await escolherNome(w);
    await botao(w, 'Ver resultado').trigger('click');
    expect(w.emitted('aplicar')).toBeUndefined();
    expect(w.get(marca('linha-da-condicao')).text()).toContain(
      'Escreva o que procurar.'
    );
    w.unmount();
  });

  it('aplica só as linhas prontas, com "juntar"', async () => {
    const w = montar();
    await w.get(marca('escolher-informacao')).trigger('click');
    await w.get(marca('escolher-informacao')).trigger('click');
    await escolherNome(w, 0);
    const linha = w.findAllComponents(LinhaDaCondicao)[0];
    linha.vm.$emit('mudar', { ...linha.props('condicao'), valor: 'Campinas' });
    await w.vm.$nextTick();
    await w
      .get(`${marca('juntar-condicoes')} [data-opcao="qualquer"]`)
      .trigger('click');
    await botao(w, 'Ver resultado').trigger('click');
    const [[filtros]] = w.emitted('aplicar');
    expect(filtros.juntar).toBe('qualquer');
    expect(filtros.condicoes).toEqual([
      {
        id: 1,
        chave: 'name',
        tipo: TIPOS.TEXTO,
        modelo: 'standard',
        como: OPERADORES.TEM,
        valor: 'Campinas',
      },
    ]);
    w.unmount();
  });

  it('mudando um grupo: "Guardar no grupo" e "Ver sem guardar"', async () => {
    const w = montar({
      doGrupo: 'Gente de Campinas',
      filtros: { ...FILTROS_VAZIOS, cidade: 'Campinas' },
    });
    expect(w.get(marca('gaveta-do-grupo')).text()).toBe(
      'Você está mudando o grupo “Gente de Campinas”.'
    );
    expect(botao(w, 'Limpar')).toBeUndefined();
    await w.get(marca('guardar-no-grupo')).trigger('click');
    expect(w.emitted('guardar')[0][0].cidade).toBe('Campinas');
    await botao(w, 'Ver sem guardar').trigger('click');
    expect(w.emitted('aplicar')).toHaveLength(1);
    w.unmount();
  });
});
