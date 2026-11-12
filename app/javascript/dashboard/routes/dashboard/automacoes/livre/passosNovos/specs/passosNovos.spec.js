import {
  FLAG,
  PASSOS_NOVOS,
  chaveDoNome,
  comPassosNovos,
  enderecoServe,
  faixasProntas,
  listaPronta,
  passoNovoPronto,
  valoresDaConsulta,
} from '../passosNovos';
import {
  ensaiarComPassosNovos,
  temPassoNovo,
  testarConsulta,
} from '../adaptadorFalso';
import { linhaDoEnsaioNovo, linhaDoHistoricoNovo } from '../frasesDosNovos';
import { comTextosDaIa, entradaDoPasso, novoPasso } from '../../catalogo';
import { fraseDoPasso } from '../../frases';
import { linhasDoEnsaio } from '../../ensaio';
import { falta, galhosDe, inserirPasso, idDaLista } from '../../receita';
import catalogoGerado from '../../../../../../../../../lib/operator_guide/automacao-passos.json';

// Protótipo #2931–#2936 — os 6 passos novos da Automação livre: só com a flag
// no catálogo, nascem prontos, o "Salvar" espera o que falta, os galhos entram
// na receita e cada um tem frase no Confira, linha no ensaio e no histórico.
const t = (chave, valores) =>
  valores ? `${chave} ${JSON.stringify(valores)}` : chave;

const TIPOS = Object.keys(PASSOS_NOVOS);
const catalogo = comPassosNovos(catalogoGerado, true);
const novo = tipo =>
  novoPasso(
    catalogo.passos.find(item => item.tipo === tipo),
    'p9',
    t
  );

describe('catálogo dos passos novos', () => {
  it('sem a flag, o catálogo é o mesmo objeto do servidor', () => {
    expect(comPassosNovos(catalogoGerado, false)).toBe(catalogoGerado);
  });

  it('com a flag, entram os 6 passos, cada um com nome, frase e a flag', () => {
    const novos = catalogo.passos.filter(item => PASSOS_NOVOS[item.tipo]);

    expect(novos.map(item => item.tipo)).toEqual(TIPOS);
    novos.forEach(item => {
      expect(item.requer).toBe(FLAG);
      expect(item.frase.endsWith('.NOME')).toBe(true);
      expect(item.dica.endsWith('.DICA')).toBe(true);
      expect(item.campos[0].peca).toBe('passo_novo');
      expect(catalogoGerado.grupos.map(g => g.chave)).toContain(item.grupo);
    });
  });

  it('montar o "Buscar em outro sistema" pede a chave de integrações', () => {
    const consultar = catalogo.passos.find(item => item.tipo === 'consultar');

    expect(consultar.chave).toBe('integration_manage');
    expect(
      catalogo.passos.filter(item => PASSOS_NOVOS[item.tipo] && item.chave)
    ).toHaveLength(1);
  });

  it('o passo da receita acha a entrada dele', () => {
    TIPOS.forEach(tipo =>
      expect(entradaDoPasso(novo(tipo), catalogo).tipo).toBe(tipo)
    );
  });
});

describe('começar pronto', () => {
  it('cada passo nasce com o que serve à maioria', () => {
    expect(novo('pedir_aprovacao')).toEqual({
      id: 'p9',
      tipo: 'pedir_aprovacao',
      quem: { de: 'responsavel' },
      pergunta: ['AUTOMACAO_LIVRE.PASSOS_NOVOS.APROVACAO.PERGUNTA_PADRAO'],
      prazo: { valor: 1, unidade: 'dias' },
    });
    expect(novo('repetir_lista')).toMatchObject({
      lista: { de: 'etapa', etapa_id: null },
      teto: 50,
      ritmo: 'aos_poucos',
    });
    expect(novo('pesquisa_nota')).toMatchObject({
      baixa_ate: 6,
      alta_desde: 9,
      intervalo_dias: 30,
    });
  });

  it('aprovação, reunião e pesquisa já nascem prontas para salvar', () => {
    expect(passoNovoPronto(novo('pedir_aprovacao'))).toBe(true);
    expect(passoNovoPronto(novo('marcar_reuniao'))).toBe(true);
    expect(passoNovoPronto(novo('pesquisa_nota'))).toBe(true);
  });

  it('lista, bloco e busca esperam o que vem da conta', () => {
    expect(passoNovoPronto(novo('repetir_lista'))).toBe(false);
    expect(passoNovoPronto(novo('usar_bloco'))).toBe(false);
    expect(passoNovoPronto(novo('consultar'))).toBe(false);
  });
});

