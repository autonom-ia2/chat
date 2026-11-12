// #2414 — protótipo dos 6 passos novos da Automação livre (#2931–#2936). O
// servidor ainda não conhece estes passos: o catálogo do editor ganha as
// entradas aqui, só com a flag ligada, e o que viria do servidor sai do
// adaptadorFalso. O Rodrigo aprova a tela antes do motor. O motor, o esquema e o
// salvar de verdade são da implementação.

export const FLAG = 'automacao_passos_novos';
export const P = 'AUTOMACAO_LIVRE.PASSOS_NOVOS';

// Cada passo: a chave dos textos, o grupo do "Adicionar passo", os galhos (na
// ordem em que aparecem no Confira), o ícone e a permissão para montar.
export const PASSOS_NOVOS = {
  pedir_aprovacao: {
    chave: 'APROVACAO',
    grupo: 'EQUIPE',
    ramos: ['aprovado', 'recusado', 'ninguem_respondeu'],
    icone: 'i-lucide-stamp',
  },
  repetir_lista: {
    chave: 'REPETIR',
    grupo: 'CONTROLE',
    ramos: ['cada'],
    icone: 'i-lucide-repeat',
  },
  usar_bloco: {
    chave: 'BLOCO',
    grupo: 'CONTROLE',
    ramos: [],
    icone: 'i-lucide-boxes',
  },
  // #2934: as consultas prontas servem a quem monta automações; só o "Outro
  // endereço" pede a chave de integrações (como o webhook, G13), na peça.
  consultar: {
    chave: 'CONSULTAR',
    grupo: 'OUTRO_SISTEMA',
    ramos: ['nao_consultou'],
    icone: 'i-lucide-search',
  },
  marcar_reuniao: {
    chave: 'REUNIAO',
    grupo: 'MENSAGEM',
    ramos: ['outro_horario', 'nao_respondeu'],
    icone: 'i-lucide-calendar-check',
  },
  pesquisa_nota: {
    chave: 'PESQUISA',
    grupo: 'MENSAGEM',
    ramos: ['nota_baixa', 'nota_media', 'nota_alta', 'nao_respondeu'],
    icone: 'i-lucide-star',
  },
};

export const ehPassoNovo = passo => Boolean(PASSOS_NOVOS[passo?.tipo]);

// #2932–#2934: os que já têm motor salvam, ligam e ensaiam de verdade. Os
// outros três seguem no protótipo (adaptadorFalso) e não salvam.
export const COM_MOTOR = ['repetir_lista', 'usar_bloco', 'consultar'];
export const temMotor = passo => COM_MOTOR.includes(passo?.tipo);
export const emTeste = passo => ehPassoNovo(passo) && !temMotor(passo);
export const chaveDoPasso = tipo => `${P}.${PASSOS_NOVOS[tipo].chave}`;

// Os galhos de cada passo, para a travessia da receita (receita.js, RAMOS).
export const RAMOS_DOS_PASSOS_NOVOS = Object.fromEntries(
  Object.entries(PASSOS_NOVOS)
    .filter(([, passo]) => passo.ramos.length)
    .map(([tipo, passo]) => [tipo, passo.ramos])
);

// A entrada do catálogo: nome por objetivo, uma frase no "Adicionar passo" e uma
// peça só no "Alterar" (LivrePassoNovo), mais os galhos, que ficam no Confira.
const entradaDe = ([tipo, passo]) => ({
  tipo,
  grupo: passo.grupo,
  requer: FLAG,
  ...(passo.permissao && { chave: passo.permissao }),
  frase: `${chaveDoPasso(tipo)}.NOME`,
  dica: `${chaveDoPasso(tipo)}.DICA`,
  campos: [
    { nome: 'passo_novo', peca: 'passo_novo', rotulo: `${P}.MONTAR` },
    ...passo.ramos.map(ramo => ({ nome: ramo, peca: 'passos' })),
  ],
});

// Sem a flag, o catálogo volta o mesmo objeto: nada muda para quem não está no
// protótipo.
export const comPassosNovos = (catalogo, ligado) => {
  if (!ligado || !catalogo?.passos) return catalogo;
  const novos = Object.entries(PASSOS_NOVOS).map(entradaDe);
  return { ...catalogo, passos: [...catalogo.passos, ...novos] };
};

// Começar pronto: cada passo nasce com o que serve à maioria. O que depende da
// conta (a etapa, o bloco, a integração) a peça escolhe ao abrir.
export const PRAZO_PADRAO = { valor: 1, unidade: 'dias' };
export const TETO_PADRAO = 50;
export const TETO_MAXIMO = 200;
export const DURACOES = [15, 30, 45, 60];
export const INTERVALOS = [7, 15, 30, 60, 90];
export const RITMOS = ['aos_poucos', 'rapido'];

const NOVOS = {
  pedir_aprovacao: t => ({
    quem: { de: 'responsavel' },
    pergunta: [t(`${P}.APROVACAO.PERGUNTA_PADRAO`)],
    prazo: { ...PRAZO_PADRAO },
  }),
  repetir_lista: () => ({
    lista: { de: 'etapa', etapa_id: null },
    teto: TETO_PADRAO,
    ritmo: 'aos_poucos',
  }),
  usar_bloco: () => ({ bloco_id: null }),
  consultar: () => ({
    fonte: { de: 'pronta', consulta: null, entradas: {} },
    guardar: [],
  }),
  marcar_reuniao: t => ({
    com: { de: 'responsavel' },
    duracao: 30,
    convite: t(`${P}.REUNIAO.CONVITE_PADRAO`),
    espera: { ...PRAZO_PADRAO },
  }),
  pesquisa_nota: t => ({
    pergunta: t(`${P}.PESQUISA.PERGUNTA_PADRAO`),
    baixa_ate: 6,
    alta_desde: 9,
    intervalo_dias: 30,
    espera: { valor: 2, unidade: 'dias' },
  }),
};

