import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraDeExemplo } from '../../demo/trazer';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
// #2894 — o cartão da pessoa repetida: cada linha é um cartão clicável
// inteiro, com "Ficar com esta" dentro dele.
withFullI18n('pt_BR');

const leitura = leituraDeExemplo('l1');

afterEach(() => {
  document.body.innerHTML = '';
});

describe('cartão da pessoa repetida', () => {
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
      expect(cartao.text()).toContain(`Linha ${linha} da planilha`);
      const acao = cartao.get('[data-relacionamentos="ficar-com-esta"]');
      expect(acao.classes()).toContain('text-n-blue-11');
    });
  });

  // Sem aria-label por cima: ele esconderia do leitor de tela o telefone e o
  // e-mail, que são o que distingue uma linha da outra.
  it('o nome acessível do cartão é o conteúdo dele: o que distingue a linha, a linha e a ação', () => {
    const w = montar();
    const cartao = w.get('[data-opcao="88"]');
    expect(cartao.attributes('aria-label')).toBeUndefined();
    expect(cartao.text()).toContain('(11) 94410-0088');
    expect(cartao.text()).toContain('paulo.hortencio@exemplo.com.br');
    expect(cartao.text()).toContain('Linha 88 da planilha');
    expect(cartao.text()).toContain('Ficar com esta');
  });
});