describe('o que segura o "Salvar"', () => {
  it('aprovação sem pergunta, sem pessoa escolhida ou sem prazo', () => {
    const passo = novo('pedir_aprovacao');

    expect(passoNovoPronto({ ...passo, pergunta: ['  '] })).toBe(false);
    expect(
      passoNovoPronto({ ...passo, quem: { de: 'pessoa', id: null } })
    ).toBe(false);
    expect(passoNovoPronto({ ...passo, quem: { de: 'time', id: 4 } })).toBe(
      true
    );
    expect(passoNovoPronto({ ...passo, prazo: { unidade: 'dias' } })).toBe(
      false
    );
  });

  it('lista com etapa ou etiqueta e o teto de 1 a 200', () => {
    const passo = novo('repetir_lista');
    const etapa = { ...passo, lista: { de: 'etapa', etapa_id: 12 } };

    expect(passoNovoPronto(etapa)).toBe(true);
    expect(
      passoNovoPronto({ ...passo, lista: { de: 'etiqueta', etiqueta: 'vip' } })
    ).toBe(true);
    expect(passoNovoPronto({ ...etapa, teto: 0 })).toBe(false);
    expect(passoNovoPronto({ ...etapa, teto: 201 })).toBe(false);
  });

  it('busca com a fonte e pelo menos um dado com nome', () => {
    const passo = {
      ...novo('consultar'),
      fonte: { de: 'integracao', id: 'loja' },
      guardar: [{ nome: 'Status do pedido', caminho: 'pedido.status' }],
    };

    expect(passoNovoPronto(passo)).toBe(true);
    expect(passoNovoPronto({ ...passo, guardar: [] })).toBe(false);
    expect(
      passoNovoPronto({
        ...passo,
        guardar: [{ nome: ' ', caminho: 'pedido.status' }],
      })
    ).toBe(false);
    expect(
      passoNovoPronto({ ...passo, fonte: { de: 'endereco', url: 'http://a' } })
    ).toBe(false);
  });

  it('só endereço https serve; o resto o servidor confere', () => {
    expect(enderecoServe('https://loja.exemplo/pedidos')).toBe(true);
    expect(enderecoServe('http://loja.exemplo')).toBe(false);
    expect(enderecoServe('loja')).toBe(false);
  });

  it('as faixas da nota deixam pelo menos uma nota no meio', () => {
    expect(faixasProntas({ baixa_ate: 6, alta_desde: 9 })).toBe(true);
    expect(faixasProntas({ baixa_ate: 6, alta_desde: 8 })).toBe(true);
    expect(faixasProntas({ baixa_ate: 7, alta_desde: 8 })).toBe(false);
    expect(faixasProntas({ baixa_ate: 9, alta_desde: 9 })).toBe(false);
  });
});

describe('a lista do "para cada um"', () => {
  it('etapa, etiqueta ou público, cada uma com a sua escolha', () => {
    expect(listaPronta({ de: 'etapa', etapa_id: 12 })).toBe(true);
    expect(listaPronta({ de: 'etiqueta', etiqueta: 'vip' })).toBe(true);
    expect(listaPronta({ de: 'publico', publico_id: 1 })).toBe(true);
    expect(listaPronta({ de: 'publico', publico_id: null })).toBe(false);
    expect(listaPronta({ de: 'outra' })).toBe(false);
  });
});

describe('o Salvar tudo com passo novo', () => {
  it('a receita com passo novo não vai à API: o passo está em teste', () => {
    const gatilho = { tipo: 'conversa.resolvida' };
    const se = { id: 'p1', tipo: 'se', entao: [novo('pesquisa_nota')] };

    expect(falta({ gatilho, passos: [se] })).toBe('EM_TESTE');
    expect(falta({ gatilho, passos: [{ id: 'p2', tipo: 'parar' }] })).toBe(
      null
    );
  });
});

describe('os galhos entram na receita', () => {
  it('o pedir aprovação tem aprovado, recusado e ninguém respondeu', () => {
    expect(galhosDe(novo('pedir_aprovacao')).map(g => g.ramo)).toEqual([
      'aprovado',
      'recusado',
      'ninguem_respondeu',
    ]);
    expect(galhosDe(novo('usar_bloco'))).toEqual([]);
  });

  it('o "+" do galho põe o passo dentro dele', () => {
    const passos = [novo('pedir_aprovacao')];
    const parar = { id: 'p10', tipo: 'parar' };

    const [passo] = inserirPasso(passos, idDaLista('p9', 'recusado'), 0, parar);

    expect(passo.recusado).toEqual([parar]);
    expect(passo.aprovado).toBeUndefined();
  });
});

