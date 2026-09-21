// @vitest-environment node
// O modo aprendiz (#537) roda no CI, em Node — igual ao gerador do mapa.
import { lerPorques } from '../build.mjs';
import {
  mudancasDoMapa,
  nadaMudou,
  montarBloco,
  aplicarNoPorques,
  pedirRascunho,
  corpoDoPr,
} from '../aprendiz.mjs';

const tela = (nome, extra = {}) => ({
  nome,
  caminho: `/app/accounts/:accountId/${nome}`,
  papeis: ['administrator'],
  flag: null,
  ...extra,
});

describe('o que mudou no mapa entre dois deploys', () => {
  it('pede rascunho da tela nova que ainda não tem explicação', () => {
    const mudancas = mudancasDoMapa({
      antes: ['inbox_list'],
      depois: [tela('inbox_list'), tela('crm_relatorios')],
      semExplicacao: ['crm_relatorios'],
      humanos: {},
    });

    expect(mudancas.entraram.map(t => t.nome)).toEqual(['crm_relatorios']);
  });

  // Quem escreveu o porquê junto com a tela nova não precisa de rascunho — e
  // pedir à IA por cima do texto de gente seria desfazer trabalho.
  it('não pede rascunho de tela nova que já veio explicada', () => {
    const mudancas = mudancasDoMapa({
      antes: ['inbox_list'],
      depois: [tela('inbox_list'), tela('crm_relatorios')],
      semExplicacao: [],
      humanos: {},
    });

    expect(mudancas.entraram).toEqual([]);
  });

  // Tela velha sem explicação não é assunto deste deploy: o critério é o que
  // mudou ENTRE os dois, não tudo que falta.
  it('não pede rascunho de tela antiga que continua sem explicação', () => {
    const mudancas = mudancasDoMapa({
      antes: ['inbox_list', 'tela_antiga'],
      depois: [tela('inbox_list'), tela('tela_antiga')],
      semExplicacao: ['tela_antiga'],
      humanos: {},
    });

    expect(nadaMudou(mudancas)).toBe(true);
  });

  it('tira o bloco da tela que saiu, e deixa os outros', () => {
    const mudancas = mudancasDoMapa({
      antes: ['inbox_list', 'tela_velha'],
      depois: [tela('inbox_list')],
      semExplicacao: [],
      humanos: {
        caixas: { rota: 'inbox_list' },
        velho: { rota: 'tela_velha' },
      },
    });

    expect(mudancas.sairam).toEqual(['tela_velha']);
    expect(mudancas.blocosSemTela).toEqual(['velho']);
  });

  // Bloco que explica várias telas e perdeu UMA não sai inteiro — apagar
  // levaria as outras junto. Ele só perde o nome da tela no `cobre:`.
  it('não apaga o bloco que ainda explica outras telas, só marca o nome a tirar', () => {
    const mudancas = mudancasDoMapa({
      antes: ['inbox_new', 'inbox_finish'],
      depois: [tela('inbox_new')],
      semExplicacao: [],
      humanos: {
        criar_caixa: { rota: 'inbox_new', cobre: 'inbox_finish, inbox_agents' },
      },
    });

    expect(mudancas.blocosSemTela).toEqual([]);
    expect(mudancas.cobreSemTela).toEqual([
      { chave: 'criar_caixa', telas: ['inbox_finish'] },
    ]);
  });

  it('nunca mexe no bloco das telas que ficam fora do Guia', () => {
    const mudancas = mudancasDoMapa({
      antes: ['tela_velha'],
      depois: [],
      semExplicacao: [],
      humanos: { _fora_do_guia: { tela_velha: 'motivo' } },
    });

    expect(mudancas.blocosSemTela).toEqual([]);
  });

  // Caso real, medido contra um deploy antigo: saiu `onboarding_first_steps` e
  // nenhum bloco a citava. Não há nada para ninguém revisar — e um PR sem
  // mudança nem pode ser aberto.
  it('fica em silêncio quando a tela que saiu não era citada por nenhum bloco', () => {
    const mudancas = mudancasDoMapa({
      antes: ['inbox_list', 'onboarding_first_steps'],
      depois: [tela('inbox_list')],
      semExplicacao: [],
      humanos: { caixas: { rota: 'inbox_list' } },
    });

    expect(mudancas.sairam).toEqual(['onboarding_first_steps']);
    expect(nadaMudou(mudancas)).toBe(true);
  });

  // "Sem mudança: nenhum aviso" (critério da #537).
  it('fica em silêncio quando nada entrou e nada saiu', () => {
    const mudancas = mudancasDoMapa({
      antes: ['inbox_list'],
      depois: [tela('inbox_list')],
      semExplicacao: [],
      humanos: {},
    });

    expect(nadaMudou(mudancas)).toBe(true);
  });
});

