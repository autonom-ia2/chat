import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import { CARTOES, cartaoDoProblema } from '../../trazer/cartaoDoProblema';
import { chaveDoTexto } from '../../trazer/textoDoProblema';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
import CartaoDaRepetida from '../../components/trazer/problema/CartaoDaRepetida.vue';
import CartaoDoTelefone from '../../components/trazer/problema/CartaoDoTelefone.vue';
import CartaoDoTexto from '../../components/trazer/problema/CartaoDoTexto.vue';
import CartaoSemConserto from '../../components/trazer/problema/CartaoSemConserto.vue';
import LinhaRecolhida from '../../components/trazer/problema/LinhaRecolhida.vue';

// #2896, Fatia 2 — o cartão de cada linha que precisa da pessoa, com os corpos
// que o servidor manda: o telefone vem como está na planilha (sem DDI), a tela
// só trava o campo vazio (o resto é o servidor que confere e diz o motivo), a
// linha resolvida mostra o valor salvo e cada tipo de cartão é um componente.
withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

const TELEFONE = {
  linha: 14,
  tipo: 'telefone',
  nome: 'Tadeu Imbirussu',
  valor: '(11) 9738-0014',
  estado: 'aberto',
};
const EMAIL = {
  linha: 37,
  tipo: 'email',
  nome: 'Rita Carvalhedo',
  valor: 'rita.carvalhedo.exemplo.com.br',
  estado: 'aberto',
};
const SEM_NOME = {
  linha: 62,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '11954120062',
  estado: 'aberto',
};
const SEM_CONTATO = {
  linha: 171,
  tipo: 'sem_contato',
  nome: 'Helena Ourivesco',
  valor: '',
  estado: 'aberto',
};
const REPETIDA = {
  linha: 143,
  tipo: 'duplicada',
  nome: 'Paulo Hortêncio',
  valor: 'Paulo Hortêncio',
  estado: 'aberto',
  outraLinha: 88,
  duplicadas: [
    {
      linha: 88,
      telefone: '11944100088',
      email: 'paulo.hortencio@exemplo.com.br',
    },
    { linha: 143, telefone: '11944100143', email: '' },
  ],
};
const COM_FORMULA = {
  linha: 9,
  tipo: 'formula',
  campo: 'empresa',
  nome: 'Caio Camargo',
  estado: 'aberto',
};

const montar = (problema, extra = {}) =>
  mount(ProblemaDaLinha, {
    attachTo: document.body,
    props: { problema, ...extra },
  });
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const numero = w => w.get('input[type="tel"]');
const pais = w => w.get('[role="combobox"]');
const salvar = w => w.get('form').trigger('submit');
const alerta = w => w.get('[role="alert"]');

describe('o telefone errado entra no campo como veio da planilha', () => {
  // Os dígitos são os da planilha; o campo só os agrupa do jeito do Brasil (o
  // que começa com 9 é agrupado como celular).
  it.each([
    ['(31) 2345-678', '(31) 2345-678'],
    ['(41) 9876-543', '(41) 98765-43'],
    ['11 2345 678', '(11) 2345-678'],
  ])('"%s" é número do Brasil: o DDD não vira outro país', (valor, noCampo) => {
    const w = montar({ ...TELEFONE, valor });
    expect(pais(w).text()).toBe('🇧🇷 +55');
    expect(numero(w).element.value).toBe(noCampo);
  });

  it('o valor que já vem com "+" continua com o país dele', () => {
    const w = montar({ ...TELEFONE, valor: '+351 912 345 67' });
    expect(pais(w).text()).toBe('🇵🇹 +351');
    const brasil = montar({ ...TELEFONE, valor: '+55 11 9738-0014' });
    expect(pais(brasil).text()).toBe('🇧🇷 +55');
    expect(numero(brasil).element.value).toBe('(11) 97380-014');
  });

  it('o número consertado sai completo, do jeito que o servidor aceita', async () => {
    const w = montar({ ...TELEFONE, valor: '(31) 2345-678' });
    await numero(w).setValue('31987654321');
    await salvar(w);
    expect(w.emitted('guardar')).toEqual([[14, '+5531987654321']]);
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });

  it('o número que ainda não vale vai ao servidor como a pessoa escreveu: quem diz o motivo é ele', async () => {
    const w = montar({ ...TELEFONE, valor: '(31) 2345-678' });
    await numero(w).setValue('3198765');
    await salvar(w);
    expect(w.emitted('guardar')).toEqual([[14, '+553198765']]);
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });
});

