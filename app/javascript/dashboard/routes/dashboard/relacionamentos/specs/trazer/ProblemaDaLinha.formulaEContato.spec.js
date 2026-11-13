import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import { LIMITES } from '../../trazer/limites';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';

// #2896 — o cartão da linha com o que o servidor manda no problema aberto: o
// `motivo` (a frase é a dele), o tipo `formula` (a linha que a tela não
// conserta, só deixa de fora) e a linha sem telefone nem e-mail (um campo só,
// que aceita os dois).
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const NOME_COM_FORMULA =
  '11987650005: o nome começa com um sinal (=, +, - ou @). Escreva sem o sinal.';

const FORMULA_NA_EMPRESA =
  'Nesta linha, “Empresa” começa com um sinal (=, +, - ou @). Corrija na planilha e envie de novo, ou deixe esta linha de fora.';

const ESCREVA_O_CONTATO = 'Escreva um telefone ou um e-mail.';

const TELEFONE = {
  linha: 4,
  tipo: 'telefone',
  nome: 'Carla Carvalhedo',
  valor: '(11) 2345-678',
  estado: 'aberto',
};

const EMAIL = {
  linha: 5,
  tipo: 'email',
  nome: 'Davi Dornelino',
  valor: 'davi.exemplo.com.br',
  estado: 'aberto',
};

const SEM_NOME = {
  linha: 6,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '11987650005',
  estado: 'aberto',
};

const SEM_CONTATO = {
  linha: 7,
  tipo: 'sem_contato',
  nome: 'Elisa Esteveira',
  valor: '',
  estado: 'aberto',
};

// A linha com uma fórmula na empresa: a tela não conserta.
const COM_FORMULA = {
  linha: 9,
  tipo: 'formula',
  campo: 'empresa',
  nome: 'Caio Camargo',
  estado: 'aberto',
};

// O conserto parcial, como o servidor responde: o telefone valeu e sobrou o nome.
const SOBROU_O_NOME = {
  linha: 3,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '11987650003',
  estado: 'aberto',
};

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('ProblemaDaLinha: o motivo que vem com o problema aberto', () => {
  const montar = problema =>
    mount(ProblemaDaLinha, { attachTo: document.body, props: { problema } });

  it('o nome que é fórmula diz isso, e não "falta o nome"', () => {
    const w = montar({
      ...SEM_NOME,
      valor: '=SOMA(A1)',
      motivo: 'formula_detected',
    });
    expect(w.text()).toContain(NOME_COM_FORMULA);
    expect(w.text()).not.toContain('falta o nome');
    expect(w.findAll('input')).toHaveLength(1);
  });

  it.each([
    [
      { ...TELEFONE, motivo: 'formula_phone_number' },
      'Carla Carvalhedo: o telefone começa com um sinal (=, +, - ou @). Escreva sem o sinal.',
    ],
    [
      { ...TELEFONE, motivo: 'blank_phone_number' },
      'Carla Carvalhedo: falta o telefone',
    ],
    [
      { ...EMAIL, motivo: 'formula_detected' },
      'Davi Dornelino: o e-mail começa com um sinal (=, +, - ou @). Escreva sem o sinal.',
    ],
    [{ ...EMAIL, motivo: 'blank_email' }, 'Davi Dornelino: falta o e-mail'],
    [
      { ...TELEFONE, motivo: 'invalid_brazilian_mobile_number' },
      'Carla Carvalhedo: este telefone não parece um celular. Confira o DDD e os dígitos.',
    ],
    [
      TELEFONE,
      'Carla Carvalhedo: este telefone não parece um celular. Confira o DDD e os dígitos.',
    ],
  ])('o cartão de %o diz "%s"', (problema, frase) => {
    expect(montar(problema).get('form p').text()).toBe(frase);
  });
});

describe('ProblemaDaLinha: a fórmula que a tela não conserta', () => {
  const montar = (problema, extra = {}) =>
    mount(ProblemaDaLinha, {
      attachTo: document.body,
      props: { problema, ...extra },
    });

  it('diz onde está a fórmula e o que fazer, sem campo de digitar e só com "Deixar de fora"', async () => {
    const w = montar(COM_FORMULA);
    expect(w.get('form p').text()).toBe(FORMULA_NA_EMPRESA);
    expect(w.text()).toContain('Linha 9 da planilha');
    expect(w.find('input').exists()).toBe(false);
    expect(w.find('button[type="submit"]').exists()).toBe(false);
    expect(w.findAll('button').map(botao => botao.text())).toEqual([
      'Deixar de fora',
    ]);
    await w.get('[data-relacionamentos="deixar-de-fora"]').trigger('click');
    expect(w.emitted('deixarDeFora')).toEqual([[9]]);
    expect(w.emitted('guardar')).toBeUndefined();
  });

  it('campo que a tela não conhece: a frase sem o nome do campo', () => {
    expect(
      montar({ ...COM_FORMULA, campo: 'outro' })
        .get('form p')
        .text()
    ).toBe(
      'Nesta linha, uma informação começa com um sinal (=, +, - ou @). Corrija na planilha e envie de novo, ou deixe esta linha de fora.'
    );
  });

  it('deixada de fora: a frase curta, o selo e o "Voltar atrás"', async () => {
    const w = montar({ ...COM_FORMULA, estado: 'deixado' });
    expect(w.text()).toContain(
      'Caio Camargo: uma informação começa com um sinal (=, +, - ou @)'
    );
    expect(w.text()).toContain('Deixada de fora');
    expect(w.text()).not.toContain('Corrija na planilha');
    await w.get('[data-relacionamentos="voltar-atras"]').trigger('click');
    expect(w.emitted('reabrir')).toEqual([[9]]);
  });

  it('com a planilha já apagada continua só com "Deixar de fora"', () => {
    const w = montar(COM_FORMULA, { semConserto: true });
    expect(w.get('form p').text()).toBe(FORMULA_NA_EMPRESA);
    expect(w.findAll('button')).toHaveLength(1);
  });
});

