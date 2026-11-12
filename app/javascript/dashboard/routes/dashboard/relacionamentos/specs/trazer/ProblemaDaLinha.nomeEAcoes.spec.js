import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { aplicarDeixarDeFora, leituraDeExemplo } from '../../demo/trazer';
import * as contagem from '../../trazer/contagem';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
// #2894 — o cartão de cada linha que precisa da pessoa: o nome dela na
// frente, a linha da planilha como apoio, as duas ações como botões da casa e
// o formato do e-mail deixado para o servidor.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

const leitura = leituraDeExemplo('l1');

const problemaDe = (l, linha) => l.problemas.find(p => p.linha === linha);

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('problemas com o nome da pessoa', () => {
  const problema = linha => leitura.problemas.find(p => p.linha === linha);
  const montar = linha =>
    mount(ProblemaDaLinha, { props: { problema: problema(linha) } });

  it('o nome vem na frente e a linha vai como apoio em cinza', () => {
    const w = montar(14);
    expect(w.text()).toContain(
      'Tadeu Imbirussu: este telefone não parece um celular. Confira o DDD e os dígitos.'
    );
    expect(w.text()).toContain('Linha 14 da planilha');
    expect(w.get('p').classes()).toContain('font-semibold');
  });

  it('sem nome usa o contato que houver', () => {
    expect(montar(62).text()).toContain('(11) 95412-0062: falta o nome');
  });

  it('sem nome nem contato cai na linha', () => {
    const w = mount(ProblemaDaLinha, {
      props: {
        problema: { linha: 9, tipo: 'nome', nome: '', estado: 'aberto' },
      },
    });
    expect(w.text()).toContain('Linha 9: falta o nome');
  });

  it('duplicada: título com o nome e cartões mostrando a diferença', async () => {
    const w = montar(143);
    expect(w.text()).toContain(
      'Paulo Hortêncio aparece duas vezes. Qual fica?'
    );
    expect(w.text()).toContain('Linhas 88 e 143 da planilha');
    const a = w.get('[data-opcao="88"]');
    const b = w.get('[data-opcao="143"]');
    // O título do cartão é o que diferencia (o telefone); a linha vai de apoio.
    expect(a.get('[data-relacionamentos="titulo-do-cartao"]').text()).toBe(
      '(11) 94410-0088'
    );
    const linhasDeA = a.findAll('span').map(s => s.text());
    expect(linhasDeA).toContain('Linha 88 da planilha');
    // O e-mail só quebra no "@".
    expect(a.html()).toContain('paulo.hortencio<wbr>@exemplo.com.br');
    // As duas linhas repetem o e-mail: é o telefone que muda de uma para a outra.
    expect(b.findAll('span').map(s => s.text())).toEqual([
      '(11) 94410-0143',
      'paulo.hortencio@exemplo.com.br',
      'Linha 143 da planilha',
      'Ficar com esta',
      '',
    ]);
    expect(a.classes()).toEqual(
      expect.arrayContaining([
        'min-h-11',
        'border',
        'border-n-weak',
        'rounded-xl',
        'focus-visible:outline-2',
      ])
    );
    expect(a.classes().join(' ')).toContain('hover:enabled:bg-');
    expect(w.text()).not.toContain('Na planilha:');
    expect(a.element.parentElement.className).toContain('sm:grid-cols-2');
    await b.trigger('click');
    expect(w.emitted('guardar')).toEqual([[143, 143]]);
  });

  it('as duas ações são botões da casa (h-12, rounded-lg), alinhados', () => {
    const w = montar(37);
    const salvar = w.findAll('button').find(b => b.text() === 'Salvar');
    const deixar = marca(w, 'deixar-de-fora');
    [salvar, deixar].forEach(b => {
      expect(b.classes()).toContain('h-12');
      expect(b.classes()).toContain('rounded-lg');
      expect(b.classes().join(' ')).not.toContain('rounded-xl');
    });
    expect(deixar.classes().join(' ')).toContain('bg-n-slate-9/10');
    expect(salvar.element.parentElement).toBe(deixar.element.parentElement);
  });

  it('Salvar não ganha opacidade extra e nunca fica desligado por falta de preenchimento', () => {
    const w = montar(37);
    const salvar = w.findAll('button').find(b => b.text() === 'Salvar');
    expect(salvar.attributes('disabled')).toBeUndefined();
    const extras = salvar.classes().filter(c => c.startsWith('opacity-'));
    expect(extras).toEqual([]);
    expect(salvar.classes().join(' ')).not.toContain('faded');
  });

  it('o bloco diz que quem ficar sem resolver fica de fora, e o botão já faz isso', () => {
    const w = mount(PrecisamDeVoce, {
      props: { problemas: leitura.problemas },
    });
    expect(w.text()).toContain('Quem ficar sem resolver fica de fora.');
    // 195 = 180 novas + 15 completadas: as 8 abertas não entram na conta.
    expect(contagem.resumoDaTela(leitura).entram).toBe(195);
    expect(contagem.resumoDaTela(aplicarDeixarDeFora(leitura, 62)).entram).toBe(
      195
    );
  });
});

describe('o formato do e-mail é do servidor', () => {
  // O cartão da linha não confere mais o formato do e-mail: só trava o campo
  // vazio. Quem confere é o servidor, e a recusa dele diz o motivo na linha.
  it('contagem não tem mais o seu e o cartão da linha deixa o formato com o servidor', async () => {
    expect(contagem.emailValido).toBeUndefined();
    const w = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(leitura, 37) },
    });
    await w.get('input').setValue('a@b..com');
    await w.get('form').trigger('submit');
    await w.get('input').setValue('  ana@exemplo.com.br ');
    await w.get('form').trigger('submit');
    expect(w.emitted('guardar')).toEqual([
      [37, 'a@b..com'],
      [37, 'ana@exemplo.com.br'],
    ]);
  });
});
