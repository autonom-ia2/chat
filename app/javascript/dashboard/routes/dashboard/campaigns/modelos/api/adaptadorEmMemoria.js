// Adaptador FALSO, em memória, da tela de Modelos do WhatsApp. Serve para
// aprovar a experiência antes do backend. Os dados vivem enquanto a página está
// aberta; recarregar volta ao começo. Formato: ver ./modelosWhatsapp.js.
//
// Para mostrar os estados vazios na demonstração: ?demo=vazio (sem modelos) ou
// ?demo=sem_numero (nenhum número do WhatsApp oficial conectado).

import { criarComIA, melhorarComIA } from './iaFalsa';

const ESPERA_MS = 250;
const HORA_MS = 60 * 60 * 1000;
const DIA_MS = 24 * HORA_MS;

const esperar = valor =>
  new Promise(resolve => {
    setTimeout(() => resolve(JSON.parse(JSON.stringify(valor))), ESPERA_MS);
  });

const cenario = () =>
  new URLSearchParams(window.location.search).get('demo') || '';

const daquiA = ms => new Date(Date.now() + ms).toISOString();

const NUMEROS = [
  {
    id: 41,
    nome: 'Atendimento Hub2You',
    telefone: '+55 11 4000-0001',
    conta: { id: 'conta_principal', nome: 'Hub2you' },
    situacao: 'conectada',
  },
  {
    id: 42,
    nome: 'Vendas Hub2You',
    telefone: '+55 11 4000-0002',
    conta: { id: 'conta_principal', nome: 'Hub2you' },
    situacao: 'conectada',
  },
  {
    id: 57,
    nome: 'Hub2You Filial Sul',
    telefone: '+55 51 4000-0003',
    conta: { id: 'conta_filial', nome: 'Hub2you Filial Sul' },
    situacao: 'conectada',
  },
  {
    id: 61,
    nome: 'Loja Centro',
    telefone: '+55 31 4000-0005',
    conta: { id: 'conta_centro', nome: 'Hub2you Centro' },
    situacao: 'conectada',
  },
  {
    id: 58,
    nome: 'Hub2You Recife',
    telefone: '+55 81 4000-0004',
    conta: { id: 'conta_principal', nome: 'Hub2you' },
    situacao: 'reconectar',
  },
];

const texto = v => ({ t: 'texto', v });
const campo = v => ({ t: 'campo', v });

