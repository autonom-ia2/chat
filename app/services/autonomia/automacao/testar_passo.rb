# "Testar este passo" (#2500 C2, D6 A): um passo de IA do rascunho roda numa conversa de verdade e mostra o que faria.
# Nada é feito: não cria nota, mensagem, execução nem registro, não toca o AntiLaco nem a Cadeia, não manda nada pelo
# ActionCable e não enfileira job. O único registro é o uso da IA (Crm::AiUsageEvent, feature `automacao_testar`, com o
# aviso dele à Gestão IA): a chamada é paga na chave da conta, e a Gestão IA mostra.
#
# - Só "decidir", "escrever" e "resumir". O "extrair" fica fora: gravar é o que ele faz, e o teste não grava (D6).
# - O texto que vai à IA é o da execução: o `consulta` de cada passo e a mesma leitura (`le`).
# - As conversas são escolhidas aqui, nunca pela tela: as que o ensaio diz que entrariam, entre as que quem pede
#   enxerga. Sem nenhuma, as mais recentes que ela enxerga, com o aviso. Gatilho que não é de conversa (card) também
#   vai às recentes, com o aviso próprio.
# - Uma conversa por pedido: o Rack::Timeout corta a requisição aos 15 s, e cada chamada tem até TEMPO no cliente HTTP
#   (abrir e ler), sem nova tentativa. O 1º pedido escolhe as candidatas, roda a primeira e devolve os ids; os seguintes
#   mandam `conversa_id`, que vale só se quem pede enxerga a conversa (como o "Ensaiar em outra conversa"); fora disso,
#   RecordNotFound, sem chamar a IA. Assim a lista não muda entre os pedidos.
# - A IA lê o que o passo declara em `le`, da conversa escolhida, que quem pede enxerga. O esquema da receita não aceita
#   `card` em `le`: o card, o valor dele e o formulário do anúncio nunca vão à IA de uma automação. Se `card` entrar na
#   lista (o gatilho de card da F6 querendo ler o card), o teste passa a ler como quem pede, junto: Crm::CardPolicy,
#   Crm::ValorDeVenda.ve_o_card? e, sem Crm::AnuncioDeOrigem.ve_no_contexto?, só a data do formulário (Funções, C2).
#
# O texto da conversa e a resposta nunca vão para o log. Sem teto de uso: o "até 3" é o tamanho do teste (D6).
class Autonomia::Automacao::TestarPasso
  TIPOS = {
    'decidir' => ::Autonomia::Automacao::PassoDeDecidir, 'escrever' => ::Autonomia::Automacao::PassoDeEscrever,
    'resumir' => ::Autonomia::Automacao::PassoDeResumir
  }.freeze
  CONVERSAS = 3
  TEMPO = 12
  FEATURE = 'automacao_testar'.freeze
  MAX_MOTIVO = ::Autonomia::Automacao::PassoDeDecidir::MAX_MOTIVO

  # O teste não pode rodar; `chave` é a frase em autonomia.automacao.testar.
  class Recusa < StandardError
    attr_reader :chave

    def initialize(chave)
      super(chave)
      @chave = chave
    end
  end

  # `account_user` é quem pede, na conta: dele saem a pessoa e o que ela enxerga.
  def initialize(receita:, passo_id:, conta:, account_user:, conversa_id: nil)
    @receita = receita
    passos = ::Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: account_user).passos
    @passo = passos.find { |passo| passo['id'] == passo_id.to_s }
    @conta = conta
    @account_user = account_user
    @usuario = account_user.user
    @conversa_id = conversa_id.presence
  end

  # Sem `conversa_id`: { conversa:, candidatas: [ids], aviso: }. Com ele: { conversa: }. A conversa é
  # { conversa_id, nome, resultado | motivo, custo_usd? }. Levanta Recusa ou RecordNotFound.
  def resultado(com_valores:)
    classe = TIPOS[@passo&.dig('tipo')]
    raise Recusa, 'passo_nao_testavel' if classe.nil?
    raise Recusa, 'ia_nao_configurada' unless ia(classe).configurada?
    return { conversa: rodar(classe, visiveis.find_by!(display_id: @conversa_id), com_valores) } if @conversa_id

    conversas, aviso = escolhidas
    raise Recusa, 'sem_conversa' if conversas.empty?

    { conversa: rodar(classe, conversas.first, com_valores), candidatas: conversas.map(&:display_id), aviso: aviso }
  end

  private

  def ia(classe, modelo = classe::MODELO)
    ::Autonomia::Automacao::PassoDeIa.new(conta: @conta, feature: FEATURE, modelo: modelo)
  end

  def escolhidas
    return [recentes, 'gatilho_sem_conversa'] unless ::Autonomia::Automacao::Ensaio.gatilho_suportado?(@receita)

    entrariam = ::Autonomia::Automacao::Ensaio.new(receita: @receita, conta: @conta, usuario: @usuario).entrariam(CONVERSAS)
    entrariam.any? ? [entrariam, nil] : [recentes, 'nenhuma_entraria']
  end

  def visiveis
    ::Conversations::PermissionFilterService.new(@conta.conversations, @usuario, @conta, for_reading: true).perform
  end

  def recentes
    visiveis.includes(:contact).reorder(last_activity_at: :desc, id: :desc).limit(CONVERSAS).to_a
  end

  def rodar(classe, conversa, com_valores)
    base = { conversa_id: conversa.display_id, nome: conversa.contact&.name }
    estado = leitura(conversa)
    return base.merge(motivo: 'nada_para_ler') if estado.vazio?

    consulta = classe.consulta(@passo, estado)
    resposta, custo = ia(classe, consulta[:modelo]).perguntar(instrucoes: consulta[:instrucoes], entrada: consulta[:entrada],
                                                              schema: consulta[:schema], tempo: TEMPO)
    base.merge(resultado: para_tela(resposta)).merge(com_valores ? { custo_usd: custo['custo_usd'] } : {})
  rescue ::Autonomia::Automacao::PassoDeIa::Falha => e
    base.merge(motivo: e.motivo)
  end

  # O valor do card só com a chave de quem pede (#2597), a mesma regra do Valores; o anúncio de origem também (#2558).
  def leitura(conversa)
    ::Autonomia::Decisores::Estado.new(conversation: conversa, leituras: ::Autonomia::Automacao::ComIa.leituras(@passo),
                                       valor_do_card: ::Autonomia::Automacao::Valores.pode_ler?('card.valor', @account_user),
                                       anuncio: ::Crm::AnuncioDeOrigem.ve?(@account_user))
  end

  def para_tela(resposta)
    case @passo['tipo']
    when 'decidir' then { caminho: resposta['caminho'], motivo: resposta['motivo'].to_s.squish.first(MAX_MOTIVO) }
    when 'escrever' then { texto: resposta['texto'].to_s.strip }
    else { texto: resposta['resumo'].to_s.strip }
    end
  end
end
