import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';

// #2896, Fatia 2 (item 18 da revisão do dono) — a demonstração faz o papel do
// servidor nas linhas que precisam da pessoa: confere o valor como ele
// (app/services/contact_imports/trazer/conserto.rb), devolve o problema que
// sobrou, deixa de fora as outras repetidas do grupo e diz quantas entram
// (app/services/relacionamentos/trazer/mudar_linha.rb e
// app/services/contact_imports/trazer/quem_entra.rb). A forma do que ela
// devolve está em paridadeDaDemonstracao.spec.js.
const LINHA = {
  TELEFONE: 14,
  EMAIL: 37,
  SEM_NOME: 62,
  DOIS_PROBLEMAS: 96,
  FORMULA: 118,
  REPETIDA: 143,
  OUTRA_REPETIDA: 156,
  APROVADA_DA_REPETIDA: 88,
  SEM_CONTATO: 171,
};
const ENTRAM = 195;

const lida = async () => {
  const fonte = trazerFonte({
    demo: 'cheio',
    carregarDemo: () => import('../../demo/trazer.js'),
    atraso: 0,
    atrasoDaLeitura: 0,
  });
  const leitura = await fonte.ler(null);
  return { fonte, id: leitura.id, leitura };
};
const daLinha = (leitura, linha) =>
  leitura.problemas.find(problema => problema.linha === linha);

beforeEach(() => esquecerMemoriaDaDemo());

describe('a planilha de exemplo', () => {
  it('tem 203 pessoas: 180 novas, 15 que já estavam e 8 linhas que precisam da pessoa', async () => {
    const { leitura } = await lida();
    expect(leitura.resumo).toEqual({
      total: 203,
      novas: 180,
      completadas: 15,
      comProblema: 8,
      juntadas: 3,
      semTelefone: 0,
      entram: ENTRAM,
      // Ninguém é cliente até a pessoa dizer quem é (E3).
      clientes: 0,
    });
    expect(leitura.problemas.map(p => [p.linha, p.tipo, p.motivo])).toEqual([
      [LINHA.TELEFONE, 'telefone', 'invalid_brazilian_mobile_number'],
      [LINHA.EMAIL, 'email', 'invalid_email'],
      [LINHA.SEM_NOME, 'nome', 'blank_name'],
      [LINHA.DOIS_PROBLEMAS, 'telefone', 'invalid_brazilian_mobile_number'],
      [LINHA.FORMULA, 'formula', 'formula_detected'],
      // A linha repetida não tem motivo em código.
      [LINHA.REPETIDA, 'duplicada', undefined],
      [LINHA.OUTRA_REPETIDA, 'duplicada', undefined],
      [LINHA.SEM_CONTATO, 'sem_contato', 'missing_contact'],
    ]);
  });

  it('a linha com fórmula diz o campo e não tem valor', async () => {
    const { leitura } = await lida();
    const formula = daLinha(leitura, LINHA.FORMULA);
    expect(formula.campo).toBe('empresa');
    expect(formula).not.toHaveProperty('valor');
  });

  it('as duas repetidas são a mesma pessoa de uma linha aprovada', async () => {
    const { leitura } = await lida();
    [LINHA.REPETIDA, LINHA.OUTRA_REPETIDA].forEach(linha => {
      const repetida = daLinha(leitura, linha);
      expect(repetida.outraLinha).toBe(LINHA.APROVADA_DA_REPETIDA);
      expect(repetida.duplicadas.map(item => item.linha)).toEqual([
        LINHA.APROVADA_DA_REPETIDA,
        linha,
      ]);
      // O que repete é o e-mail: é ele o valor da linha.
      expect(repetida.duplicadas.map(item => item.email)).toEqual([
        repetida.valor,
        repetida.valor,
      ]);
    });
  });
});

