// #2894 — os dados fictícios da ficha de Relacionamentos. Só é carregado no
// ambiente de desenvolvimento (fonte/fichaFonte.js, `import.meta.env.DEV`).
//
// Conversas, cards, notas, arquivos e origem saem do id da pessoa, sempre iguais
// (demo/sorteioFixo.js). Quem nunca conversou não tem conversa nem arquivo; quem é
// cliente tem ao menos um card ganho. Os textos são inventados e neutros.
// As escritas ficam na memória deste módulo para a tela refletir o que foi feito,
// e devolvem uma cópia nova: nada que chega é alterado.
import { empresaPorId, pessoaPorId, pessoas } from './base';
import { sorteioFixo } from './sorteioFixo';
import { DIA_EM_MS } from '../fonte/grupos';
import { semAcento } from '../fonte/texto';

const SEGUNDOS_POR_DIA = DIA_EM_MS / 1000;
const SEMENTE_BASE = 1009;
const MAXIMO_DE_CONVERSAS = 6;
const MAXIMO_DE_NOTAS = 4;
const MAXIMO_DE_ARQUIVOS = 5;
const MAXIMO_DE_CARDS_DE_NAO_CLIENTE = 2;
const MAXIMO_DE_CARDS_DE_CLIENTE = 3;
const MULTIPLO_DO_VALOR = 50;
const VALOR_MINIMO = 300;
const VALOR_MAXIMO = 12_000;
const MAIOR_INTERVALO_ENTRE_CONVERSAS_EM_DIAS = 20;
const TOTAL_DE_PESSOAS_NA_FILA_DA_EMPRESA = 10;
const NOME_DE_QUEM_ESCREVE = 'Você';

const CANAIS = ['whatsapp', 'whatsapp', 'email', 'instagram', 'site'];
const TRECHOS = [
  'Oi, tudo bem? Queria saber os horários de atendimento.',
  'Obrigado pelo retorno! Vou olhar e te aviso.',
  'Pode me mandar o endereço de novo, por favor?',
  'Combinado, então fico no aguardo.',
  'Consegue me ligar amanhã de manhã?',
  'Recebi o material, ficou ótimo.',
  'Posso trocar a data que a gente combinou?',
  'Já resolvi aqui, pode fechar o assunto.',
  'Bom dia! Chegou o que eu pedi?',
  'Perfeito, muito obrigada pela ajuda.',
];
const SITUACOES_DA_ULTIMA = ['aberta', 'pendente', 'resolvida'];
const TITULOS_DE_CARD = [
  'Plano mensal',
  'Pedido de orçamento',
  'Renovação do contrato',
  'Visita agendada',
  'Troca de produto',
  'Pacote para a equipe',
  'Reforma da recepção',
];
const FUNIS = [
  { nome: 'Vendas', etapas: ['Novo', 'Em contato', 'Proposta', 'Fechamento'] },
  { nome: 'Atendimento', etapas: ['Recebido', 'Em análise', 'Resolvido'] },
];
const SITUACOES_DE_CARD_SEM_GANHO = ['aberto', 'aberto', 'perdido'];
const TEXTOS_DE_NOTA = [
  'Pediu retorno na próxima semana.',
  'Prefere conversar pelo WhatsApp, à tarde.',
  'Indicou um amigo que também quer conhecer.',
  'Está comparando com outro fornecedor. Vale acompanhar.',
];
const IDADE_DAS_NOTAS_EM_DIAS = [3, 35, 125, 200];
const AUTORES_DE_NOTA = [
  'Sônia Guedelha',
  'Tiago Brandolim',
  'Marina Esteveira',
];
const ARQUIVOS = [
  { nome: 'foto-da-fachada.jpg', tipo: 'imagem' },
  { nome: 'comprovante.pdf', tipo: 'documento' },
  { nome: 'audio-do-pedido.ogg', tipo: 'audio' },
  { nome: 'planilha-de-itens.xlsx', tipo: 'documento' },
  { nome: 'video-do-local.mp4', tipo: 'video' },
];
const LISTAS_DE_ORIGEM = ['Clientes 2025', 'Feira de maio', 'Indicações'];
const CANAIS_DE_ORIGEM = ['whatsapp', 'instagram', 'site', 'email'];
const CAMPOS_EXTRAS = [
  ['melhor_horario', ['Manhã', 'Tarde', 'Fim do dia']],
  ['como_prefere_ser_chamado', null],
];
const PERFIS_DAS_REDES = ['instagram', 'linkedin'];
const CHANCE_DE_TER_CADA_INFORMACAO_DA_CONTA = 0.7;
const CHANCE_DE_TER_CADA_REDE = 0.3;

