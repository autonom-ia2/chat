# == Schema Information
#
# Table name: autonomia_agent_sources
#
#  id                 :bigint           not null, primary key
#  confidence         :string
#  error              :text
#  external_link      :string
#  kind               :integer          default("knowledge"), not null
#  metadata           :jsonb            not null
#  quality_score      :integer
#  reference          :string
#  review_label       :string
#  review_reason      :text
#  review_status      :string
#  review_summary     :text
#  reviewed_at        :datetime
#  source_type        :string           not null
#  status             :integer          default("pending"), not null
#  sync_status        :string
#  sync_token         :string
#  synced_at          :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  autonomia_agent_id :bigint           not null
#
# Indexes
#
#  index_autonomia_agent_sources_on_account_id                     (account_id)
#  index_autonomia_agent_sources_on_autonomia_agent_id             (autonomia_agent_id)
#  index_autonomia_agent_sources_on_autonomia_agent_id_and_kind    (autonomia_agent_id,kind)
#  index_autonomia_agent_sources_on_autonomia_agent_id_and_status  (autonomia_agent_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (autonomia_agent_id => autonomia_agents.id)
#
module Autonomia
  module Agents
    class Source < ApplicationRecord
      self.table_name = 'autonomia_agent_sources'

      scope :for_kept_agents, -> { joins(:agent).merge(Autonomia::Agents::Agent.kept) }

      # Arquivo enviado (pdf/xlsx/docx/json/txt/md). Em fontes do tipo `link` não há anexo.
      # O controller faz file.attach(...) e os Processors leem via @source.file.
      has_one_attached :file

      belongs_to :account
      belongs_to :agent, class_name: 'Autonomia::Agents::Agent',
                         foreign_key: :autonomia_agent_id
      has_many :knowledge_entries, class_name: 'Autonomia::Agents::KnowledgeEntry',
                                   foreign_key: :source_id, dependent: :delete_all

      enum status: { pending: 0, processing: 1, ready: 2, failed: 3 }

      # GAP (A) — DOIS grupos de materiais (plano v2 §1). `kind` decide o PIPELINE:
      #   - knowledge: "o que ela SABE" → ingest → chunk → embed → revisora (caminho ATUAL, inalterado).
      #   - media:     "o que ela ENVIA" (catálogo/tabela/imagem) → só armazenada (ready direto), SEM
      #                embed e SEM revisora de qualidade de KB.
      # Prefixo `kind_` evita colisão de métodos com o enum `status` e deixa explícito (kind_media?).
      enum kind: { knowledge: 0, media: 1 }, _prefix: :kind

      # Escopos por grupo. `knowledge`/`media` (do enum) já existem; estes são aliases legíveis usados
      # pelos serializers e pelo contexto do Construtor (mídias de envio).
      scope :knowledge_sources, -> { where(kind: kinds[:knowledge]) }
      scope :media_sources,     -> { where(kind: kinds[:media]) }

      # Parecer da IA Revisora (colunas reais — migration 20260620120000). 'needs_review' é o default
      # conservador quando a IA falha/credencial ausente: NÃO bloqueia o agente (conhecimento já foi
      # gravado), só marca confiança baixa sem summary. Só fontes 'accepted' alimentam o Construtor e
      # o retrieval (ver Retriever / Builder).
      REVIEW_STATUSES = %w[accepted needs_resend needs_review].freeze
      CONFIDENCE_LEVELS = %w[alta media baixa].freeze
      REVIEW_LABELS = %w[otima boa fraca].freeze

      # Escopo do parecer aceito — usado pelo retrieval e pelos resumos do Construtor.
      scope :accepted, -> { where(review_status: 'accepted') }

      # G6 — fontes SERVÍVEIS: aceitas E com geração de entries vigente — `ready` (caminho normal)
      # OU `failed` transitório (mark_failed! restaurou o parecer 'accepted'; os KnowledgeEntry
      # antigos seguem intactos e servidos pelo Retriever). Usado por Reviewer.recompute_overall!
      # para uma fonte que falhou num re-sync transitório NÃO sumir do topic_map/knowledge_summary
      # (o que faria o InstructionRefresher apagar esse escopo da instrução — exatamente a regressão
      # que a restauração do parecer evita). Fontes failed NUNCA-aceitas ficam de fora: o
      # previous_review_attributes as restaura como needs_review, e `accepted` já as exclui.
      scope :servable, -> { accepted.where(status: [statuses[:ready], statuses[:failed]]) }

      # Teto de fontes de CONHECIMENTO por agente (base-primeiro §c). Mídias de envio ficam fora do
      # limite (pipeline distinto). Aplicado no SourcesController#create e refletido no dropzone do FE.
      MAX_KNOWLEDGE_SOURCES = 30

      # #1426 — `foto`: a foto mandada na criação, lida por OCR (Processors::Foto) e revisada como os outros.
      FOTO = 'foto'.freeze
      SOURCE_TYPES = (%w[link pdf xlsx docx json txt md] + [FOTO]).freeze
      # Teto de tamanho do ANEXO comprimido (defesa contra upload gigante / zip-bomb). O cap do
      # tamanho DESCOMPRIMIDO de docx/xlsx é aplicado no processor.
      MAX_FILE_BYTES = 25.megabytes
      ALLOWED_CONTENT_TYPES = %w[
        application/pdf
        application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
        application/vnd.openxmlformats-officedocument.wordprocessingml.document
        application/json text/plain text/markdown text/x-markdown application/octet-stream
      ].freeze

      validates :source_type, inclusion: { in: SOURCE_TYPES }
      # Validação branda dos campos de revisão: aceita nil (fontes antigas / ainda não revisadas) mas
      # rejeita valores fora do vocabulário pt-BR. allow_nil mantém a migração aditiva sem regressão.
      validates :review_status, inclusion: { in: REVIEW_STATUSES }, allow_nil: true
      validates :confidence, inclusion: { in: CONFIDENCE_LEVELS }, allow_nil: true
      validates :review_label, inclusion: { in: REVIEW_LABELS }, allow_nil: true
      validate :file_within_limits

      store_accessor :metadata, :fingerprint, :byte_size, :chunk_count, :mime, :origem

      # #1426 — a foto da criação divide a imagem (o mesmo blob) com a conversa do Construtor. Tirá-la da base solta o
      # anexo sem apagar a imagem, que a conversa ainda mostra e lê.
      ORIGEM_FOTO_DA_CRIACAO = 'foto_da_criacao'.freeze
      # #1426 — as páginas do PDF que ficaram de fora da leitura (teto, página grande, prazo), para o aviso ao dono.
      PAGINAS_DE_FORA = 'paginas_de_fora'.freeze
      # #1427 — "Lendo a página X de N…": a página que o OCR do PDF está lendo agora e quantas ele vai ler, só durante a
      # leitura (sai quando ela termina, falha ou é superada).
      PROGRESSO = 'progresso'.freeze
      # #1426 (t4e) — o índice do material grande ([{ paginas, resumo, temas }], Knowledge::ResumoPorSecao), desta leitura:
      # o fim da leitura nova tira o da anterior, e o resumo da nova grava o dela.
      RESUMO_POR_SECAO = 'resumo_por_secao'.freeze
      # #1426 — teto da releitura, o mesmo do painel (TETO_DA_RELEITURA_MS em autonomiaSources.js).
      TETO_DA_RELEITURA = 10.minutes
      attr_accessor :paginas_de_fora
      # #1426 (t4e) — o PDF grande dividido em seções por faixa de páginas ([{ 'paginas' => [ini, fim], 'texto' }]), posto
      # pelo Processors::Pdf só durante a leitura. O Ingestor corta cada seção à parte e grava as páginas em cada trecho.
      attr_accessor :secoes

      before_destroy :soltar_foto_da_conversa, prepend: true # antes do has_one_attached apagar o anexo

      # token-guard idêntico ao padrão EmailCampaign#ai_guarded_update: marca processing + novo
      # sync_token; toda escrita posterior (mark_ready!/mark_failed!) só vence se o token ainda for
      # o ativo E o status ainda for processing. Retorna o token p/ o IngestJob/ProcessJob carregarem.
      def begin_ingestion!
        token = SecureRandom.hex(16)
        # Rebaixa a fonte a NÃO-utilizável até a nova revisão vencer: no re-sync de uma fonte antes
        # 'accepted', o Ingestor recria os KnowledgeEntry (status ready) ANTES do Reviewer rodar, e o
        # Retriever (que exclui needs_review) deixaria o conteúdo re-embebido mas ainda-não-revalidado
        # entrar em Testar/Operar — violando "revisado ANTES de usar". Limpa também o parecer antigo
        # para o Construtor não ler um review_summary defasado. mark_reviewed! recoloca em 'accepted'.
        # Guarda o PARECER ANTERIOR INTEIRO (não só o status) para poder RESTAURAR a geração anterior
        # (entries já servidos) se este re-sync falhar por extração vazia — senão a fonte ficaria
        # needs_review+failed (e mesmo restaurando só o status, sem review_summary o Retriever perderia
        # a exclusão "fora do negócio" e o Construtor leria contexto em branco). Restaura tudo.
        # #1426 — as páginas de fora da leitura anterior saem já aqui: a leitura nova escreve as dela no fim.
        base = (metadata || {}).except(PAGINAS_DE_FORA, PROGRESSO)
        # CORRIDA: se a fonte JÁ estava `processing` (um re-sync anterior em curso), os campos de
        # review já estão rebaixados/em branco — NÃO os capture (preservaria lixo). Mantém o
        # prev_review verdadeiro do re-sync anterior. Só captura snapshot fresco quando não-processing.
        prev_review = if processing?
                        base['prev_review']
                      else
                        { 'review_status' => review_status, 'review_summary' => review_summary,
                          'review_label' => review_label, 'review_reason' => review_reason,
                          'quality_score' => quality_score, 'confidence' => confidence,
                          'reviewed_at' => reviewed_at&.iso8601 }
                      end
        prev_review = prev_review.merge('legado' => true) if !processing? && legado_sem_parecer?
        prev_metadata = base.merge('prev_review' => prev_review)
        update_columns(status: self.class.statuses[:processing], sync_token: token,
                       error: nil, sync_status: nil, metadata: prev_metadata,
                       review_status: 'needs_review', quality_score: nil, confidence: nil,
                       review_summary: nil, review_label: nil, review_reason: nil, reviewed_at: nil,
                       updated_at: Time.current)
        token
      end

      # Re-sync que extraiu VAZIO mas a fonte JÁ tinha conhecimento bom: volta EXATAMENTE ao parecer
      # anterior (ready + review_status/summary/label/reason/score/confidence/reviewed_at) sem apagar
      # nada, preservando a recuperabilidade E o isolamento "fora do negócio" (que o Retriever lê do
      # review_summary). accepted continua accepted; needs_review continua excluído (sem promover).
      # Token-guard. Usado pelo ProcessJob no EmptyExtraction quando há entries.
      # #1426 — na Fase 2, material antigo de verdade (de antes da Revisora: pronto, sem parecer e sem data de revisão, marcado
      # `legado` no begin_ingestion!) volta sem parecer, como estava: "pronto" na tela e servido na busca. Com `needs_review`
      # ele ficaria "Revisando…" para sempre. Material novo nunca revisado (também sem parecer) NÃO leva a marca e volta
      # `needs_review`, fora da busca. Fora da Fase 2, como antes.
      def restore_previous_generation!(token)
        anterior = previous_review_attributes
        anterior = anterior.merge(review_status: nil) if legado_marcado?
        anterior = anterior.merge(status: self.class.statuses[:ready], error: nil, sync_status: nil, synced_at: Time.current)
        guarded_update(token, com_paginas_desta_leitura(anterior))
      end

      # #1426 (revisão adversarial) — a leitura que este job faz ainda é a vigente: mesmo token e ainda lendo. O OCR do PDF
      # confere antes de cada página e para quando outra leitura venceu.
      def leitura_vigente?
        self.class.exists?(id: id, sync_token: sync_token, status: self.class.statuses[:processing])
      end

      # #1427 — o OCR anota a página que começa a ler, sob a mesma guarda das outras escritas da leitura (mesmo token e ainda
      # lendo): um job superado não escreve. Escreve só a chave do progresso (o resto do metadata fica) e renova o
      # updated_at: material avançando não é material parado. A escrita de fim de leitura tira a chave.
      def anotar_progresso!(pagina:, total:)
        progresso = { 'pagina' => pagina, 'total' => total }.to_json
        rows = self.class.where(id: id, sync_token: sync_token, status: self.class.statuses[:processing])
                   .update_all(["metadata = jsonb_set(metadata, '{#{PROGRESSO}}', ?::jsonb), updated_at = ?", progresso, Time.current])
        rows.positive?
      end

      # #1426 (t4e) — o índice por seção, sob a guarda do token (como o parecer: depois do mark_ready!, sem exigir
      # `processing`): um job superado não escreve. Escreve só esta chave; o resto do metadata fica. Recarrega, como o
      # review_guard: o Revisor, que vem logo depois com este mesmo objeto, lê o índice e regrava o metadata a partir dele.
      def anotar_resumo_por_secao!(token, indice)
        return false if token.blank?

        rows = self.class.where(id: id, sync_token: token)
                   .update_all(["metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{#{RESUMO_POR_SECAO}}', ?::jsonb), " \
                                'updated_at = ?', indice.to_json, Time.current])
        reload if rows.positive?
        rows.positive?
      end

      # #1426 — lendo agora, e não parado: começou há menos que o teto da releitura (o mesmo TETO_DA_RELEITURA_MS do painel,
      # depois do qual a tela libera "Ler de novo" num material parado).
      def lendo_agora?
        processing? && updated_at > TETO_DA_RELEITURA.ago
      end

      # GAP (A) — mídia de ENVIO: caminho NOVO, sem ingestão. NÃO embeda, NÃO chama a revisora; só
      # marca `ready` e guarda os metadados de exibição (nome/tipo já vêm de reference/source_type +
      # metadata byte_size/mime do upload). Sem token-guard porque não há pipeline concorrente de
      # ingestão para uma mídia (ela nunca passa por begin_ingestion!). review_status fica nil — as
      # mídias NUNCA entram no retrieval nem no portão de materiais do Construtor.
      def mark_media_ready!
        update_columns(status: self.class.statuses[:ready], error: nil, sync_status: nil,
                       synced_at: Time.current, updated_at: Time.current)
      end

      # #1426 — as páginas do PDF que ficaram de fora nesta leitura (Processors::Pdf põe em `paginas_de_fora`, só em
      # memória) vão junto, sob a mesma guarda de token: um job superado não escreve. Sem nada de fora, a marca some. Vale
      # também para restore_previous_generation! e mark_failed!, que trocam só as chaves desta leitura (com_paginas_desta_leitura).
      def mark_ready!(token, chunk_count:)
        guarded_update(token, status: self.class.statuses[:ready], error: nil,
                              metadata: metadata_desta_leitura.merge('chunk_count' => chunk_count), synced_at: Time.current)
      end

      # FALHA DE REPROCESSO: begin_ingestion! rebaixou o parecer para needs_review ANTES do reprocesso.
      # Se a falha for TRANSITÓRIA (embedding fora do ar, timeout), os KnowledgeEntry antigos seguem
      # INTACTOS (o Ingestor só substitui depois de embedar) — mas sem restaurar o parecer a fonte
      # ficaria needs_review+failed e o Retriever (que exclui needs_review) apagaria da busca uma base
      # BOA. Restaura o snapshot do parecer anterior junto com o `failed`: accepted volta a accepted
      # (entries antigos continuam servíveis); nunca-revisado permanece needs_review (sem promover).
      def mark_failed!(token, message)
        falha = previous_review_attributes.merge(status: self.class.statuses[:failed], error: message.to_s.truncate(500))
        guarded_update(token, com_paginas_desta_leitura(falha))
      end

      # Grava o parecer da IA Revisora. Corre DEPOIS de mark_ready! (status já é `ready`), por isso
      # NÃO usa o guarded_update de ingestão (que exige `processing`); usa o review_guard, que só
      # vence se o sync_token desta revisão ainda for o ativo (anti-supersede: um re-sync concorrente
      # gerou outro token e esta escrita vira no-op). `attrs` traz quality_score/confidence/
      # review_status/review_summary/review_label/review_reason. Retorna true se ganhou a escrita.
      def mark_reviewed!(token, attrs)
        review_guard(token, attrs.merge(reviewed_at: Time.current))
      end

      def accepted?
        review_status == 'accepted'
      end

      private

      # Snapshot do parecer anterior (metadata['prev_review'], gravado por begin_ingestion!) mapeado
      # de volta para as colunas de review — fonte ÚNICA de verdade da restauração, usada por
      # restore_previous_generation! (re-sync vazio) e mark_failed! (falha de reprocesso).
      # SEGURANÇA "revisado antes de usar": só valores do vocabulário voltam; nil/ausente/inesperado
      # vira needs_review (NÃO-recuperável): nunca auto-serve conteúdo nunca-revisado (ex.: entries
      # criados por um job superseded antes do review). needs_resend/needs_review seguem excluídos
      # (fiel). NOTA: uma fonte legada genuína (review_status nil, servida via legado) que falhar no
      # re-sync passa a needs_review — tradeoff seguro e raro (re-revisar reativa).
      # #1426 — material de antes da Revisora: já pronto, sem parecer e sem data de revisão. Material novo (ainda não lido)
      # não é pronto e não entra. Só a Fase 2 usa a marca (restore_previous_generation!).
      def legado_sem_parecer?
        kind_knowledge? && ready? && review_status.nil? && reviewed_at.nil? && Autonomia::Agents::Fase2.ligada?(account)
      end

      # A marca só nasce na Fase 2; conferida de novo aqui, para a conta que saiu do piloto no meio da leitura voltar à main.
      def legado_marcado?
        (metadata || {}).dig('prev_review', 'legado') == true && Autonomia::Agents::Fase2.ligada?(account)
      end

      # O metadata com o que ficou de fora NESTA leitura (Source#paginas_de_fora): a marca da leitura anterior sai sempre.
      def metadata_desta_leitura
        base = (metadata || {}).except(PAGINAS_DE_FORA, PROGRESSO, RESUMO_POR_SECAO)
        paginas_de_fora.present? ? base.merge(PAGINAS_DE_FORA => paginas_de_fora) : base
      end

      # #1427 — a falha e a volta à geração anterior mexem só nas chaves desta leitura, no próprio banco: tiram o progresso
      # (anotado por update_all, às vezes por outra instância, então este objeto pode nem conhecê-lo) e trocam as páginas
      # de fora pelas desta leitura. O resto do metadata fica como está no banco, mesmo o que foi gravado no meio-tempo.
      def com_paginas_desta_leitura(attrs)
        desta_leitura = paginas_de_fora.present? ? { PAGINAS_DE_FORA => paginas_de_fora } : {}
        sql = self.class.sanitize_sql_array(
          ["(COALESCE(metadata, '{}'::jsonb) - ? - ?) || ?::jsonb", PROGRESSO, PAGINAS_DE_FORA, desta_leitura.to_json]
        )
        attrs.merge(metadata: Arel.sql(sql))
      end

      def previous_review_attributes
        prev = (metadata || {})['prev_review'] || {}
        status_value = prev['review_status']
        status_value = 'needs_review' unless REVIEW_STATUSES.include?(status_value)
        { review_status: status_value, review_summary: prev['review_summary'],
          review_label: prev['review_label'], review_reason: prev['review_reason'],
          quality_score: prev['quality_score'], confidence: prev['confidence'],
          reviewed_at: prev['reviewed_at'] }
      end

      # Guard de revisão: escreve só se o sync_token ainda for o desta execução (não exige status —
      # a fonte já está `ready`/`failed`). update_all atômico fecha a janela check→write. true se ganhou.
      def review_guard(token, attrs)
        return false if token.blank?

        rows = self.class.where(id: id, sync_token: token)
                   .update_all(attrs.merge(updated_at: Time.current))
        reload if rows.positive?
        rows.positive?
      end

      # Bloqueia anexos acima do teto comprimido e de content-types não suportados (DoS de memória /
      # zip-bomb / upload arbitrário). Só roda quando há arquivo (fontes `link` não têm anexo).
      def file_within_limits
        return unless file.attached?

        # #1426 — a mensagem vai inteira para a tela (422): texto para quem manda o arquivo, nunca código.
        errors.add(:base, I18n.t('autonomia.source.arquivo_grande')) if file.blob.byte_size > MAX_FILE_BYTES
        errors.add(:base, I18n.t('autonomia.source.arquivo_tipo')) unless allowed_content_types.include?(file.blob.content_type)
      end

      def soltar_foto_da_conversa
        file.detach if origem == ORIGEM_FOTO_DA_CRIACAO && file.attached?
      end

      # Imagem só na foto (#1426), e a foto só com imagem.
      def allowed_content_types
        source_type == FOTO ? Autonomia::Agents::Config::IMAGE_CONTENT_TYPES : ALLOWED_CONTENT_TYPES
      end

      # Escreve só se a ingestão identificada por `token` ainda for a ativa e ainda processing.
      # update_all atômico fecha a janela entre checagem e escrita. Retorna true se ganhou (1 linha).
      def guarded_update(token, attrs)
        return false if token.blank?

        rows = self.class.where(id: id, sync_token: token, status: self.class.statuses[:processing])
                   .update_all(attrs.merge(updated_at: Time.current))
        reload if rows.positive?
        rows.positive?
      end
    end
  end
end
