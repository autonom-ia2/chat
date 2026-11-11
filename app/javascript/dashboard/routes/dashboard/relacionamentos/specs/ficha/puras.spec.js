import { readFileSync } from 'node:fs';
import {
  formatarCnpj,
  formatarCpf,
  formatarDiaMes,
  formatarMes,
  formatarReais,
  quandoRelativo,
} from '../../ficha/formatos';
import { cpfValido, emailValido } from '../../ficha/validacao';
import { errosDoFormulario } from '../../ficha/errosDoFormulario';
import {
  ORIGENS_LIBERAVEIS,
  chaveDaOrigem,
  podeLiberar,
} from '../../ficha/origemDaRecusa';
import {
  dadosParaSalvar,
  formularioDaPessoa,
  linhasDaEmpresa,
  linhasDaPessoa,
  nomeDaInformacao,
  redesPreenchidas,
} from '../../ficha/informacoes';

// As funções puras da ficha (#2894): formatos, conferência, origem da recusa e
// informações.
const MARCO_2024 = Date.UTC(2024, 2, 15, 12) / 1000;
const SETEMBRO = Date.UTC(2026, 8, 12, 12) / 1000;
const AGORA = Date.UTC(2026, 10, 11, 12);
const DIA = 86_400;
// CPF válido de exemplo conhecido (número de teste público, de ninguém).
const CPF_VALIDO = '52998224725';

describe('formatos', () => {
  it('põe pontuação no CPF e no CNPJ, e deixa o resto como veio', () => {
    expect(formatarCpf('52998224725')).toBe('529.982.247-25');
    expect(formatarCpf('123')).toBe('123');
    expect(formatarCnpj('11222333000181')).toBe('11.222.333/0001-81');
    expect(formatarCnpj(null)).toBe('');
  });

  it('abrevia o mês no idioma do painel', () => {
    expect(formatarMes(MARCO_2024, 'pt-BR')).toBe('mar. de 2024');
    expect(formatarMes(MARCO_2024, 'en')).toBe('Mar 2024');
  });

  it('mostra dia e mês na ordem do idioma', () => {
    expect(formatarDiaMes(SETEMBRO, 'pt-BR')).toBe('12/09');
    expect(formatarDiaMes(SETEMBRO, 'en')).toBe('09/12');
  });

  it('põe o ano quando a data não é do ano corrente', () => {
    const marco2025 = Date.UTC(2025, 10, 27, 12) / 1000;
    expect(formatarDiaMes(marco2025, 'pt-BR', AGORA)).toBe('27/11/2025');
    expect(formatarDiaMes(marco2025, 'en', AGORA)).toBe('11/27/2025');
    expect(formatarDiaMes(SETEMBRO, 'pt-BR', AGORA)).toBe('12/09');
  });

  it('escreve o valor em reais sem centavos', () => {
    expect(formatarReais(1250, 'pt-BR').replaceAll('\u00a0', ' ')).toBe(
      'R$ 1.250'
    );
  });

  it.each([
    [0, 'agora'],
    [3 * DIA, 'há 3 dias'],
    [DIA, 'ontem'],
    [45 * DIA, 'mês passado'],
  ])('diz "há quanto tempo" (%s s) em palavras', (atras, esperado) => {
    const quando = AGORA / 1000 - atras;
    expect(quandoRelativo(quando, AGORA, 'pt-BR')).toBe(esperado);
  });

  it('nunca fala do futuro', () => {
    expect(quandoRelativo(AGORA / 1000 + 5 * DIA, AGORA, 'pt-BR')).toBe(
      'agora'
    );
  });
});

describe('emailValido', () => {
  it.each(['ana@exemplo.com.br', 'a.b@x.co'])('aceita %s', email => {
    expect(emailValido(email)).toBe(true);
  });

  it.each([
    '',
    'ana',
    'ana@',
    '@exemplo.com',
    'ana@exemplo',
    'ana@@exemplo.com',
    'ana @exemplo.com',
    'ana@exemplo..com',
    'ana@.com',
  ])('recusa "%s"', email => {
    expect(emailValido(email)).toBe(false);
  });
});

