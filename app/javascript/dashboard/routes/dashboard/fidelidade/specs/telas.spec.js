import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import FidelidadeTela from '../components/FidelidadeTela.vue';
import PainelDoCartao from '../components/PainelDoCartao.vue';
import MontarPrograma from '../components/MontarPrograma.vue';
import CartaoDeCarimbos from '../components/CartaoDeCarimbos.vue';
import ProgramaPronto from '../components/ProgramaPronto.vue';
import ConferirCupom from '../components/cupons/ConferirCupom.vue';
import LinhaDoCupom from '../components/cupons/LinhaDoCupom.vue';
import ListaDeCupons from '../components/cupons/ListaDeCupons.vue';
import MontarCupom from '../components/cupons/MontarCupom.vue';
import { cupomNovo, programaNovo } from '../regras';

// #3100 — as telas da fidelidade com o texto real em pt_BR: o que aparece em
// cada estado e o que cada botão avisa a quem usa.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 23, 15);
const S = AGORA / 1000;
const PROGRAMA = {
  ...programaNovo(),
  premio: 'Lavagem grátis',
  validade_meses: 6,
};
const CUPOM = {
  id: 1,
  nome: 'Volta de dezembro',
  oferta: { tipo: 'porcentagem', valor: 10 },
  moeda: 'BRL',
  prefixo: 'VOLTA',
  validade_dias: 15,
  ligado: true,
  mandados: 240,
  usados: 37,
  vendas: [{ moeda: 'BRL', total: 4820 }],
};
// Junta as linhas e os espaços repetidos do texto da tela (sem expressão
// regular). O Intl separa "R$" do número com espaço que não quebra.
const texto = wrapper =>
  wrapper
    .text()
    .replaceAll('\n', ' ')
    .replaceAll('\u00a0', ' ')
    .split(' ')
    .filter(Boolean)
    .join(' ');
const sel = nome => `[data-fidelidade="${nome}"]`;
// O Dialog da casa lê a store: aqui, só a casca com o confirmar.
const stubs = {
  Dialog: {
    template:
      '<div data-dialog><slot /><slot name="footer" /><button data-confirmar @click="$emit(\'confirm\')" /></div>',
    methods: { open() {}, close() {} },
  },
};

describe('FidelidadeTela', () => {
  const montar = props =>
    mount(FidelidadeTela, { props: { aba: 'cartao', agora: AGORA, ...props } });

  it('sem cartão, quem pode vê o convite e cria', async () => {
    const tela = montar({ programa: null, podeMudar: true });
    expect(texto(tela)).toContain(
      'Faça o cliente voltar com um cartão fidelidade.'
    );
    await tela.find(sel('criar')).trigger('click');
    expect(tela.emitted('criar')).toHaveLength(1);
  });

  it('sem cartão, quem só vê lê que outra pessoa cria e não tem botão', () => {
    const tela = montar({ programa: null, podeMudar: false });
    expect(tela.find(sel('criar')).exists()).toBe(false);
    expect(texto(tela)).toContain('Quem administra a conta pode criar.');
  });

  it('carregando mostra o esqueleto no lugar do convite', () => {
    const tela = montar({ programa: null, carregando: true });
    expect(tela.find(sel('carregando')).exists()).toBe(true);
    expect(tela.find(sel('vazio')).exists()).toBe(false);
  });

  it('na aba Cupons, sem cupom, não mostra o conferir', () => {
    const tela = montar({ aba: 'cupons', cupons: [], podeMudar: true });
    expect(tela.find(sel('conferir')).exists()).toBe(false);
    expect(texto(tela)).toContain(
      'Crie um cupom para trazer o cliente de volta.'
    );
  });

  it('as abas trocam pela seta e avisam a aba nova', async () => {
    const tela = montar({ programa: PROGRAMA, resumo: null });
    await tela
      .find(sel('aba-cartao'))
      .trigger('keydown', { key: 'ArrowRight' });
    expect(tela.emitted('update:aba')[0]).toEqual(['cupons']);
  });
});

