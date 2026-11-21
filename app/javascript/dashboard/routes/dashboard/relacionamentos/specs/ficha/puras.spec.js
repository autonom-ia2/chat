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
  CANAIS,
  SITUACOES_DE_CARD,
  SITUACOES_DE_CONVERSA,
  canalConhecido,
  situacaoDeCardConhecida,
  situacaoDeConversaConhecida,
} from '../../ficha/rotulos';
import {
  formularioDaPessoa,
  linhasDaPessoa,
  nomeDaInformacao,
  pedidoParaSalvar,
  redesPreenchidas,
} from '../../ficha/informacoes';
import {
  blocoDosCamposAparece,
  camposDaPessoa,
  linhasDosCampos,
  linkCompleto,
  linkSeguro,
} from '../../ficha/atributos';
import {
  nomeDoPais,
  nomeGravadoDoPais,
  opcoesDePais,
} from '../../ficha/paises';

// Endereço que roda código no clique: nunca pode virar link. Montado em partes
// para não ser um link de verdade dentro do teste.
const LINK_PERIGOSO = ['javascript', 'alert(1)'].join(':');

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

  // #3075 — o campo personalizado do tipo link aceita o endereço sem "https://".
  it('link sem "https://" passa; o que não é site é cobrado', () => {
    const comLinks = { ...inicial, atributos: { site: '' } };
    const tipos = { site: 'link' };
    const com = site => ({ ...comLinks, atributos: { site } });
    expect(errosDoFormulario(comLinks, com('seusite.com.br'), tipos)).toEqual(
      {}
    );
    expect(errosDoFormulario(comLinks, com('padaria bom dia'), tipos)).toEqual({
      'atributo:site': 'LINK',
    });
  });

  it('empresa escrita e não escolhida trava o salvar', () => {
    expect(
      errosDoFormulario(inicial, { ...inicial, empresaPendente: ' Quitanda ' })
    ).toEqual({ empresa: 'EMPRESA_SEM_ESCOLHA' });
    expect(
      errosDoFormulario(inicial, { ...inicial, empresaPendente: '  ' })
    ).toEqual({});
  });

  it('cobra o link novo que não abre; o antigo e o vazio passam', () => {
    const comLinks = { ...inicial, atributos: { site: 'velho', outro: 'x' } };
    const tipos = { site: 'link', outro: 'text' };
    expect(
      errosDoFormulario(
        comLinks,
        { ...comLinks, atributos: { site: LINK_PERIGOSO, outro: 'y' } },
        tipos
      )
    ).toEqual({ 'atributo:site': 'LINK' });
    expect(errosDoFormulario(comLinks, comLinks, tipos)).toEqual({});
    expect(
      errosDoFormulario(
        comLinks,
        { ...comLinks, atributos: { site: 'https://exemplo.com.br' } },
        tipos
      )
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
    company_id: null,
    additional_attributes: {
      city: 'Santos',
      company_name: '',
      social_profiles: { instagram: '@ana', github: '', outra: 'x' },
    },
    custom_attributes: { cpf: CPF_VALIDO, melhor_horario: 'Tarde' },
  };
  const DEFINICOES = [
    {
      id: 1,
      attribute_model: 'contact_attribute',
      attribute_key: 'melhor_horario',
      attribute_display_name: 'Melhor hora para ligar',
      attribute_display_type: 'list',
      attribute_values: ['Manhã', 'Tarde'],
    },
  ];
  const linhasCom = alvo => linhasDaPessoa(alvo, { idioma: 'pt-BR' });
  const linhasDosCamposDe = (alvo, definicoes = DEFINICOES, escolhidos = []) =>
    linhasDosCampos(
      camposDaPessoa({
        definicoes,
        escolhidos,
        valores: alvo.custom_attributes,
      })
    );

  it('lista o fixo; os campos da conta ficam fora de Informações', () => {
    const linhas = linhasCom(pessoa);
    const por = chave => linhas.find(l => l.chave === chave);
    expect(por('cpf')).toMatchObject({ valor: '529.982.247-25', copiar: true });
    // A empresa fica só no cabeçalho.
    expect(por('empresa')).toBeUndefined();
    // #3082 — os campos da conta vão para o bloco "Seus campos".
    expect(por('conta:melhor_horario')).toBeUndefined();
    // Telefone e e-mail ficam só no cabeçalho; país e "Sobre" vazios não vêm.
    expect(linhas.map(l => l.chave).slice(0, 2)).toEqual(['cpf', 'cidade']);
    expect(por('telefone')).toBeUndefined();
    expect(por('email')).toBeUndefined();
    expect(por('pais')).toBeUndefined();
    expect(por('sobre')).toBeUndefined();
  });

  it('país no idioma do painel e "Sobre a pessoa" com as quebras de linha', () => {
    const linhas = linhasCom({
      ...pessoa,
      additional_attributes: {
        ...pessoa.additional_attributes,
        country_code: 'BR',
        country: 'Brazil',
        description: 'Prefere WhatsApp.\nLigar à tarde.',
      },
    });
    const por = chave => linhas.find(l => l.chave === chave);
    expect(por('pais').valor).toBe('Brasil');
    expect(por('sobre')).toMatchObject({
      valor: 'Prefere WhatsApp.\nLigar à tarde.',
      longo: true,
    });
  });

  it('"Seus campos": o campo com o nome que a conta deu e o tipo', () => {
    expect(linhasDosCamposDe(pessoa)).toEqual([
      {
        chave: 'conta:melhor_horario',
        rotulo: 'Melhor hora para ligar',
        tipo: 'list',
        valor: 'Tarde',
      },
    ]);
  });

  it('"Seus campos": o escolhido sem valor vem vazio; o não escolhido sem valor fica fora', () => {
    const definicoes = [
      ...DEFINICOES,
      {
        id: 2,
        attribute_model: 'contact_attribute',
        attribute_key: 'placa',
        attribute_display_name: 'Placa do carro',
        attribute_display_type: 'text',
      },
      {
        id: 3,
        attribute_model: 'contact_attribute',
        attribute_key: 'apelido',
        attribute_display_name: 'Apelido',
        attribute_display_type: 'text',
      },
    ];
    const linhas = linhasDosCamposDe(pessoa, definicoes, [2]);
    expect(linhas.map(l => [l.chave, l.valor])).toEqual([
      ['conta:placa', ''],
      ['conta:melhor_horario', 'Tarde'],
    ]);
  });

  it('o bloco "Seus campos" aparece com campo para mostrar ou para quem pode criar', () => {
    const mostrado = { chave: 'a', principal: true };
    const escondido = { chave: 'b', principal: false };
    expect(blocoDosCamposAparece([mostrado], false)).toBe(true);
    expect(blocoDosCamposAparece([escondido], false)).toBe(false);
    expect(blocoDosCamposAparece([], false)).toBe(false);
    expect(blocoDosCamposAparece([], true)).toBe(true);
  });

  it('valor gravado sem definição usa o nome da chave, com acento', () => {
    expect(linhasDosCamposDe(pessoa, [])).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          chave: 'conta:melhor_horario',
          rotulo: 'Melhor horário',
        }),
      ])
    );
    expect(nomeDaInformacao('como_prefere_ser_chamado')).toBe(
      'Como prefere ser chamado'
    );
  });

  it('mesmo com empresa preenchida, Informações não a repete', () => {
    const comEmpresa = {
      ...pessoa,
      company_id: 4,
      additional_attributes: {
        ...pessoa.additional_attributes,
        company_name: 'Padaria Dornelaz',
      },
    };
    expect(linhasCom(comEmpresa).map(l => l.chave)).not.toContain('empresa');
    expect(formularioDaPessoa(comEmpresa)).toMatchObject({
      empresa: 'Padaria Dornelaz',
      empresaId: 4,
      empresaNova: false,
    });
  });

  it('só mostra redes conhecidas e preenchidas', () => {
    expect(redesPreenchidas(pessoa)).toEqual([
      { rede: 'instagram', usuario: '@ana' },
    ]);
  });

  it('ida e volta do formulário, sem mutar a pessoa', () => {
    const antes = JSON.stringify(pessoa);
    const form = formularioDaPessoa(pessoa);
    expect(form.cpf).toBe('529.982.247-25');
    expect(form.redes.instagram).toBe('@ana');
    expect(form.atributos).toEqual({ melhor_horario: 'Tarde' });
    expect(form.foto).toBeNull();
    const { contato } = pedidoParaSalvar(
      { ...form, cidade: ' Bauru ', redes: { ...form.redes, instagram: '' } },
      form
    );
    expect(contato.additional_attributes.city).toBe('Bauru');
    expect(contato.additional_attributes.social_profiles).toEqual({
      outra: 'x',
      instagram: '',
    });
    // O que ninguém mexeu não vai de novo: o servidor junta com o que há.
    expect(contato.custom_attributes).toEqual({});
    expect(JSON.stringify(pessoa)).toBe(antes);
  });

  it('manda telefone e e-mail vazios como nulos', () => {
    const form = formularioDaPessoa(pessoa);
    const { contato } = pedidoParaSalvar(
      { ...form, telefone: '', email: ' ' },
      form
    );
    expect(contato.phone_number).toBeNull();
    expect(contato.email).toBeNull();
  });
});