const MODELOS_INICIAIS = [
  {
    id: '1048213377610211',
    nome: 'Segunda via do boleto',
    nomeNoWhatsapp: 'segunda_via_do_boleto',
    objetivo: 'cobranca',
    biblioteca: false,
    idioma: 'pt_BR',
    situacao: 'recusado',
    tipo: 'aviso',
    tipoMudouPeloWhatsapp: false,
    numeros: [41, 42],
    conteudo: {
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Olá, '),
        campo('nome_cliente'),
        texto('. A segunda via do seu boleto de '),
        campo('valor'),
        texto(' está pronta: '),
        campo('link'),
      ],
      exemplos: {
        nome_cliente: 'Ana',
        valor: 'R$ 189,90',
        link: 'hub2you.com.br/b/123',
      },
      rodape: '',
      botoes: [],
    },
    recusa: { codigo: 'campo_no_fim' },
    pausa: null,
    enviosNoMes: 0,
    enviadoEm: daquiA(-5 * HORA_MS),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
  {
    id: '1048213377610212',
    nome: 'Retomar conversa',
    nomeNoWhatsapp: 'retomar_conversa',
    objetivo: 'retomar',
    biblioteca: false,
    idioma: 'pt_BR',
    situacao: 'pausado',
    tipo: 'divulgacao',
    tipoMudouPeloWhatsapp: false,
    numeros: [42, 41],
    conteudo: {
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto(
          '! Ficou alguma dúvida da nossa última conversa? É só responder aqui que a gente continua.'
        ),
      ],
      exemplos: { nome_cliente: 'Carlos' },
      rodape: '',
      botoes: [{ tipo: 'resposta', texto: 'Quero continuar', valor: '' }],
    },
    recusa: null,
    pausa: { desde: daquiA(-2 * HORA_MS) },
    enviosNoMes: 2310,
    enviadoEm: daquiA(-40 * DIA_MS),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
  {
    id: '1048213377610213',
    nome: 'Promoção de fim de mês',
    nomeNoWhatsapp: 'promocao_de_fim_de_mes',
    objetivo: 'promocao',
    biblioteca: false,
    idioma: 'pt_BR',
    situacao: 'em_analise',
    tipo: 'divulgacao',
    tipoMudouPeloWhatsapp: false,
    numeros: [42, 41],
    conteudo: {
      topo: { tipo: 'foto', arquivo: 'oferta-outubro.jpg' },
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto('! Só até '),
        campo('data'),
        texto(': '),
        campo('desconto'),
        texto(' de desconto em toda a loja. Quer aproveitar?'),
      ],
      exemplos: { nome_cliente: 'Ana', data: '31/10', desconto: '20%' },
      rodape: '',
      botoes: [
        {
          tipo: 'site',
          texto: 'Ver ofertas',
          valor: 'https://hub2you.com.br/ofertas',
        },
      ],
    },
    recusa: null,
    pausa: null,
    enviosNoMes: 0,
    enviadoEm: daquiA(-12 * 60 * 1000),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
  {
    id: '1048213377610214',
    nome: 'Pesquisa de satisfação',
    nomeNoWhatsapp: 'pesquisa_satisfacao_v2',
    objetivo: 'pesquisa',
    biblioteca: true,
    idioma: 'pt_BR',
    situacao: 'pronto',
    tipo: 'aviso',
    tipoMudouPeloWhatsapp: false,
    numeros: [41, 42],
    conteudo: {
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Olá, '),
        campo('nome_cliente'),
        texto(
          '! Como foi o seu atendimento com a gente? Sua opinião ajuda muito.'
        ),
      ],
      exemplos: { nome_cliente: 'Ana' },
      rodape: '',
      botoes: [
        { tipo: 'resposta', texto: 'Ótimo', valor: '' },
        { tipo: 'resposta', texto: 'Bom', valor: '' },
        { tipo: 'resposta', texto: 'Pode melhorar', valor: '' },
      ],
    },
    recusa: null,
    pausa: null,
    enviosNoMes: 412,
    enviadoEm: daquiA(-60 * DIA_MS),
    edicoes: { restantesNoMes: 9, liberadaEm: null },
  },
  {
    id: '1048213377610215',
    nome: 'Lembrete de agendamento',
    nomeNoWhatsapp: 'lembrete_agendamento',
    objetivo: 'lembrete',
    biblioteca: true,
    idioma: 'pt_BR',
    situacao: 'pronto',
    tipo: 'aviso',
    tipoMudouPeloWhatsapp: false,
    numeros: [41, 42],
    conteudo: {
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Olá, '),
        campo('nome_cliente'),
        texto('! Passando para lembrar do seu horário em '),
        campo('data'),
        texto(', às '),
        campo('horario'),
        texto('. Podemos confirmar?'),
      ],
      exemplos: { nome_cliente: 'Ana', data: '15/10', horario: '14h30' },
      rodape: '',
      botoes: [
        { tipo: 'resposta', texto: 'Confirmo', valor: '' },
        { tipo: 'resposta', texto: 'Preciso remarcar', valor: '' },
      ],
    },
    recusa: null,
    pausa: null,
    enviosNoMes: 863,
    enviadoEm: daquiA(-90 * DIA_MS),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
  {
    id: '1048213377610216',
    nome: 'Confirmação de pedido',
    nomeNoWhatsapp: 'confirmacao_pedido',
    objetivo: 'em_branco',
    biblioteca: false,
    idioma: 'pt_BR',
    situacao: 'pronto',
    tipo: 'divulgacao',
    tipoMudouPeloWhatsapp: true,
    numeros: [57],
    conteudo: {
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto(
          '! Recebemos o seu pedido. Aproveite e veja as novidades da semana na nossa loja.'
        ),
      ],
      exemplos: { nome_cliente: 'Bruno' },
      rodape: '',
      botoes: [],
    },
    recusa: null,
    pausa: null,
    enviosNoMes: 97,
    enviadoEm: daquiA(-20 * DIA_MS),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
  {
    id: '1048213377610218',
    nome: 'Novidades da semana',
    nomeNoWhatsapp: 'novidades_da_semana',
    objetivo: 'carrossel',
    biblioteca: false,
    idioma: 'pt_BR',
    situacao: 'pronto',
    tipo: 'divulgacao',
    tipoMudouPeloWhatsapp: false,
    numeros: [42, 41],
    conteudo: {
      formato: 'carrossel',
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Oi, '),
        campo('nome_cliente'),
        texto('! Separamos as novidades da semana para você:'),
      ],
      exemplos: { nome_cliente: 'Ana' },
      rodape: '',
      botoes: [],
      cartoes: [
        {
          midia: 'foto',
          arquivo: 'tenis-corrida.jpg',
          texto: 'Tênis de corrida leve, do 34 ao 44.',
          botoes: [
            {
              tipo: 'site',
              texto: 'Ver produto',
              valor: 'https://hub2you.com.br/p/1',
            },
          ],
        },
        {
          midia: 'foto',
          arquivo: 'mochila.jpg',
          texto: 'Mochila resistente à água, com bolso para notebook.',
          botoes: [
            {
              tipo: 'site',
              texto: 'Ver produto',
              valor: 'https://hub2you.com.br/p/2',
            },
          ],
        },
        {
          midia: 'video',
          arquivo: 'garrafa.mp4',
          texto: 'Garrafa térmica que mantém gelado por 24 horas.',
          botoes: [
            {
              tipo: 'site',
              texto: 'Ver produto',
              valor: 'https://hub2you.com.br/p/3',
            },
          ],
        },
      ],
    },
    recusa: null,
    pausa: null,
    enviosNoMes: 530,
    enviadoEm: daquiA(-15 * DIA_MS),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
  {
    id: '1048213377610217',
    nome: 'Boas-vindas',
    nomeNoWhatsapp: 'boas_vindas_v1',
    objetivo: 'boas_vindas',
    biblioteca: false,
    idioma: 'pt_BR',
    situacao: 'pronto',
    tipo: 'divulgacao',
    tipoMudouPeloWhatsapp: false,
    numeros: [41, 42],
    conteudo: {
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Olá, '),
        campo('nome_cliente'),
        texto('! Que bom ter você com a gente na '),
        campo('nome_empresa'),
        texto('. Pode contar com a gente por aqui sempre que precisar.'),
      ],
      exemplos: { nome_cliente: 'Ana', nome_empresa: 'Hub2you' },
      rodape: '',
      botoes: [{ tipo: 'resposta', texto: 'Quero saber mais', valor: '' }],
    },
    recusa: null,
    pausa: null,
    enviosNoMes: 1240,
    enviadoEm: daquiA(-120 * DIA_MS),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
];

