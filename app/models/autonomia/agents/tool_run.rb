# == Schema Information
#
# Table name: autonomia_agent_tool_runs
#
#  id                 :bigint           not null, primary key
#  arguments          :jsonb            not null
#  attempts           :integer          default(0), not null
#  delivered_count    :integer          default(0), not null
#  expected_chunks    :integer          default(0), not null
#  expires_at         :datetime
#  failure_code       :string
#  handle             :jsonb            not null
#  notify_customer    :boolean          default(FALSE), not null
#  sequence           :integer          default(0), not null
#  slug               :string           not null
#  status             :string           default("pending"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  agent_inbox_id     :bigint
#  autonomia_agent_id :bigint           not null
#  conversation_id    :bigint           not null
#  execution_key      :string           not null
#  origin_message_id  :bigint
#
# Indexes
#
#  idx_autonomia_tool_runs_account_slug   (account_id,slug,created_at)
#  idx_autonomia_tool_runs_active         (conversation_id,slug) UNIQUE WHERE status IN ('pending','running')
#  idx_autonomia_tool_runs_conversation   (conversation_id,created_at)
#  idx_autonomia_tool_runs_execution_key  (execution_key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
# Uma EXECUÇÃO de ferramenta assíncrona (#313).
#
# Existe porque uma cotação leva até ~90s e o turno do agente não pode esperar por ela. A linha é o
# que torna a espera segura: nela mora o progresso (em vez da memória de um worker que um deploy
# mata), a idempotência da publicação (retry do Sidekiq não duplica mensagem), o teto de tempo de
# parede, e o argumento que o modelo montou — que fica AQUI e não no payload do job, porque no Redis
# ele sobreviveria no dead set, visível em /monitoring/sidekiq, sem TTL controlado por nós.
#
# UMA execução viva por (conversa, ferramenta), garantido por índice único parcial. Chamada nova
# SUPERSEDE a anterior em vez de coexistir com ela: o cliente que corrige um dado no meio da conversa
# ("na verdade é 2019") não pode acabar com duas cotações concorrentes e dois preços conflitantes.
# É o mesmo last-writer-wins que o namespace já usa no debounce, no sync_token e no build_token.
class Autonomia::Agents::ToolRun < ApplicationRecord
  self.table_name = 'autonomia_agent_tool_runs'

  # `pending` é o estado em que a ferramenta foi ACEITA dentro do turno mas o turno ainda não
  # terminou. Só o Responder promove para `running` — se o turno morrer (falha de IA na segunda
  # chamada, sinal de silêncio), a execução é descartada e nunca chega a falar com o portal.
  ACTIVE_STATUSES = %w[pending running].freeze
  TERMINAL_STATUSES = %w[done failed superseded discarded blocked].freeze
  STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze

  belongs_to :account
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id,
                     inverse_of: false
  # Opcionais na LEITURA: a conversa pode ter sido apagada enquanto a execução corria, e nesse caso
  # o job precisa parar limpo, não levantar. Quem cria a linha sempre tem as duas.
  belongs_to :conversation, optional: true
  belongs_to :agent_inbox, class_name: 'Autonomia::Agents::AgentInbox', optional: true

  validates :slug, presence: true
  validates :execution_key, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  # As que podem ter cotado duas vezes no portal (entrega 5): o worker morreu entre o envio e o
  # registro do número, e o job tentou de novo. É a lista que o corretor precisa quando vê duas
  # cotações idênticas no portal e não sabe qual é a boa.
  scope :possivelmente_duplicadas, -> { where('handle @> ?', { POSSIVELMENTE_DUPLICADA => true }.to_json) }

  # Marcas NOSSAS dentro do handle, ao lado do que a ferramenta devolveu. `submitted` é a que diz
  # "o retorno do `start` foi registrado" — um número, uma recusa com `pedido` (que nem chama o
  # portal), ou nada (#313) — gravada pelo `AsyncRunJob`, lida também pelo varredor e pelo desfecho.
  # `intencoes` conta quantas vezes o job decidiu submeter (entrega 5); `possivelmente_duplicada`
  # fica quando ele decidiu uma segunda vez sem saber se a primeira chegou ao portal, ou quando a
  # execução acabou nesse estado. Só sai na volta a zero: a única chamada feita falhou com certeza.
  SUBMITTED_KEY = 'autonomia_submitted'.freeze
  INTENCOES = 'autonomia_intencoes'.freeze
  POSSIVELMENTE_DUPLICADA = 'autonomia_possivelmente_duplicada'.freeze
  # A IDENTIDADE DO PEDIDO (entrega 10): o digest da entrada normalizada pelo adapter, gravado na
  # abertura. É o que diz se "e aí, saiu?" é o mesmo pedido da última consulta — e não o cru do modelo.
  PEDIDO = 'autonomia_pedido'.freeze
  # QUANDO a execução encerrou, gravado pelo `finish!` no mesmo comando que muda o status. Não é
  # `updated_at`: uma publicação adiada que sai depois do fim (`advance_sequence!`) mexe nele, e a
  # janela do pedido contaria da publicação, não do encerramento.
  ENCERRADA_EM = 'autonomia_encerrada_em'.freeze
  # O QUE O PUBLICADOR ACEITOU (entrega 8a): a lista das identidades de entrega que voltaram
  # `published` ou `deferred`. É o REGISTRO DO ACEITE — o que separa "eu tentei entregar" de "o
  # publicador assumiu esta entrega" —, e quem o escreve é sempre quem publicou
  # (`Tools::EntregaAceita`). A recusa não escreve nada. Ver `registrar_entrega_aceita!`.
  ENTREGAS_ACEITAS = 'autonomia_entregas_aceitas'.freeze

  # Por quanto tempo uma consulta ENCERRADA com entrega ainda conta como "este pedido já foi feito".
  # Depois disso, repetir os mesmos dados é um pedido novo (o preço muda; a cotação do portal vence).
  # É decisão registrada, não medida: o plano fala em "última execução" sem prazo; sem prazo, dados
  # idênticos ficariam barrados para sempre na conversa.
  PEDIDO_VALE_POR = 24.hours

  # Abre uma execução para (conversa, ferramenta), substituindo a que estiver viva.
  #
  # `scope` = { conversation_id:, agent_inbox_id:, origin_message_id: }. A mensagem de origem entra
  # aqui, na criação, porque é a chave que separa um PEDIDO NOVO de um RETRY do mesmo turno.
  # `pedido` é a identidade do pedido (entrega 10), gravada como marca do handle; nil quando a
  # conferência não pôde dizer (o conferente não é portão).
  #
  # Duas escritas numa transação: supersede a anterior e insere a nova. O índice único parcial é
  # quem garante de verdade — duas chamadas concorrentes fazem a segunda estourar `RecordNotUnique`,
  # e aí devolvemos nil em vez de mentir para o modelo dizendo que aceitamos.
  def self.open!(agent:, slug:, arguments:, scope:, pedido: nil)
    transaction(requires_new: true) do
      active.for_conversation(scope[:conversation_id]).where(slug: slug)
            .update_all(status: 'superseded', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      create!(account: agent.account, agent: agent, slug: slug, status: 'pending',
              conversation_id: scope[:conversation_id], agent_inbox_id: scope[:agent_inbox_id],
              origin_message_id: scope[:origin_message_id], handle: pedido ? { PEDIDO => pedido } : {},
              execution_key: SecureRandom.uuid, arguments: arguments.to_h.deep_stringify_keys)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # ABRE, OU DEVOLVE A EXECUÇÃO QUE JÁ É ESTE PEDIDO (entrega 10). Comparação e abertura na MESMA
  # seção crítica por (conversa, ferramenta) — um lock consultivo de transação —, senão dois turnos
  # simultâneos com o mesmo pedido comparam com nada, um abre, o outro supersede, e se o primeiro já
  # foi promovido e submetido há duas cotações no portal. A conferência (HTTP) fica fora da seção.
  # -> [execução aberta, nil] ou [nil, execução repetida]; [nil, nil] quando o índice único recusou.
  def self.abrir_ou_repetida(agent:, slug:, arguments:, scope:, pedido: nil)
    transaction do
      travar!(scope[:conversation_id], slug)
      repetida = pedido_repetido(scope[:conversation_id], slug, pedido)
      next [nil, repetida] if repetida

      [open!(agent: agent, slug: slug, arguments: arguments, scope: scope, pedido: pedido), nil]
    end
  end

  # Lock consultivo, liberado no fim da transação. UMA chave de 64 bits derivada do par
  # (conversa, ferramenta): a variante de dois argumentos exige `int4`, e o id da conversa é bigint.
  def self.travar!(conversation_id, slug)
    connection.execute(sanitize_sql_array(['SELECT pg_advisory_xact_lock(?)', chave_do_lock(conversation_id, slug)]))
  end

  def self.chave_do_lock(conversation_id, slug)
    Digest::SHA256.digest("#{conversation_id.to_i}:#{slug}")[0, 8].unpack1('q>')
  end

  # A ÚLTIMA execução desta ferramenta na conversa, se ela AINDA CONTA como pedido feito e tem os
  # mesmos dados (entrega 10). Conta: a que está rodando; e a que encerrou com algo entregue há menos
  # de `PEDIDO_VALE_POR`. NÃO conta: supersedida, descartada, bloqueada, falhada sem entrega, nem
  # `pending` — repetir depois delas é tentar de novo, não duplicar. `pending` de propósito: uma
  # `pending` é uma aceitação que ainda não virou trabalho; quem chega depois com o mesmo pedido a
  # SUPERSEDE (e a promoção dela perde pelo status, sob o mesmo lock), e o RETRY do turno cujo worker
  # morreu entre o aceite e o despacho precisa reabrir — contá-la travaria a cotação por uma órfã.
  # Isto vale mesmo com dois turnos da conversa vivos ao mesmo tempo (IA em andamento quando chega
  # mensagem nova): o custo é uma linha supersedida, nunca duas cotações. -> a execução, ou nil.
  def self.pedido_repetido(conversation_id, slug, pedido)
    return nil if pedido.blank?

    ultima = for_conversation(conversation_id).where(slug: slug).order(created_at: :desc).first
    ultima if ultima&.conta_como_pedido? && ultima.pedido == pedido
  end

  def pedido
    handle.to_h[PEDIDO]
  end

  def conta_como_pedido?
    return true if running?

    %w[done failed].include?(status) && delivered_count.positive? && encerrada_em > PEDIDO_VALE_POR.ago
  end

  # O instante do encerramento. Linhas anteriores a esta marca (encerradas antes da entrega 10) caem
  # em `updated_at`: aproximação aceitável para uma janela de um dia.
  def encerrada_em
    Time.zone.parse(handle.to_h[ENCERRADA_EM].to_s) || updated_at
  rescue ArgumentError
    updated_at
  end

  # Este turno já abriu uma execução desta ferramenta? É o freio do RETRY: o `ReplyJob` pode
  # reexecutar o settle e refazer a chamada ao modelo, e sem esta guarda a segunda passada
  # superseder a primeira e abriria uma cotação nova no portal — sem duplicar mensagem, mas
  # duplicando o custo e o registro na seguradora.
  def self.opened_for_turn?(conversation_id, slug, origin_message_id)
    return false if origin_message_id.blank?

    # `pending` órfã NÃO conta: se o worker morreu entre o aceite e o despacho (um deploy basta —
    # o Sidekiq desta instalação tem `:timeout: 25`), a linha ficou parada e ninguém vai executá-la.
    # Contá-la faria o retry do turno recusar a ferramenta e a cotação nunca aconteceria.
    for_conversation(conversation_id).where.not(status: %w[pending discarded blocked])
                                     .exists?(slug: slug, origin_message_id: origin_message_id)
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def running?
    status == 'running'
  end

  def expired?
    expires_at.present? && Time.current > expires_at
  end

  # Quantas vezes o job decidiu submeter. Zero quando nunca decidiu.
  def intencoes
    handle.to_h[INTENCOES].to_i
  end

  # A cotação PODE existir no portal sem registro nosso: o job decidiu submeter e o número nunca
  # chegou — o processo morreu, ou o portal ficou mudo. É o estado que muda a frase ao cliente; quem
  # marca a linha para o corretor achar é o `finish!`, com a mesma condição em SQL.
  def envio_incerto?
    intencoes.positive? && handle.to_h[SUBMITTED_KEY].blank?
  end

  # Token que carimba a mensagem publicada, derivado do CONTEÚDO. É por ele que a publicação é
  # idempotente: um retry do Sidekiq, ou uma consulta que reemite a mesma entrega, encontra a
  # mensagem já postada e não posta de novo.
  #
  # Por conteúdo e não por posição: `sequence` identifica ONDE a mensagem entrou, não O QUE ela diz.
  # Uma nova consulta que devolva a mesma lista (o contrato de `Progress` não exige que as entregas
  # sejam incrementais) republicaria o mesmo texto num índice diferente.
  def delivery_token(text)
    "#{execution_key}:#{Digest::SHA256.hexdigest(text.to_s)[0, 16]}"
  end

  # pending -> running. Guardado pelo status para que um despacho repetido (retry do turno) não
  # reabra uma execução que já terminou. -> true quando ESTA chamada promoveu.
  #
  # SOB O MESMO LOCK de `abrir_ou_repetida` (entrega 10): um turno B que leu a `pending` de A (que
  # não conta) não pode abrir enquanto A promove — ou A promove primeiro e B, ao entrar, encontra
  # uma `running` e não abre; ou B abre primeiro (supersede) e a promoção de A perde pelo status.
  # Sem isto, B supersedia uma execução já promovida e possivelmente submetida ao portal.
  def promote!(expected_chunks:, notify_customer:, expires_at:)
    self.class.transaction do
      self.class.travar!(conversation_id, slug)
      guarded_update('pending', status: 'running', expected_chunks: expected_chunks.to_i,
                                notify_customer: notify_customer, expires_at: expires_at)
    end
  end

  # O desfecho MARCA o envio incerto (`envio_incerto?` em SQL: intenção anotada, número ausente) no
  # MESMO comando que muda o status: uma intenção anotada por outro processo pouco antes deste
  # `finish!` (janela de milissegundos) não pode acabar em `failed` sem marca com uma cotação aberta
  # no portal (Codex, rodada 4). Depois daqui, nenhuma escrita com posse passa: a anotação seguinte
  # perde pelo status. A marca é o único caminho para `possivelmente_duplicadas` além de
  # `anotar_intencao!` (segunda intenção) — e por isso não existe "marcar" avulso no modelo.
  def finish!(status, failure_code: nil)
    agora = Time.current
    marca = 'CASE WHEN COALESCE((handle->>?)::int, 0) > 0 AND (handle->>?) IS NULL THEN ?::jsonb ELSE ?::jsonb END'
    updated = vivas.update_all(["status = ?, failure_code = ?, updated_at = ?, handle = handle || #{marca} || ?::jsonb", # rubocop:disable Rails/SkipsModelValidations
                                status, failure_code, agora, INTENCOES, SUBMITTED_KEY,
                                { POSSIVELMENTE_DUPLICADA => true }.to_json, '{}', { ENCERRADA_EM => agora.iso8601(3) }.to_json])
    return false if updated.zero?

    reload
    true
  end

  # Descarta uma execução que nunca chegou a rodar (o turno morreu antes de despachar).
  def discard!
    guarded_update('pending', status: 'discarded')
  end

  # Conta uma tentativa e, se vier handle, MESCLA-O no banco (`handle || ?`): o que a ferramenta
  # devolveu por cima do que estava, marcas preservadas. Nunca substitui o handle por uma cópia da
  # memória — era o que um processo com objeto velho fazia com a marca gravada por outro (Codex,
  # 10/09/2026). `intencao:` exige a POSSE da passada (ver `posse`).
  def record_attempt!(handle: nil, intencao: nil)
    mesclar(posse(intencao), adicionar: handle.to_h, contar: true)
  end

  # Escreve NAS marcas do handle sem tocar no resto: `(handle || adicionar) - remover`, no banco,
  # sem contar tentativa. É a anotação da intenção de submeter (entrega 5), que precisa ficar no
  # banco ANTES de o portal ser chamado — e a volta atrás dela. `ausente:` é aquisição: só escreve
  # se a chave ainda não está lá (o `closed` do encerramento). -> true quando a escrita valeu.
  def merge_handle!(adicionar, remover: [], intencao: nil, ausente: nil)
    scope = posse(intencao)
    scope = sem_chave(scope, ausente) if ausente
    mesclar(scope, adicionar: adicionar, remover: remover)
  end

  # Registra que uma ENTREGA DA FERRAMENTA foi aceita para publicação (publicada ou adiada). O aviso
  # de espera e a frase de falha NÃO passam por aqui — é o que permite saber, no fim, se o cliente
  # recebeu algum resultado de verdade.
  def record_delivery!
    self.class.where(id: id).update_all('delivered_count = delivered_count + 1, updated_at = NOW()') # rubocop:disable Rails/SkipsModelValidations
    reload
  end

  # ACRESCENTA À LISTA DO ACEITE a identidade de uma entrega que o publicador assumiu (entrega 8a).
  #
  # O IRMÃO DE `record_delivery!`: aquele conta QUANTAS entregas foram aceitas, esta diz QUAIS. O
  # contador não serve para o fecho — ele soma qualquer item aceito, inclusive a pergunta pelo dado
  # que falta —, e a lista serve, porque a ferramenta sabe qual identidade emitiu como resultado.
  #
  # ESCRITA NA HORA DO ACEITE, E NÃO NO FIM DA PASSADA: o handle da ferramenta só vai ao banco no
  # `record_attempt!` seguinte, e um processo morto entre a publicação e ele (deploy, 25 s de
  # shutdown do Sidekiq) deixaria o cliente com o preço na tela e a linha sem saber disso — o fecho
  # diria "não consegui" ao lado do preço. Por isso é UM UPDATE, aqui.
  #
  # E É UM UPDATE SÓ, sem ler-modificar-escrever: a lista é concatenada pelo BANCO
  # (`|| ?::jsonb`), então dois publicadores da mesma execução não apagam um o token do outro. O
  # `WHERE` com `@>` torna a escrita idempotente — o retry do Sidekiq que republica a mesma entrega
  # (e recebe `published` pela dedupe do token) não acrescenta uma segunda cópia. `COALESCE` nos
  # dois lados porque a chave só existe depois da primeira entrega aceita.
  def registrar_entrega_aceita!(token)
    lista = "COALESCE(handle->'#{ENTREGAS_ACEITAS}', '[]'::jsonb)"
    escrita = "handle = jsonb_set(handle, ARRAY['#{ENTREGAS_ACEITAS}'], #{lista} || ?::jsonb), updated_at = ?"
    updated = self.class.where(id: id)
                  .where.not("#{lista} @> ?::jsonb", [token].to_json)
                  .update_all([escrita, [token].to_json, Time.current]) # rubocop:disable Rails/SkipsModelValidations
    reload
    updated.positive?
  end

  # Já morreu: supersedida por um pedido novo, descartada com o turno, ou barrada pelo gate da conta.
  # Publicar a partir de uma destas entregaria ao cliente o resultado de um pedido que ele corrigiu.
  def dead?
    %w[superseded discarded blocked].include?(status)
  end

  # Avança o contador de mensagens. Otimista no valor atual: se dois publicadores correrem, só um
  # avança e o outro relê — evita duas mensagens com o mesmo número de sequência.
  def advance_sequence!(from)
    updated = self.class.where(id: id, sequence: from)
                  .update_all(sequence: from + 1, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    return false if updated.zero?

    self.sequence = from + 1
    true
  end

  private

  # Escrita guardada pelo status atual, sem callbacks nem validações — mesmo padrão de
  # `Autonomia::Agents::Source#guarded_update`. Recarrega o objeto quando a escrita valeu.
  def guarded_update(from_status, **attrs)
    updated = self.class.where(id: id, status: from_status)
                  .update_all(attrs.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    return false if updated.zero?

    reload
    true
  end

  # A escrita do handle é uma MESCLA feita pelo banco, nunca uma substituição pelo objeto: dois
  # processos com a mesma execução (o Sidekiq re-enfileira o job no hard shutdown, e o antigo pode
  # estar vivo noutro host) não apagam um a marca do outro. Recarrega quando a escrita valeu.
  def mesclar(scope, adicionar: {}, remover: [], contar: false)
    sets = ['handle = (handle || ?::jsonb) - ?::text[]', 'updated_at = ?']
    sets.unshift('attempts = attempts + 1') if contar
    updated = scope.update_all([sets.join(', '), adicionar.to_h.deep_stringify_keys.to_json, # rubocop:disable Rails/SkipsModelValidations
                                "{#{Array(remover).join(',')}}", Time.current])
    return false if updated.zero?

    reload
    true
  end

  def vivas
    self.class.where(id: id, status: 'running')
  end

  # A POSSE da passada (entrega 5): a linha ainda está na intenção que o processo leu E ninguém
  # registrou número. O contador sozinho não basta — ele volta atrás (2→1) e não muda quando o
  # número entra; era assim que um objeto velho passava no compare-and-set depois de outro
  # processo registrar o número, e o apagava (Codex, 10/09/2026). Sem `intencao`, basta estar viva.
  def posse(intencao)
    return vivas if intencao.nil?

    sem_numero(vivas).where('COALESCE((handle->>?)::int, 0) = ?', INTENCOES, intencao)
  end

  def sem_numero(scope)
    sem_chave(scope, SUBMITTED_KEY)
  end

  def sem_chave(scope, chave)
    scope.where('(handle->>?) IS NULL', chave)
  end
end