describe('PainelDoCartao', () => {
  it('mostra os números e chama quem está perto do prêmio', async () => {
    const painel = mount(PainelDoCartao, {
      global: { stubs },
      props: {
        programa: PROGRAMA,
        resumo: { com_saldo: 128, perto: 9, premios_30d: 14 },
        podeMudar: true,
      },
    });
    const numero = nome => painel.find(sel(`numero-${nome}`));
    expect(numero('com-saldo').find('dd').text()).toBe('128');
    expect(numero('com-saldo').find('dt').text()).toBe('clientes no cartão');
    expect(numero('perto').find('dt').text()).toBe('estão perto do prêmio');
    expect(texto(painel)).toContain(
      'Os carimbos vencem 6 meses depois de recebidos.'
    );
    await painel.find(sel('ver-perto')).trigger('click');
    expect(painel.emitted('verPerto')).toHaveLength(1);
  });

  it('sem ninguém no cartão, explica de onde vêm os carimbos', () => {
    const painel = mount(PainelDoCartao, {
      global: { stubs },
      props: {
        programa: PROGRAMA,
        resumo: { com_saldo: 0, perto: 0, premios_30d: 0 },
      },
    });
    expect(painel.find(sel('ninguem')).exists()).toBe(true);
    expect(painel.find(sel('ver-perto')).exists()).toBe(false);
  });

  it('pausado avisa e quem só vê não muda as regras', () => {
    const painel = mount(PainelDoCartao, {
      global: { stubs },
      props: { programa: { ...PROGRAMA, ligado: false }, resumo: null },
    });
    expect(painel.find(sel('pausado')).exists()).toBe(true);
    expect(painel.find(sel('mudar')).exists()).toBe(false);
    expect(painel.find(sel('ligar')).exists()).toBe(false);
    expect(texto(painel)).toContain(
      'Peça a quem administra a conta para ligar de novo.'
    );
  });

  it('pausado, quem pode liga o cartão de novo pela faixa', async () => {
    const painel = mount(PainelDoCartao, {
      global: { stubs },
      props: {
        programa: { ...PROGRAMA, ligado: false },
        resumo: null,
        podeMudar: true,
      },
    });
    expect(painel.find(sel('pausar')).exists()).toBe(false);
    await painel.find(sel('ligar')).trigger('click');
    expect(painel.emitted('ligar')).toHaveLength(1);
  });

  it('o cartão do painel é o modelo da conta, sem saldo de ninguém', () => {
    const painel = mount(PainelDoCartao, {
      global: { stubs },
      props: { programa: PROGRAMA, resumo: null, podeMudar: true },
    });
    expect(texto(painel)).toContain('Cartão de 10 carimbos');
    expect(texto(painel)).not.toContain('Faltam');
    expect(painel.find(sel('pausar')).exists()).toBe(true);
  });

  it('pausar pergunta antes', async () => {
    const painel = mount(PainelDoCartao, {
      global: { stubs },
      props: { programa: PROGRAMA, resumo: null, podeMudar: true },
    });
    await painel.find(sel('pausar')).trigger('click');
    expect(painel.emitted('pausar')).toBeUndefined();
    expect(texto(painel)).toContain('Quem já tem continua com o que juntou.');
    await painel.find('[data-confirmar]').trigger('click');
    expect(painel.emitted('pausar')).toHaveLength(1);
  });
});

describe('CartaoDeCarimbos', () => {
  it('carimba as bolinhas que a pessoa tem e diz quantas faltam', () => {
    const cartao = mount(CartaoDeCarimbos, {
      props: { meta: 10, tem: 7, premio: 'Lavagem grátis' },
    });
    expect(cartao.findAll('[data-fidelidade="bolinhas"] > span')).toHaveLength(
      10
    );
    expect(cartao.findAll('[data-cheia]')).toHaveLength(7);
    expect(texto(cartao)).toContain('Faltam 3 carimbos para o prêmio');
  });

  it('em pontos mostra a barra no lugar das bolinhas', () => {
    const cartao = mount(CartaoDeCarimbos, {
      props: { tipo: 'pontos', meta: 500, tem: 320 },
    });
    expect(cartao.find(sel('bolinhas')).exists()).toBe(false);
    expect(texto(cartao)).toContain('320 de 500 pontos');
  });
});

