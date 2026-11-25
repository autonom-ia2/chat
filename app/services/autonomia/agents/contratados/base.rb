# A BASE OFICIAL DO AGENTE CONTRATADO (#3211): os textos da pasta `base/` do modelo (condições gerais e folheto da
# seguradora), mantidos pela Autonom.ia no deploy. Cada agente contratado recebe uma cópia na própria base de
# conhecimento, numa fonte de sistema (`ready` e `accepted`, sem a IA Revisora, como a base do Guia), com um trecho por
# bloco `### ` (cada bloco é autocontido: a busca devolve a cláusula inteira).
#
# A versão é o hash dos arquivos: mudou um arquivo no deploy, o cron (`BaseEmDiaJob`) re-semeia os contratados. Semear
# passa pela chamada PAGA de embedding (a chave de IA da conta), por isso só roda em segundo plano (`SemearBaseJob`) e
# só quando a versão do agente é outra.
module Autonomia::Agents::Contratados::Base
  MODELO = 'seguro_viagem_universal'.freeze
  PASTA = Autonomia::Agents::Contratados::MODELOS.fetch(MODELO)[:pasta].join('base')
  REFERENCIA = 'Base oficial Universal'.freeze
  # A marca da fonte de sistema na `metadata` (a fonte que a semeadura apaga e recria).
  MARCA_DA_FONTE = 'contratado_base'.freeze
  INICIO_DO_BLOCO = '### '.freeze
  TRAVA = 'autonomia:contratados:base:'.freeze

  module_function

  # -> 16 caracteres do SHA256 do conteúdo dos arquivos `.md` da pasta, em ordem de nome.
  def versao_de(pasta)
    Digest::SHA256.hexdigest(arquivos(pasta).map(&:read).join("\n")).first(16)
  end

  def arquivos(pasta)
    Pathname.new(pasta).glob('*.md').sort
  end

  # O texto em blocos que começam por `### ` (o que vem antes do primeiro bloco, como o comentário da fonte, fica fora).
  def blocos(texto)
    blocos = []
    texto.each_line do |linha|
      if linha.start_with?(INICIO_DO_BLOCO)
        blocos << +linha
      elsif blocos.any?
        blocos.last << linha
      end
    end
    blocos.map(&:strip)
  end

  def fontes(agent)
    agent.sources.where("metadata->>'#{MARCA_DA_FONTE}' = 'true'")
  end

  # A versão gravada é a do deploy e a base tem trechos prontos.
  def em_dia?(agent)
    agent.config.to_h[Autonomia::Agents::Contratados::BASE_VERSAO] == VERSAO &&
      agent.knowledge_entries.ready.exists?(source_id: fontes(agent).select(:id))
  end

  # Semeia sempre (apaga a fonte anterior e recria). Quem decide se precisa é `semear_se_preciso!`.
  def semear!(agent, pasta: PASTA)
    com_trava(agent) { semear_sem_trava!(agent, pasta) }
  end

  # O caminho do job: relê o agente sob a trava, e dois jobs do mesmo agente não pagam o embedding duas vezes.
  def semear_se_preciso!(agent)
    com_trava(agent) do
      atual = Autonomia::Agents::Agent.kept.find_by(id: agent.id)
      next false if atual.nil? || !atual.contratado? || em_dia?(atual)

      semear_sem_trava!(atual, PASTA)
      true
    end
  end

  def semear_sem_trava!(agent, pasta)
    textos = arquivos(pasta).flat_map { |arquivo| blocos(arquivo.read) }
    return if textos.empty?

    modelo = Autonomia::Agents::Config.active_embedding_model
    large = Autonomia::Agents::Config.embedding_column(modelo) == Autonomia::Agents::Config::EMBEDDING_LARGE_COLUMN
    # Fora da transação: é a chamada externa (paga). Se falhar, a base anterior fica como estava.
    vetores = Autonomia::Agents::EmbeddingService.new(account: agent.account, model: modelo).embed_batch(textos)

    ActiveRecord::Base.transaction do
      fontes(agent).find_each(&:destroy!)
      fonte = criar_fonte!(agent)
      textos.each_with_index do |texto, indice|
        criar_entrada!(fonte, texto, vetores[indice], indice, large) if vetores[indice].present?
      end
      gravar_versao!(agent, versao_de(pasta))
    end
  end

  # Fonte de SISTEMA (conteúdo nosso): direto a `ready` e `accepted`, como a do Guia. O Retriever ignora `needs_review`.
  def criar_fonte!(agent)
    agent.sources.create!(account_id: agent.account_id, source_type: 'md', kind: :knowledge, reference: REFERENCIA,
                          metadata: { MARCA_DA_FONTE => true }, status: :ready, review_status: 'accepted')
  end

  # Na coluna do modelo ativo, como o Guia (`Guide::Seed#create_guide_entry`): `embedding_large` (halfvec) por SQL
  # sanitizado, que a gem neighbor não casta; `embedding` pela gem.
  def criar_entrada!(fonte, texto, vetor, indice, large)
    entrada = Autonomia::Agents::KnowledgeEntry.create!(
      autonomia_agent_id: fonte.autonomia_agent_id, account_id: fonte.account_id, source_id: fonte.id, content: texto,
      chunk_index: indice, status: :ready, metadata: { source_type: 'md' }, **(large ? {} : { embedding: vetor })
    )
    return unless large

    Autonomia::Agents::KnowledgeEntry.where(id: entrada.id)
                                     .update_all(['embedding_large = ?::halfvec', "[#{vetor.join(',')}]"]) # rubocop:disable Rails/SkipsModelValidations
  end

  # Só a chave da versão, por `jsonb_set` (o desenho de `Agent#bump_knowledge_refresh_token!`): um `config` lido antes
  # da semeadura e gravado depois não apaga o que outro caminho mudou no meio. O Agent mantém a chave num save com
  # cópia velha (`Contratado#manter_marca_salva`).
  def gravar_versao!(agent, versao)
    Autonomia::Agents::Agent.kept.where(id: agent.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ['config = jsonb_set(COALESCE(config, \'{}\'::jsonb), \'{contratado_base_versao}\', ?::jsonb, true), updated_at = ?',
       versao.to_json, Time.current]
    )
  end

  # Trava de SESSÃO por agente: serializa a semeadura inteira sem segurar uma transação durante o embedding.
  def com_trava(agent)
    conexao = ActiveRecord::Base.connection
    chave = conexao.quote("#{TRAVA}#{agent.id}")
    conexao.execute("SELECT pg_advisory_lock(hashtext(#{chave}))")
    begin
      yield
    ensure
      conexao.execute("SELECT pg_advisory_unlock(hashtext(#{chave}))")
    end
  end

  VERSAO = versao_de(PASTA)
end
