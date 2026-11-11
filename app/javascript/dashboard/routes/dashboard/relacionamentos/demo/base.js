// #2894 — a base fictícia de Relacionamentos. Só é carregada no ambiente de
// desenvolvimento (fonte/listaFonte.js, `import.meta.env.DEV`); em produção o
// arquivo nem entra no pacote.
//
// Tudo é inventado e sempre igual: 280 pessoas e 38 empresas. Nomes e
// sobrenomes não existem; telefones ficam no bloco fictício +55 11 9XXXX-00NN;
// e-mails são @exemplo.com.br; CPF e CNPJ têm o dígito verificador trocado.
// As datas são relativas ao "agora" para os grupos não envelhecerem.
//
// Distribuição das pessoas: 120 clientes · 96 falaram nos últimos 30 dias · 42
// sumiram há 1 a 3 meses · 71 há mais de 3 meses · 71 nunca conversaram · 9 não
// querem mensagens · 4 sem telefone. Cliente e "não quer mensagens" cruzam com
// os quatro grupos de conversa. Empresas: 14 com cliente, 5 sem ninguém.
import { cnpjFalso, cpfFalso } from './documentosFalsos';
import { embaralhadoFixo, sorteioFixo } from './sorteioFixo';
import { DIA_EM_MS } from '../fonte/grupos';
import { normalizado } from '../fonte/texto';

const TOTAL_DE_PESSOAS = 280;
const TOTAL_DE_EMPRESAS = 38;
const TOTAL_DE_CLIENTES = 120;
const TOTAL_QUE_FALOU_HA_POUCO = 96;
const TOTAL_QUE_SUMIU_1_A_3_MESES = 42;
const TOTAL_QUE_SUMIU_MAIS_DE_3_MESES = 71;
const TOTAL_NAO_QUER_MENSAGENS = 9;
const TOTAL_SEM_TELEFONE = 4;
const EMPRESAS_COM_CLIENTE = 14;
const EMPRESAS_SEM_PESSOAS = 5;
const CHANCE_DE_CLIENTE_TER_EMPRESA = 0.45;
const CHANCE_DE_OUTRO_TER_EMPRESA = 0.4;

// Faixas de "dias sem conversar" bem longe das bordas de 30 e 90 dias.
const FAIXAS_DE_CONVERSA = {
  poucoDias: { de: 0, ate: 27 },
  umATresMeses: { de: 35, ate: 85 },
  maisDeTresMeses: { de: 100, ate: 400 },
};

const SEMENTES = {
  nomes: 11,
  conversa: 23,
  clientes: 37,
  recusa: 41,
  semTelefone: 53,
  detalhes: 67,
  empresas: 79,
  tiposDeEmpresa: 83,
  papelDaEmpresa: 97,
};

const NOMES = [
  'Ana',
  'Bruno',
  'Carla',
  'Diego',
  'Elisa',
  'Fábio',
  'Gabriela',
  'Hugo',
  'Inês',
  'João',
  'Karina',
  'Lucas',
  'Marina',
  'Nádia',
  'Otávio',
  'Paula',
  'Rafael',
  'Sônia',
  'Tiago',
  'Vânia',
];
// Sobrenomes inventados: não são de família nenhuma.
const SOBRENOMES = [
  'Albuquerino',
  'Brandolim',
  'Carvalhedo',
  'Dornelaz',
  'Esteveira',
  'Figueirão',
  'Guedelha',
  'Hortêncio',
  'Imbirussu',
  'Jacobelli',
  'Lourenzatto',
  'Mendonzela',
  'Nogueirão',
  'Ourivesco',
];
const TIPOS_DE_EMPRESA = [
  'Padaria',
  'Oficina',
  'Clínica',
  'Escritório',
  'Mercearia',
  'Estúdio',
  'Transportes',
  'Construtora',
  'Ótica',
  'Papelaria',
  'Farmácia',
  'Gráfica',
  'Escola',
  'Consultoria',
  'Pet Shop',
  'Marcenaria',
  'Lavanderia',
  'Floricultura',
  'Academia',
];
const CIDADES = [
  'São Paulo',
  'Campinas',
  'Santos',
  'Sorocaba',
  'Ribeirão Preto',
  'São José dos Campos',
  'Jundiaí',
  'Bauru',
];
const ETIQUETAS = ['clientes-2025', 'indicacao', 'feira', 'site', 'evento'];
const ORIGENS_DA_RECUSA = ['manual', 'follow_up_reply', 'email_unsubscribe'];

const DOMINIO_DE_EMAIL = 'exemplo.com.br';
const DDD_FICTICIO = '+5511';
const PRIMEIRO_BLOCO_FICTICIO = 1000;
const PASSO_DO_BLOCO = 31;
const FIM_DO_NUMERO_FICTICIO = 99;

const emSegundos = ms => Math.floor(ms / 1000);
const diasAtras = (agora, dias) => emSegundos(agora - dias * DIA_EM_MS);
const entre = (sorteio, { de, ate }) => de + sorteio() * (ate - de);
const escolher = (sorteio, lista) =>
  lista[Math.floor(sorteio() * lista.length)];