describe('MontarPrograma', () => {
  const montar = (programa, opcoes = {}) =>
    mount(MontarPrograma, { props: { modelValue: programa }, ...opcoes });

  it('sem prêmio, o salvar mostra o que falta, leva o foco e não salva', async () => {
    const tela = montar(
      { ...PROGRAMA, premio: '' },
      { attachTo: document.body }
    );
    await tela.find(sel('salvar')).trigger('click');
    await new Promise(resolve => {
      setTimeout(resolve);
    });
    expect(tela.emitted('salvar')).toBeUndefined();
    expect(texto(tela)).toContain('Escreva o prêmio, em até 80 letras.');
    expect(tela.find(sel('erro-geral')).attributes('role')).toBe('alert');
    expect(document.activeElement).toBe(
      tela.find(`${sel('premio')} input`).element
    );
    tela.unmount();
  });

  it('pronto, o salvar avisa', async () => {
    const tela = montar(PROGRAMA);
    await tela.find(sel('salvar')).trigger('click');
    expect(tela.emitted('salvar')).toHaveLength(1);
  });

  it('trocar para pontos manda o programa com a meta de pontos', async () => {
    const tela = montar(PROGRAMA);
    await tela.find('[data-escolha="pontos"] input').setValue(true);
    expect(tela.emitted('update:modelValue')[0][0]).toMatchObject({
      tipo: 'pontos',
      meta: 500,
    });
  });

  it('a prévia mostra a compra de exemplo sem troco', () => {
    const tela = montar(PROGRAMA);
    expect(tela.find(sel('resumo')).text()).toContain('2 carimbos');
  });

  it('em pontos, a compra de exemplo não fica pequena demais', () => {
    const tela = montar({ ...PROGRAMA, tipo: 'pontos', a_cada: 1, meta: 500 });
    expect(texto(tela.find(sel('resumo')))).toContain(
      'uma compra de R$ 100 dá 100 pontos'
    );
  });
});

describe('ProgramaPronto', () => {
  it('cada aviso abre a automação pronta pelo seu nome', async () => {
    const tela = mount(ProgramaPronto, { props: { programa: PROGRAMA } });
    await tela.find(`${sel('aviso-meta')} button`).trigger('click');
    expect(tela.emitted('usar')[0]).toEqual(['meta']);
  });

  it('a mensagem de exemplo segue o programa criado', () => {
    const tela = mount(ProgramaPronto, {
      props: {
        programa: { ...PROGRAMA, tipo: 'pontos', a_cada: 1, meta: 500 },
      },
    });
    expect(texto(tela.find(sel('aviso-saldo')))).toContain(
      'Você recebeu 100 pontos e já tem 320 de 500 pontos.'
    );
    expect(texto(tela)).not.toContain('carimbo');
  });
});

describe('ConferirCupom', () => {
  const montar = props =>
    mount(ConferirCupom, { props: { agora: AGORA, ...props } });

  it('confere o código digitado, limpo', async () => {
    const tela = montar();
    await tela.find(sel('codigo')).setValue(' volta-7kd2 ');
    await tela.find('form').trigger('submit');
    expect(tela.emitted('conferir')[0]).toEqual(['VOLTA-7KD2']);
  });

  it('não confere com o campo vazio', async () => {
    const tela = montar();
    await tela.find('form').trigger('submit');
    expect(tela.emitted('conferir')).toBeUndefined();
  });

  it('valendo, mostra de quem é e deixa usar', async () => {
    const tela = montar({
      resultado: {
        estado: 'valido',
        oferta: { tipo: 'porcentagem', valor: 10 },
        cliente: 'Maria Souza',
        vale_ate: S + 8 * 86400,
      },
    });
    expect(texto(tela)).toContain('Vale! 10% de desconto.');
    expect(texto(tela)).toContain('De Maria Souza.');
    await tela.find(sel('usar')).trigger('click');
    expect(tela.emitted('usar')).toHaveLength(1);
  });

  it.each([
    ['usado', { estado: 'usado', usado_em: S - 86400 }, 'já foi usado'],
    ['vencido', { estado: 'vencido', vale_ate: S - 86400 }, 'venceu em'],
    ['nao_existe', { estado: 'nao_existe' }, 'Não achamos este código.'],
  ])('%s diz o que aconteceu e não deixa usar', (_, resultado, frase) => {
    const tela = montar({ resultado });
    expect(texto(tela)).toContain(frase);
    expect(tela.find(sel('usar')).exists()).toBe(false);
  });

  it('depois de usado, a frase troca e não diz mais que vale', () => {
    const tela = montar({
      resultado: {
        estado: 'valido',
        oferta: { tipo: 'porcentagem', valor: 10 },
      },
      usado: true,
    });
    expect(tela.find(sel('usado-ok')).exists()).toBe(true);
    expect(texto(tela)).toContain(
      'Pronto, cupom marcado como usado. Dê 10% de desconto ao cliente.'
    );
    expect(texto(tela)).not.toContain('Vale!');
    expect(tela.find(sel('usar')).exists()).toBe(false);
  });
});

