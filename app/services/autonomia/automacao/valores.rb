# Os valores que uma receita lê do alvo (#2414 F3, ADR-001 2.3): `{"$valor": "conversa.status"}`.
#
# A lista de caminhos é fechada: a receita só lê o que está aqui, e o salvar recusa caminho desconhecido. Não é Liquid
# nem texto livre; cada caminho é um campo do modelo. Os atributos personalizados entram pela chave
# (`contato.atributos.placa`). A mensagem do gatilho `mensagem.criada` só existe no filtro do gatilho
# (`mensagem.tipo`: recebida, enviada ou nota; `mensagem.privada`; `mensagem.primeira`; `mensagem.tem_anexo`;
# `mensagem.campanha`, #2681); nos passos ela já passou, e o salvar recusa ler a mensagem fora dali.
#
# #2499 (F6): cada caminho começa pela base (`conversa`, `contato` ou `card`), lida do alvo pelas pontes do Contexto.
# A base que o alvo não alcança (card num gatilho de contato) o salvar recusa; a ponte vazia ao rodar (card sem
# conversa) chega como valor vazio. O card da conversa (#2716) é só para ler: CardDaConversa.
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
    'card.responsavel_nome' => ->(card) { card.owner&.name },
    'card.time_id' => ->(card) { card.team_id },
    'card.dias_na_etapa' => ->(card) { card.entered_stage_at && ((Time.current - card.entered_stage_at) / 1.day).floor },
    'card.motivo_da_perda' => ->(card) { card.lost_reason },
    # G32: o card tem reunião marcada e ainda por vir (não cancelada nem remarcada para outra). O "esperar até" que lê
    # este valor acorda quando uma reunião do card é marcada, remarcada ou cancelada (Escuta#acordar_o_card).
    'card.tem_reuniao_marcada' => ->(card) { ::Autonomia::Automacao::ValoresDaReuniao.marcada_no_card?(card) },
    # G29 (#2702): de onde o card veio (OrigemDoCard) e o nome do anúncio do formulário (Crm::MetaAds::LeadForms::Importer).
    'card.origem' => ->(card) { ::Autonomia::Automacao::OrigemDoCard.de(card.source) },
    'card.anuncio' => ->(card) { card.metadata.to_h.dig('meta_lead_form', 'ad_name') },
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

  # G22 (exemplo 8, passo 9): quem o RH pediu e ainda falta mandar documento (Solicitados::VALORES; o caminho e o
  # gatilho em que ele vale, Solicitados::CAMINHO e ::GATILHO).
  DA_SELECAO = ::Autonomia::Automacao::Solicitados::VALORES

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

  # G9 (#2707): quem cuidava do card e o time de antes da troca que disparou o gatilho (TrocaNoCard), lidos da marca
  # do fato: na partida (o filtro do gatilho) e nos passos da execução. Só nos gatilhos da troca (LugarDoValor).
  TROCA = ::Autonomia::Automacao::TrocaNoCard::VALORES

  # G53: a mensagem que disparou o gatilho "mensagem que falhou" (Contexto#mensagem_que_falhou), para os passos depois
  # dele ("manda por e-mail o mesmo conteúdo"). Só existe nesse gatilho; o salvar recusa no resto. A mensagem apagada
  # e a que só tem anexo leem vazio, e o passo pula com `faltou_valor`: nunca sai pela metade.
  FALHOU = {
    'falhou.texto' => ->(mensagem) { mensagem.content unless mensagem.content_attributes.to_h['deleted'] }
  }.freeze

  # Os valores que uma lambda lê direto do objeto da base (o contexto, na troca).
  LEITURA_DIRETA = [CAMPOS, ENVIO, TROCA, FALHOU].freeze

  # #2679: o texto que um passo de IA ("escrever", "resumir") desta execução produziu: `ia.<id do passo>`. Vale em
  # qualquer alvo: fica na execução, não no alvo. O salvar confere que o id é de um passo que escreve (Receita); antes de
  # ele rodar, ou num caminho em que ele não rodou, lê vazio, e o passo pula com `faltou_valor`. O "para cada item" (G24)
  # deixa `ia.<id>.quantos` e `ia.<id>.nomes`, guardados na execução com a mesma chave (TextoDaIaNaReceita).
  IA = 'ia.'.freeze
  PASSOS_QUE_ESCREVEM = %w[escrever resumir].freeze

  # G44: o link da agenda de uma página escolhida, `agenda.<id da página>` (AgendaDaPagina), em qualquer alvo.
  PAGINA = ::Autonomia::Automacao::AgendaDaPagina

  # G49: o id do registro que um passo desta execução criou (`criado.<id do passo>`: o contato do `POST contacts`, o
  # card do "criar card"). Como o texto da IA, vale em qualquer alvo e só na execução que criou (RegistroCriado).
  CRIADO = ::Autonomia::Automacao::RegistroCriado

  # O que cada alvo alcança, pelas pontes do Contexto. O card da conversa (#2716) só para ler: CardDaConversa.
  # De onde cada base lê no contexto da execução. O `card` fica fora: na conversa, ele cai no card dela (#2716). O
  # `gatilho` (G9) lê o próprio contexto, que guarda a marca da troca.
  LEITURA_DA_BASE = {
    'conversa' => :conversa, 'contato' => :contato, 'reuniao' => :reuniao, 'envio' => :ultimo_envio, 'falhou' => :mensagem_que_falhou,
    'gatilho' => :itself
  }.freeze

  BASES_DO_ALVO = {
    'Conversation' => %w[conversa contato card envio gatilho falhou],
    'Crm::Card' => %w[card conversa contato reuniao envio gatilho],
    'Contact' => %w[contato envio gatilho]
  }.freeze

  # A mensagem que disparou o gatilho, para o filtro separar a do cliente da resposta da equipe e da nota: Valores::Mensagem.
  MENSAGEM = ::Autonomia::Automacao::Valores::Mensagem::VALORES

  # O gatilho cuja mensagem o filtro lê.
  GATILHO_DA_MENSAGEM = 'mensagem.criada'.freeze

  # Valores fechados (#2496): Valores::Fechados.
  FECHADOS = ::Autonomia::Automacao::Valores::Fechados::TABELA

  # Os valores que pedem permissão para ler (#2597): a pergunta é a mesma do resto do CRM, feita a quem salva a receita
  # e a quem ligou a automação. O dono de um card não ganha, pela automação, o valor dos cards alheios: `ve?`, não
  # `ve_o_card?`. Sem a permissão, o salvar recusa e a execução lê vazio. Cada regra responde `ve?(account_user)` e diz
  # a chave (`CHAVE`) que o catálogo manda ao editor, para ele não oferecer o valor a quem não pode ler.
  PROTEGIDOS = {
    'card.valor' => ::Crm::ValorDeVenda
  }.freeze

  # Decisão 9 do Rodrigo (#2780, 09/11): o texto que a pessoa escreve (mensagem, e-mail, corpo) pode levar o valor
  # protegido, em qualquer automação, com a permissão de quem salva e de quem ligou. A IA nunca o recebe para escrever
  # (ComIa.leva_o_valor?): só o "decidir" o lê.

  # Os atributos personalizados (`contato.atributos.placa`) ficam em Valores::Atributos.
  MODELOS = ::Autonomia::Automacao::Valores::Atributos::MODELOS

  # Onde cada valor existe na receita (LugarDoValor): a mensagem, a resposta, a reunião e a troca de quem cuida do card;
  # a mensagem que falhou (G53).
  extend ::Autonomia::Automacao::LugarDoValor

  class << self
    def caminho_valido?(caminho)
      [CAMPOS, DO_QUE_QUEM_VE, DA_SELECAO, MENSAGEM, RESPOSTA, AGENDA, ENVIO, TROCA, FALHOU].any? { |lista| lista.key?(caminho.to_s) } ||
        atributo(caminho).present? || livre?(caminho)
    end

    def da_ia?(caminho) = caminho.to_s.start_with?(IA) && caminho.to_s.length > IA.length

    # O texto da IA (#2679), a página da agenda (G44) e o registro criado (G49) valem em qualquer alvo.
    def livre?(caminho) = da_ia?(caminho) || PAGINA.caminho?(caminho) || CRIADO.caminho?(caminho)

    # "ia.p3" => "p3".
    def passo_da_ia(caminho) = caminho.to_s.delete_prefix(IA)

    # O alvo (`Conversation`, `Crm::Card`, `Contact`) chega à base do caminho? A mensagem fica com a regra própria dela.
    def no_alvo?(caminho, alvo_type)
      return true if da_mensagem?(caminho) || livre?(caminho)
      return true if BASES_DO_ALVO.fetch(alvo_type, []).include?(caminho.to_s.split('.', 2).first)

      caminho.to_s == RESPOSTA_DO_CONTATO && BASES_DO_ALVO.fetch(alvo_type, []).include?('contato')
    end

    # A ausência da pessoa num campo do card (G62) fecha como a G23.
    def fechado(caminho)
      return FECHADOS['card.responsavel_ausente'] if ::Autonomia::Automacao::Valores::Atributos.ausente_da_pessoa?(caminho)

      FECHADOS[caminho.to_s]
    end

    # O que impede a receita de ler o caminho que já vale ali: o atributo que a conta não tem, ou o valor que pede
    # permissão (#2597) para quem salva sem ela. Sem pessoa (`account_user` nil: o catálogo), a permissão não é
    # conferida aqui; a execução lê vazio. A página da agenda (G44) tem a conferência dela (AgendaDaPagina).
    def problema_de_leitura(caminho, conta:, account_user:)
      return PAGINA.problema_ao_salvar(caminho, conta: conta, account_user: account_user) if PAGINA.caminho?(caminho)
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
  def falta_da_agenda = (@por_da_agenda if @vazios.any? && @vazios.all? { |caminho| AGENDA.key?(caminho) || PAGINA.caminho?(caminho) })

  def ler(caminho)
    valor = do_passo(caminho)
    @vazios << caminho.to_s if valor.blank?
    valor
  end

  private

  # O texto da IA e o registro criado ficam na execução; o resto, no alvo.
  def do_passo(caminho)
    return @contexto.texto_da_ia(self.class.passo_da_ia(caminho)) if self.class.da_ia?(caminho)
    return @contexto.criado(CRIADO.passo_do(caminho)) if CRIADO.caminho?(caminho)

    lido(caminho)
  end

  def lido(caminho)
    return unless permitido?(caminho)
    return @mensagem && MENSAGEM.fetch(caminho.to_s).call(@mensagem) if MENSAGEM.key?(caminho.to_s)
    return resposta(caminho) if RESPOSTA.key?(caminho.to_s)
    return do_campo(caminho.to_s) if campo?(caminho.to_s)

    base, chave = self.class.atributo(caminho)
    raise ArgumentError, "caminho desconhecido: #{caminho}" unless base

    do_objeto(caminho) { |objeto| ::Autonomia::Automacao::Valores::Atributos.ler(base, chave, objeto) }
  end

  def campo?(chave) = [AGENDA, DO_QUE_QUEM_VE, DA_SELECAO, *LEITURA_DIRETA].any? { |lista| lista.key?(chave) } || PAGINA.caminho?(chave)

  def do_campo(chave)
    return guardar_link(PAGINA.resultado(chave, contexto: @contexto, account_user: account_user)) if PAGINA.caminho?(chave)
    return do_objeto(chave) { |objeto| DA_SELECAO[chave].call(objeto, account_user, @contexto.selecao) } if DA_SELECAO.key?(chave)
    return do_objeto(chave) { |objeto| DO_QUE_QUEM_VE[chave].call(objeto, account_user) } if DO_QUE_QUEM_VE.key?(chave)
    return link_da_agenda(chave) if AGENDA.key?(chave)

    do_objeto(chave) { |objeto| LEITURA_DIRETA.find { |lista| lista.key?(chave) }.fetch(chave).call(objeto) }
  end

  # G60: a página de quem atende; sem ninguém (ou sem a ponte: o contato ainda sem conversa na caixa escolhida), a página
  # de agenda de reserva da receita (AgendaDeReserva); sem ela, vazio por `sem_responsavel`.
  def link_da_agenda(chave)
    objeto = da_base(chave)
    pessoa = objeto && AGENDA[chave].call(objeto)
    guardar_link(pessoa ? ::Autonomia::Automacao::LinkDaAgenda.resultado(@contexto.conta, pessoa, pagina_id: pagina_da_reuniao) : sem_quem_atenda)
  end

  def sem_quem_atenda
    reserva = ::Autonomia::Automacao::AgendaDeReserva.pagina_id(@contexto.execucao&.versao&.receita)
    return ::Autonomia::Automacao::AgendaDeReserva.resultado(@contexto.conta, reserva, @quem) if reserva

    ::Autonomia::Automacao::LinkDaAgenda::Resultado.new(url: nil, por: 'sem_responsavel')
  end

  # O link da agenda (do responsável, G12, da página de reserva, G60, ou da página escolhida, G44) e, vazio, o porquê.
  def guardar_link(resultado) = resultado.url.tap { @por_da_agenda = resultado.por if @por_da_agenda.nil? }

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

  # O card da conversa (#2716), quando o alvo é uma conversa. Buscado uma vez: a lista guarda também a resposta vazia.
  def card_da_conversa = (@card_da_conversa ||= [::Autonomia::Automacao::CardDaConversa.ler(@contexto.alvo, account_user)]).first

  # A ponte vazia (card sem conversa, conversa sem contato) lê vazio.
  def da_base(caminho)
    base = caminho.to_s.split('.', 2).first
    return @contexto.card || card_da_conversa if base == 'card'

    leitura = LEITURA_DA_BASE[base]
    leitura && @contexto.public_send(leitura)
  end
end