describe('pedidoParaSalvar: link completo', () => {
  const pessoa = {
    name: 'Ana',
    additional_attributes: {},
    custom_attributes: { site: 'velho.com.br', blog: '' },
  };
  const tipos = { site: 'link', blog: 'link' };
  it('o link novo sem "https://" vai completo; o antigo sem ele não conta como mudado', () => {
    const inicial = formularioDaPessoa(pessoa);
    expect(
      pedidoParaSalvar(inicial, inicial, { tipos }).contato.custom_attributes
    ).toEqual({});
    const atual = {
      ...inicial,
      atributos: { ...inicial.atributos, blog: 'ana.blog.br' },
    };
    expect(
      pedidoParaSalvar(atual, inicial, { tipos }).contato.custom_attributes
    ).toEqual({ blog: 'https://ana.blog.br' });
  });
});

describe('pedidoParaSalvar: o que muda e o que sai', () => {
  const pessoaCheia = {
    name: 'Ana',
    phone_number: '+5511900001007',
    email: 'ana@exemplo.com.br',
    company_id: 4,
    additional_attributes: {
      city: 'Santos',
      company_name: 'Padaria Dornelaz',
      description: 'Cliente antiga.',
      social_profiles: { instagram: '@ana', github: '' },
    },
    custom_attributes: {
      cpf: CPF_VALIDO,
      melhor_horario: 'Tarde',
      filhos: 2,
      vip: false,
    },
  };
  const inicial = formularioDaPessoa(pessoaCheia);

  it('campo esvaziado sai de verdade; o tipo do que muda continua', () => {
    const { contato, apagar } = pedidoParaSalvar(
      {
        ...inicial,
        cpf: '',
        atributos: { ...inicial.atributos, melhor_horario: '', filhos: 3 },
      },
      inicial
    );
    expect(apagar).toEqual(['cpf', 'melhor_horario']);
    expect(contato.custom_attributes).toEqual({ filhos: 3 });
  });

  it('"não" (false) é valor: marcar e desmarcar vão; quem nunca teve não sai', () => {
    const { contato, apagar } = pedidoParaSalvar(
      { ...inicial, atributos: { ...inicial.atributos, vip: true, novo: '' } },
      inicial
    );
    expect(contato.custom_attributes).toEqual({ vip: true });
    expect(apagar).toEqual([]);
  });

  it('país e "Sobre a pessoa" vão como a ficha antiga grava', () => {
    const { contato } = pedidoParaSalvar(
      { ...inicial, pais: 'PT', sobre: ' ' },
      inicial
    );
    expect(contato.additional_attributes).toMatchObject({
      country_code: 'PT',
      country: 'Portugal',
      description: '',
    });
    const semMudar = pedidoParaSalvar(inicial, inicial).contato;
    expect(semMudar.additional_attributes).not.toHaveProperty('country_code');
    expect(semMudar.additional_attributes.description).toBe('Cliente antiga.');
  });

  it('empresa: escolher outra manda o id; tirar manda nulo; sem a chave, só o nome', () => {
    const outra = { ...inicial, empresa: 'Oficina', empresaId: 9 };
    expect(
      pedidoParaSalvar(outra, inicial, { comEmpresas: true }).contato
    ).toMatchObject({
      company_id: 9,
      additional_attributes: { company_name: 'Oficina' },
    });
    const tirada = { ...inicial, empresa: '', empresaId: null };
    expect(
      pedidoParaSalvar(tirada, inicial, { comEmpresas: true }).contato
        .company_id
    ).toBeNull();
    expect(pedidoParaSalvar(outra, inicial).contato).not.toHaveProperty(
      'company_id'
    );
    expect(
      pedidoParaSalvar(inicial, inicial, { comEmpresas: true }).contato
    ).not.toHaveProperty('company_id');
  });

  it('empresa nova vai pelo nome, para a fonte cadastrar', () => {
    const nova = {
      ...inicial,
      empresa: ' Padaria Nova ',
      empresaId: null,
      empresaNova: true,
    };
    const pedido = pedidoParaSalvar(nova, inicial, { comEmpresas: true });
    expect(pedido.empresaNova).toBe('Padaria Nova');
    expect(pedido.contato).not.toHaveProperty('company_id');
  });

  it('a foto pedida vai junto', () => {
    expect(
      pedidoParaSalvar({ ...inicial, foto: { tirar: true } }, inicial).foto
    ).toEqual({ tirar: true });
  });

  it('continua omitindo a rede que nunca existiu, e não muda a entrada', () => {
    const formulario = { ...inicial, cpf: '' };
    const antes = JSON.stringify([inicial, formulario]);
    const { contato } = pedidoParaSalvar(formulario, inicial);
    expect(contato.additional_attributes.social_profiles).toEqual({
      instagram: '@ana',
    });
    expect(JSON.stringify([inicial, formulario])).toBe(antes);
  });

  // O servidor troca `social_profiles` inteiro. Rede que a tela não mostra
  // (gravada por outra tela ou por importação) tem de voltar junto.
  it('devolve as redes que a tela não mostra, sem perder nenhuma', () => {
    const comOutraRede = formularioDaPessoa({
      ...pessoaCheia,
      additional_attributes: {
        ...pessoaCheia.additional_attributes,
        social_profiles: { instagram: '@ana', youtube: 'canaldaana' },
      },
    });
    const { contato } = pedidoParaSalvar(
      {
        ...comOutraRede,
        redes: { ...comOutraRede.redes, instagram: '@ana.nova' },
      },
      comOutraRede
    );
    expect(contato.additional_attributes.social_profiles).toEqual({
      youtube: 'canaldaana',
      instagram: '@ana.nova',
    });
  });
});