const FORMULARIOS = [
  { id: 'f1', nome: 'Cadastro de novo cliente' },
  { id: 'f2', nome: 'Pedido de orçamento' },
  { id: 'f3', nome: 'Agendar visita' },
];

// Modelos que a própria plataforma usa (agendamento, Anúncios, satisfação):
// selo "Usado pelo sistema", não se alteram nem se apagam; duplicar pode.
const MODELOS_DO_SISTEMA = [
  {
    id: '1048213377610219',
    nome: 'Resumo de anúncios',
    nomeNoWhatsapp: 'chat2you_resumo_anuncios',
    objetivo: 'em_branco',
    biblioteca: false,
    sistema: true,
    idioma: 'pt_BR',
    situacao: 'pronto',
    tipo: 'aviso',
    tipoMudouPeloWhatsapp: false,
    conta: 'conta_principal',
    numeros: [41, 42],
    conteudo: {
      formato: 'padrao',
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Olá, '),
        campo('nome_cliente'),
        texto('. Seus anúncios trouxeram '),
        campo('valor'),
        texto(' contatos ontem. O resumo completo está no painel.'),
      ],
      exemplos: { nome_cliente: 'Ana', valor: '37' },
      rodape: '',
      botoes: [],
    },
    recusa: null,
    pausa: null,
    enviosNoMes: 30,
    enviadoEm: daquiA(-200 * DIA_MS),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
  {
    id: '1048213377610220',
    nome: 'Alerta de anúncio',
    nomeNoWhatsapp: 'chat2you_alerta_anuncio',
    objetivo: 'em_branco',
    biblioteca: false,
    sistema: true,
    idioma: 'pt_BR',
    situacao: 'pronto',
    tipo: 'aviso',
    tipoMudouPeloWhatsapp: false,
    conta: 'conta_principal',
    numeros: [41, 42],
    conteudo: {
      formato: 'padrao',
      topo: { tipo: 'nenhum', arquivo: '' },
      texto: [
        texto('Olá, '),
        campo('nome_cliente'),
        texto(
          '. Um anúncio parou de trazer contatos. Vale olhar o painel hoje.'
        ),
      ],
      exemplos: { nome_cliente: 'Ana' },
      rodape: '',
      botoes: [],
    },
    recusa: null,
    pausa: null,
    enviosNoMes: 4,
    enviadoEm: daquiA(-200 * DIA_MS),
    edicoes: { restantesNoMes: 10, liberadaEm: null },
  },
];

