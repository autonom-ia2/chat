// #2894 — os dados fictícios da ficha de Relacionamentos. Só é carregado no
// ambiente de desenvolvimento (fonte/fichaFonte.js, `import.meta.env.DEV`).
//
// Conversas, cards, notas, arquivos e origem saem do id da pessoa, sempre iguais
// (demo/sorteioFixo.js). Quem nunca conversou não tem conversa nem arquivo; quem é
// cliente tem ao menos um card ganho. Os textos são inventados e neutros.
// As escritas ficam na memória deste módulo para a tela refletir o que foi feito,
// e devolvem uma cópia nova: nada que chega é alterado.
import {
  apagarEmpresaDaDemo,
  empresaPorId,
  empresas,
  esquecerEmpresasApagadas,
  pessoaPorId,
  pessoas,
} from './base';
import { sorteioFixo } from './sorteioFixo';
import { DIA_EM_MS } from '../fonte/grupos';
import { normalizado, semAcento } from '../fonte/texto';
import { ETIQUETAS as ETIQUETAS_DA_CONTA } from './acoesDaLista';

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
  'Valeu pelo retorno! Vou olhar e te aviso.',
  'Pode me mandar o endereço de novo, por favor?',
  'Combinado, então fico no aguardo.',
  'Consegue me ligar amanhã de manhã?',
  'Recebi o material, ficou ótimo.',
  'Posso trocar a data que a gente combinou?',
  'Já resolvi aqui, pode fechar o assunto.',
  'Bom dia! Chegou o que eu pedi?',
  'Perfeito, ajudou muito.',
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
  'Sônia Valtorini',
  'Tiago Zanquetta',
  'Marina Pavanelli',
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
  // #3071 — as ações que vieram da ficha antiga.
  bloqueios: new Map(),
  recusas: new Map(),
  etiquetas: new Map(),
  notasApagadas: new Set(),
  apagadas: new Set(),
  // id de quem ficou -> ids de quem foi absorvido.
  juntadas: new Map(),
  // #3078 — a empresa de cada pessoa depois de pôr ou tirar (null: sem
  // empresa). As empresas apagadas ficam em demo/base.js, que a lista lê.
  vinculos: new Map(),
};

export const esquecerEscritas = () => {
  memoria.edicoes.clear();
  memoria.empresas.clear();
  memoria.clientes.clear();
  memoria.liberadas.clear();
  memoria.notas.clear();
  memoria.proximaNota = 1;
  memoria.bloqueios.clear();
  memoria.recusas.clear();
  memoria.etiquetas.clear();
  memoria.notasApagadas.clear();
  memoria.apagadas.clear();
  memoria.juntadas.clear();
  memoria.vinculos.clear();
  esquecerEmpresasApagadas();
};

// Quem foi absorvido por esta pessoa num "Juntar", e quem os absorvidos já tinham absorvido.
const absorvidas = id =>
  (memoria.juntadas.get(id) ?? []).flatMap(outra => [
    outra,
    ...absorvidas(outra),
  ]);
const daPessoaEDasAbsorvidas = (id, ler) =>
  [id, ...absorvidas(id)].flatMap(cada => ler(cada));

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