describe('cupons no relatório', () => {
  it('mostra mandados, usados com a taxa e quanto vendeu', () => {
    const linha = mount(LinhaDoCupom, { props: { cupom: CUPOM } });
    expect(texto(linha)).toContain('usados (15%)');
    expect(linha.find(sel('vendeu')).text()).toContain('4.820');
    expect(texto(linha)).toContain('VOLTA-7KD2');
  });

  it('sem acesso aos valores, não mostra o dinheiro', () => {
    const linha = mount(LinhaDoCupom, {
      props: { cupom: { ...CUPOM, vendas: null } },
    });
    expect(linha.find(sel('vendeu')).text()).toContain('você não vê valores');
  });

  it('cupom não mandado traz o botão que abre a automação pronta', async () => {
    const linha = mount(LinhaDoCupom, {
      props: { cupom: { ...CUPOM, mandados: 0, usados: 0 }, podeMudar: true },
    });
    await linha.find(sel('mandar-cupom')).trigger('click');
    expect(linha.emitted('mandar')).toHaveLength(1);
    await linha.find(sel('pausar-cupom')).trigger('click');
    expect(linha.emitted('pausar')).toHaveLength(1);
  });

  it('cupom pausado liga de novo e não manda mandar', async () => {
    const linha = mount(LinhaDoCupom, {
      props: {
        cupom: { ...CUPOM, ligado: false, mandados: 0, usados: 0 },
        podeMudar: true,
      },
    });
    expect(linha.find(sel('nao-mandado')).exists()).toBe(false);
    await linha.find(sel('ligar-cupom')).trigger('click');
    expect(linha.emitted('ligar')).toHaveLength(1);
  });

  it('quem só vê não cria cupom', () => {
    const lista = mount(ListaDeCupons, { props: { cupons: [CUPOM] } });
    expect(lista.find(sel('novo-cupom')).exists()).toBe(false);
  });
});

describe('MontarCupom', () => {
  it('sem nome, o salvar diz o que falta', async () => {
    const tela = mount(MontarCupom, {
      props: { modelValue: { ...cupomNovo(), prefixo: 'VOLTA' }, agora: AGORA },
    });
    await tela.find(sel('salvar-cupom')).trigger('click');
    expect(tela.emitted('salvar')).toBeUndefined();
    expect(texto(tela)).toContain('Dê um nome ao cupom.');
    expect(texto(tela)).toContain('Faltam os dados do cupom.');
  });

  it('o começo do código sai limpo e a prévia mostra o código', async () => {
    const tela = mount(MontarCupom, {
      props: {
        modelValue: { ...cupomNovo(), nome: 'Volta', prefixo: 'VOLTA' },
        agora: AGORA,
      },
    });
    expect(tela.find(sel('previa-cupom')).text()).toContain('VOLTA-7KD2');
    await tela.find(`${sel('prefixo')} input`).setValue('são joão');
    expect(tela.emitted('update:modelValue').at(-1)[0].prefixo).toBe('SAOJOAO');
  });
});