// Os que o sistema usa entre os iniciais: pesquisa de satisfação e lembrete do
// agendamento.
const SISTEMA = ['1048213377610214', '1048213377610215'];
const CONTA_DA_FILIAL = ['1048213377610216'];

// Onde cada modelo está em uso. `agendado`: ainda vai sair (bloqueia apagar).
// `rota`: onde a pessoa resolve (nomes de rota reais do painel).
const USOS = {
  1048213377610214: [
    {
      tipo: 'campanha',
      nome: 'Pesquisa pós-atendimento de outubro',
      quando: 'agendada para 20/10',
      agendado: true,
      rota: { name: 'campaigns_journey_index' },
    },
    {
      tipo: 'satisfacao',
      nome: 'Pesquisa enviada ao fim de cada atendimento',
      agendado: true,
      rota: { name: 'settings_inbox_list' },
    },
    {
      tipo: 'crm',
      nome: 'Follow-up do funil Vendas, etapa "Atendimento concluído"',
      agendado: false,
      rota: { name: 'crm_kanban_index' },
    },
  ],
  1048213377610215: [
    {
      tipo: 'agendamento',
      nome: 'Aviso 1 dia antes do horário',
      agendado: true,
      rota: { name: 'settings_booking' },
    },
  ],
  1048213377610217: [
    {
      tipo: 'campanha',
      nome: 'Boas-vindas para novos contatos',
      quando: 'agendada para 18/10',
      agendado: true,
      rota: { name: 'campaigns_journey_index' },
    },
  ],
  1048213377610213: [
    {
      tipo: 'campanha',
      nome: 'Queima de estoque',
      quando: 'agendada para 31/10',
      agendado: true,
      rota: { name: 'campaigns_journey_index' },
    },
  ],
  1048213377610219: [
    {
      tipo: 'anuncios',
      nome: 'Resumo diário dos anúncios',
      agendado: true,
      rota: { name: 'campaigns_meta_ads_index' },
    },
  ],
  1048213377610220: [
    {
      tipo: 'anuncios',
      nome: 'Alerta quando um anúncio para',
      agendado: true,
      rota: { name: 'campaigns_meta_ads_index' },
    },
  ],
};

// Campanhas que pararam por causa do modelo (conferência no disparo).
// motivo: modelo_pausado | modelo_recusado | modelo_mudou | tipo_mudou.
const CAMPANHAS_PARADAS = [
  {
    id: 3107,
    nome: 'Reativar clientes de setembro',
    modeloId: '1048213377610212',
    modeloNome: 'Retomar conversa',
    motivo: 'modelo_pausado',
  },
  {
    id: 3112,
    nome: 'Lembrete de pagamento de outubro',
    modeloId: '1048213377610211',
    modeloNome: 'Segunda via do boleto',
    motivo: 'modelo_recusado',
  },
];

// Custo por envio, em reais. VALORES FICTÍCIOS só para o protótipo: o preço real
// vem da tabela da Meta para o Brasil e muda com o tempo.
const CUSTO_POR_ENVIO = { aviso: 0.035, divulgacao: 0.32, codigo: 0.03 };

let modelos = [
  ...MODELOS_INICIAIS.map(modelo => ({
    ...modelo,
    sistema: SISTEMA.includes(modelo.id),
    conta: CONTA_DA_FILIAL.includes(modelo.id)
      ? 'conta_filial'
      : 'conta_principal',
    nomeNoWhatsapp:
      {
        1048213377610214: 'pesquisa_satisfacao',
        1048213377610215: 'agendamento_lembrete_1_dia',
      }[modelo.id] || modelo.nomeNoWhatsapp,
    conteudo: { formato: 'padrao', ...modelo.conteudo },
  })),
  ...MODELOS_DO_SISTEMA,
];
// Ids no formato da Meta: um número longo, em texto.
let proximoId = 1048213377610300;

// "Pesquisa de satisfação" → "pesquisa_de_satisfacao", sem expressão regular.
const nomeParaWhatsapp = nome =>
  nome
    .normalize('NFD')
    .split('')
    .filter(letra => letra.charCodeAt(0) < 0x300 || letra.charCodeAt(0) > 0x36f)
    .join('')
    .toLowerCase()
    .split('')
    .map(letra =>
      'abcdefghijklmnopqrstuvwxyz0123456789'.includes(letra) ? letra : '_'
    )
    .join('')
    .split('_')
    .filter(Boolean)
    .join('_');

