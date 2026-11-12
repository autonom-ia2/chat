# A receita de uma automação (#2414 F3, ADR-001 2.1 e 2.3). O formato mora no esquema
# (lib/operator_guide/automacao-receita.schema.json), que o Versao confere pelo JsonSchemaValidator. Aqui fica o que o
# esquema não sabe dizer, conferido ao salvar:
# - o id de cada passo é único na receita inteira (o cursor da execução aponta para ele);
# - a ação está na lista de permitidas (F3.2) e tem todo parâmetro do caminho;
# - o corpo bate com o formato da ação, como no Guia, e traz o que a automação exige (F3.10), os campos fixos e
#   nenhum campo proibido;
# - o valor calculado no corpo (G16: `$valor`, `$texto`, `$data`) lê caminhos que a automação sabe ler, e a data parte
#   de "hoje" ou de um atributo do tipo data;
# - todo `$valor` do caminho, do corpo e das condições é um caminho que a automação sabe ler;
# - a condição sobre um valor fechado (`mensagem.tipo`) usa uma das opções e um dos operadores dele (#2496);
# - o gatilho de card só com a flag da F6, e a etapa ou o funil escolhidos nele são da conta (#2499);
# - o "esperar até" sem prazo não tem passos em "se vencer", que nunca rodariam (#2750);
# - o "decidir" a cada resposta (G31/G46) repete caminhos dele e deixa um para seguir (DecidirDeNovo);
# - o que o "esperar até" faz enquanto espera (G63, G64): a hora da conferência só sem prazo, o galho "a cada mensagem"
#   só com cliente e fora de outro galho (EnquantoEspera).
class Autonomia::Automacao::Receita
  ESQUEMA = JSON.parse(Rails.root.join('lib/operator_guide/automacao-receita.schema.json').read).freeze
  # `passos`: o ramo do "em outro registro" (G18, #2671), que roda numa execução filha, no registro ligado. `se_recusar`:
  # o do "webhook" (G13), quando o outro sistema recusa.
  RAMOS = %w[entao senao se_vencer a_cada_mensagem se_recusar passos].freeze
  # O "decidir" (F7, #2500) abre um ramo por caminho (`caminhos[].passos`) e o de "nenhum se aplica" (`nenhum`).
  NENHUM = 'nenhum'.freeze
  # Os passos de IA (F7), só com a flag da F7.
  IA = %w[decidir extrair escrever resumir].freeze
  # Onde o extrair pode gravar, além dos atributos do contato e da conversa (`<base>.atributos.<chave>`).
  DESTINOS_FIXOS = %w[contato.nome empresa.nome].freeze
  DESTINOS_DE_ATRIBUTO = %w[contato.atributos conversa.atributos].freeze
  # G70: o campo do card no extrair só onde há card (o alvo ou o da conversa), e nunca o que guarda gente: a pessoa da
  # equipe (G62) e o contato da conta (decisão 16, a âncora do "em outro registro"). A IA não escolhe gente.
  CARD_OU_CONVERSA = %w[Crm::Card Conversation].freeze
  CAMPOS_DE_GENTE = %w[pessoa contato].freeze

  include ::Autonomia::Automacao::Receita::Frase
  # O passo "ação" ao salvar (AcaoNaReceita): a ação da lista, o caminho e o corpo.
  include ::Autonomia::Automacao::AcaoNaReceita

  # As listas de passos que um passo abre, na ordem em que aparecem. É a única travessia da receita: o salvar, o ligar, a
  # chave de funis (sem_funil? do controller) e o Roteiro andam por aqui. Um ramo que ficasse de fora deixaria a ação
  # dentro dele sem conferência.
  def self.ramos(passo)
    caminhos = Array(passo['caminhos']).map { |caminho| caminho['passos'] if caminho.is_a?(Hash) }
    [*RAMOS.map { |ramo| passo[ramo] }, *caminhos, passo[NENHUM]].select { |lista| lista.is_a?(Array) }
  end

  # O JsonSchemaValidator põe o erro na chave de dentro (`gatilho`), não em `receita`; quem segue para a conferência
  # do código pergunta aqui.
  def self.esquema_valido?(receita)
    @esquema ||= JSONSchemer.schema(ESQUEMA)
    @esquema.valid?(JSON.parse(receita.to_json))
  end

  # `account_user`: quem salva ou liga, na conta. Com ele, o valor que pede permissão (Valores::PROTEGIDOS, #2597) só
  # entra se ele pode ler; `nil` explícito (o catálogo, a leitura sem pessoa) não aplica a regra aqui, e a execução
  # continua lendo vazio. Obrigatório, sem padrão: quem monta a Receita diz quem é, e o esquecimento quebra o spec.
  # `alvo`: o tipo do registro em que a receita roda, quando não é o do gatilho: o ramo do "em outro registro" (G18) é
  # conferido como uma receita própria, no registro ligado (EmOutroRegistro.problemas_ao_salvar). `origem`: nesse ramo, o
  # tipo do alvo do gatilho da mãe, que o ramo lê com `origem.*` (G65); fora dele, nil e `origem.*` é recusado.
  def initialize(receita, conta:, account_user:, alvo: nil, origem: nil)
    @receita = receita
    @conta = conta
    @account_user = account_user
    @alvo = alvo
    @origem = origem
  end

  # Frases para a pessoa (ou o Guia) corrigir. Vazio = pode salvar. Só roda com a receita já no esquema.
  def problemas
    [*(@alvo ? [] : ids_repetidos), *gatilho_novo, *conversa_nova, *agenda_de_reserva, *filtros_do_gatilho,
     *do_alvo.flat_map { |passo| problemas_do_passo(passo) },
     *::Autonomia::Automacao::Duracao.sem_prazo_que_vence(do_alvo).map { |id| texto(:sem_prazo_com_se_vencer, passo: id) },
     *::Autonomia::Automacao::EnquantoEspera.problemas_ao_salvar(@receita, do_alvo, alvo)]
  end

  # Todos os passos, inclusive os de dentro dos ramos, na ordem em que aparecem.
  def passos(lista = @receita['passos'])
    Array(lista).flat_map { |passo| [passo, *self.class.ramos(passo).flat_map { |ramo| passos(ramo) }] }
  end

  # Os passos que rodam no alvo desta receita, na mesma execução: o ramo do "em outro registro" roda numa execução filha,
  # no registro ligado, e é conferido lá. O texto da IA (#2679) também só passa entre passos da mesma execução.
  def do_alvo(lista = @receita['passos']) = Array(lista).flat_map { |passo| [passo, *ramos_do_alvo(passo).flat_map { |ramo| do_alvo(ramo) }] }

  def ramos_do_alvo(passo) = ::Autonomia::Automacao::EmOutroRegistro.do_tipo?(passo) ? [] : self.class.ramos(passo)

  private

  def ids_repetidos = passos.pluck('id').tally.select { |_id, vezes| vezes > 1 }.keys.map { |id| texto(:id_repetido, passo: id) }

  # O gatilho de card e o de tempo (#2499): a flag, a etapa, o funil e o campo de data são da conta; no da conta (G7),
  # os passos que ele aceita.
  def gatilho_novo
    ::Autonomia::Automacao::ProblemasDoGatilho.new(@receita['gatilho'].to_h, @conta, passos: passos, account_user: @account_user).problemas
  end

  # A caixa por onde abrir a conversa de quem não tem (#2680): da conta, e quem salva pode começar conversa nela. O ramo
  # do "em outro registro" no card ou contato que um passo criou também não tem conversa (G49).
  def conversa_nova
    ramos = ::Autonomia::Automacao::EmOutroRegistro.alvos_dos_criados(passos, @receita)
    ::Autonomia::Automacao::ConversaNova.problemas_ao_salvar(@conta, @receita['gatilho'].to_h, @account_user, ramos: ramos)
  end

  # G60: a página de agenda de reserva é da conta, e quem salva lê as páginas.
  def agenda_de_reserva = ::Autonomia::Automacao::AgendaDeReserva.problemas_ao_salvar(@conta, @receita['gatilho'].to_h, @account_user)

  def filtros_do_gatilho
    Array(@receita.dig('gatilho', 'filtros')).flat_map { |condicao| condicoes.problemas('gatilho', condicao, no_gatilho: true) }
  end

  def problemas_do_passo(passo)
    return condicoes.problemas(passo['id'], passo['condicao'], na_espera: passo['tipo'] == 'esperar_ate') if passo.key?('condicao')
    return mensagens.problemas(passo) if %w[mensagem avisar email].include?(passo['tipo'])
    return problemas_da_ia(passo) if IA.include?(passo['tipo'])
    return passos_proprios.problemas(passo) if ::Autonomia::Automacao::PassosProprios.do_tipo?(passo)
    return [] unless passo['tipo'] == 'acao'

    problemas_da_acao(passo)
  end

  # Os passos com conferência própria (PassosProprios); os caminhos que eles leem passam pela régua daqui.
  def passos_proprios
    @passos_proprios ||= ::Autonomia::Automacao::PassosProprios.new(conta: @conta, account_user: @account_user, receita: @receita,
                                                                    alvo: alvo, dentro: @alvo.present?) do |id, c, **opcoes|
                                                                      problemas_do_caminho(id, c, **opcoes)
                                                                    end
  end

  # Passos de IA (F7): só com a flag da F7; o que fala com gente (escrever ao cliente, resumir avisando) também com a da
  # F4. Os caminhos e os campos não repetem, e o extrair só grava onde pode.
  def problemas_da_ia(passo)
    id = passo['id']
    [*(::Autonomia::Automacao::Motor.ia?(@conta) ? [] : [texto(:ia_desligada, passo: id)]),
     *(fala_com_gente?(passo) && !::Autonomia::Automacao::Motor.mensagens?(@conta) ? [texto(:passo_desligado, passo: id)] : []),
     *::Autonomia::Automacao::CaminhosDoDecidir.problemas(id, Array(passo['caminhos'])),
     *::Autonomia::Automacao::DecidirDeNovo.problemas_ao_salvar(passo, @receita),
     *repetidos(id, Array(passo['campos']).pluck('chave'), :campo_repetido),
     *Array(passo['campos']).flat_map { |campo| destino_invalido(id, campo['destino']) },
     *destinatarios_de_fora('id' => id, 'para' => avisar_do_resumir(passo))]
  end

  # O destino do resumir é "nota" (texto) ou { avisar: ... }; o do escrever é sempre texto.
  def avisar_do_resumir(passo) = passo['destino'].is_a?(Hash) ? passo['destino']['avisar'] : nil

  def fala_com_gente?(passo)
    (passo['tipo'] == 'escrever' && passo['destino'] == 'mensagem') || (passo['tipo'] == 'resumir' && passo['destino'].is_a?(Hash))
  end

  def repetidos(id, chaves, motivo) = chaves.tally.select { |_chave, vezes| vezes > 1 }.keys.map { |chave| texto(motivo, passo: id, chave: chave) }

  def destino_invalido(id, destino)
    return campo_do_card_invalido(id, destino) if ::Autonomia::Automacao::CardDaConversa.destino_do_card?(destino)

    base = DESTINOS_DE_ATRIBUTO.find { |prefixo| destino.to_s.start_with?("#{prefixo}.") }
    valido = DESTINOS_FIXOS.include?(destino) ||
             (base && destino.to_s.length > base.length + 1 && ::Autonomia::Automacao::Valores.atributo_definido?(destino, @conta))
    valido ? [] : [texto(:destino_invalido, passo: id, destino: destino)]
  end

  # G70 (decisão 20): o extrair preenche um campo personalizado do card (o alvo, o card da conversa ou o que a execução
  # criou), nunca o que guarda gente (CAMPOS_DE_GENTE) e só onde há card: gatilho de card ou de conversa.
  def campo_do_card_invalido(id, destino)
    return [texto(:destino_card_sem_card, passo: id)] unless CARD_OU_CONVERSA.include?(alvo)

    campo_do_card_valido?(destino) ? [] : [texto(:destino_invalido, passo: id, destino: destino)]
  end

  # Sem conta (o catálogo), basta a chave; com ela, o campo do card existe e não guarda gente.
  def campo_do_card_valido?(destino)
    _base, chave = ::Autonomia::Automacao::Valores.atributo(destino)
    return chave.present? if @conta.nil?

    campo = chave.present? && @conta.custom_attribute_definitions.find_by(attribute_model: 'card_attribute', attribute_key: chave)
    campo.present? && CAMPOS_DE_GENTE.exclude?(campo.attribute_display_type)
  end

  def destinatarios_de_fora(passo)
    ::Autonomia::Automacao::DestinatariosDoAviso.new(@conta, alvo).problemas(passo['id'], passo['para'])
  end

  # A régua dos valores (Leitura): a ação, os passos próprios e os textos perguntam aqui.
  def problemas_do_caminho(...) = leitura.problemas(...)

  def leitura = @leitura ||= ::Autonomia::Automacao::Receita::Leitura.new(self, contexto)

  def condicoes = @condicoes ||= ::Autonomia::Automacao::Receita::Condicoes.new(leitura)

  def mensagens = @mensagens ||= ::Autonomia::Automacao::Receita::Mensagens.new(contexto, leitura)

  # O que os validadores recebem (Receita::Contexto).
  def contexto
    @contexto ||= ::Autonomia::Automacao::Receita::Contexto.new(receita: @receita, conta: @conta, account_user: @account_user,
                                                                alvo: alvo, origem: @origem)
  end

  # O tipo do registro em que a receita roda: o do ramo do "em outro registro" (G18), ou o do gatilho.
  def alvo = @alvo || ::Autonomia::Automacao::Gatilhos.alvo(@receita.dig('gatilho', 'tipo'))
end