describe('ProblemaDaLinha: a linha sem telefone nem e-mail tem um campo só', () => {
  const montar = () =>
    mount(ProblemaDaLinha, {
      attachTo: document.body,
      props: { problema: SEM_CONTATO },
    });
  const salvar = w => w.get('form').trigger('submit');

  it('um campo de texto "Telefone ou e-mail", sem o campo de telefone e com o limite do servidor', () => {
    const w = montar();
    expect(w.findComponent(CampoDeTelefone).exists()).toBe(false);
    expect(w.findAll('input')).toHaveLength(1);
    expect(w.get('label').text()).toBe('Telefone ou e-mail');
    expect(w.get('input').attributes('maxlength')).toBe(String(LIMITES.VALOR));
    expect(LIMITES.VALOR).toBe(255);
  });

  it.each([
    ['elisa.esteveira@exemplo.com.br', 'elisa.esteveira@exemplo.com.br'],
    ['  11 98765-0007 ', '11 98765-0007'],
    [`${'e'.repeat(40)}@exemplo.com.br`, `${'e'.repeat(40)}@exemplo.com.br`],
  ])('salva "%s" como a pessoa escreveu', async (escrito, enviado) => {
    const w = montar();
    await w.get('input').setValue(escrito);
    await salvar(w);
    expect(w.emitted('guardar')).toEqual([[7, enviado]]);
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });

  it('salvar sem escrever diz o que falta, como alerta, e leva o foco ao campo', async () => {
    const w = montar();
    await salvar(w);
    expect(w.emitted('guardar')).toBeUndefined();
    expect(w.get('[role="alert"]').text()).toBe(ESCREVA_O_CONTATO);
    expect(document.activeElement).toBe(w.get('input').element);
    expect(
      w.get('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();
  });

  it.each([
    ['missing_contact', ESCREVA_O_CONTATO],
    [
      'invalid_brazilian_mobile_number',
      'Este telefone não parece um celular do Brasil. Confira o DDD e os dígitos.',
    ],
    ['invalid_email', 'Este e-mail não parece certo.'],
    ['muito_longo', 'Este texto é longo demais. Encurte e tente de novo.'],
    [
      'motivo_que_a_tela_nao_conhece',
      'Não consegui salvar esta linha. Tente de novo.',
    ],
  ])('a recusa `%s` diz a frase certa no campo', async (motivo, frase) => {
    const w = montar();
    await w.setProps({ recusa: { linha: 7, motivo } });
    await flushPromises();
    expect(w.get('[role="alert"]').text()).toBe(frase);
    expect(document.activeElement).toBe(w.get('input').element);
  });
});

describe('PrecisamDeVoce: o que sobra na linha depois do conserto', () => {
  const montar = problemas =>
    mount(PrecisamDeVoce, { attachTo: document.body, props: { problemas } });

  it('sobrou a fórmula na empresa: o cartão vira o da fórmula, com o foco em "Deixar de fora"', async () => {
    const w = montar([{ ...TELEFONE, linha: 9 }, SEM_CONTATO]);
    await w.setProps({ problemas: [COM_FORMULA, SEM_CONTATO] });
    await flushPromises();
    const cartao = w.get('[data-linha="9"]');
    expect(cartao.text()).toContain(FORMULA_NA_EMPRESA);
    expect(cartao.find('input').exists()).toBe(false);
    expect(document.activeElement).toBe(
      cartao.get('[data-relacionamentos="deixar-de-fora"]').element
    );
    expect(w.get('[data-relacionamentos="anuncio-precisam"]').text()).toBe(
      'Linha 9: salvei. Ainda falta resolver outra coisa nesta linha.'
    );
    expect(w.get('[data-relacionamentos="precisam-titulo"]').text()).toBe(
      'Precisam de você (2)'
    );
  });

  it('voltar atrás na linha guardada devolve o problema do começo, com outro tipo', async () => {
    const guardada = {
      ...SOBROU_O_NOME,
      estado: 'guardado',
      corrigido: 'Bruno Brandolim',
    };
    const w = montar([guardada]);
    expect(w.get('[data-linha="3"]').text()).toContain('Pronto');
    await w.setProps({
      problemas: [{ ...TELEFONE, linha: 3, nome: '', valor: '(11) 2345-678' }],
    });
    await flushPromises();
    expect(w.get('[data-linha="3"]').text()).toContain(
      'este telefone não parece um celular'
    );
    expect(w.get('[data-relacionamentos="anuncio-precisam"]').text()).toBe(
      'Linha 3: voltou para você conferir'
    );
  });
});