describe('o rascunho no formato do porques.md', () => {
  const rascunho = {
    titulo: 'Relatórios do CRM',
    intent: 'Onde vejo os relatórios?; Como sei quantos negócios fechei?',
    onde_fica: 'CRM > Relatórios',
    perfil: 'administrador',
    pre_requisitos: '',
    passos: '1. Abra o CRM; 2. Clique em Relatórios',
    gotchas: '',
    duvidas: 'não sei se agente comum vê',
  };

  // O bloco tem que voltar pela MESMA leitura que o gerador usa. Se ele sair
  // num formato que o gerador não entende, o rascunho some do Guia calado.
  it('sai num bloco que o gerador do mapa lê de volta', () => {
    const fluxos = lerPorques(montarBloco(tela('crm_relatorios'), rascunho));

    expect(fluxos.crm_relatorios).toEqual({
      titulo: 'Relatórios do CRM',
      rota: 'crm_relatorios',
      intent: 'Onde vejo os relatórios?; Como sei quantos negócios fechei?',
      onde_fica: 'CRM > Relatórios',
      perfil: 'administrador',
      passos: '1. Abra o CRM; 2. Clique em Relatórios',
    });
  });

  // Quebra de linha no meio do campo faria o gerador ler só a primeira linha
  // e jogar o resto fora.
  it('junta numa linha só o campo que a IA escreveu em várias', () => {
    const bloco = montarBloco(tela('x'), {
      ...rascunho,
      passos: '1. Abra\n2. Clique\n\n3. Salve',
    });

    expect(lerPorques(bloco).x.passos).toBe('1. Abra 2. Clique 3. Salve');
  });

  it('não põe no bloco o que a IA não soube — isso vai para o PR', () => {
    expect(montarBloco(tela('x'), rascunho)).not.toContain('não sei se');
  });
});

describe('a escrita no porques.md', () => {
  const texto = `# Explicações

### criar_funil
- titulo: Criar funil
- rota: crm_kanban_index

### tela_velha
- titulo: Tela que saiu
- rota: tela_velha

### criar_etiqueta
- titulo: Criar etiqueta
- rota: labels_list
`;

  it('tira só o bloco que saiu e mantém o texto de gente intacto', () => {
    const novo = aplicarNoPorques(texto, {
      novos: [],
      remover: ['tela_velha'],
    });
    const fluxos = lerPorques(novo);

    expect(Object.keys(fluxos)).toEqual(['criar_funil', 'criar_etiqueta']);
    expect(novo).toContain('# Explicações');
  });

  it('tira do cobre: só a tela que saiu, e mantém as outras', () => {
    const comCobre = `### criar_caixa
- titulo: Criar caixa
- rota: inbox_new
- cobre: inbox_finish, inbox_agents
`;
    const novo = aplicarNoPorques(comCobre, {
      novos: [],
      remover: [],
      limparCobre: [{ chave: 'criar_caixa', telas: ['inbox_finish'] }],
    });

    expect(lerPorques(novo).criar_caixa.cobre).toBe('inbox_agents');
  });

  it('tira a linha cobre: inteira quando não sobra tela nenhuma', () => {
    const comCobre = `### criar_caixa
- titulo: Criar caixa
- rota: inbox_new
- cobre: inbox_finish
`;
    const novo = aplicarNoPorques(comCobre, {
      novos: [],
      remover: [],
      limparCobre: [{ chave: 'criar_caixa', telas: ['inbox_finish'] }],
    });

    expect(lerPorques(novo).criar_caixa).toEqual({
      titulo: 'Criar caixa',
      rota: 'inbox_new',
    });
  });

  // A limpeza é do bloco que perdeu a tela — o `cobre:` de outro bloco que
  // cite o mesmo nome por engano não é assunto desta mudança.
  it('limpa o cobre: só do bloco indicado', () => {
    const doisBlocos = `### a
- cobre: x, y

### b
- cobre: x, z
`;
    const novo = aplicarNoPorques(doisBlocos, {
      novos: [],
      remover: [],
      limparCobre: [{ chave: 'a', telas: ['x'] }],
    });
    const fluxos = lerPorques(novo);

    expect(fluxos.a.cobre).toBe('y');
    expect(fluxos.b.cobre).toBe('x, z');
  });

  it('acrescenta o rascunho no fim, como um bloco a mais', () => {
    const novo = aplicarNoPorques(texto, {
      novos: [
        '### crm_relatorios\n- titulo: Relatórios\n- rota: crm_relatorios',
      ],
      remover: [],
    });

    expect(Object.keys(lerPorques(novo))).toEqual([
      'criar_funil',
      'tela_velha',
      'criar_etiqueta',
      'crm_relatorios',
    ]);
  });
});