describe('camposDaPessoa', () => {
  const definicao = (id, chave, tipo, extra) => ({
    id,
    attribute_model: 'contact_attribute',
    attribute_key: chave,
    attribute_display_name: `Nome de ${chave}`,
    attribute_display_type: tipo,
    ...extra,
  });
  const DEFINICOES = [
    definicao(1, 'aniversario', 'date'),
    definicao(2, 'site', 'link'),
    definicao(3, 'escondido', 'text', { oculto_na_tela: true }),
    definicao(4, 'waha_whatsapp_chat_id', 'text'),
    definicao(5, 'cpf', 'text'),
    definicao(6, 'plano', 'list', { attribute_values: ['Ouro'] }),
    definicao(7, 'vip', 'checkbox'),
    { ...definicao(8, 'setor', 'text'), attribute_model: 'company_attribute' },
    definicao(9, 'cor', 'moeda'),
  ];

  it('a ordem: escolhidos pelo configurador, os com valor, os soltos e o resto', () => {
    const campos = camposDaPessoa({
      definicoes: DEFINICOES,
      escolhidos: [6],
      valores: {
        site: 'https://exemplo.com.br',
        escondido: 'x',
        waha_whatsapp_chat_id: '55@c.us',
        cpf: CPF_VALIDO,
        vip: false,
        solto: 'algo',
      },
    });
    expect(campos.map(c => [c.chave, c.principal])).toEqual([
      ['plano', true],
      ['site', true],
      ['vip', true],
      ['solto', true],
      ['aniversario', false],
      ['cor', false],
    ]);
    expect(campos.find(c => c.chave === 'plano')).toMatchObject({
      rotulo: 'Nome de plano',
      tipo: 'list',
      opcoes: ['Ouro'],
      valor: '',
    });
    // Tipo desconhecido vira texto.
    expect(campos.find(c => c.chave === 'cor').tipo).toBe('text');
  });

  it('link só abre com http ou https', () => {
    expect(linkSeguro('https://exemplo.com.br')).toBe(
      'https://exemplo.com.br/'
    );
    expect(linkSeguro(LINK_PERIGOSO)).toBe('');
    expect(linkSeguro('exemplo.com.br')).toBe('');
  });

  it('o link escrito sem "https://" ganha o começo; o que não é site fica vazio', () => {
    expect(linkCompleto('https://exemplo.com.br')).toBe(
      'https://exemplo.com.br'
    );
    expect(linkCompleto(' exemplo.com.br ')).toBe('https://exemplo.com.br');
    expect(linkCompleto('padaria bom dia')).toBe('');
    expect(linkCompleto(LINK_PERIGOSO)).toBe('');
  });

  it('só completa com https:// quando o nome do site tem ponto e não termina nele', () => {
    expect(linkCompleto('seusite.com.br')).toBe('https://seusite.com.br');
    expect(linkCompleto('naotenho')).toBe('');
    expect(linkCompleto('seusite.')).toBe('');
    // O que já veio com esquema vale como está.
    expect(linkCompleto('https://intranet')).toBe('https://intranet');
    expect(linkCompleto('')).toBe('');
  });
});