describe('a tela só trava o campo vazio', () => {
  it.each([
    [{ ...EMAIL, valor: '' }, 'Escreva o e-mail para salvar.'],
    [SEM_NOME, 'Escreva o nome para salvar.'],
    [SEM_CONTATO, 'Escreva um telefone ou um e-mail.'],
    [{ ...TELEFONE, valor: '' }, 'Escreva o telefone para salvar.'],
  ])('o cartão de %o vazio diz "%s"', async (problema, frase) => {
    const w = montar(problema);
    await salvar(w);
    expect(alerta(w).text()).toBe(frase);
    expect(w.emitted('guardar')).toBeUndefined();
    expect(document.activeElement).toBe(w.get('form input').element);
    expect(
      w.get('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('só espaços também é vazio', async () => {
    const w = montar(SEM_NOME);
    await w.get('input').setValue('   ');
    await salvar(w);
    expect(alerta(w).text()).toBe('Escreva o nome para salvar.');
    expect(w.emitted('guardar')).toBeUndefined();
  });

  it.each([
    ['rita@exemplo', 'rita@exemplo'],
    ['a@b..com', 'a@b..com'],
    [' sem arroba ', 'sem arroba'],
  ])(
    'e-mail "%s" vai ao servidor, que é quem confere o formato',
    async (escrito, enviado) => {
      const w = montar(EMAIL);
      await w.get('input').setValue(escrito);
      await salvar(w);
      expect(w.emitted('guardar')).toEqual([[37, enviado]]);
      expect(w.find('[role="alert"]').exists()).toBe(false);
    }
  );

  it('o e-mail como veio da planilha também vai ao servidor', async () => {
    const w = montar(EMAIL);
    await salvar(w);
    expect(w.emitted('guardar')).toEqual([
      [37, 'rita.carvalhedo.exemplo.com.br'],
    ]);
  });

  it('telefone igual ao da planilha: diz para corrigir, como alerta, com o foco no campo, e não envia', async () => {
    const w = montar(TELEFONE);
    await salvar(w);
    expect(alerta(w).text()).toBe('Corrija o telefone para salvar.');
    expect(document.activeElement).toBe(numero(w).element);
    expect(w.emitted('guardar')).toBeUndefined();
    await numero(w).setValue('11973800014');
    expect(w.find('[role="alert"]').exists()).toBe(false);
    await salvar(w);
    expect(w.emitted('guardar')).toEqual([[14, '+5511973800014']]);
  });
});

describe('a frase da recusa não sobrevive à recusa', () => {
  const RECUSA = { linha: 37, motivo: 'invalid_email' };

  it('some quando a recusa some, com a linha ainda aberta', async () => {
    const w = montar(EMAIL, { recusa: RECUSA });
    await flushPromises();
    expect(alerta(w).text()).toBe('Este e-mail não parece certo.');
    await w.setProps({ recusa: null });
    expect(w.find('[role="alert"]').exists()).toBe(false);
    expect(w.get('input').attributes('aria-invalid')).toBeUndefined();
  });

  it('recusou, deixou de fora e voltou atrás: a linha reabre sem a frase vermelha velha', async () => {
    const w = montar(EMAIL, { recusa: RECUSA });
    await flushPromises();
    expect(w.find('[role="alert"]').exists()).toBe(true);
    await w.setProps({
      recusa: null,
      problema: { ...EMAIL, estado: 'deixado' },
    });
    expect(w.find('[role="alert"]').exists()).toBe(false);
    await w.setProps({ problema: EMAIL });
    await flushPromises();
    expect(w.find('form').exists()).toBe(true);
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });

  it('a frase que a própria tela disse não some por causa da recusa de outra linha', async () => {
    const w = montar(SEM_NOME, { recusa: { linha: 62, motivo: 'blank_name' } });
    await flushPromises();
    await w.get('input').setValue(' ');
    await salvar(w);
    expect(alerta(w).text()).toBe('Escreva o nome para salvar.');
    await w.setProps({ recusa: null });
    expect(alerta(w).text()).toBe('Escreva o nome para salvar.');
  });
});

describe('a linha resolvida mostra o valor salvo', () => {
  it('guardada com o valor corrigido: "quem: valor" e o selo Pronto, sem o problema antigo', () => {
    const w = montar({
      ...TELEFONE,
      estado: 'guardado',
      corrigido: '+5511973800014',
    });
    expect(w.text()).toContain('Tadeu Imbirussu: +5511973800014');
    expect(w.text()).toContain('Pronto');
    expect(w.text()).not.toContain('não parece um celular');
    expect(w.findAll('button').map(b => b.text())).toEqual(['Voltar atrás']);
  });

  it('o nome consertado aparece ao lado de por onde a pessoa é achada', () => {
    const w = montar({
      ...SEM_NOME,
      estado: 'guardado',
      corrigido: 'Ana Brandolim',
    });
    expect(w.text()).toContain('11954120062: Ana Brandolim');
    expect(w.text()).not.toContain('falta o nome');
  });

  it('a repetida com que a pessoa ficou não tem valor corrigido: continua com a frase dela', () => {
    const w = montar({ ...REPETIDA, estado: 'guardado', ficar_com: 143 });
    expect(w.text()).toContain('Paulo Hortêncio aparece duas vezes.');
    expect(w.text()).toContain('Pronto');
  });

  it('a deixada de fora continua com a frase do problema', () => {
    const w = montar({ ...TELEFONE, estado: 'deixado' });
    expect(w.text()).toContain(
      'Tadeu Imbirussu: este telefone não parece um celular. Confira o DDD e os dígitos.'
    );
    expect(w.text()).toContain('Deixada de fora');
  });

  it('a chave da frase: a do valor salvo só quando há valor corrigido', () => {
    const RESOLVIDA = 'RELACIONAMENTOS_TRAZER.PRECISAM.RESOLVIDA';
    expect(
      chaveDoTexto({ ...EMAIL, estado: 'guardado', corrigido: 'a@b.com' })
    ).toBe(RESOLVIDA);
    expect(chaveDoTexto({ ...EMAIL, estado: 'guardado' })).not.toBe(RESOLVIDA);
    expect(
      chaveDoTexto({ ...EMAIL, estado: 'guardado', corrigido: '' })
    ).not.toBe(RESOLVIDA);
    expect(chaveDoTexto({ ...EMAIL, corrigido: 'a@b.com' })).not.toBe(
      RESOLVIDA
    );
  });
});

describe('acessibilidade do cartão', () => {
  it('o cartão da linha repetida é lido pelo conteúdo: telefone, e-mail e linha, sem aria-label por cima', () => {
    const w = montar(REPETIDA);
    const opcao = w.get('[data-opcao="88"]');
    expect(opcao.attributes('aria-label')).toBeUndefined();
    expect(opcao.text()).toContain('11944100088');
    expect(opcao.text()).toContain('paulo.hortencio@exemplo.com.br');
    expect(opcao.text()).toContain('Linha 88 da planilha');
    expect(opcao.text()).toContain('Ficar com esta');
    expect(
      w.get('[data-opcao="143"]').attributes('aria-label')
    ).toBeUndefined();
  });

  it('o erro do telefone fica ligado ao campo, e a frase aparece uma vez só', async () => {
    const w = montar(TELEFONE);
    expect(numero(w).attributes('aria-invalid')).toBeUndefined();
    await w.setProps({
      recusa: { linha: 14, motivo: 'invalid_brazilian_mobile_number' },
    });
    await flushPromises();
    const frase =
      'Este telefone não parece um celular do Brasil. Confira o DDD e os dígitos.';
    expect(w.findAll('[role="alert"]')).toHaveLength(1);
    expect(alerta(w).text()).toBe(frase);
    expect(w.text().split(frase)).toHaveLength(2);
    expect(numero(w).attributes('aria-invalid')).toBe('true');
    expect(numero(w).attributes('aria-describedby')).toBe(
      alerta(w).attributes('id')
    );
    expect(marca(w, 'erro-do-campo').element).toBe(alerta(w).element);
  });

  it('o erro do campo de texto fica ligado ao campo', async () => {
    const w = montar(SEM_CONTATO);
    await salvar(w);
    expect(w.get('input').attributes('aria-invalid')).toBe('true');
    expect(w.get('input').attributes('aria-describedby')).toBe(
      alerta(w).attributes('id')
    );
  });
});

describe('alvos de toque de 44 px', () => {
  it.each([
    ['guardada', { ...SEM_NOME, estado: 'guardado', corrigido: 'Ana' }],
    ['deixada de fora', { ...SEM_NOME, estado: 'deixado' }],
  ])('"Voltar atrás" da linha %s', (_, problema) => {
    expect(marca(montar(problema), 'voltar-atras').classes()).toContain(
      'min-h-11'
    );
  });

  it.each([
    ['e-mail', EMAIL],
    ['nome', SEM_NOME],
    ['telefone ou e-mail', SEM_CONTATO],
  ])('o campo de texto de %s', (_, problema) => {
    expect(montar(problema).get('input').classes()).toContain('!h-11');
  });

  it('o campo de telefone: o número e o país', () => {
    const w = montar(TELEFONE);
    expect(numero(w).classes()).toContain('!h-11');
    expect(pais(w).element.closest('.w-\\[7\\.5rem\\]').className).toContain(
      '[&_[role=combobox]]:h-11'
    );
  });
});

describe('as frases de cada problema', () => {
  const frase = problema => montar(problema).get('form p').text();

  it.each([
    [
      TELEFONE,
      'Tadeu Imbirussu: este telefone não parece um celular. Confira o DDD e os dígitos.',
    ],
    [EMAIL, 'Rita Carvalhedo: este e-mail não parece certo.'],
    [
      { ...SEM_NOME, valor: '=SOMA(A1)', motivo: 'formula_detected' },
      '11954120062: o nome começa com um sinal (=, +, - ou @). Escreva sem o sinal.',
    ],
    [
      { ...TELEFONE, motivo: 'formula_phone_number' },
      'Tadeu Imbirussu: o telefone começa com um sinal (=, +, - ou @). Escreva sem o sinal.',
    ],
    [
      { ...EMAIL, motivo: 'formula_detected' },
      'Rita Carvalhedo: o e-mail começa com um sinal (=, +, - ou @). Escreva sem o sinal.',
    ],
    [
      COM_FORMULA,
      'Nesta linha, “Empresa” começa com um sinal (=, +, - ou @). Corrija na planilha e envie de novo, ou deixe esta linha de fora.',
    ],
    [
      { ...COM_FORMULA, campo: 'outro' },
      'Nesta linha, uma informação começa com um sinal (=, +, - ou @). Corrija na planilha e envie de novo, ou deixe esta linha de fora.',
    ],
  ])('o cartão de %o diz "%s"', (problema, esperada) => {
    expect(frase(problema)).toBe(esperada);
  });

  it('a linha de fórmula deixada de fora', () => {
    expect(montar({ ...COM_FORMULA, estado: 'deixado' }).text()).toContain(
      'Caio Camargo: uma informação começa com um sinal (=, +, - ou @)'
    );
  });

  it.each(['formula_phone_number', 'formula_detected'])(
    'a recusa `%s` diz para escrever sem o sinal',
    async motivo => {
      const w = montar(SEM_NOME, { recusa: { linha: 62, motivo } });
      await flushPromises();
      expect(alerta(w).text()).toBe(
        'Este texto começa com um sinal (=, +, - ou @). Escreva sem o sinal.'
      );
    }
  );
});

describe('um componente por tipo de cartão', () => {
  it.each([
    ['telefone', TELEFONE, {}, CartaoDoTelefone],
    ['e-mail', EMAIL, {}, CartaoDoTexto],
    ['nome', SEM_NOME, {}, CartaoDoTexto],
    ['sem telefone nem e-mail', SEM_CONTATO, {}, CartaoDoTexto],
    ['repetida', REPETIDA, {}, CartaoDaRepetida],
    ['fórmula', COM_FORMULA, {}, CartaoSemConserto],
    [
      'repetida sem a outra',
      { ...REPETIDA, outraLinha: null },
      {},
      CartaoSemConserto,
    ],
    ['planilha apagada', TELEFONE, { semConserto: true }, CartaoSemConserto],
    [
      'guardada',
      { ...EMAIL, estado: 'guardado', corrigido: 'a@b.com' },
      {},
      LinhaRecolhida,
    ],
    ['deixada', { ...EMAIL, estado: 'deixado' }, {}, LinhaRecolhida],
  ])('linha %s', (_, problema, extra, componente) => {
    const w = montar(problema, extra);
    const todos = [
      CartaoDoTelefone,
      CartaoDoTexto,
      CartaoDaRepetida,
      CartaoSemConserto,
      LinhaRecolhida,
    ];
    expect(todos.filter(um => w.findComponent(um).exists())).toEqual([
      componente,
    ]);
    expect(w.element.tagName).toBe('LI');
    expect(w.attributes('data-linha')).toBe(String(problema.linha));
  });

  it('só o cartão do telefone usa o campo de telefone', () => {
    expect(montar(TELEFONE).findComponent(CampoDeTelefone).exists()).toBe(true);
    expect(montar(SEM_CONTATO).findComponent(CampoDeTelefone).exists()).toBe(
      false
    );
  });

  it('a escolha do cartão, sem montar nada', () => {
    expect(cartaoDoProblema(TELEFONE, false)).toBe(CARTOES.TELEFONE);
    expect(cartaoDoProblema(EMAIL, false)).toBe(CARTOES.TEXTO);
    expect(cartaoDoProblema(SEM_CONTATO, false)).toBe(CARTOES.TEXTO);
    expect(cartaoDoProblema(REPETIDA, false)).toBe(CARTOES.REPETIDA);
    expect(cartaoDoProblema(REPETIDA, true)).toBe(CARTOES.SEM_CONSERTO);
    expect(cartaoDoProblema(COM_FORMULA, false)).toBe(CARTOES.SEM_CONSERTO);
    expect(cartaoDoProblema({ ...TELEFONE, tipo: 'tipo_novo' }, false)).toBe(
      CARTOES.SEM_CONSERTO
    );
    expect(cartaoDoProblema({ ...TELEFONE, tipo: 'constructor' }, false)).toBe(
      CARTOES.SEM_CONSERTO
    );
  });

  it('o cartão sem conserto diz a recusa que a linha tinha e leva o foco a "Deixar de fora"', async () => {
    const w = montar(TELEFONE, {
      semConserto: true,
      recusa: { linha: 14, motivo: 'planilha_apagada' },
    });
    await flushPromises();
    expect(alerta(w).text()).toBe(
      'A planilha já foi apagada daqui. Para corrigir uma linha, envie a planilha de novo.'
    );
    expect(document.activeElement).toBe(marca(w, 'deixar-de-fora').element);
    expect(w.find('button[type="submit"]').exists()).toBe(false);
  });

  it('a recusa na linha repetida leva o foco à primeira escolha', async () => {
    const w = montar(REPETIDA, {
      recusa: { linha: 143, motivo: 'coisa_nova' },
    });
    await flushPromises();
    expect(alerta(w).text()).toBe(
      'Não consegui salvar esta linha. Tente de novo.'
    );
    expect(document.activeElement).toBe(w.get('[data-opcao="88"]').element);
  });
});

describe('a linha recolhida diz a recusa do "Voltar atrás" ali mesmo', () => {
  const DEIXADA = { ...EMAIL, estado: 'deixado' };
  const NAO_SALVOU = 'Não consegui salvar esta linha. Tente de novo.';

  it('sem recusa não há alerta', () => {
    expect(montar(DEIXADA).find('[role="alert"]').exists()).toBe(false);
  });

  it.each([
    ['deixada de fora', DEIXADA],
    ['guardada', { ...EMAIL, estado: 'guardado', corrigido: 'a@b.com' }],
  ])(
    'linha %s: a frase fixa como alerta e o foco de volta no "Voltar atrás"',
    async (_, problema) => {
      const w = montar(problema);
      await w.setProps({ recusa: { linha: 37, motivo: 'nao_salvou' } });
      await flushPromises();
      expect(w.findAll('[role="alert"]')).toHaveLength(1);
      expect(alerta(w).text()).toBe(NAO_SALVOU);
      expect(document.activeElement).toBe(marca(w, 'voltar-atras').element);
      expect(marca(w, 'voltar-atras').attributes('aria-describedby')).toBe(
        alerta(w).attributes('id')
      );
    }
  );

  it('a frase não é a do campo: voltar atrás não confere valor nenhum', async () => {
    const w = montar(
      { ...TELEFONE, estado: 'deixado' },
      {
        recusa: { linha: 14, motivo: 'nao_salvou' },
      }
    );
    await flushPromises();
    expect(alerta(w).text()).toBe(NAO_SALVOU);
  });

  it('o foco espera a escrita acabar (o botão desligado não recebe foco)', async () => {
    const w = montar(DEIXADA, { ocupado: true });
    await w.setProps({ recusa: { linha: 37, motivo: 'nao_salvou' } });
    await flushPromises();
    expect(alerta(w).text()).toBe(NAO_SALVOU);
    await w.setProps({ ocupado: false });
    await flushPromises();
    expect(document.activeElement).toBe(marca(w, 'voltar-atras').element);
  });

  it('a frase some quando a recusa some', async () => {
    const w = montar(DEIXADA, { recusa: { linha: 37, motivo: 'nao_salvou' } });
    await flushPromises();
    expect(w.find('[role="alert"]').exists()).toBe(true);
    await w.setProps({ recusa: null });
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });
});