describe('o pedido à IA', () => {
  const resposta = (status, corpo) => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => corpo,
  });

  const saidaDaIa = rascunho => ({
    output: [
      { type: 'reasoning' },
      {
        type: 'message',
        content: [{ type: 'output_text', text: JSON.stringify(rascunho) }],
      },
    ],
  });

  it('pede no formato fechado e devolve o rascunho', async () => {
    let enviado;
    const buscar = async (_url, opcoes) => {
      enviado = JSON.parse(opcoes.body);
      return resposta(200, saidaDaIa({ titulo: 'Relatórios', duvidas: '' }));
    };

    const rascunho = await pedirRascunho({
      tela: tela('crm_relatorios'),
      contexto: 'código',
      exemplos: 'exemplo',
      chave: 'sk-teste',
      buscar,
    });

    expect(rascunho.titulo).toBe('Relatórios');
    expect(enviado.model).toBe('gpt-5.6-sol');
    expect(enviado.text.format.strict).toBe(true);
    expect(enviado.input).toContain('crm_relatorios');
  });

  // A mensagem de erro vai para o log do CI, que qualquer pessoa com acesso ao
  // repositório lê. A chave não pode estar nela.
  it('falha dizendo o motivo, sem nunca mostrar a chave', async () => {
    const buscar = async () =>
      resposta(401, { error: { message: 'Incorrect API key provided' } });

    const falha = pedirRascunho({
      tela: tela('crm_relatorios'),
      contexto: 'código',
      exemplos: 'exemplo',
      chave: 'sk-segredo-que-nao-pode-vazar',
      buscar,
    });

    await expect(falha).rejects.toThrow('HTTP 401');
    await expect(falha).rejects.not.toThrow('sk-segredo');
  });
});

describe('quando a IA não responde', () => {
  const pedir = buscar =>
    pedirRascunho({
      tela: tela('crm_relatorios'),
      contexto: 'código',
      exemplos: 'exemplo',
      chave: 'sk-segredo-que-nao-pode-vazar',
      buscar,
    });

  // Achado da revisão da #579: rede caída virava só "fetch failed" e um stack
  // trace no log do CI, sem dizer de qual tela era.
  it('diz qual tela e o que aconteceu quando a rede cai', async () => {
    const falha = pedir(async () => {
      throw new TypeError('fetch failed');
    });

    await expect(falha).rejects.toThrow('crm_relatorios');
    await expect(falha).rejects.toThrow('fetch failed');
    await expect(falha).rejects.not.toThrow('sk-segredo');
  });

  // Sem isto, `JSON.parse('')` estouraria com "Unexpected end of JSON input".
  it('diz que veio vazio quando a IA recusa ou não escreve nada', async () => {
    const falha = pedir(async () => ({
      ok: true,
      status: 200,
      json: async () => ({ output: [] }),
    }));

    await expect(falha).rejects.toThrow('sem rascunho para crm_relatorios');
  });
});

describe('o Pull Request', () => {
  const mudancas = {
    entraram: [tela('crm_relatorios')],
    sairam: ['tela_velha'],
    blocosSemTela: ['velho'],
    cobreSemTela: [{ chave: 'criar_caixa', telas: ['inbox_finish'] }],
  };
  const corpo = corpoDoPr({
    commit: 'abc1234',
    mudancas,
    rascunhos: [
      {
        tela: tela('crm_relatorios'),
        rascunho: { duvidas: 'não sei quem vê' },
      },
    ],
  });

  // "Nada publicado sem revisão humana" (critério da #537).
  it('deixa claro que nada disto está no ar antes do merge', () => {
    expect(corpo).toContain('Nada disto está no ar');
  });

  it('mostra o que a IA não conseguiu saber, para quem revisa completar', () => {
    expect(corpo).toContain('não sei quem vê');
  });

  it('lista os blocos removidos e os que perderam uma tela', () => {
    expect(corpo).toContain('`velho`');
    expect(corpo).toContain('criar_caixa');
    expect(corpo).toContain('inbox_finish');
  });
});
