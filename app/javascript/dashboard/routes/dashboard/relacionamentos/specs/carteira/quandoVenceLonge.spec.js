import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import FraseDoSeguro from '../../components/carteira/FraseDoSeguro.vue';
import LinhaDeSeguro from '../../components/carteira/LinhaDeSeguro.vue';
import LinhaDoSeguroNaFicha from '../../components/carteira/LinhaDoSeguroNaFicha.vue';
import ControlesDeSeguros from '../../components/carteira/ControlesDeSeguros.vue';
import CampoDeBusca from '../../components/lista/CampoDeBusca.vue';
import { DIA_EM_MS } from '../../fonte/grupos';
import { daCarteira, textoDe } from './apoio';

// "Vence em N dias" só até 90 dias (#2897): mais longe, a tela mostra só a
// data, com o ano. Vale na lista, na ficha, no painel da conversa e na frase da
// gaveta, pela mesma regra (carteira/quandoDoSeguro.js).
withFullI18n('pt_BR');

const AGORA = new Date(2026, 10, 11, 12, 0, 0).getTime();
const em = dias => Math.floor((AGORA + dias * DIA_EM_MS) / 1000);
const seguro = dias => ({
  id: 2,
  tipo: 'residencial',
  seguradora: 'Horizonte Seguros',
  numero: 'HZ-002318',
  termina: em(dias),
  temPdf: true,
  renovacao: null,
  segurado: { tipo: 'pessoa', nome: 'Fábio Figueirão' },
  pessoa: { name: 'Fábio Figueirão', phone_number: '+5511910000023' },
});
const montar = (peca, props) =>
  mount(peca, { props: { agora: AGORA, ...props } });

describe('acima de 90 dias a tela mostra só a data', () => {
  it('na lista de seguros', () => {
    const longe = montar(LinhaDeSeguro, { seguro: seguro(214) });
    const perto = montar(LinhaDeSeguro, { seguro: seguro(90) });

    expect(longe.text()).toContain('vence em 13/06/2027');
    expect(longe.text()).not.toContain('214 dias');
    expect(perto.text()).toContain('vence em 90 dias (09/02');
  });

  it('na ficha e no painel da conversa', () => {
    const naFicha = montar(LinhaDoSeguroNaFicha, { seguro: seguro(214) });
    const noPainel = montar(LinhaDoSeguroNaFicha, {
      seguro: seguro(214),
      compacta: true,
    });
    const perto = montar(LinhaDoSeguroNaFicha, { seguro: seguro(18) });

    expect(naFicha.text()).toContain('Vence em 13/06/2027');
    expect(naFicha.text()).not.toContain('dias');
    expect(noPainel.text()).toContain('vence em 13/06/2027');
    expect(noPainel.text()).not.toContain('dias');
    expect(perto.text()).toContain('Vence em 18 dias · 29/11/2026');
  });

  it('na frase da gaveta de um seguro com parcela em aberto ou em renovação', () => {
    const emRenovacao = dias => ({
      ...seguro(dias),
      renovacao: { etapa: 'A vencer', cuida: 'Bia Lunardelli' },
    });
    const frase = dias =>
      textoDe(
        montar(FraseDoSeguro, {
          seguro: emRenovacao(dias),
          daConta: { cotaSozinha: true },
        }),
        daCarteira('frase-do-seguro')
      );

    expect(frase(18)).toBe(
      'Vence em 18 dias. A renovação começou. Falta cotar.'
    );
    expect(frase(1)).toBe('Vence amanhã. A renovação começou. Falta cotar.');
  });
});

describe('a busca da aba Seguros', () => {
  it('o texto de exemplo é curto e a busca tem largura mínima para ele', () => {
    const w = mount(ControlesDeSeguros, {
      props: { ordem: 'vence_primeiro' },
    });
    const busca = w.get(daCarteira('busca'));

    // Em tela larga o campo usa este texto (em 390 px, o curto).
    expect(w.getComponent(CampoDeBusca).props('placeholder')).toBe(
      'Buscar por nome, placa ou documento'
    );
    // 26rem de campo menos 6rem de margens internas: 20rem para o texto.
    expect(busca.classes()).toContain('md:min-w-[26rem]');
  });
});