describe('em frase', () => {
  it('o Confira diz o que cada passo faz, sem endereço', () => {
    const consulta = {
      ...novo('consultar'),
      fonte: { de: 'endereco', url: 'https://segredo.exemplo/x' },
      guardar: [{ nome: 'Status do pedido', caminho: 'pedido.status' }],
    };

    expect(fraseDoPasso(novo('pedir_aprovacao'), catalogo, t)).toContain(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.APROVACAO.FRASE'
    );
    expect(fraseDoPasso(consulta, catalogo, t)).not.toContain('segredo');
    expect(fraseDoPasso(consulta, catalogo, t)).toContain('Status do pedido');
  });

  it('sem a flag, o passo novo aparece como ação avançada', () => {
    expect(fraseDoPasso(novo('pesquisa_nota'), catalogoGerado, t)).toContain(
      'AUTOMACAO_LIVRE.FRASES.AVANCADA'
    );
  });

  it('o ensaio diz o que faria e mostra a mensagem, sem mandar nada', () => {
    const reuniao = linhaDoEnsaioNovo(novo('marcar_reuniao'), t);
    const pesquisa = linhaDoEnsaioNovo(novo('pesquisa_nota'), t);

    expect(reuniao.destaque).toContain('REUNIAO.ENSAIO');
    expect(reuniao.balao).toContain('1. AUTOMACAO_LIVRE.PASSOS_NOVOS.EXEMPLO');
    expect(pesquisa.balao).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.PESQUISA.PERGUNTA_PADRAO'
    );
  });

  it('o histórico do bloco traz os passos de dentro', () => {
    const linha = linhaDoHistoricoNovo(
      { ...novo('usar_bloco'), bloco_id: 1 },
      t
    );

    expect(linha.texto).toContain('BLOCO.HISTORICO');
    expect(linha.dentro).toHaveLength(3);
  });

  it('cada passo tem linha no ensaio e no histórico', () => {
    TIPOS.forEach(tipo => {
      expect(linhaDoEnsaioNovo(novo(tipo), t).destaque).toBeTruthy();
      expect(linhaDoHistoricoNovo(novo(tipo), t).texto).toBeTruthy();
    });
  });
});

describe('ensaio pelo adaptador falso', () => {
  it('acha o passo novo em qualquer galho', () => {
    const se = { id: 'p1', tipo: 'se', entao: [novo('usar_bloco')] };

    expect(temPassoNovo([se])).toBe(true);
    expect(temPassoNovo([{ id: 'p1', tipo: 'parar' }])).toBe(false);
  });

  it('responde no formato da API e a linha sai pela frase do passo novo', async () => {
    const aprovacao = {
      ...novo('pedir_aprovacao'),
      aprovado: [{ id: 'p2', tipo: 'parar' }],
    };
    const { data } = await ensaiarComPassosNovos(
      { passos: [aprovacao] },
      ramo => `RAMO.${ramo}`
    );

    expect(data.conversas).toHaveLength(2);
    const linhas = linhasDoEnsaio(data.conversas[0].passos, () => 'F', t);
    expect(linhas[0].destaque).toContain('APROVACAO.ENSAIO');
    expect(linhas[1]).toMatchObject({ caminho: true });
    // O galho fixo diz o próprio nome, sem "Se a IA escolher".
    expect(linhas[1].texto).toContain('PASSOS_NOVOS.CAMINHO_NO_ENSAIO');
    expect(linhas[1].texto).toContain('AUTOMACAO_LIVRE.RAMOS.APROVADO');
    expect(linhas[1].texto).not.toContain('SE_CAMINHO');
  });

  it('o caminho do "decidir" continua com o nome que a IA escolhe', async () => {
    const decidir = {
      id: 'p1',
      tipo: 'decidir',
      caminhos: [{ nome: 'Quer comprar', passos: [novo('usar_bloco')] }],
    };
    const { data } = await ensaiarComPassosNovos(
      { passos: [decidir] },
      ramo => `RAMO.${ramo}`
    );
    const linhas = linhasDoEnsaio(data.conversas[0].passos, () => 'F', t);

    expect(linhas[1].texto).toContain('SE_CAMINHO');
    expect(linhas[1].texto).toContain('Quer comprar');
  });

  it('o teste da busca devolve os dados para tocar', async () => {
    const dados = await testarConsulta({ de: 'integracao', id: 'loja' }, t);

    expect(dados.map(dado => dado.caminho)).toContain('pedido.status');
    // O nome é o do dia a dia, não a chave do JSON.
    expect(dados.find(d => d.caminho === 'cliente.nome').nome).toBe(
      'AUTOMACAO_LIVRE.PASSOS_NOVOS.EXEMPLO.DADOS.NOME_DO_CLIENTE'
    );
  });
});

describe('o dado da busca nos passos seguintes', () => {
  it('a chave sai do nome, sem acento e sem espaço', () => {
    expect(chaveDoNome('Situação do Pedido!')).toBe('situacao_do_pedido');
    expect(chaveDoNome('  ')).toBe('');
  });

  it('vira um dado do "Pôr um dado" com o nome que a pessoa deu', () => {
    const passo = {
      ...novo('consultar'),
      guardar: [{ nome: 'Status do pedido', caminho: 'pedido.status' }],
    };

    expect(valoresDaConsulta(passo)).toEqual([
      {
        caminho: 'consulta.p9.status_do_pedido',
        chave: 'p9.status_do_pedido',
        rotulo: 'Status do pedido',
      },
    ]);
    expect(comTextosDaIa({ valores: [] }, [passo], t).valores).toHaveLength(1);
  });
});