// Minúsculo, sem acento, só letras e números ligados por `ligacao`.
const ehLetraOuNumero = char =>
  (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9');
const apelido = (texto, ligacao) =>
  [...normalizado(texto)]
    .map(char => (ehLetraOuNumero(char) ? char : ' '))
    .join('')
    .split(' ')
    .filter(Boolean)
    .join(ligacao);

const nomeDaPessoa = ordem =>
  `${NOMES[ordem % NOMES.length]} ${SOBRENOMES[Math.floor(ordem / NOMES.length)]}`;

const telefoneFalso = i => {
  const bloco = PRIMEIRO_BLOCO_FICTICIO + i * PASSO_DO_BLOCO;
  const final = String((i % FIM_DO_NUMERO_FICTICIO) + 1).padStart(2, '0');
  return `${DDD_FICTICIO}9${bloco}00${final}`;
};

// Quem, entre 0..n-1, cai nos `quantos` primeiros lugares da ordem embaralhada.
const sorteados = (ordem, quantos) => new Set(ordem.slice(0, quantos));

const TOTAL_DE_FAIXAS = [
  TOTAL_QUE_FALOU_HA_POUCO,
  TOTAL_QUE_SUMIU_1_A_3_MESES,
  TOTAL_QUE_SUMIU_MAIS_DE_3_MESES,
];

// Posição sorteada (0..279) -> faixa de conversa; sobra = nunca conversou.
const faixaDaPosicao = posicao => {
  const [pouco, umATres, maisDeTres] = TOTAL_DE_FAIXAS;
  if (posicao < pouco) return FAIXAS_DE_CONVERSA.poucoDias;
  if (posicao < pouco + umATres) return FAIXAS_DE_CONVERSA.umATresMeses;
  if (posicao < pouco + umATres + maisDeTres) {
    return FAIXAS_DE_CONVERSA.maisDeTresMeses;
  }
  return null;
};

const ultimaConversa = (agora, faixa, sorteio) =>
  faixa ? diasAtras(agora, entre(sorteio, faixa)) : null;

const criadoEm = (agora, ultima, sorteio) => {
  const base = ultima ? (agora / 1000 - ultima) / (DIA_EM_MS / 1000) : 0;
  const dias = base + entre(sorteio, { de: 5, ate: 400 });
  return diasAtras(agora, dias);
};

const planejarPessoas = agora => {
  const sorteio = sorteioFixo(SEMENTES.detalhes);
  const ordemDeConversa = embaralhadoFixo(TOTAL_DE_PESSOAS, SEMENTES.conversa);
  const ehCliente = sorteados(
    embaralhadoFixo(TOTAL_DE_PESSOAS, SEMENTES.clientes),
    TOTAL_DE_CLIENTES
  );
  const ultimas = ordemDeConversa.map(posicao =>
    ultimaConversa(agora, faixaDaPosicao(posicao), sorteio)
  );
  // Quem pediu para parar já conversou; quem está sem telefone não pediu.
  const recusaram = new Set(
    embaralhadoFixo(TOTAL_DE_PESSOAS, SEMENTES.recusa)
      .filter(i => ultimas[i] !== null)
      .slice(0, TOTAL_NAO_QUER_MENSAGENS)
  );
  const semTelefone = new Set(
    embaralhadoFixo(TOTAL_DE_PESSOAS, SEMENTES.semTelefone)
      .filter(i => !recusaram.has(i))
      .slice(0, TOTAL_SEM_TELEFONE)
  );
  const nomes = embaralhadoFixo(TOTAL_DE_PESSOAS, SEMENTES.nomes);
  return { sorteio, ultimas, ehCliente, recusaram, semTelefone, nomes };
};

const pessoaDoPlano = (plano, agora, i, empresaDaPessoa) => {
  const { sorteio, ultimas, ehCliente, recusaram, semTelefone, nomes } = plano;
  const nome = nomeDaPessoa(nomes[i]);
  const cliente = ehCliente.has(i);
  const empresa = empresaDaPessoa[i];
  const recusou = recusaram.has(i);
  return {
    id: i + 1,
    name: nome,
    email: `${apelido(nome, '.')}@${DOMINIO_DE_EMAIL}`,
    phone_number: semTelefone.has(i) ? null : telefoneFalso(i),
    thumbnail: '',
    availability_status: 'offline',
    blocked: false,
    identifier: null,
    contact_type: cliente ? 'customer' : 'lead',
    customer_since: cliente
      ? diasAtras(agora, entre(sorteio, { de: 20, ate: 900 }))
      : null,
    last_activity_at: ultimas[i],
    created_at: criadoEm(agora, ultimas[i], sorteio),
    additional_attributes: {
      city: escolher(sorteio, CIDADES),
      company_name: empresa ? empresa.name : '',
    },
    custom_attributes: i % 3 === 0 ? { cpf: cpfFalso(i + 1) } : {},
    labels: [escolher(sorteio, ETIQUETAS)],
    company_id: empresa ? empresa.id : null,
    opted_out_at: recusou
      ? diasAtras(agora, entre(sorteio, { de: 3, ate: 60 }))
      : null,
    opt_out_source: recusou ? escolher(sorteio, ORIGENS_DA_RECUSA) : null,
  };
};

// As empresas nascem sem pessoas; os papéis (com cliente, só com gente, vazia)
// saem de uma ordem embaralhada para a lista não parecer arrumada.
const papeisDasEmpresas = () =>
  embaralhadoFixo(TOTAL_DE_EMPRESAS, SEMENTES.papelDaEmpresa).map(posicao => {
    if (posicao < EMPRESAS_COM_CLIENTE) return 'com_cliente';
    if (posicao < TOTAL_DE_EMPRESAS - EMPRESAS_SEM_PESSOAS) return 'so_gente';
    return 'vazia';
  });

const nomeDaEmpresa = k =>
  `${TIPOS_DE_EMPRESA[k % TIPOS_DE_EMPRESA.length]} ${SOBRENOMES[(k * 3) % SOBRENOMES.length]}`;

const esqueletoDasEmpresas = agora => {
  const papeis = papeisDasEmpresas();
  const ordemDeTipos = embaralhadoFixo(
    TOTAL_DE_EMPRESAS,
    SEMENTES.tiposDeEmpresa
  );
  return papeis.map((papel, k) => {
    const nome = nomeDaEmpresa(ordemDeTipos[k]);
    return {
      id: k + 1,
      name: nome,
      domain: `${apelido(nome, '-')}.${DOMINIO_DE_EMAIL}`,
      cnpj: cnpjFalso(k + 1),
      created_at: diasAtras(agora, 30 + k * 11),
      papel,
    };
  });
};

// As primeiras pessoas de cada tipo garantem o desenho: cada empresa "com
// cliente" ganha um cliente e cada "só com gente" ganha alguém que não é
// cliente. O resto cai ao acaso (cliente só em empresa "com cliente").
const empresaDeCadaPessoa = (plano, empresasBase) => {
  const sorteio = sorteioFixo(SEMENTES.empresas);
  const comCliente = empresasBase.filter(e => e.papel === 'com_cliente');
  const soGente = empresasBase.filter(e => e.papel === 'so_gente');
  const comGente = [...comCliente, ...soGente];
  const vistos = { cliente: 0, outro: 0 };
  const proximaDaFila = (tipo, fila) => {
    const ordem = vistos[tipo];
    vistos[tipo] += 1;
    return ordem < fila.length ? fila[ordem] : null;
  };
  return Array.from({ length: TOTAL_DE_PESSOAS }, (_, i) => {
    const garantida = plano.ehCliente.has(i)
      ? proximaDaFila('cliente', comCliente)
      : proximaDaFila('outro', soGente);
    if (garantida) return garantida;
    if (plano.ehCliente.has(i)) {
      return sorteio() < CHANCE_DE_CLIENTE_TER_EMPRESA
        ? escolher(sorteio, comCliente)
        : null;
    }
    return sorteio() < CHANCE_DE_OUTRO_TER_EMPRESA
      ? escolher(sorteio, comGente)
      : null;
  });
};

const maiorDataOuNull = datas => {
  const validas = datas.filter(Boolean);
  return validas.length ? Math.max(...validas) : null;
};

const empresaCompleta = (empresaBase, pessoasDela) => {
  const { papel, ...empresa } = empresaBase;
  return {
    ...empresa,
    contacts_count: pessoasDela.length,
    customers_count: pessoasDela.filter(p => p.contact_type === 'customer')
      .length,
    last_activity_at: maiorDataOuNull(pessoasDela.map(p => p.last_activity_at)),
  };
};

const montarBase = agora => {
  const plano = planejarPessoas(agora);
  const empresasBase = esqueletoDasEmpresas(agora);
  const empresaDaPessoa = empresaDeCadaPessoa(plano, empresasBase);
  const listaDePessoas = Array.from({ length: TOTAL_DE_PESSOAS }, (_, i) =>
    pessoaDoPlano(plano, agora, i, empresaDaPessoa)
  );
  const listaDeEmpresas = empresasBase.map(base =>
    empresaCompleta(
      base,
      listaDePessoas.filter(p => p.company_id === base.id)
    )
  );
  return { pessoas: listaDePessoas, empresas: listaDeEmpresas };
};

export const pessoas = (agora = Date.now()) => montarBase(agora).pessoas;

export const empresas = (agora = Date.now()) => montarBase(agora).empresas;

export const pessoaPorId = (id, agora = Date.now()) =>
  pessoas(agora).find(pessoa => pessoa.id === id) ?? null;

export const empresaPorId = (id, agora = Date.now()) =>
  empresas(agora).find(empresa => empresa.id === id) ?? null;
