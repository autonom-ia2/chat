import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { aplicarDeixarDeFora, leituraDeExemplo } from '../../demo/trazer';
import { resumoDaTela } from '../../trazer/contagem';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
import { tudoResolvido } from './apoioDaDemo';
// #2894 — o topo do Conferir: o título curto, os contadores (cada um lido
// junto, o "precisam de você" como botão, uma região viva só) e os botões da
// casa.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

const leitura = leituraDeExemplo('l1');

const conferir = (l = leitura, extra = {}) =>
  mount(TelaConferir, {
    attachTo: document.body,
    props: {
      leitura: l,
      resumo: resumoDaTela(l),
      total: resumoDaTela(l).entram,
      ...extra,
    },
  });

const leituraDoContador = (w, chave) =>
  w.get(`[data-contador="${chave}"] .sr-only`).text();

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('título curto e contadores', () => {
  it('o título é só "Achei 203 pessoas." e cada contador é um nó lido junto', () => {
    const w = conferir();
    expect(w.get('h1').text()).toBe('Achei 203 pessoas.');
    expect(w.get('h1').attributes('aria-live')).toBeUndefined();
    expect(leituraDoContador(w, 'NOVAS')).toBe('180 novas');
    expect(leituraDoContador(w, 'COMPLETADAS')).toBe('15 já estavam aqui');
    expect(leituraDoContador(w, 'PRECISAM')).toBe('8 precisam de você');
    const numero = w.get('[data-contador="NOVAS"] .tabular-nums');
    expect(numero.text()).toBe('180');
    expect(numero.attributes('aria-hidden')).toBe('true');
  });

  it('contador com zero não aparece', () => {
    // Ninguém ficou de fora ainda.
    expect(conferir().find('[data-contador="DEIXADAS"]').exists()).toBe(false);
    const w = conferir(tudoResolvido(leitura));
    expect(w.find('[data-contador="PRECISAM"]').exists()).toBe(false);
    // "Novas" é a conta do servidor: a linha consertada não vira nova na tela.
    // Quem entra a mais aparece no botão (cinco consertos somam uma pessoa
    // cada; a linha repetida é troca: ela fica e a outra, já contada, sai).
    expect(leituraDoContador(w, 'NOVAS')).toBe('180 novas');
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 200 pessoas');
  });

  it('"precisam de você" é um botão que rola até o bloco e leva o foco ao título dele', async () => {
    const w = conferir();
    const contador = w.get('[data-contador="PRECISAM"] button');
    await contador.trigger('click');
    expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
    expect(document.activeElement).toBe(marca(w, 'precisam-titulo').element);
    expect(w.find('[data-contador="NOVAS"] button').exists()).toBe(false);
  });
});

describe('contadores com a mesma caixa', () => {
  it('o botão não traz padding, margem nem borda próprios; três em grid-cols-3, quatro em 2×2', () => {
    const w = conferir();
    const botao = w.get('[data-contador="PRECISAM"] button');
    expect(botao.classes()).toEqual(
      expect.arrayContaining(['p-0', 'm-0', 'border-0', 'min-h-11'])
    );
    const caixaDosOutros = w.get('[data-contador="NOVAS"] > div');
    ['p-0', 'm-0', 'min-h-11', 'justify-start'].forEach(classe => {
      expect(caixaDosOutros.classes()).toContain(classe);
      expect(botao.classes()).toContain(classe);
    });
    const lista = marca(w, 'contadores');
    expect(lista.classes()).toContain('grid-cols-3');
    const quatro = conferir(aplicarDeixarDeFora(leitura, 62));
    expect(marca(quatro, 'contadores').classes()).toContain('grid-cols-2');
  });
});

describe('a região viva dos contadores e as fichas de exemplo', () => {
  it('os contadores avisam a mudança por uma região viva só', () => {
    const w = conferir();
    expect(marca(w, 'contadores').attributes('aria-live')).toBe('polite');
    expect(w.findAll('[aria-live]')).toHaveLength(1);
  });

  it('exemplos com o mesmo nome não repetem a chave do v-for', () => {
    const aviso = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const repetida = {
      ...leitura,
      exemplos: [leitura.exemplos[0], leitura.exemplos[0], leitura.exemplos[1]],
    };
    const w = conferir(repetida);
    expect(w.findAll('[data-ficha-de-exemplo]')).toHaveLength(3);
    const duplicadas = aviso.mock.calls.filter(chamada =>
      String(chamada[0]).includes('Duplicate keys')
    );
    expect(duplicadas).toEqual([]);
    aviso.mockRestore();
  });
});

describe('os botões do Conferir', () => {
  it('o Salvar da pessoa é o mesmo Button azul sólido da casa, como o "Trazer N pessoas"', () => {
    const w = mount(TelaConferir, {
      props: {
        leitura,
        resumo: resumoDaTela(leitura),
        total: resumoDaTela(leitura).entram,
      },
    });
    // Só o Salvar das linhas: o da informação nova, em "O que vou guardar", é
    // ação secundária (cinza).
    const salvar = marca(w, 'precisam-de-voce')
      .findAll('button')
      .filter(b => b.text() === 'Salvar');
    expect(salvar.length).toBeGreaterThan(0);
    salvar.forEach(b => {
      expect(b.classes().join(' ')).toContain('bg-n-blue-11');
    });
    expect(marca(w, 'trazer-confirmar').classes().join(' ')).toContain(
      'bg-n-blue-11'
    );
  });
});