describe('país', () => {
  it('nome no idioma do painel; gravado em inglês, como a ficha antiga', () => {
    expect(nomeDoPais('BR', 'pt-BR')).toBe('Brasil');
    expect(nomeDoPais('BR', 'en')).toBe('Brazil');
    expect(nomeDoPais('ZZ', 'pt-BR', 'Terra do Nunca')).toBe('Terra do Nunca');
    expect(nomeGravadoDoPais('BR')).toBe('Brazil');
  });

  it('a escolha começa pelo país padrão do telefone e segue em ordem alfabética', () => {
    const [padrao, ...resto] = opcoesDePais('pt-BR', 'Não informado');
    expect(padrao.value).toBe('BR');
    expect(padrao.label).toContain('Brasil');
    const nomes = resto.map(opcao => opcao.searchLabel);
    expect(nomes).toEqual(
      [...nomes].sort((a, b) => a.localeCompare(b, 'pt-BR'))
    );
    expect(resto.some(opcao => opcao.value === '')).toBe(false);
  });

  it('"Não informado" só aparece, em primeiro, quando há país escolhido', () => {
    const [limpar, padrao] = opcoesDePais('pt-BR', 'Não informado', 'PT');
    expect(limpar).toEqual({ value: '', label: 'Não informado' });
    expect(padrao.value).toBe('BR');
  });
});