// ---- memória das escritas ---------------------------------------------------

const memoria = {
  edicoes: new Map(),
  empresas: new Map(),
  clientes: new Map(),
  liberadas: new Set(),
  notas: new Map(),
  proximaNota: 1,
};

export const esquecerEscritas = () => {
  memoria.edicoes.clear();
  memoria.empresas.clear();
  memoria.clientes.clear();
  memoria.liberadas.clear();
  memoria.notas.clear();
  memoria.proximaNota = 1;
};

// ---- geração a partir do id -------------------------------------------------

const copia = valor => JSON.parse(JSON.stringify(valor));
const sorteioDe = (id, sal) => sorteioFixo(SEMENTE_BASE * sal + id);
const escolher = (sorteio, lista) =>
  lista[Math.floor(sorteio() * lista.length)];
const agoraEmSegundos = () => Math.floor(Date.now() / 1000);

const informacoesDaConta = pessoa => {
  const sorteio = sorteioDe(pessoa.id, 3);
  const primeiroNome = pessoa.name.split(' ')[0];
  return Object.fromEntries(
    CAMPOS_EXTRAS.filter(
      () => sorteio() < CHANCE_DE_TER_CADA_INFORMACAO_DA_CONTA
    ).map(([chave, opcoes]) => [
      chave,
      opcoes ? escolher(sorteio, opcoes) : primeiroNome,
    ])
  );
};

// Rede social não tem acento. Instagram: "@fabio.23"; LinkedIn, em outro
// formato: "fabio-figueirao".
const USUARIO_DA_REDE = {
  instagram: pessoa =>
    `@${semAcento(pessoa.name.split(' ')[0]).toLowerCase()}.${pessoa.id}`,
  linkedin: pessoa =>
    semAcento(pessoa.name).toLowerCase().split(' ').filter(Boolean).join('-'),
};

const redesDaPessoa = pessoa => {
  const sorteio = sorteioDe(pessoa.id, 5);
  return Object.fromEntries(
    PERFIS_DAS_REDES.filter(() => sorteio() < CHANCE_DE_TER_CADA_REDE).map(
      rede => [rede, USUARIO_DA_REDE[rede](pessoa)]
    )
  );
};

const comExtras = pessoa => ({
  ...pessoa,
  custom_attributes: {
    ...pessoa.custom_attributes,
    ...informacoesDaConta(pessoa),
  },
  additional_attributes: {
    ...pessoa.additional_attributes,
    social_profiles: redesDaPessoa(pessoa),
  },
});

const comEscritas = pessoa => {
  const editada = { ...pessoa, ...memoria.edicoes.get(pessoa.id) };
  const cliente = memoria.clientes.get(pessoa.id);
  const comCliente = cliente
    ? { ...editada, contact_type: 'customer', customer_since: cliente }
    : editada;
  return memoria.liberadas.has(pessoa.id)
    ? { ...comCliente, opted_out_at: null, opt_out_source: null }
    : comCliente;
};

const pessoaCompleta = base => copia(comEscritas(comExtras(base)));

export const pessoa = id => {
  const base = pessoaPorId(id);
  return base ? pessoaCompleta(base) : null;
};