const achar = id => {
  const modelo = modelos.find(item => item.id === String(id));
  if (!modelo) throw new Error('modelo_nao_encontrado');
  return modelo;
};

const contaDoNumero = id => NUMEROS.find(numero => numero.id === id)?.conta.id;

export default {
  // Números conectados (para Modelos). Os que precisam reconectar ficam de fora.
  listarNumeros() {
    return esperar(
      cenario() === 'sem_numero'
        ? []
        : NUMEROS.filter(numero => numero.situacao === 'conectada')
    );
  },

  // Caixas do WhatsApp oficial para a campanha, inclusive as que precisam
  // reconectar (aparecem desativadas, com o motivo).
  listarCaixasDaCampanha() {
    return esperar(cenario() === 'sem_numero' ? [] : NUMEROS);
  },

  listarModelos() {
    return esperar(['vazio', 'sem_numero'].includes(cenario()) ? [] : modelos);
  },

  obterModelo(id) {
    return esperar(achar(id));
  },

  ondeEstaEmUso(id) {
    return esperar(USOS[String(id)] || []);
  },

  listarCampanhasParadas() {
    return esperar(
      CAMPANHAS_PARADAS.filter(campanha =>
        modelos.some(modelo => modelo.id === campanha.modeloId)
      )
    );
  },

  custoPorEnvio(tipo) {
    return esperar({ valor: CUSTO_POR_ENVIO[tipo] ?? 0, moeda: 'BRL' });
  },

  // Um modelo por conta do WhatsApp: números de contas diferentes viram
  // modelos diferentes, cada um com a sua análise. Devolve a lista criada.
  criarModelo(rascunho) {
    const contas = [...new Set(rascunho.numeros.map(contaDoNumero))];
    const novos = contas.map(conta => {
      proximoId += 1;
      return {
        id: String(proximoId),
        nome: rascunho.nome,
        nomeNoWhatsapp: nomeParaWhatsapp(rascunho.nome),
        objetivo: rascunho.objetivo,
        biblioteca: rascunho.biblioteca,
        sistema: false,
        idioma: 'pt_BR',
        situacao: 'em_analise',
        tipo: rascunho.tipo,
        tipoMudouPeloWhatsapp: false,
        conta,
        numeros: rascunho.numeros.filter(id => contaDoNumero(id) === conta),
        conteudo: rascunho.conteudo,
        recusa: null,
        pausa: null,
        enviosNoMes: 0,
        enviadoEm: new Date().toISOString(),
        edicoes: { restantesNoMes: 10, liberadaEm: null },
      };
    });
    modelos = [...novos, ...modelos];
    return esperar(novos);
  },

  alterarModelo(id, rascunho) {
    const atual = achar(id);
    if (atual.sistema) throw new Error('modelo_do_sistema');
    const eraAprovado = atual.situacao === 'pronto';
    const alterado = {
      ...atual,
      nome: rascunho.nome,
      conteudo: rascunho.conteudo,
      situacao: 'em_analise',
      recusa: null,
      pausa: null,
      enviadoEm: new Date().toISOString(),
      edicoes: eraAprovado
        ? {
            restantesNoMes: atual.edicoes.restantesNoMes - 1,
            liberadaEm: daquiA(DIA_MS),
          }
        : atual.edicoes,
    };
    modelos = modelos.map(item => (item.id === atual.id ? alterado : item));
    return esperar(alterado);
  },

  apagarModelo(id) {
    const atual = achar(id);
    if (atual.sistema) throw new Error('modelo_do_sistema');
    if ((USOS[atual.id] || []).some(uso => uso.agendado)) {
      throw new Error('modelo_em_uso');
    }
    modelos = modelos.filter(item => item.id !== atual.id);
    return esperar({ nomeBloqueadoAte: daquiA(30 * DIA_MS) });
  },

  // Catálogo de produtos conectado à conta do WhatsApp (null quando não há).
  obterCatalogo() {
    return esperar(
      cenario() === 'sem_catalogo'
        ? null
        : { nome: 'Loja Hub2you', produtos: 48 }
    );
  },

  // Formulários (Flows) que já existem na conta do WhatsApp.
  listarFormularios() {
    return esperar(cenario() === 'sem_formulario' ? [] : FORMULARIOS);
  },

  criarComIA,
  melhorarComIA,
};
