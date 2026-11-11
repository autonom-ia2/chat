import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import pt from 'dashboard/i18n/locale/pt_BR/relacionamentosTrazer.json';
import en from 'dashboard/i18n/locale/en/relacionamentosTrazer.json';
import { leituraDeExemplo } from '../../demo/trazer';
import EtapasDoTopo from '../../components/trazer/EtapasDoTopo.vue';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
import TelaEnviar from '../../components/trazer/TelaEnviar.vue';
import TelaPronto from '../../components/trazer/TelaPronto.vue';

// Última leva antes da banca (#2894): texto sem gênero, cartão de pessoa
// repetida clicável, frase do Pronto numa linha, alinhamento e etapas em 390.
withFullI18n('pt_BR');

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const leitura = leituraDeExemplo('l1');

describe('R1. texto sem supor gênero', () => {
  it('a pergunta de clientes fala das pessoas, sem "suas clientes"', () => {
    expect(pt.RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.TITULO).toBe(
      'Essas pessoas já são clientes?'
    );
    expect(en.RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.TITULO).toBe(
      'Are these people already customers?'
    );
  });

  it('nenhuma frase do catálogo põe "cliente" no feminino ou no masculino de pessoa', () => {
    const textos = JSON.stringify(pt).toLowerCase();
    ['suas clientes', 'seus clientes', 'a cliente ', 'o cliente '].forEach(
      trecho => expect(textos).not.toContain(trecho)
    );
  });
});

describe('R2. cartão da pessoa repetida', () => {
  const montar = () =>
    mount(ProblemaDaLinha, {
      props: { problema: leitura.problemas.find(p => p.linha === 143) },
    });

  it('cada cartão termina com "Ficar com esta" e a seta, dentro do próprio botão', () => {
    const w = montar();
    ['88', '143'].forEach(linha => {
      const cartao = w.get(`[data-opcao="${linha}"]`);
      expect(cartao.text()).toContain('Ficar com esta');
      expect(cartao.find('.i-lucide-arrow-right').exists()).toBe(true);
      expect(cartao.findAll('button')).toHaveLength(0);
      expect(cartao.text()).toContain(`Ficar com a linha ${linha}`);
      const acao = cartao.get('[data-relacionamentos="ficar-com-esta"]');
      expect(acao.classes()).toContain('text-n-blue-11');
    });
  });

  it('o nome acessível do cartão diz qual linha fica', () => {
    const w = montar();
    expect(w.get('[data-opcao="88"]').attributes('aria-label')).toBe(
      'Ficar com a linha 88'
    );
  });
});

describe('R3. "N pessoas chegaram." numa linha a partir de md', () => {
  it('a frase não quebra em md+ e a ação discreta não reserva a coluna do canto', () => {
    const w = mount(TelaPronto, { props: { total: 195 } });
    const frase = w.get('[data-titulo-da-tela]');
    expect(frase.classes()).toContain('md:whitespace-nowrap');
    expect(w.find('[data-heroi-discreta]').exists()).toBe(false);
    expect(
      marca(w, 'trazer-outra').element.closest('[data-heroi-acao]')
    ).not.toBeNull();
    expect(marca(w, 'trazer-outra').text()).toBe('Trazer outra lista');
  });
});

describe('R4. alinhamento à borda esquerda dos outros blocos', () => {
  it('"Usar uma planilha de exemplo" não tem padding próprio', () => {
    const w = mount(TelaEnviar, { props: { mostrarExemplo: true } });
    const botao = marca(w, 'usar-exemplo');
    expect(botao.classes()).toEqual(
      expect.arrayContaining(['p-0', 'min-h-11', 'bg-transparent', 'border-0'])
    );
  });

  it('o botão do título "O que vou guardar" também não', () => {
    const w = mount(OQueVouGuardar, { props: { colunas: leitura.colunas } });
    expect(w.get('h2 button').classes()).toEqual(
      expect.arrayContaining(['p-0', 'min-h-11', 'bg-transparent', 'border-0'])
    );
  });
});

describe('R5. etapas do topo em 390 px', () => {
  it('traços e vãos encolhem no celular e a lista nunca passa da largura', () => {
    const w = mount(EtapasDoTopo, {
      props: { atual: 'pronto', trazendo: true },
    });
    const lista = marca(w, 'etapas');
    expect(lista.classes()).toEqual(
      expect.arrayContaining(['max-w-full', 'min-w-0', 'gap-2'])
    );
    const traco = w.get('[data-etapa="enviar"] .h-px');
    expect(traco.classes()).toEqual(
      expect.arrayContaining(['w-3', 'sm:w-6', 'md:w-12'])
    );
  });
});