// Rede social não tem acento. Instagram: "@fabio.figueirao" (sem número de id);
// LinkedIn, em outro formato: "fabio-figueirao".
const USUARIO_DA_REDE = {
  instagram: pessoa =>
    `@${semAcento(pessoa.name).toLowerCase().split(' ').filter(Boolean).join('.')}`,
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

// `memoria.clientes` guarda desde quando a pessoa é cliente, ou `null` para quem
// deixou de ser (inclusive quem já era cliente nos dados de base). Quem não
// está lá fica como veio da base.
const marcaDeCliente = id => {
  if (!memoria.clientes.has(id)) return {};
  const desde = memoria.clientes.get(id);
  return desde
    ? { contact_type: 'customer', customer_since: desde }
    : { contact_type: 'lead', customer_since: null };
};

const empresaDaPessoa = pessoa =>
  memoria.vinculos.has(pessoa.id)
    ? memoria.vinculos.get(pessoa.id)
    : pessoa.company_id;

const comEscritas = pessoa => {
  const comCliente = {
    ...pessoa,
    company_id: empresaDaPessoa(pessoa),
    ...memoria.edicoes.get(pessoa.id),
    ...marcaDeCliente(pessoa.id),
  };
  const id = pessoa.id;
  const extras = {
    ...(memoria.bloqueios.has(id) && { blocked: memoria.bloqueios.get(id) }),
    ...(memoria.etiquetas.has(id) && { labels: memoria.etiquetas.get(id) }),
  };
  if (memoria.recusas.has(id)) {
    return {
      ...comCliente,
      ...extras,
      opted_out_at: memoria.recusas.get(id),
      opt_out_source: 'manual',
    };
  }
  return memoria.liberadas.has(id)
    ? { ...comCliente, ...extras, opted_out_at: null, opt_out_source: null }
    : { ...comCliente, ...extras };
};

const pessoaCompleta = base => copia(comEscritas(comExtras(base)));

export const pessoa = id => {
  const base = memoria.apagadas.has(id) ? null : pessoaPorId(id);
  return base ? pessoaCompleta(base) : null;
};

const conversasSo = id => {
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

export const conversas = id =>
  daPessoaEDasAbsorvidas(id, conversasSo).sort((a, b) => b.quando - a.quando);

const cardsSo = id => {
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

export const cards = id => daPessoaEDasAbsorvidas(id, cardsSo);

// #3097 — o resumo de compras da demonstração: sai do id, como o resto. Só o
// cliente comprou; o costume só existe com 2 compras ou mais.
const COMPRAS_NO_MAXIMO = 6;
const DIAS_DA_ULTIMA_NO_MAXIMO = 220;
const VALOR_BASE_DA_COMPRA = 300;
export const compras = id => {
  const base = pessoaPorId(id);
  if (!base || pessoaCompleta(base).contact_type !== 'customer') return null;
  const quantas = 1 + (id % COMPRAS_NO_MAXIMO);
  const dias = (id * 17) % DIAS_DA_ULTIMA_NO_MAXIMO;
  const total = quantas * (VALOR_BASE_DA_COMPRA + (id % 9) * 120);
  return {
    quantas,
    ultima_em: agoraEmSegundos() - dias * SEGUNDOS_POR_DIA,
    intervalo_medio_dias: quantas > 1 ? 20 + (id % 5) * 10 : null,
    por_moeda: [{ moeda: 'BRL', total, quantas }],
  };
};

const notasSo = id => [...(memoria.notas.get(id) ?? []), ...notasDeBase(id)];

export const notas = id =>
  copia(
    daPessoaEDasAbsorvidas(id, notasSo)
      .filter(nota => !memoria.notasApagadas.has(nota.id))
      .sort((a, b) => b.quando - a.quando)
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

// #3075 — `pedido` é o da gaveta (ficha/informacoes.js#pedidoParaSalvar): os
// campos que saem saem, a empresa escolhida vem com o id e a nova fica só com o
// nome (a demonstração não cadastra empresa). A foto nova aparece pela prévia.
const fotoDoPedido = foto => {
  if (foto?.arquivo) return { thumbnail: foto.previa };
  if (foto?.tirar) return { thumbnail: '' };
  return {};
};

export const salvar = (id, { contato, empresaNova, foto, apagar = [] }) => {
  exigir(id);
  const atual = pessoa(id);
  const atributos = Object.entries({
    ...atual.custom_attributes,
    ...contato.custom_attributes,
  }).filter(([chave]) => !apagar.includes(chave));
  const empresaId =
    'company_id' in contato ? contato.company_id : atual.company_id;
  memoria.edicoes.set(id, {
    name: contato.name,
    email: contato.email,
    phone_number: contato.phone_number,
    additional_attributes: copia({
      ...atual.additional_attributes,
      ...contato.additional_attributes,
    }),
    custom_attributes: copia(Object.fromEntries(atributos)),
    company_id: empresaNova ? null : empresaId,
    ...fotoDoPedido(foto),
  });
  return pessoa(id);
};

const TOTAL_DE_EMPRESAS_NA_BUSCA = 8;

export const buscarEmpresas = termo =>
  empresas()
    .filter(item => normalizado(item.name).includes(normalizado(termo)))
    .slice(0, TOTAL_DE_EMPRESAS_NA_BUSCA)
    .map(item => ({ id: item.id, nome: item.name }));

export const marcarCliente = id => {
  exigir(id);
  memoria.clientes.set(id, agoraEmSegundos());
  return pessoa(id);
};

export const desmarcarCliente = id => {
  exigir(id);
  memoria.clientes.set(id, null);
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

// #3071 — as ações que vieram da ficha antiga.
export const marcarNaoQuer = id => {
  exigir(id);
  memoria.liberadas.delete(id);
  memoria.recusas.set(id, agoraEmSegundos());
  return pessoa(id);
};

// "Liberar" também desfaz a marca feita aqui.
export const liberarMensagensDepoisDeMarcar = id => {
  memoria.recusas.delete(id);
  return liberarMensagens(id);
};

const trocarBloqueio = (id, bloqueada) => {
  exigir(id);
  memoria.bloqueios.set(id, bloqueada);
  return pessoa(id);
};
export const bloquear = id => trocarBloqueio(id, true);
export const desbloquear = id => trocarBloqueio(id, false);

export const apagar = id => {
  exigir(id);
  memoria.apagadas.add(id);
};

export const etiquetasDaConta = () => copia(ETIQUETAS_DA_CONTA);

// Como o servidor (AlterarEtiquetasConcern): tira e põe sobre a lista que está
// gravada, sem diferenciar maiúscula.
export const alterarEtiquetas = (id, { por = [], tirar = [] }) => {
  const atual = (pessoa(id) ?? exigir(id)).labels ?? [];
  const tiradas = new Set(tirar.map(nome => nome.toLowerCase()));
  const ficam = atual.filter(nome => !tiradas.has(nome.toLowerCase()));
  const ja = new Set(ficam.map(nome => nome.toLowerCase()));
  const novas = por.filter(nome => {
    const chave = nome.toLowerCase();
    if (ja.has(chave)) return false;
    ja.add(chave);
    return true;
  });
  memoria.etiquetas.set(id, [...ficam, ...novas]);
  return pessoa(id);
};

export const apagarNota = (id, notaId) => {
  exigir(id);
  memoria.notasApagadas.add(notaId);
};

const LIMITE_DA_BUSCA = 8;
export const buscarPessoas = (termo, semId) => {
  const procurado = semAcento(termo).toLowerCase();
  return pessoas()
    .filter(item => item.id !== semId && !memoria.apagadas.has(item.id))
    .filter(item =>
      [item.name, item.email, item.phone_number]
        .filter(Boolean)
        .some(valor => semAcento(valor).toLowerCase().includes(procurado))
    )
    .slice(0, LIMITE_DA_BUSCA)
    .map(item => pessoaCompleta(item));
};

// A pessoa da ficha fica; a outra some, e o que era da outra passa para cá.
export const juntar = (id, outraId) => {
  const fica = pessoa(id) ?? exigir(id);
  const sai = pessoa(outraId) ?? exigir(outraId);
  memoria.apagadas.add(outraId);
  memoria.juntadas.set(id, [...(memoria.juntadas.get(id) ?? []), outraId]);
  memoria.etiquetas.set(id, [
    ...new Set([...(fica.labels ?? []), ...(sai.labels ?? [])]),
  ]);
  return pessoa(id);
};

// ---- empresa ----------------------------------------------------------------

// #3078 — a empresa da demonstração ganha o que a ficha antiga de Empresas
// tinha: a descrição e os campos da conta (os de `porte` e `ramo`), para a
// metade delas.
const PORTES = ['Pequena', 'Média', 'Grande'];
const RAMOS = ['Alimentação', 'Serviços', 'Comércio', 'Saúde'];
const DESCRICOES = [
  'Atende o bairro há mais de dez anos. Compra todo mês.',
  'Prefere falar com a gerência pelo WhatsApp, de manhã.',
];

const extrasDaEmpresa = base => {
  if (base.id % 2) return { description: null, custom_attributes: {} };
  const sorteio = sorteioDe(base.id, 19);
  return {
    description: escolher(sorteio, DESCRICOES),
    custom_attributes: {
      porte: escolher(sorteio, PORTES),
      ramo: escolher(sorteio, RAMOS),
    },
  };
};

const pessoasDaEmpresaBase = id =>
  pessoas()
    .filter(item => !memoria.apagadas.has(item.id))
    .filter(item => empresaDaPessoa(item) === id);

export const empresa = id => {
  const base = empresaPorId(id);
  if (!base) return null;
  const gente = pessoasDaEmpresaBase(id).map(item => pessoaCompleta(item));
  return copia({
    ...base,
    ...extrasDaEmpresa(base),
    contacts_count: gente.length,
    customers_count: gente.filter(item => item.contact_type === 'customer')
      .length,
    ...memoria.empresas.get(id),
  });
};

const exigirEmpresa = id => {
  if (!empresa(id))
    throw Object.assign(new Error('Empresa não encontrada.'), {
      name: 'NAO_ACHEI',
    });
};

// O pedido da gaveta (ficha/informacoesDaEmpresa.js#pedidoDaEmpresa). A foto
// nova aparece pela prévia; "tirar" deixa as iniciais.
export const salvarEmpresa = (
  id,
  { empresa: dados, foto, apagar: queSaem = [] }
) => {
  exigirEmpresa(id);
  const atual = empresa(id);
  const atributos = Object.fromEntries(
    Object.entries({
      ...atual.custom_attributes,
      ...dados.custom_attributes,
    }).filter(([chave]) => !queSaem.includes(chave))
  );
  const thumbnail = foto?.tirar ? '' : (foto?.previa ?? atual.thumbnail);
  memoria.empresas.set(id, {
    name: dados.name,
    domain: dados.domain,
    description: dados.description,
    cnpj: dados.additional_attributes.cnpj,
    city: dados.additional_attributes.city,
    custom_attributes: atributos,
    thumbnail,
  });
  return empresa(id);
};

// Na demonstração a empresa sai na hora, como a pequena no servidor.
export const apagarEmpresa = id => {
  exigirEmpresa(id);
  apagarEmpresaDaDemo(id);
  return { naFila: false };
};

export const pessoasDaEmpresa = id =>
  pessoasDaEmpresaBase(id).map(item => pessoaCompleta(item));

// As notas das pessoas da empresa, das mais novas para trás (as 20 primeiras,
// como no servidor), com de quem é cada uma.
const NOTAS_DA_EMPRESA = 20;
export const notasDaEmpresa = id =>
  pessoasDaEmpresaBase(id)
    .flatMap(item =>
      notas(item.id).map(nota => ({
        ...nota,
        pessoa: { id: item.id, nome: item.name },
      }))
    )
    .sort((a, b) => b.quando - a.quando)
    .slice(0, NOTAS_DA_EMPRESA);

const MIDIAS_DA_EMPRESA = 5;
export const midiasDaEmpresa = id => {
  const todas = pessoasDaEmpresaBase(id)
    .flatMap(item =>
      arquivos(item.id).map(arquivo => ({ ...arquivo, pessoa: item.name }))
    )
    .sort((a, b) => b.quando - a.quando);
  return { itens: todas.slice(0, MIDIAS_DA_EMPRESA), total: todas.length };
};

// Quem pode entrar: quem não está nesta empresa, pelo nome, telefone ou e-mail.
export const buscarPessoasParaEmpresa = (id, termo) => {
  const procurado = normalizado(termo);
  return pessoas()
    .filter(item => !memoria.apagadas.has(item.id))
    .filter(item => empresaDaPessoa(item) !== id)
    .filter(item =>
      [item.name, item.email, item.phone_number].some(campo =>
        normalizado(campo).includes(procurado)
      )
    )
    .slice(0, 15)
    .map(item => {
      const daPessoa = empresaDaPessoa(item);
      const atual = daPessoa ? empresaPorId(daPessoa) : null;
      return {
        id: item.id,
        name: item.name,
        email: item.email,
        phone_number: item.phone_number,
        thumbnail: '',
        empresa: atual ? { id: atual.id, nome: atual.name } : null,
      };
    });
};

export const porPessoaNaEmpresa = (id, pessoaId) => {
  exigirEmpresa(id);
  memoria.vinculos.set(pessoaId, id);
};

export const tirarPessoaDaEmpresa = (id, pessoaId) => {
  exigirEmpresa(id);
  memoria.vinculos.set(pessoaId, null);
};

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
  compras,
  notas,
  arquivos,
  origem,
  salvar,
  salvarEmpresa,
  apagarEmpresa,
  notasDaEmpresa,
  midiasDaEmpresa,
  buscarPessoasParaEmpresa,
  porPessoaNaEmpresa,
  tirarPessoaDaEmpresa,
  marcarCliente,
  desmarcarCliente,
  guardarNota,
  liberarMensagens: liberarMensagensDepoisDeMarcar,
  marcarNaoQuer,
  bloquear,
  desbloquear,
  apagar,
  juntar,
  etiquetasDaConta,
  buscarPessoas,
  buscarEmpresas,
  alterarEtiquetas,
  apagarNota,
  empresa,
  pessoasDaEmpresa,
  conversasDaEmpresa,
  cardsDaEmpresa,
};