describe('texto da ficha não supõe gênero', () => {
  const PALAVRAS_COM_GENERO = [
    'ela',
    'ele',
    'dela',
    'dele',
    'obrigada',
    'obrigado',
  ];
  const ehLetra = char => char.toLowerCase() !== char.toUpperCase();
  const palavrasDe = texto =>
    texto
      .split(' ')
      .map(palavra => [...palavra].filter(ehLetra).join('').toLowerCase());
  const folhas = objeto =>
    Object.values(objeto).flatMap(valor =>
      typeof valor === 'object' ? folhas(valor) : [valor]
    );
  const ler = caminho => readFileSync(caminho, 'utf8');
  const raiz = 'app/javascript/dashboard';

  it.each(['en', 'pt_BR'])(
    'o catálogo %s não tem pronome nem adjetivo de gênero',
    lingua => {
      const catalogo = JSON.parse(
        ler(`${raiz}/i18n/locale/${lingua}/relacionamentosFicha.json`)
      );
      const proibidas =
        lingua === 'pt_BR'
          ? PALAVRAS_COM_GENERO
          : ['she', 'he', 'her', 'his', 'him'];
      folhas(catalogo).forEach(frase =>
        expect(palavrasDe(frase).filter(p => proibidas.includes(p))).toEqual([])
      );
    }
  );

  it.each(['en', 'pt_BR'])(
    'em %s o erro de tela inteira não repete "tente de novo" (o botão já diz)',
    lingua => {
      const { ESTADOS } = JSON.parse(
        ler(`${raiz}/i18n/locale/${lingua}/relacionamentosFicha.json`)
      ).RELACIONAMENTOS_FICHA;
      expect(ESTADOS.ERRO.toLowerCase()).not.toContain('tente de novo');
      expect(ESTADOS.ERRO.toLowerCase()).not.toContain('try again');
    }
  );

  it('a frase de apoio e o texto do Liberar usam {nome}', () => {
    ['en', 'pt_BR'].forEach(lingua => {
      const { FAIXA } = JSON.parse(
        ler(`${raiz}/i18n/locale/${lingua}/relacionamentosFicha.json`)
      ).RELACIONAMENTOS_FICHA;
      expect(FAIXA.APOIO).toContain('{nome}');
      expect(FAIXA.CONFIRMA_TEXTO).toContain('{nome}');
    });
  });

  it('as falas de exemplo da demo não marcam gênero', () => {
    const fonte = ler(`${raiz}/routes/dashboard/relacionamentos/demo/ficha.js`);
    expect(
      palavrasDe(fonte.split('\n').join(' ')).filter(p =>
        PALAVRAS_COM_GENERO.includes(p)
      )
    ).toEqual([]);
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

// O servidor pode mandar canal e situação que a demonstração não tinha (#2895).
describe('rótulos do que vem do servidor', () => {
  it('canal que a tela conhece fica como veio; `outro` e desconhecido viram "outro"', () => {
    expect(canalConhecido('whatsapp')).toBe('whatsapp');
    expect(canalConhecido('outro')).toBe('outro');
    expect(canalConhecido('telegram')).toBe('outro');
    expect(canalConhecido(null)).toBe('outro');
  });

  it('conversa adiada tem rótulo próprio; situação desconhecida vira "outra"', () => {
    expect(situacaoDeConversaConhecida('adiada')).toBe('adiada');
    expect(situacaoDeConversaConhecida('qualquer')).toBe('outra');
  });

  it('card tem os estados do CRM; estado desconhecido vira "outra"', () => {
    ['aberto', 'ganho', 'perdido', 'resolvido', 'cancelado'].forEach(situacao =>
      expect(situacaoDeCardConhecida(situacao)).toBe(situacao)
    );
    expect(situacaoDeCardConhecida('estado_novo')).toBe('outra');
    expect(situacaoDeCardConhecida(undefined)).toBe('outra');
  });

  // O que vem depois de cada `=>` no mapa do servidor, da chave à chave.
  const palavrasDoServidor = (arquivo, constante) =>
    readFileSync(`app/services/relacionamentos/ficha/${arquivo}`, 'utf8')
      .split(`${constante} = {`)[1]
      .split('}')[0]
      .split("=> '")
      .slice(1)
      .map(pedaco => pedaco.split("'")[0]);

  it('as situações batem com as palavras que o servidor manda', () => {
    expect([...SITUACOES_DE_CARD].sort()).toEqual(
      palavrasDoServidor('cards.rb', 'SITUACOES').sort()
    );
    expect([...SITUACOES_DE_CONVERSA].sort()).toEqual(
      palavrasDoServidor('conversas.rb', 'SITUACOES').sort()
    );
  });

  it.each(['en', 'pt_BR'])(
    'o catálogo %s tem texto para cada canal e cada situação, e para o neutro',
    lingua => {
      const { CONVERSAS, CARDS } = JSON.parse(
        readFileSync(
          `app/javascript/dashboard/i18n/locale/${lingua}/relacionamentosFicha.json`,
          'utf8'
        )
      ).RELACIONAMENTOS_FICHA;
      expect(Object.keys(CONVERSAS.CANAL).sort()).toEqual(
        [...CANAIS, 'outro'].sort()
      );
      expect(Object.keys(CONVERSAS.SITUACAO).sort()).toEqual(
        [...SITUACOES_DE_CONVERSA, 'outra'].sort()
      );
      expect(Object.keys(CARDS.SITUACAO).sort()).toEqual(
        [...SITUACOES_DE_CARD, 'outra'].sort()
      );
    }
  );
});
