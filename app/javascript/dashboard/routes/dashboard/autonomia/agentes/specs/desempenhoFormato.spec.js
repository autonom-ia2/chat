import { withFullI18n } from 'test-i18n';
import { defineComponent } from 'vue';
import { mount } from '@vue/test-utils';
import { useFormatoDoPainel } from '../composables/useFormatoDoPainel';

// #2226 v2 — os formatos do painel de desempenho no idioma que o Rodrigo vê (pt_BR): o tempo nunca
// arredonda para baixo, os pontos têm sempre 1 casa, o fuso é o da conta (nunca o nome longo do
// navegador) e a lista usa o "e" do idioma.
withFullI18n('pt_BR');

const formato = () => {
  let fmt = null;
  mount(
    defineComponent({
      setup() {
        fmt = useFormatoDoPainel();
        return () => null;
      },
    })
  );
  return fmt;
};

describe('useFormatoDoPainel', () => {
  it('shows seconds, then minutes and seconds, without rounding 70 s down to 1 min', () => {
    const fmt = formato();
    expect(fmt.segundos(33)).toBe('33 s');
    expect(fmt.segundos(70)).toBe('1 min 10 s');
    expect(fmt.segundos(89)).toBe('1 min 29 s');
    expect(fmt.segundos(120)).toBe('2 min');
    expect(fmt.segundos(null)).toBe('—');
  });

  it('always gives points with one decimal', () => {
    const fmt = formato();
    expect(fmt.pontos(5)).toBe('5,0 pontos');
    expect(fmt.pontos(-4.7)).toBe('4,7 pontos');
  });

  it('always says which dates a gain refers to, and says so when it is the full history', () => {
    const fmt = formato();
    const painel = { ticket: { moeda: 'BRL' } };
    const doPeriodo = {
      fechamentos: 4,
      valor: 1360,
      historico: false,
      periodo: { inicio: '2026-09-27', fim: '2026-10-26', dias: 30 },
    };
    const frase = fmt.fraseDoGanho(doPeriodo, painel);
    expect(frase.startsWith('≈ 4 vendas a mais · ≈ R$')).toBe(true);
    expect(frase.endsWith('1.360 em 30 dias (27/09 a 26/10)')).toBe(true);
    const doHistorico = {
      fechamentos: 19,
      valor: null,
      historico: true,
      periodo: { inicio: '2026-06-25', fim: '2026-10-26', dias: 124 },
    };
    expect(fmt.fraseDoGanho(doHistorico, painel)).toBe(
      'neste período ainda não dá para estimar; no histórico completo (4 meses, 25/06 a 26/10): ≈ 19 vendas a mais'
    );
    expect(fmt.fraseDoGanho({ fechamentos: null, valor: null }, painel)).toBe(
      ''
    );
  });

  it('names the time zone like the account settings do', () => {
    const fmt = formato();
    expect(fmt.fuso('America/Sao_Paulo')).toBe('America/Sao Paulo');
    expect(fmt.fuso('America/Sao_Paulo')).not.toContain('Horário');
  });

  it('joins a list with the word "e"', () => {
    const fmt = formato();
    expect(fmt.lista(['a conferência', 'o valor típico'])).toBe(
      'a conferência e o valor típico'
    );
  });
});