describe('recusa o valor que não vale, com o motivo do servidor', () => {
  const LONGO = 'a'.repeat(256);

  it.each([
    [LINHA.TELEFONE, '', 'blank_phone_number'],
    [LINHA.TELEFONE, '   ', 'blank_phone_number'],
    // Fixo, dígito faltando, DDD que não existe: não é celular do Brasil.
    [LINHA.TELEFONE, '(11) 2345-6789', 'invalid_brazilian_mobile_number'],
    [LINHA.TELEFONE, '(11) 9738-0014', 'invalid_brazilian_mobile_number'],
    [LINHA.TELEFONE, '(11) 37380-0014', 'invalid_brazilian_mobile_number'],
    [LINHA.TELEFONE, '(01) 97380-0014', 'invalid_brazilian_mobile_number'],
    [LINHA.TELEFONE, '+1 917 555 0100', 'invalid_brazilian_mobile_number'],
    [LINHA.TELEFONE, '=1+1', 'formula_phone_number'],
    [LINHA.TELEFONE, '-11973800014', 'formula_phone_number'],
    [LINHA.TELEFONE, '@11973800014', 'formula_phone_number'],
    [LINHA.TELEFONE, '+ 11973800014', 'formula_phone_number'],
    [LINHA.EMAIL, '', 'blank_email'],
    [LINHA.EMAIL, ' ', 'blank_email'],
    [LINHA.EMAIL, 'rita.carvalhedo.exemplo.com.br', 'invalid_email'],
    [LINHA.EMAIL, 'rita@', 'invalid_email'],
    [LINHA.EMAIL, '@exemplo.com.br', 'invalid_email'],
    [LINHA.EMAIL, 'rita carvalhedo@exemplo.com.br', 'invalid_email'],
    [LINHA.EMAIL, '=rita@exemplo.com.br', 'formula_detected'],
    [LINHA.EMAIL, '-rita@exemplo.com.br', 'formula_detected'],
    [LINHA.EMAIL, '+rita@exemplo.com.br', 'formula_detected'],
    [LINHA.SEM_NOME, '', 'blank_name'],
    [LINHA.SEM_NOME, '=SOMA(A1)', 'formula_detected'],
    [LINHA.SEM_NOME, '+Ana', 'formula_detected'],
    [LINHA.SEM_NOME, '-Ana', 'formula_detected'],
    [LINHA.SEM_NOME, '@ana', 'formula_detected'],
    [LINHA.SEM_CONTATO, '', 'missing_contact'],
    [LINHA.SEM_CONTATO, '  ', 'missing_contact'],
    [LINHA.SEM_CONTATO, '123', 'invalid_brazilian_mobile_number'],
    [LINHA.SEM_CONTATO, 'helena@', 'invalid_email'],
    // A fórmula numa célula que a tela não conserta: nenhum valor serve.
    [LINHA.FORMULA, 'Casa Aurora', 'formula_detected'],
    [LINHA.SEM_NOME, LONGO, 'muito_longo'],
    [LINHA.FORMULA, LONGO, 'muito_longo'],
  ])('linha %i, "%s": %s', async (linha, valor, motivo) => {
    const { fonte, id, leitura } = await lida();
    await expect(fonte.consertar(id, linha, valor)).rejects.toMatchObject({
      name: 'VALOR_INVALIDO',
      motivo,
    });
    // Nada ficou guardado.
    expect(await fonte.retomar(id)).toEqual(leitura);
  });

  it('a linha que a leitura não tem dá o mesmo erro da fonte real', async () => {
    const { fonte, id } = await lida();
    await expect(fonte.consertar(id, 999, 'x')).rejects.toMatchObject({
      name: 'LINHA_NAO_ENCONTRADA',
    });
    await expect(fonte.deixarDeFora(id, 999)).rejects.toMatchObject({
      name: 'LINHA_NAO_ENCONTRADA',
    });
    await expect(fonte.reabrir(id, 999)).rejects.toMatchObject({
      name: 'LINHA_NAO_ENCONTRADA',
    });
  });
});

