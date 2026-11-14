import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { LIMITES } from '../../trazer/limites';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
// #2896 — o cartão da linha com os motivos que o servidor manda na recusa do
// conserto, e o cartão que troca quando o valor vale mas a linha ainda tem
// outro problema.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const FORMULA =
  'Este texto começa com um sinal (=, +, - ou @). Escreva sem o sinal.';

const PLANILHA_APAGADA =
  'A planilha já foi apagada daqui. Para corrigir uma linha, envie a planilha de novo.';

const MUITO_LONGO = 'Este texto é longo demais. Encurte e tente de novo.';

// As linhas como o servidor as devolve (a planilha `com_problemas` do spec).
const TELEFONE = {
  linha: 4,
  tipo: 'telefone',
  nome: 'Carla Carvalhedo',
  valor: '(11) 2345-678',
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

// O telefone da linha 4 valeu, mas a linha também não tinha nome: o servidor
// guarda o telefone e devolve o problema que sobrou.
const SOBROU_O_NOME = {
  linha: 4,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '+5511987650004',
  estado: 'aberto',
};

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('ProblemaDaLinha: a frase de cada motivo do servidor', () => {
  const montar = problema =>
    mount(ProblemaDaLinha, { attachTo: document.body, props: { problema } });

  it.each([
    ['formula_phone_number', TELEFONE, FORMULA],
    ['blank_name', SEM_NOME, 'Escreva o nome.'],
    ['formula_detected', SEM_NOME, FORMULA],
    ['missing_contact', SEM_CONTATO, 'Escreva um telefone ou um e-mail.'],
    ['planilha_apagada', TELEFONE, PLANILHA_APAGADA],
    ['muito_longo', SEM_NOME, MUITO_LONGO],
  ])('motivo `%s`', async (motivo, problema, frase) => {
    const w = montar(problema);
    await w.setProps({ recusa: { linha: problema.linha, motivo } });
    await flushPromises();
    expect(w.get('[role="alert"]').text()).toBe(frase);
  });

  it('a linha sem nome diz por onde a pessoa é achada', () => {
    expect(montar(SEM_NOME).text()).toContain('11987650005: falta o nome');
  });

  it('o campo de texto do conserto não deixa passar do limite do servidor', () => {
    expect(montar(SEM_NOME).get('input').attributes('maxlength')).toBe(
      String(LIMITES.VALOR)
    );
    expect(LIMITES).toEqual({
      VALOR: 255,
      NOME_DO_CAMPO: 255,
      PARA_QUE_SERVE: 1000,
    });
  });
});

describe('PrecisamDeVoce: o conserto valeu e sobrou outro problema na linha', () => {
  it('troca o cartão pelo problema novo, com o campo dele vazio, o foco nele e o anúncio', async () => {
    const w = mount(PrecisamDeVoce, {
      attachTo: document.body,
      props: { problemas: [TELEFONE, SEM_CONTATO] },
    });
    const cartao = () => w.get('[data-linha="4"]');
    expect(cartao().text()).toContain('este telefone não parece um celular');
    await w.setProps({ problemas: [SOBROU_O_NOME, SEM_CONTATO] });
    await flushPromises();
    expect(cartao().text()).toContain('+5511987650004: falta o nome');
    expect(cartao().text()).not.toContain(
      'este telefone não parece um celular'
    );
    expect(cartao().findAll('input')).toHaveLength(1);
    expect(cartao().get('input').element.value).toBe('');
    expect(cartao().find('[role="alert"]').exists()).toBe(false);
    expect(document.activeElement).toBe(cartao().get('input').element);
    expect(w.get('[data-relacionamentos="anuncio-precisam"]').text()).toBe(
      'Linha 4: salvei. Ainda falta resolver outra coisa nesta linha.'
    );
    expect(w.get('[data-relacionamentos="precisam-titulo"]').text()).toBe(
      'Precisam de você (2)'
    );
  });
});
