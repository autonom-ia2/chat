# Os valores que uma receita lê do alvo (#2414 F3, ADR-001 2.3): `{"$valor": "conversa.status"}`.
#
# A lista de caminhos é fechada: a receita só lê o que está aqui, e o salvar recusa caminho desconhecido. Não é Liquid
# nem texto livre; cada caminho é um campo do modelo. Os atributos personalizados entram pela chave
# (`contato.atributos.placa`). A mensagem do gatilho `mensagem.criada` só existe no filtro do gatilho
# (`mensagem.tipo`: recebida, enviada ou nota; `mensagem.privada`; `mensagem.primeira`); nos passos ela já passou, e o
# salvar recusa ler a mensagem fora dali.
#
# #2499 (F6): cada caminho começa pela base (`conversa`, `contato` ou `card`), lida do alvo pelas pontes do Contexto.
# A base que o alvo não alcança (card num gatilho de conversa) o salvar recusa; a ponte vazia ao rodar (card sem
# conversa) chega como valor vazio.
class Autonomia::Automacao::Valores
  # `conversa.id` é o número que a pessoa vê (#123) e o que as rotas da conversa recebem, não o id do banco.
  CAMPOS = {
    'conversa.id' => ->(conversa) { conversa.display_id },
    'conversa.status' => ->(conversa) { conversa.status },
    'conversa.prioridade' => ->(conversa) { conversa.priority },
    'conversa.caixa_id' => ->(conversa) { conversa.inbox_id },
    'conversa.responsavel_id' => ->(conversa) { conversa.assignee_id },
    'conversa.time_id' => ->(conversa) { conversa.team_id },
    'conversa.etiquetas' => ->(conversa) { conversa.label_list },
    # "cliente" ou "equipe", pela primeira mensagem de verdade (#2527); vazio enquanto a conversa não tem mensagem.
    'conversa.iniciada_por' => ->(conversa) { ::Autonomia::Automacao::PrimeiraMensagem.iniciada_por(conversa) },
    'contato.id' => ->(contato) { contato.id },
    'contato.nome' => ->(contato) { contato.name },
    'contato.email' => ->(contato) { contato.email },
    'contato.telefone' => ->(contato) { contato.phone_number },
    'contato.empresa_id' => ->(contato) { contato.company_id },
    'contato.etiquetas' => ->(contato) { contato.label_list },
    # `card.id` é o id do banco: é o que as rotas do card recebem e o que a tela mostra (#123).
    'card.id' => ->(card) { card.id },
    'card.titulo' => ->(card) { card.title },
    'card.etapa_id' => ->(card) { card.stage_id },
    'card.funil_id' => ->(card) { card.pipeline_id },
    'card.status' => ->(card) { card.status },
    'card.valor' => ->(card) { card.value_cents.to_d / 100 },
    'card.responsavel_id' => ->(card) { card.owner_id },
    'card.time_id' => ->(card) { card.team_id },
    'card.dias_na_etapa' => ->(card) { card.entered_stage_at && ((Time.current - card.entered_stage_at) / 1.day).floor },
    'card.motivo_da_perda' => ->(card) { card.lost_reason },
    # G32: o card tem reunião marcada e ainda por vir (não cancelada nem remarcada para outra). O "esperar até" que lê
    # este valor acorda quando uma reunião do card é marcada, remarcada ou cancelada (Escuta#acordar_o_card).
    'card.tem_reuniao_marcada' => ->(card) { ::Autonomia::Automacao::ValoresDaReuniao.marcada_no_card?(card) },
    # G12: a reunião da atividade que disparou o gatilho de reunião (Contexto#reuniao). O início sai no fuso da reunião,
    # o mesmo do convite que o cliente recebeu.
    'reuniao.inicio' => ->(reuniao) { ::Autonomia::Automacao::ValoresDaReuniao.inicio(reuniao) },
    'reuniao.link_da_reuniao' => ->(reuniao) { reuniao.online_meeting_url }
  }.merge(::Autonomia::Automacao::Ausencia::VALORES).freeze

  # Os valores que leem outros registros além do alvo: só os que quem ligou a automação vê (ValoresDaReuniao).
  # #2710: a página de agendamento põe a reunião no card aberto do funil e, sem ele (o card já ganho), cria outro: quem
  # espera no card ganho lê o valor do contato, não o do card. O "esperar até" acorda com a reunião de qualquer card do
  # contato (Escuta#acordar_o_card).
  DO_QUE_QUEM_VE = {
    'contato.tem_reuniao_marcada' => lambda do |contato, account_user|
      ::Autonomia::Automacao::ValoresDaReuniao.marcada_no_contato?(contato, account_user)
    end
  }.freeze

  # G12: o link da agenda (LinkDaAgenda) de quem cuida: o responsável do card ou a pessoa da conversa. Vale em qualquer
  # gatilho com card ou conversa: vai no texto para o cliente marcar, quando ainda não há reunião. A página da reunião
  # do gatilho, quando há, desempata entre as páginas da pessoa.
  AGENDA = {
    'card.link_da_agenda' => ->(card) { card.owner },
    'conversa.link_da_agenda' => ->(conversa) { conversa.assignee }
  }.freeze

  # G11: a resposta que chegou durante o "esperar até" (Resposta::VALORES). Só existe na condição dele, onde há a janela
  # da espera (`espera`); o salvar recusa no resto. Sem a janela, ou sem conversa (card sem conversa principal), lê
  # false: nunca "respondeu", e "diferente de true" não vira resposta. O cliente responde de qualquer conversa dele
  # (#2680: o e-mail abre outra), então a resposta dele sai do contato, nas conversas que `quem` vê, e vale também no
  # alvo contato. Lote 4 (#2682): a resposta da pessoa atribuída e o gatilho que aconteceu de novo durante a espera
  # (`gatilho.repetiu`, da execução; no ensaio, sem execução, false). G59: a reunião do contato que aconteceu durante a
  # espera (`contato.reuniao_atendida`), só nos cards que quem ligou vê.
  RESPOSTA = ::Autonomia::Automacao::Resposta::VALORES
  RESPOSTA_DO_CONTATO = 'conversa.cliente_respondeu'.freeze

  # A última mensagem que a execução mandou ao cliente (#2680): o texto e a situação (Envio).
  ENVIO = ::Autonomia::Automacao::Envio::VALORES

  # #2679: o texto que um passo de IA ("escrever", "resumir") desta execução produziu: `ia.<id do passo>`. Vale em
  # qualquer alvo: fica na execução, não no alvo. O salvar confere que o id é de um passo que escreve (Receita); antes de
  # ele rodar, ou num caminho em que ele não rodou, lê vazio, e o passo pula com `faltou_valor`.
  IA = 'ia.'.freeze
  PASSOS_QUE_ESCREVEM = %w[escrever resumir].freeze

  # O que cada alvo alcança, pelas pontes do Contexto.
  BASES_DO_ALVO = {
    'Conversation' => %w[conversa contato envio gatilho],
    'Crm::Card' => %w[card conversa contato reuniao envio gatilho],
    'Contact' => %w[contato envio gatilho]
  }.freeze

  # A mensagem que disparou o gatilho, para o filtro separar a do cliente da resposta da equipe e da nota.
  MENSAGEM = {
    'mensagem.tipo' => lambda do |mensagem|
      next 'nota' if mensagem.private?

      mensagem.incoming? ? 'recebida' : 'enviada'
    end,
    'mensagem.privada' => ->(mensagem) { mensagem.private? },
    # A mensagem é a primeira de verdade da conversa (#2527)? A nota e a atividade nunca são.
    'mensagem.primeira' => ->(mensagem) { ::Autonomia::Automacao::PrimeiraMensagem.primeira?(mensagem) }
  }.freeze

  # O gatilho cuja mensagem o filtro lê.
  GATILHO_DA_MENSAGEM = 'mensagem.criada'.freeze

  # Valores fechados (#2496): fora destas opções e destes operadores a condição nunca casa, e a automação falharia em
  # silêncio. O salvar recusa o resto; o editor mostra só isto.
  FECHADOS = {
    'mensagem.tipo' => { 'opcoes' => %w[recebida enviada nota], 'operadores' => %w[igual diferente] },
    'mensagem.privada' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'mensagem.primeira' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'conversa.iniciada_por' => { 'opcoes' => %w[cliente equipe], 'operadores' => %w[igual diferente] },
    'conversa.cliente_respondeu' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'conversa.equipe_respondeu' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'conversa.responsavel_respondeu' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'gatilho.repetiu' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'contato.reuniao_atendida' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'card.tem_reuniao_marcada' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'contato.tem_reuniao_marcada' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'envio.situacao' => { 'opcoes' => ::Autonomia::Automacao::Envio::SITUACOES.values, 'operadores' => %w[igual diferente] }
  }.merge(::Autonomia::Automacao::Ausencia::FECHADOS).freeze

  # Os valores que pedem permissão para ler (#2597): a pergunta é a mesma do resto do CRM, feita a quem salva a receita
  # e a quem ligou a automação. O dono de um card não ganha, pela automação, o valor dos cards alheios: `ve?`, não
  # `ve_o_card?`. Sem a permissão, o salvar recusa e a execução lê vazio. Cada regra responde `ve?(account_user)` e diz
  # a chave (`CHAVE`) que o catálogo manda ao editor, para ele não oferecer o valor a quem não pode ler.
  PROTEGIDOS = {
    'card.valor' => ::Crm::ValorDeVenda
  }.freeze

  # Os atributos personalizados (`contato.atributos.placa`) ficam em Valores::Atributos.
  MODELOS = ::Autonomia::Automacao::Valores::Atributos::MODELOS

  class << self
    def caminho_valido?(caminho)
      [CAMPOS, DO_QUE_QUEM_VE, MENSAGEM, RESPOSTA, AGENDA, ENVIO].any? { |lista| lista.key?(caminho.to_s) } || atributo(caminho).present? ||
        da_ia?(caminho)
    end

    def da_ia?(caminho) = caminho.to_s.start_with?(IA) && caminho.to_s.length > IA.length

    # "ia.p3" => "p3".
    def passo_da_ia(caminho) = caminho.to_s.delete_prefix(IA)

    def da_reuniao?(caminho) = caminho.to_s.start_with?('reuniao.')

    def da_mensagem?(caminho) = MENSAGEM.key?(caminho.to_s)

    def da_resposta?(caminho) = RESPOSTA.key?(caminho.to_s)

    # O valor que só existe num lugar da receita: a mensagem no filtro do gatilho dela (`mensagem`: a receita está lá);
    # a resposta no "esperar até" (`na_espera`); a reunião nos gatilhos de reunião (`gatilho`). Devolve a chave da
    # frase do salvar, ou nil.
    def fora_do_lugar(caminho, mensagem:, na_espera:, gatilho: nil)
      return :mensagem_so_no_gatilho if da_mensagem?(caminho) && !mensagem
      return :reuniao_so_no_gatilho if da_reuniao?(caminho) && !::Autonomia::Automacao::Gatilhos.de_reuniao?(gatilho)

      :resposta_so_na_espera if da_resposta?(caminho) && !na_espera
    end

    # O alvo (`Conversation`, `Crm::Card`, `Contact`) chega à base do caminho? A mensagem fica com a regra própria dela.
    def no_alvo?(caminho, alvo_type)
      return true if da_mensagem?(caminho) || da_ia?(caminho)
      return true if BASES_DO_ALVO.fetch(alvo_type, []).include?(caminho.to_s.split('.', 2).first)

      caminho.to_s == RESPOSTA_DO_CONTATO && BASES_DO_ALVO.fetch(alvo_type, []).include?('contato')
    end

    def fechado(caminho) = FECHADOS[caminho.to_s]

    # O que impede a receita de ler o caminho que já vale ali: o atributo que a conta não tem, ou o valor que pede
    # permissão (#2597) para quem salva sem ela. Sem pessoa (`account_user` nil: o catálogo), a permissão não é
    # conferida aqui; a execução lê vazio.
    def problema_de_leitura(caminho, conta:, account_user:)
      return :atributo_inexistente unless atributo_definido?(caminho, conta)

      :valor_de_venda if account_user && !pode_ler?(caminho, account_user)
    end

    # `account_user` pode ler o caminho? Sem pessoa (nil), o valor protegido fica fechado.
    def pode_ler?(caminho, account_user)
      regra = PROTEGIDOS[caminho.to_s]
      regra.nil? || regra.ve?(account_user)
    end

    def atributo_definido?(caminho, conta) = ::Autonomia::Automacao::Valores::Atributos.definido?(caminho, conta)

    def data?(caminho, conta) = ::Autonomia::Automacao::Valores::Atributos.data?(caminho, conta)

    # "contato.atributos.placa" => ["contato.atributos", "placa"].
    def atributo(caminho) = ::Autonomia::Automacao::Valores::Atributos.do_caminho(caminho)
  end

  # `alvo`: a conversa, o card ou o contato da execução (ou um Contexto já montado). `quem`: a pessoa com cujas
  # permissões a receita lê (quem ligou a automação; no ensaio, quem pede). `nil` explícito: o valor protegido lê
  # vazio. Obrigatório, sem padrão: quem cria o Valores diz quem é, e o esquecimento quebra o spec em vez de ler vazio.
  # `espera`: a janela (Range de instantes) do "esperar até" que está conferindo a condição.
  def initialize(alvo:, quem:, mensagem: nil, espera: nil)
    @contexto = alvo.is_a?(::Autonomia::Automacao::Contexto) ? alvo : ::Autonomia::Automacao::Contexto.de(alvo)
    @mensagem = mensagem
    @quem = quem
    @espera = espera
    @vazios = []
  end

  # Por que o link da agenda lido ficou vazio (`por` do LinkDaAgenda), para o passo pular com o motivo próprio. Só
  # quando ele é o único valor vazio lido: com outro vazio junto, o motivo é o geral (`faltou_valor`).
  def falta_da_agenda = (@por_da_agenda if @vazios.any? && @vazios.all? { |caminho| AGENDA.key?(caminho) })

  def ler(caminho)
    valor = self.class.da_ia?(caminho) ? @contexto.texto_da_ia(self.class.passo_da_ia(caminho)) : lido(caminho)
    @vazios << caminho.to_s if valor.blank?
    valor
  end

  private

  def lido(caminho)
    return unless permitido?(caminho)
    return @mensagem && MENSAGEM.fetch(caminho.to_s).call(@mensagem) if MENSAGEM.key?(caminho.to_s)
    return resposta(caminho) if RESPOSTA.key?(caminho.to_s)
    return do_campo(caminho.to_s) if campo?(caminho.to_s)

    base, chave = self.class.atributo(caminho)
    raise ArgumentError, "caminho desconhecido: #{caminho}" unless base

    do_objeto(caminho) { |objeto| ::Autonomia::Automacao::Valores::Atributos.ler(base, chave, objeto) }
  end

  def campo?(chave) = CAMPOS.key?(chave) || AGENDA.key?(chave) || ENVIO.key?(chave) || DO_QUE_QUEM_VE.key?(chave)

  def do_campo(chave)
    return do_objeto(chave) { |objeto| DO_QUE_QUEM_VE[chave].call(objeto, account_user) } if DO_QUE_QUEM_VE.key?(chave)
    return do_objeto(chave) { |objeto| link_da_agenda(objeto, AGENDA[chave].call(objeto)) } if AGENDA.key?(chave)

    do_objeto(chave) { |objeto| (CAMPOS[chave] || ENVIO[chave]).call(objeto) }
  end

  def link_da_agenda(objeto, pessoa)
    resultado = ::Autonomia::Automacao::LinkDaAgenda.resultado(objeto.account, pessoa, pagina_id: pagina_da_reuniao)
    @por_da_agenda ||= resultado.por
    resultado.url
  end

  # A página de agendamento em que a reunião do gatilho foi marcada, quando veio de uma.
  def pagina_da_reuniao = @contexto.reuniao&.metadata.to_h['booking_profile_id']

  def resposta(caminho) = !@espera.nil? && RESPOSTA.fetch(caminho.to_s).call(@contexto, @espera, @quem) == true

  # A pessoa só é buscada quando o caminho pede permissão.
  def permitido?(caminho) = !PROTEGIDOS.key?(caminho.to_s) || self.class.pode_ler?(caminho, account_user)

  def account_user
    return @account_user if defined?(@account_user)

    @account_user = @quem && @contexto.conta.account_users.find_by(user_id: @quem.id)
  end

  def do_objeto(caminho)
    objeto = da_base(caminho)
    objeto && yield(objeto)
  end

  # A ponte vazia (card sem conversa, conversa sem contato) lê vazio.
  def da_base(caminho)
    case caminho.to_s.split('.', 2).first
    when 'conversa' then @contexto.conversa
    when 'contato' then @contexto.contato
    when 'card' then @contexto.card
    when 'reuniao' then @contexto.reuniao
    when 'envio' then @contexto.ultimo_envio
    end
  end
end