describe('guarda o valor que vale, como vai ser gravado', () => {
  it.each([
    [LINHA.TELEFONE, '(11) 97380-0014', '+5511973800014'],
    // No telefone o "+" vale.
    [LINHA.TELEFONE, '+55 11 97380-0014', '+5511973800014'],
    [LINHA.TELEFONE, ' 11973800014 ', '+5511973800014'],
    [
      LINHA.EMAIL,
      ' Rita.Carvalhedo@Exemplo.com.br ',
      'rita.carvalhedo@exemplo.com.br',
    ],
    [LINHA.SEM_NOME, '  Ana   Imbirussu ', 'Ana Imbirussu'],
    [LINHA.SEM_CONTATO, '11 98123-0171', '+5511981230171'],
    [LINHA.SEM_CONTATO, 'Helena@Exemplo.com.br', 'helena@exemplo.com.br'],
  ])('linha %i, "%s" fica "%s"', async (linha, valor, corrigido) => {
    const { fonte, id, leitura } = await lida();
    const antes = daLinha(leitura, linha);
    const depois = await fonte.consertar(id, linha, valor);
    const { motivo, ...semMotivo } = antes;
    expect(daLinha(depois, linha)).toEqual({
      ...semMotivo,
      estado: 'guardado',
      corrigido,
    });
    expect(depois.resumo.entram).toBe(ENTRAM + 1);
    // No Conferir a linha consertada não vira "nova": o servidor não sabe ainda
    // se a pessoa já existe na conta.
    expect(depois.resumo.novas).toBe(leitura.resumo.novas);
    expect(depois.resumo.completadas).toBe(leitura.resumo.completadas);
  });

  it('na linha sem telefone nem e-mail o contato novo toma o lugar do anterior', async () => {
    const { fonte, id } = await lida();
    await fonte.consertar(id, LINHA.SEM_CONTATO, '11 98123-0171');
    const depois = await fonte.consertar(
      id,
      LINHA.SEM_CONTATO,
      'helena@exemplo.com.br'
    );
    expect(daLinha(depois, LINHA.SEM_CONTATO)).toMatchObject({
      tipo: 'sem_contato',
      estado: 'guardado',
      corrigido: 'helena@exemplo.com.br',
    });
    expect(depois.resumo.entram).toBe(ENTRAM + 1);
  });
});

describe('o valor valeu e sobrou outro problema na linha', () => {
  it('conserta o telefone e a linha volta aberta, agora sem nome', async () => {
    const { fonte, id } = await lida();
    const depois = await fonte.consertar(
      id,
      LINHA.DOIS_PROBLEMAS,
      '(11) 96540-0096'
    );
    expect(daLinha(depois, LINHA.DOIS_PROBLEMAS)).toEqual({
      linha: LINHA.DOIS_PROBLEMAS,
      tipo: 'nome',
      nome: '',
      valor: '',
      // O telefone como a pessoa escreveu: é por ele que ela acha a linha.
      contato: '(11) 96540-0096',
      estado: 'aberto',
      motivo: 'blank_name',
    });
    // A linha ainda não entra.
    expect(depois.resumo.entram).toBe(ENTRAM);
  });

  it('o nome que falta é recusado e depois guardado: aí a linha entra', async () => {
    const { fonte, id } = await lida();
    await fonte.consertar(id, LINHA.DOIS_PROBLEMAS, '(11) 96540-0096');
    await expect(
      fonte.consertar(id, LINHA.DOIS_PROBLEMAS, '')
    ).rejects.toMatchObject({ name: 'VALOR_INVALIDO', motivo: 'blank_name' });
    const depois = await fonte.consertar(
      id,
      LINHA.DOIS_PROBLEMAS,
      'Bruno Brandolim'
    );
    expect(daLinha(depois, LINHA.DOIS_PROBLEMAS)).toEqual({
      linha: LINHA.DOIS_PROBLEMAS,
      tipo: 'nome',
      nome: '',
      valor: '',
      contato: '(11) 96540-0096',
      estado: 'guardado',
      corrigido: 'Bruno Brandolim',
    });
    expect(depois.resumo.entram).toBe(ENTRAM + 1);
  });

  it.each(['deixarDeFora', 'reabrir'])(
    '%s esquece o telefone consertado: a linha volta a ser a do telefone',
    async escrita => {
      const { fonte, id, leitura } = await lida();
      const original = daLinha(leitura, LINHA.DOIS_PROBLEMAS);
      await fonte.consertar(id, LINHA.DOIS_PROBLEMAS, '(11) 96540-0096');
      const depois = await fonte[escrita](id, LINHA.DOIS_PROBLEMAS);
      const { motivo, ...semMotivo } = original;
      expect(daLinha(depois, LINHA.DOIS_PROBLEMAS)).toEqual(
        escrita === 'reabrir' ? original : { ...semMotivo, estado: 'deixado' }
      );
      expect(depois.resumo.entram).toBe(ENTRAM);
    }
  );
});