describe('cpfValido', () => {
  it('aceita CPF com ou sem pontuação', () => {
    expect(cpfValido(CPF_VALIDO)).toBe(true);
    expect(cpfValido('529.982.247-25')).toBe(true);
  });

  it.each(['52998224726', '11111111111', '123', '', '5299822472500'])(
    'recusa "%s"',
    cpf => {
      expect(cpfValido(cpf)).toBe(false);
    }
  );
});

describe('errosDoFormulario', () => {
  const inicial = { nome: 'Ana', email: 'velho', cpf: '00000000000' };

  it('só cobra o que a pessoa mexeu: dado antigo ruim não trava', () => {
    expect(
      errosDoFormulario(inicial, { ...inicial, nome: 'Ana Maria' })
    ).toEqual({});
  });

  it('pede o nome', () => {
    expect(errosDoFormulario(inicial, { ...inicial, nome: '  ' })).toEqual({
      nome: 'NOME',
    });
  });

  it('cobra e-mail e CPF quando mudaram e estão errados', () => {
    const atual = { ...inicial, email: 'sem-arroba', cpf: '123' };
    expect(errosDoFormulario(inicial, atual)).toEqual({
      email: 'EMAIL',
      cpf: 'CPF',
    });
  });

  it('deixa limpar e-mail e CPF', () => {
    expect(
      errosDoFormulario(inicial, { ...inicial, email: '', cpf: '' })
    ).toEqual({});
  });
});

describe('origem da recusa', () => {
  it('libera só as origens que a casa já deixa desfazer', () => {
    expect(ORIGENS_LIBERAVEIS).toEqual(['manual', 'campaign_reply']);
    expect(podeLiberar('manual')).toBe(true);
    expect(podeLiberar('campaign_reply')).toBe(true);
    expect(podeLiberar('email_unsubscribe')).toBe(false);
    expect(podeLiberar('follow_up_reply')).toBe(false);
    expect(podeLiberar(null)).toBe(false);
  });

  it('traduz origem desconhecida como "outra"', () => {
    expect(chaveDaOrigem('manual')).toBe('manual');
    expect(chaveDaOrigem('algo_novo')).toBe('outra');
    expect(chaveDaOrigem(null)).toBe('outra');
  });
});

describe('informações da pessoa', () => {
  const pessoa = {
    name: 'Ana Teste',
    email: 'ana@exemplo.com.br',
    phone_number: '+5511900001001',
    additional_attributes: {
      city: 'Santos',
      company_name: '',
      social_profiles: { instagram: '@ana', github: '', outra: 'x' },
    },
    custom_attributes: { cpf: CPF_VALIDO, melhor_horario: 'Tarde' },
  };

  it('lista o fixo e o que a conta criou; o que falta fica vazio', () => {
    const linhas = linhasDaPessoa(pessoa);
    const por = chave => linhas.find(l => l.chave === chave);
    expect(por('cpf')).toMatchObject({ valor: '529.982.247-25', copiar: true });
    expect(por('empresa').valor).toBe('');
    expect(por('conta:melhor_horario')).toMatchObject({
      rotulo: 'Melhor horário',
      valor: 'Tarde',
    });
    // Telefone e e-mail ficam só no cabeçalho.
    expect(linhas.map(l => l.chave).slice(0, 3)).toEqual([
      'cpf',
      'cidade',
      'empresa',
    ]);
    expect(por('telefone')).toBeUndefined();
    expect(por('email')).toBeUndefined();
  });

  it('o nome das informações da conta leva acento', () => {
    expect(nomeDaInformacao('melhor_horario')).toBe('Melhor horário');
  });

  it('só mostra redes conhecidas e preenchidas', () => {
    expect(redesPreenchidas(pessoa)).toEqual([
      { rede: 'instagram', usuario: '@ana' },
    ]);
  });

  it('dá nome à informação da conta', () => {
    expect(nomeDaInformacao('como_prefere_ser_chamado')).toBe(
      'Como prefere ser chamado'
    );
  });

  it('ida e volta do formulário, sem mutar a pessoa', () => {
    const antes = JSON.stringify(pessoa);
    const form = formularioDaPessoa(pessoa);
    expect(form.cpf).toBe('529.982.247-25');
    expect(form.redes.instagram).toBe('@ana');
    expect(form.extras).toEqual({ melhor_horario: 'Tarde' });
    const dados = dadosParaSalvar({
      ...form,
      cidade: ' Bauru ',
      redes: { ...form.redes, instagram: '' },
    });
    expect(dados.additional_attributes.city).toBe('Bauru');
    expect(dados.additional_attributes.social_profiles).toEqual({});
    expect(dados.custom_attributes).toEqual({
      cpf: CPF_VALIDO,
      melhor_horario: 'Tarde',
    });
    expect(JSON.stringify(pessoa)).toBe(antes);
  });

  it('manda telefone e e-mail vazios como nulos', () => {
    const dados = dadosParaSalvar({
      ...formularioDaPessoa(pessoa),
      telefone: '',
      email: ' ',
    });
    expect(dados.phone_number).toBeNull();
    expect(dados.email).toBeNull();
  });
});

