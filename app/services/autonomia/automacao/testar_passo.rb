# "Testar este passo" (#2500 C2, D6 A): um passo de IA do rascunho roda numa conversa de verdade e mostra o que faria.
# Nada é feito: não cria nota, mensagem, execução nem registro, não toca o AntiLaco nem a Cadeia, não manda nada pelo
# ActionCable e não enfileira job. O único registro é o uso da IA (Crm::AiUsageEvent, feature `automacao_testar`, com o
# aviso dele à Gestão IA): a chamada é paga na chave da conta, e a Gestão IA mostra.
#
# - Só "decidir", "escrever" e "resumir". O "extrair" fica fora: gravar é o que ele faz, e o teste não grava (D6).
# - O texto que vai à IA é o da execução: o `consulta` de cada passo e a mesma leitura (`le`), com os anexos (G20).
# - As conversas são escolhidas aqui, nunca pela tela: as que o ensaio diz que entrariam, entre as que quem pede
#   enxerga. Sem nenhuma, as mais recentes que ela enxerga, com o aviso. Gatilho que não é de conversa (card) também
#   vai às recentes, com o aviso próprio.
# - Uma conversa por pedido: o Rack::Timeout corta a requisição aos 15 s, e cada chamada tem até TEMPO no cliente HTTP
#   (abrir e ler), sem nova tentativa. O 1º pedido escolhe as candidatas, roda a primeira e devolve os ids; os seguintes
#   mandam `conversa_id`, que vale só se quem pede enxerga a conversa (como o "Ensaiar em outra conversa"); fora disso,
#   RecordNotFound, sem chamar a IA. Assim a lista não muda entre os pedidos.
# - A IA lê o que o passo declara em `le`, da conversa escolhida, que quem pede enxerga. Com `card` (#2679), o card da
#   conversa vai só se quem pede o vê (Crm::CardPolicy, ComIa.ve_o_card?), o valor só com a chave dele (#2597), e o
#   anúncio de origem nunca, como no passo de verdade: só a data do formulário (Funções, C2). O card é o da conversa
#   escolhida: no gatilho de card, o passo de verdade lê o card do gatilho, que costuma ser esse mesmo.
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

  # `account_user` é quem pede, na conta: dele saem a pessoa e o que ela enxerga. `ligada_por`: quem ligou a automação
  # já salva (nil: nova ou nunca ligada); o valor do card só vai se os dois podem (#2780).
  def initialize(receita:, passo_id:, conta:, account_user:, conversa_id: nil, ligada_por: nil) # rubocop:disable Metrics/ParameterLists
    @receita = receita
    passos = ::Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: account_user).passos
    @passo = passos.find { |passo| passo['id'] == passo_id.to_s }
    @conta = conta
    @account_user = account_user
    @usuario = account_user.user
    @conversa_id = conversa_id.presence
    @ligada_por = ligada_por
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
    anexos = estado.anexos&.partes(modelo: consulta[:modelo]) || []
    resposta, custo = ia(classe, consulta[:modelo]).perguntar(instrucoes: consulta[:instrucoes], entrada: consulta[:entrada],
                                                              schema: consulta[:schema], tempo: TEMPO, anexos: anexos)
    base.merge(resultado: para_tela(resposta)).merge(com_valores ? { custo_usd: custo['custo_usd'] } : {})
  rescue ::Autonomia::Automacao::PassoDeIa::Falha, ::Autonomia::Automacao::AnexosDaConversa::Recusa => e
    base.merge(motivo: e.motivo)
  end

  # O valor do card só com a chave de quem pede (#2597), a mesma regra do Valores, e, no gatilho de conversa, só no
  # "decidir" (#2780). O anúncio de origem nunca (#2558), como no passo de verdade (ComIa.leva_o_valor?).
  # Com `le: anexos` (G20), os anexos da conversa, como no passo de verdade.
  def leitura(conversa)
    leituras = ::Autonomia::Automacao::ComIa.leituras(@passo)
    estado = estado_de(conversa, leituras)
    estado = estado_de(conversa, leituras - ['card']) if leituras.include?('card') && estado.card && !ve_o_card?(estado.card)
    ::Autonomia::Automacao::AnexosDaConversa.leitura(estado, @passo, conversa)
  end

  def estado_de(conversa, leituras)
    ::Autonomia::Decisores::Estado.new(conversation: conversa, leituras: leituras, motivo_da_perda: true,
                                       valor_do_card: leva_o_valor?)
  end

  # O valor vai só se quem testa e quem ligou (quando já há) podem: o teste nunca mostra a quem não pode, nem mais que a
  # execução. Quem ligou e saiu da conta não pode.
  def leva_o_valor?
    pessoas = @ligada_por ? [@account_user, @conta.account_users.find_by(user_id: @ligada_por.id)] : [@account_user]
    pessoas.all? { |pessoa| ::Autonomia::Automacao::ComIa.leva_o_valor?(@passo, @receita.dig('gatilho', 'tipo'), pessoa) }
  end

  def ve_o_card?(card) = ::Autonomia::Automacao::ComIa.ve_o_card?(@usuario, card)

  def para_tela(resposta)
    case @passo['tipo']
    when 'decidir' then { caminho: resposta['caminho'], motivo: resposta['motivo'].to_s.squish.first(MAX_MOTIVO) }
    when 'escrever' then { texto: resposta['texto'].to_s.strip }
    else { texto: resposta['resumo'].to_s.strip }
    end
  end
end