describe('deixar de fora e voltar atrás esquecem o conserto', () => {
  it('a linha guardada que fica de fora perde o valor e não entra', async () => {
    const { fonte, id, leitura } = await lida();
    await fonte.consertar(id, LINHA.TELEFONE, '(11) 97380-0014');
    const depois = await fonte.deixarDeFora(id, LINHA.TELEFONE);
    const { motivo, ...semMotivo } = daLinha(leitura, LINHA.TELEFONE);
    expect(daLinha(depois, LINHA.TELEFONE)).toEqual({
      ...semMotivo,
      estado: 'deixado',
    });
    expect(depois.resumo.entram).toBe(ENTRAM);
  });

  it('voltar atrás devolve a linha aberta, com o motivo e sem o valor', async () => {
    const { fonte, id, leitura } = await lida();
    await fonte.consertar(id, LINHA.TELEFONE, '(11) 97380-0014');
    const aberta = await fonte.reabrir(id, LINHA.TELEFONE);
    expect(daLinha(aberta, LINHA.TELEFONE)).toEqual(
      daLinha(leitura, LINHA.TELEFONE)
    );
    expect(aberta.resumo.entram).toBe(ENTRAM);
    await fonte.deixarDeFora(id, LINHA.TELEFONE);
    const deNovo = await fonte.reabrir(id, LINHA.TELEFONE);
    expect(daLinha(deNovo, LINHA.TELEFONE)).toEqual(
      daLinha(leitura, LINHA.TELEFONE)
    );
  });

  it('a linha com fórmula só pode ficar de fora, e volta como era', async () => {
    const { fonte, id, leitura } = await lida();
    const fora = await fonte.deixarDeFora(id, LINHA.FORMULA);
    expect(daLinha(fora, LINHA.FORMULA)).toEqual({
      linha: LINHA.FORMULA,
      tipo: 'formula',
      campo: 'empresa',
      nome: daLinha(leitura, LINHA.FORMULA).nome,
      estado: 'deixado',
    });
    const aberta = await fonte.reabrir(id, LINHA.FORMULA);
    expect(daLinha(aberta, LINHA.FORMULA)).toEqual(
      daLinha(leitura, LINHA.FORMULA)
    );
  });
});