export const conversas = id => {
  const base = pessoaPorId(id);
  if (!base?.last_activity_at) return [];
  const sorteio = sorteioDe(id, 7);
  const quantas = 1 + (id % MAXIMO_DE_CONVERSAS);
  let quando = base.last_activity_at;
  return Array.from({ length: quantas }, (_, i) => {
    const conversa = {
      id: id * 100 + i,
      canal: escolher(sorteio, CANAIS),
      trecho: escolher(sorteio, TRECHOS),
      quando,
      situacao: i === 0 ? escolher(sorteio, SITUACOES_DA_ULTIMA) : 'resolvida',
    };
    const intervalo = 1 + sorteio() * MAIOR_INTERVALO_ENTRE_CONVERSAS_EM_DIAS;
    quando -= Math.floor(intervalo * SEGUNDOS_POR_DIA);
    return conversa;
  });
};

const cardDe = (id, i, sorteio, situacao, titulo) => {
  const funil = escolher(sorteio, FUNIS);
  const passos = funil.etapas.length;
  const valor = VALOR_MINIMO + sorteio() * (VALOR_MAXIMO - VALOR_MINIMO);
  return {
    id: id * 100 + i,
    titulo,
    funil: funil.nome,
    etapa: situacao === 'ganho' ? funil.etapas[passos - 1] : funil.etapas[0],
    valor: Math.round(valor / MULTIPLO_DO_VALOR) * MULTIPLO_DO_VALOR,
    situacao,
  };
};

export const cards = id => {
  const base = pessoaPorId(id);
  if (!base) return [];
  const sorteio = sorteioDe(id, 11);
  const cliente = pessoaCompleta(base).contact_type === 'customer';
  const quantos = cliente
    ? 1 + (id % MAXIMO_DE_CARDS_DE_CLIENTE)
    : id % (MAXIMO_DE_CARDS_DE_NAO_CLIENTE + 1);
  // Títulos em sequência a partir de um sorteado: nenhum se repete na pessoa.
  const inicio = Math.floor(sorteio() * TITULOS_DE_CARD.length);
  return Array.from({ length: quantos }, (_, i) =>
    cardDe(
      id,
      i,
      sorteio,
      cliente && i === 0
        ? 'ganho'
        : escolher(sorteio, SITUACOES_DE_CARD_SEM_GANHO),
      TITULOS_DE_CARD[(inicio + i) % TITULOS_DE_CARD.length]
    )
  );
};

const notasDeBase = id => {
  const sorteio = sorteioDe(id, 13);
  const base = pessoaPorId(id);
  const quantas = id % (MAXIMO_DE_NOTAS + 1);
  const agora = agoraEmSegundos();
  return Array.from({ length: quantas }, (_, i) => ({
    id: `base-${id}-${i}`,
    autor: escolher(sorteio, AUTORES_DE_NOTA),
    // Datas variadas (há 3 dias, mês passado, há 4 meses...), sempre depois de
    // a pessoa chegar.
    quando: Math.max(
      (base?.created_at ?? agora) + (i + 1) * SEGUNDOS_POR_DIA,
      agora -
        IDADE_DAS_NOTAS_EM_DIAS[i % IDADE_DAS_NOTAS_EM_DIAS.length] *
          SEGUNDOS_POR_DIA
    ),
    texto: TEXTOS_DE_NOTA[(id + i) % TEXTOS_DE_NOTA.length],
  }));
};

export const notas = id =>
  copia(
    [...(memoria.notas.get(id) ?? []), ...notasDeBase(id)].sort(
      (a, b) => b.quando - a.quando
    )
  );

export const arquivos = id => {
  const base = pessoaPorId(id);
  if (!base?.last_activity_at) return [];
  return Array.from({ length: id % (MAXIMO_DE_ARQUIVOS + 1) }, (_, i) => ({
    id: id * 100 + i,
    ...ARQUIVOS[(id + i) % ARQUIVOS.length],
    quando: base.last_activity_at - i * SEGUNDOS_POR_DIA,
  }));
};