describe('dadosParaSalvar: campos esvaziados', () => {
  const pessoaCheia = {
    name: 'Ana',
    phone_number: '+5511900001007',
    email: 'ana@exemplo.com.br',
    additional_attributes: {
      city: 'Santos',
      social_profiles: { instagram: '@ana', github: '' },
    },
    custom_attributes: { cpf: CPF_VALIDO, melhor_horario: 'Tarde' },
  };

  it('manda vazio explícito para o que existia e a pessoa apagou', () => {
    const inicial = formularioDaPessoa(pessoaCheia);
    const dados = dadosParaSalvar(
      {
        ...inicial,
        cpf: '',
        redes: { ...inicial.redes, instagram: '' },
        extras: { melhor_horario: '' },
      },
      inicial
    );
    expect(dados.custom_attributes).toEqual({ cpf: '', melhor_horario: '' });
    expect(dados.additional_attributes.social_profiles).toEqual({
      instagram: '',
    });
  });

  it('continua omitindo o que nunca existiu, e não muda a entrada', () => {
    const inicial = formularioDaPessoa(pessoaCheia);
    const formulario = { ...inicial, cpf: '' };
    const antes = JSON.stringify([inicial, formulario]);
    const dados = dadosParaSalvar(formulario, inicial);
    expect(dados.additional_attributes.social_profiles).toEqual({
      instagram: '@ana',
    });
    expect(
      Object.keys(dados.additional_attributes.social_profiles)
    ).not.toContain('github');
    expect(JSON.stringify([inicial, formulario])).toBe(antes);
  });
});

describe('texto da faixa de quem não quer mensagens', () => {
  const catalogo = lingua =>
    JSON.parse(
      readFileSync(
        `app/javascript/dashboard/i18n/locale/${lingua}/relacionamentosFicha.json`,
        'utf8'
      )
    ).RELACIONAMENTOS_FICHA.FAIXA;

  it.each(['en', 'pt_BR'])(
    'em %s não tem "Veio de" nem "Came from"',
    lingua => {
      const faixa = catalogo(lingua);
      expect(faixa.TEXTO).not.toContain('Veio de');
      expect(faixa.TEXTO).not.toContain('Came from');
      expect(faixa.TEXTO).toContain('{origem}');
      Object.values(faixa.ORIGEM).forEach(frase => {
        expect(frase.endsWith('.')).toBe(true);
        expect(frase.charAt(0)).toBe(frase.charAt(0).toUpperCase());
      });
    }
  );
});

describe('origens liberáveis', () => {
  it('batem com UNDOABLE_SOURCES do servidor', () => {
    const codigo = readFileSync(
      'app/controllers/api/v1/accounts/contacts/opt_outs_controller.rb',
      'utf8'
    );
    const linha = codigo
      .split('\n')
      .find(l => l.includes('UNDOABLE_SOURCES = %w['));
    const valores = linha.split('%w[')[1].split(']')[0].split(' ');
    expect([...ORIGENS_LIBERAVEIS].sort()).toEqual([...valores].sort());
  });
});

describe('informações da empresa', () => {
  it('formata o CNPJ e conta pessoas e clientes', () => {
    const linhas = linhasDaEmpresa({
      cnpj: '11222333000181',
      domain: 'x.exemplo.com.br',
      contacts_count: 3,
      customers_count: 1,
    });
    // CNPJ e site ficam só no cabeçalho.
    expect(linhas.map(l => [l.chave, l.valor])).toEqual([
      ['pessoas', '3'],
      ['clientes', '1'],
    ]);
  });
});