describe('a linha repetida: de um grupo da mesma pessoa entra uma só', () => {
  it('ficar com esta guarda a linha, deixa a outra repetida de fora e não soma ninguém', async () => {
    const { fonte, id } = await lida();
    const depois = await fonte.consertar(id, LINHA.REPETIDA, LINHA.REPETIDA);
    expect(daLinha(depois, LINHA.REPETIDA)).toMatchObject({
      estado: 'guardado',
      ficar_com: LINHA.REPETIDA,
    });
    expect(daLinha(depois, LINHA.REPETIDA)).not.toHaveProperty('corrigido');
    expect(daLinha(depois, LINHA.OUTRA_REPETIDA).estado).toBe('deixado');
    // A linha que fica toma o lugar da aprovada: é uma troca.
    expect(depois.resumo.entram).toBe(ENTRAM);
  });

  it('escolher a outra repetida desfaz a escolha anterior', async () => {
    const { fonte, id } = await lida();
    await fonte.consertar(id, LINHA.REPETIDA, LINHA.REPETIDA);
    const depois = await fonte.consertar(
      id,
      LINHA.OUTRA_REPETIDA,
      LINHA.OUTRA_REPETIDA
    );
    expect(daLinha(depois, LINHA.OUTRA_REPETIDA)).toMatchObject({
      estado: 'guardado',
      ficar_com: LINHA.OUTRA_REPETIDA,
    });
    expect(daLinha(depois, LINHA.REPETIDA).estado).toBe('deixado');
    expect(daLinha(depois, LINHA.REPETIDA)).not.toHaveProperty('ficar_com');
    expect(depois.resumo.entram).toBe(ENTRAM);
  });

  it('ficar com a linha aprovada deixa só esta de fora', async () => {
    const { fonte, id } = await lida();
    const depois = await fonte.consertar(
      id,
      LINHA.REPETIDA,
      LINHA.APROVADA_DA_REPETIDA
    );
    expect(daLinha(depois, LINHA.REPETIDA).estado).toBe('deixado');
    expect(daLinha(depois, LINHA.REPETIDA)).not.toHaveProperty('ficar_com');
    expect(daLinha(depois, LINHA.OUTRA_REPETIDA).estado).toBe('aberto');
    expect(depois.resumo.entram).toBe(ENTRAM);
  });

  it('voltar atrás na que ficou reabre só ela', async () => {
    const { fonte, id } = await lida();
    await fonte.consertar(id, LINHA.REPETIDA, LINHA.REPETIDA);
    const depois = await fonte.reabrir(id, LINHA.REPETIDA);
    expect(daLinha(depois, LINHA.REPETIDA).estado).toBe('aberto');
    expect(daLinha(depois, LINHA.REPETIDA)).not.toHaveProperty('ficar_com');
    expect(daLinha(depois, LINHA.OUTRA_REPETIDA).estado).toBe('deixado');
  });

  it('a linha que não é nenhuma das duas é tela desatualizada, como no servidor', async () => {
    const { fonte, id } = await lida();
    await expect(
      fonte.consertar(id, LINHA.REPETIDA, LINHA.TELEFONE)
    ).rejects.toMatchObject({ name: 'TELA_DESATUALIZADA' });
  });
});

describe('a lista trazida conta o que de fato entrou', () => {
  it('quem foi consertado entra como pessoa nova; a soma fecha com o que o Conferir disse que entrava', async () => {
    const { fonte, id } = await lida();
    await fonte.consertar(id, LINHA.TELEFONE, '(11) 97380-0014');
    await fonte.consertar(id, LINHA.EMAIL, 'rita@exemplo.com.br');
    await fonte.consertar(id, LINHA.REPETIDA, LINHA.REPETIDA);
    const conferida = await fonte.deixarDeFora(id, LINHA.SEM_NOME);
    expect(conferida.resumo).toMatchObject({
      novas: 180,
      completadas: 15,
      entram: 197,
    });
    const { trazidaId } = await fonte.trazer(id);
    const andamento = await fonte.andamento(trazidaId);
    expect(andamento).toMatchObject({
      total: 197,
      novas: 182,
      completadas: 15,
    });
    expect(andamento.novas + andamento.completadas).toBe(andamento.total);
    expect(andamento.total).toBe(conferida.resumo.entram);
    const [lista] = await fonte.historico();
    expect(lista).toMatchObject({ id: trazidaId, total: 197 });
  });
});