export const origem = id => {
  const base = pessoaPorId(id);
  if (!base) return null;
  const sorteio = sorteioDe(id, 17);
  return id % 3 === 0
    ? {
        tipo: 'lista',
        nome: escolher(sorteio, LISTAS_DE_ORIGEM),
        quando: base.created_at,
      }
    : {
        tipo: 'canal',
        canal: escolher(sorteio, CANAIS_DE_ORIGEM),
        quando: base.created_at,
      };
};

// ---- escritas (só na memória) -----------------------------------------------

const exigir = id => {
  const base = pessoaPorId(id);
  if (!base)
    throw Object.assign(new Error('Pessoa não encontrada.'), {
      name: 'NAO_ACHEI',
    });
  return base;
};

export const salvar = (id, dados) => {
  const base = exigir(id);
  const mesmaEmpresa =
    dados.additional_attributes?.company_name ===
    base.additional_attributes?.company_name;
  memoria.edicoes.set(id, {
    name: dados.name,
    email: dados.email,
    phone_number: dados.phone_number,
    additional_attributes: copia(dados.additional_attributes ?? {}),
    custom_attributes: copia(dados.custom_attributes ?? {}),
    company_id: mesmaEmpresa ? base.company_id : null,
  });
  return pessoa(id);
};

export const marcarCliente = id => {
  exigir(id);
  memoria.clientes.set(id, agoraEmSegundos());
  return pessoa(id);
};

export const guardarNota = (id, texto) => {
  exigir(id);
  const nota = {
    id: `nova-${memoria.proximaNota}`,
    autor: NOME_DE_QUEM_ESCREVE,
    quando: agoraEmSegundos(),
    texto,
  };
  memoria.proximaNota += 1;
  memoria.notas.set(id, [nota, ...(memoria.notas.get(id) ?? [])]);
  return copia(nota);
};

export const liberarMensagens = id => {
  exigir(id);
  memoria.liberadas.add(id);
  return pessoa(id);
};

// ---- empresa ----------------------------------------------------------------

export const empresa = id => {
  const base = empresaPorId(id);
  return base ? copia({ ...base, ...memoria.empresas.get(id) }) : null;
};

export const salvarEmpresa = (id, dados) => {
  if (!empresaPorId(id))
    throw Object.assign(new Error('Empresa não encontrada.'), {
      name: 'NAO_ACHEI',
    });
  memoria.empresas.set(id, {
    name: dados.name,
    cnpj: dados.cnpj,
    domain: dados.domain,
  });
  return empresa(id);
};

const pessoasDaEmpresaBase = id =>
  pessoas().filter(item => item.company_id === id);

export const pessoasDaEmpresa = id =>
  pessoasDaEmpresaBase(id).map(item => pessoaCompleta(item));

const doMaisNovoAoMaisAntigo = campo => (a, b) => b[campo] - a[campo];

export const conversasDaEmpresa = id =>
  pessoasDaEmpresaBase(id)
    .flatMap(item =>
      conversas(item.id).map(conversa => ({ ...conversa, pessoa: item.name }))
    )
    .sort(doMaisNovoAoMaisAntigo('quando'))
    .slice(0, TOTAL_DE_PESSOAS_NA_FILA_DA_EMPRESA);

export const cardsDaEmpresa = id =>
  pessoasDaEmpresaBase(id).flatMap(item =>
    cards(item.id).map(card => ({ ...card, pessoa: item.name }))
  );

export const demoDaFicha = {
  pessoa,
  conversas,
  cards,
  notas,
  arquivos,
  origem,
  salvar,
  salvarEmpresa,
  marcarCliente,
  guardarNota,
  liberarMensagens,
  empresa,
  pessoasDaEmpresa,
  conversasDaEmpresa,
  cardsDaEmpresa,
};