export const novoPassoNovo = (tipo, id, t) => ({
  id,
  tipo,
  ...NOVOS[tipo](t),
});

const escrito = texto => Boolean((texto || '').trim());
const textoEscrito = partes =>
  (partes || []).some(parte => typeof parte !== 'string' || parte.trim());
const prazoPronto = prazo => Number.isInteger(prazo?.valor) && prazo.valor > 0;

// Quem aprova ou atende: quem cuida do card, uma pessoa ou um time.
export const QUEM = ['responsavel', 'pessoa', 'time'];
export const quemPronto = quem =>
  quem?.de === 'responsavel' ||
  (['pessoa', 'time'].includes(quem?.de) && Number.isInteger(quem.id));

// #2934: a consulta pronta escolhida e o que ela pede, cada um dito (a peça
// põe uma entrada para cada coisa que a consulta pede, ao escolher).
export const PRONTA = 'pronta';
export const ENDERECO = 'endereco';
const prontaPronta = fonte => {
  const entradas = Object.values(fonte.entradas || {});
  return (
    Boolean(fonte.consulta) &&
    entradas.length > 0 &&
    entradas.every(textoEscrito)
  );
};

// O endereço próprio do "Consultar": só https. Endereço interno ou privado o
// servidor recusa (SSRF, #2934); a tela não decide isso.
export const enderecoServe = texto => {
  try {
    return new URL(texto).protocol === 'https:';
  } catch {
    return false;
  }
};

// #2936: as três faixas cobrem de 0 a 10 e a do meio tem pelo menos uma nota.
export const faixasProntas = ({ baixa_ate: baixa, alta_desde: alta }) =>
  Number.isInteger(baixa) &&
  Number.isInteger(alta) &&
  baixa >= 0 &&
  alta <= 10 &&
  baixa + 1 < alta;

// #2932: de onde vem a lista (os cards de uma etapa, os contatos com uma
// etiqueta ou os de um público) e o que cada uma pede escolhido.
export const LISTAS = ['etapa', 'etiqueta', 'publico'];
const LISTA_PRONTA = {
  etapa: lista => Number.isInteger(lista.etapa_id),
  etiqueta: lista => escrito(lista.etiqueta),
  publico: lista => Number.isInteger(lista.publico_id),
};
export const listaPronta = lista => Boolean(LISTA_PRONTA[lista?.de]?.(lista));

const PRONTO = {
  pedir_aprovacao: passo =>
    quemPronto(passo.quem) &&
    textoEscrito(passo.pergunta) &&
    prazoPronto(passo.prazo),
  repetir_lista: ({ lista, teto }) =>
    listaPronta(lista) &&
    Number.isInteger(teto) &&
    teto >= 1 &&
    teto <= TETO_MAXIMO,
  usar_bloco: passo => passo.bloco_id != null,
  consultar: ({ fonte, guardar }) =>
    (fonte?.de === ENDERECO
      ? enderecoServe(fonte.url)
      : fonte?.de === PRONTA && prontaPronta(fonte)) &&
    (guardar || []).length > 0 &&
    guardar.every(dado => escrito(dado.nome) && escrito(dado.caminho)),
  marcar_reuniao: passo =>
    quemPronto(passo.com) &&
    DURACOES.includes(passo.duracao) &&
    escrito(passo.convite) &&
    prazoPronto(passo.espera),
  pesquisa_nota: passo =>
    escrito(passo.pergunta) &&
    faixasProntas(passo) &&
    INTERVALOS.includes(passo.intervalo_dias) &&
    prazoPronto(passo.espera),
};

export const passoNovoPronto = passo =>
  ehPassoNovo(passo) && PRONTO[passo.tipo](passo);

// O nome do dado guardado vira a chave do `{{consulta.<chave>}}`: minúsculas,
// sem acento, e o que não é letra nem número vira "_". Sem expressão regular.
const ACENTOS = [0x300, 0x36f];
const letraOuNumero = letra =>
  (letra >= 'a' && letra <= 'z') || (letra >= '0' && letra <= '9');
export const chaveDoNome = nome =>
  Array.from((nome || '').normalize('NFD').toLowerCase())
    .filter(letra => {
      const codigo = letra.charCodeAt(0);
      return codigo < ACENTOS[0] || codigo > ACENTOS[1];
    })
    .map(letra => (letraOuNumero(letra) ? letra : '_'))
    .join('')
    .split('_')
    .filter(Boolean)
    .join('_');

// #2934: cada dado guardado pelo "Consultar" vira um dado dos passos seguintes
// (`consulta.<passo>.<chave>`), com o nome que a pessoa deu, para o "se" e as
// mensagens. Antes de o passo rodar, o dado está vazio e o passo que o lê pula.
export const valoresDaConsulta = passo =>
  (passo.guardar || [])
    .filter(dado => chaveDoNome(dado.nome))
    .map(dado => ({
      caminho: `consulta.${passo.id}.${chaveDoNome(dado.nome)}`,
      chave: `${passo.id}.${chaveDoNome(dado.nome)}`,
      rotulo: dado.nome.trim(),
    }));
