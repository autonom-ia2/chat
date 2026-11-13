# Os três passos que param e esperam alguém responder (#2931, #2935, #2936, épico #2414): "Pedir aprovação" (a equipe
# responde no painel), "Marcar reunião pela conversa" e "Pesquisa de satisfação" (o cliente responde na conversa). Um
# mecanismo só para os três (EsperaDeResposta, no Executor): o passo pergunta, a execução espera até o prazo e segue
# pelo galho da resposta, ou pelo galho "sem resposta" quando o prazo vence. Aqui fica o que é comum: os galhos de cada
# um, a classe que pergunta e entende a resposta, o prazo e a conferência ao salvar.
#
# Ao salvar (a Receita chama `problemas_ao_salvar`):
# - os três só com a flag `automacao_passos_novos` (fica desligada em produção até o motor dos seis passos estar
#   completo, exceção registrada em docs/2414-prototipos/passos-novos.md);
# - a reunião e a pesquisa mandam mensagem (a flag da F4) e a IA entende a resposta (a flag da F7). Nunca lista de
#   palavras: quem entende o que o cliente escreveu é a IA;
# - quem aprova ou em qual agenda: a pessoa e o time são da conta; "quem cuida do card" precisa de card ou conversa;
# - a reunião e a pesquisa precisam de conversa (gatilho de conversa ou de card) e o modelo da janela fechada existe na
#   conta, como na mensagem;
# - a reunião, das páginas de agendamento ligadas e de quem salva poder lê-las (`agendamento_view`, como o link da
#   agenda, G44);
# - a pesquisa, com a nota média de pelo menos uma nota (a tela avisa a faixa vazia; a Receita recusa);
# - o texto do pedido de aprovação passa pela régua dos valores (Receita::Leitura), como o texto da mensagem.
module Autonomia::Automacao::PassosQueEsperam
  APROVACAO = 'pedir_aprovacao'.freeze
  REUNIAO = 'marcar_reuniao'.freeze
  PESQUISA = 'pesquisa_nota'.freeze

  # Os galhos de cada passo, na ordem do Confira. O último é o de quando ninguém responde no prazo.
  RAMOS = {
    APROVACAO => %w[aprovado recusado ninguem_respondeu],
    REUNIAO => %w[outro_horario nao_respondeu],
    PESQUISA => %w[nota_baixa nota_media nota_alta nao_respondeu]
  }.freeze
  TIPOS = RAMOS.keys.freeze
  # Os que esperam o cliente: a mensagem nova dele acorda a execução (Escuta). A aprovação acorda pelo painel.
  DO_CLIENTE = [REUNIAO, PESQUISA].freeze
  # Onde fica o prazo de cada um.
  PRAZO = { APROVACAO => 'prazo', REUNIAO => 'espera', PESQUISA => 'espera' }.freeze
  # Alvos com conversa: a reunião e a pesquisa perguntam nela.
  COM_CONVERSA = ['Conversation', ::Autonomia::Automacao::Gatilhos::CARD].freeze
  AGENDA = 'agendamento_view'.freeze

  module_function

  def do_tipo?(passo) = passo.is_a?(Hash) && TIPOS.include?(passo['tipo'])

  def espera_o_cliente?(passo) = passo.is_a?(Hash) && DO_CLIENTE.include?(passo['tipo'])

  def todos_os_ramos = RAMOS.values.flatten.uniq

  def sem_resposta(passo) = RAMOS.fetch(passo['tipo']).last

  def prazo(passo) = passo[PRAZO.fetch(passo['tipo'])]

  def classe(passo)
    { APROVACAO => ::Autonomia::Automacao::PassoDeAprovacao, REUNIAO => ::Autonomia::Automacao::PassoDeReuniao,
      PESQUISA => ::Autonomia::Automacao::PassoDePesquisa }.fetch(passo['tipo'])
  end

  # A flag que falta para o passo rodar agora, como motivo do histórico; nil quando pode.
  def desligado(passo, conta)
    return 'passos_novos_desligados' unless ::Autonomia::Automacao::Motor.passos_novos?(conta)
    return unless espera_o_cliente?(passo)
    return 'mensagens_desligadas' unless ::Autonomia::Automacao::Motor.mensagens?(conta)

    'ia_desligada' unless ::Autonomia::Automacao::Motor.ia?(conta)
  end

  # `alvo`: o tipo do registro em que o passo roda (Receita#alvo). `leitura`: (caminho) → problemas, a régua da Receita.
  def problemas_ao_salvar(passo, conta:, account_user:, alvo:, &leitura)
    id = passo['id']
    [*flags(passo, conta), *quem(passo, conta, alvo), *conversa(passo, conta, alvo), *proprios(passo, conta, account_user),
     *::Autonomia::Automacao::Texto.caminhos(passo['pergunta']).flat_map(&leitura)].map { |chave, dados| frase(chave, passo: id, **dados.to_h) }
  end

  def flags(passo, conta)
    return [[:passos_novos_desligados]] unless ::Autonomia::Automacao::Motor.passos_novos?(conta)
    return [] unless espera_o_cliente?(passo)
    return [[:passo_desligado]] unless ::Autonomia::Automacao::Motor.mensagens?(conta)

    ::Autonomia::Automacao::Motor.ia?(conta) ? [] : [[:ia_desligada]]
  end

  # A pessoa e o time da conta; "quem cuida do card" só onde há card ou conversa. A pesquisa não escolhe ninguém.
  def quem(passo, conta, alvo)
    return [] if passo['tipo'] == PESQUISA

    escolha = passo['quem'] || passo['com']
    case escolha['de']
    when 'pessoa', 'time' then de_fora(conta, escolha)
    else COM_CONVERSA.include?(alvo) ? [] : [[:quem_sem_responsavel]]
    end
  end

  # A pessoa ou o time escolhido não é desta conta.
  def de_fora(conta, escolha)
    daqui = escolha['de'] == 'pessoa' ? conta.users : conta.teams
    daqui.exists?(id: escolha['id']) ? [] : [[:"#{escolha['de']}_de_fora", { id: escolha['id'] }]]
  end

  def conversa(passo, conta, alvo)
    return [] unless espera_o_cliente?(passo)
    return [[:espera_resposta_sem_conversa]] unless COM_CONVERSA.include?(alvo)

    ::Autonomia::Automacao::ModeloWhatsapp.problemas_ao_salvar(conta, passo['id'], passo['modelo']).map { |texto| [:texto, { texto: texto }] }
  end

  def proprios(passo, conta, account_user)
    case passo['tipo']
    when REUNIAO then agenda(conta, account_user)
    when PESQUISA then passo['baixa_ate'] + 1 < passo['alta_desde'] ? [] : [[:pesquisa_faixa_media_vazia]]
    else []
    end
  end

  # As páginas de agendamento (G44): ligadas na conta e lidas por quem salva. Sem pessoa (o catálogo), só a conta.
  def agenda(conta, account_user)
    return [[:reuniao_sem_agenda]] unless ::Crm::Config.booking_v2_enabled?(conta)
    return [] if account_user.nil? || account_user.permission_granted?(AGENDA)

    [[:reuniao_sem_permissao]]
  end

  # O problema que já veio em frase (o modelo, a leitura) passa como está.
  def frase(chave, **valores)
    return valores[:texto] if chave == :texto
    return chave if chave.is_a?(String)

    I18n.t("autonomia.automacao.receita.#{chave}", **valores)
  end
end
