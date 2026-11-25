# A BASE OFICIAL DO AGENTE CONTRATADO (#3211): os textos da pasta `base/` do modelo (condições gerais e folheto da
# seguradora), mantidos pela Autonom.ia no deploy. Cada agente contratado recebe uma cópia na própria base de
# conhecimento, numa fonte de sistema (`ready` e `accepted`, sem a IA Revisora, como a base do Guia), com um trecho por
# bloco `### ` (cada bloco é autocontido: a busca devolve a cláusula inteira).
#
# A versão é o hash dos arquivos: mudou um arquivo no deploy, o cron (`BaseEmDiaJob`) re-semeia os contratados. Semear
# passa pela chamada PAGA de embedding, por isso só roda em segundo plano (`SemearBaseJob`) e só quando a versão do
# agente é outra. A chave é SEMPRE a da própria conta (regra do Rodrigo, 24/11): sem ela, não semeia, e a corretora põe
# a dela; a chave da instalação nunca paga a base de um cliente.
module Autonomia::Agents::Contratados::Base
  MODELO = 'seguro_viagem_universal'.freeze
  PASTA = Autonomia::Agents::Contratados::MODELOS.fetch(MODELO)[:pasta].join('base')
  REFERENCIA = 'Base oficial Universal'.freeze
  # A marca da fonte de sistema na `metadata` (a fonte que a semeadura apaga e recria).
  MARCA_DA_FONTE = 'contratado_base'.freeze
  INICIO_DO_BLOCO = '### '.freeze
  TRAVA = 'autonomia:contratados:base:'.freeze
  # Por que a semeadura não aconteceu (log e retorno), nunca a mensagem do provedor.
  SEM_CHAVE_DA_CONTA = 'sem_chave_da_conta'.freeze
  BASE_PARCIAL = 'base_parcial'.freeze
  # Cada semeadura que volta `BASE_PARCIAL` pagou o embedding inteiro. Depois deste número de tentativas na mesma versão,
  # o cron (`BaseEmDiaJob`) para de enfileirar o agente; a contagem é por versão (o deploy seguinte zera) e vence em
  # `VALIDADE_DAS_PARCIAIS` (depois disso, mais `TETO_DE_PARCIAIS` tentativas).
  TETO_DE_PARCIAIS = 3
  VALIDADE_DAS_PARCIAIS = 30.days
  PARCIAIS = 'autonomia:contratados:base:parciais:'.freeze

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

  # Semeia mesmo em dia (apaga a fonte anterior e recria), com o retorno de `semear_sem_trava!`. Quem decide se precisa é
  # `semear_se_preciso!`.
  def semear!(agent, pasta: PASTA)
    com_trava(agent) { semear_sem_trava!(agent, pasta) }
  end

  # O caminho do job: relê o agente sob a trava, e dois jobs do mesmo agente não pagam o embedding duas vezes.
  # -> false quando não precisa (apagado, não contratado, em dia); senão, o retorno de `semear_sem_trava!`.
  def semear_se_preciso!(agent)
    com_trava(agent) do
      atual = Autonomia::Agents::Agent.kept.find_by(id: agent.id)
      next false if atual.nil? || !atual.contratado? || em_dia?(atual)

      semear_sem_trava!(atual, PASTA)
    end
  end

  # A chave de IA da PRÓPRIA conta (o hook `crm_kanban_ai`, `source: :hook`), ou nil. O `CredentialResolver` cai na chave
  # da instalação quando a conta não tem o hook; aqui isso não vale (o desenho de `Crm::MetaAds::ComentariosIa::ChaveDaConta`).
  def chave_da_conta(account)
    credencial = Crm::Ai::CredentialResolver.new(account: account).resolve
    credencial if credencial.present? && credencial[:source] == :hook
  end

  # -> true quando semeou; senão o motivo (`SEM_CHAVE_DA_CONTA`, `BASE_PARCIAL`), com a base anterior intacta.
  def semear_sem_trava!(agent, pasta)
    textos = arquivos(pasta).flat_map { |arquivo| blocos(arquivo.read) }
    return false if textos.empty?

    # Lida sob a trava, logo antes da chamada, e passada ao serviço: a chamada não resolve a chave de novo, então um hook
    # tirado no meio do caminho não a faz cair na chave da instalação.
    credencial = chave_da_conta(agent.account)
    return SEM_CHAVE_DA_CONTA if credencial.nil?

    modelo = Autonomia::Agents::Config.active_embedding_model
    # Fora da transação: é a chamada externa (paga). Se falhar, a base anterior fica como estava.
    vetores = Autonomia::Agents::EmbeddingService.new(account: agent.account, model: modelo, credencial: credencial)
                                                 .embed_batch(textos)
    # Um trecho sem vetor deixaria a base pela metade com a versão nova gravada, e o cron nunca a consertaria.
    return BASE_PARCIAL if vetores.size != textos.size || vetores.any?(&:blank?)

    trocar_base!(agent, textos, vetores, modelo, versao_de(pasta))
    true
  end

  def trocar_base!(agent, textos, vetores, modelo, versao)
    large = Autonomia::Agents::Config.embedding_column(modelo) == Autonomia::Agents::Config::EMBEDDING_LARGE_COLUMN
    ActiveRecord::Base.transaction do
      fontes(agent).find_each(&:destroy!)
      fonte = criar_fonte!(agent)
      textos.each_with_index { |texto, indice| criar_entrada!(fonte, texto, vetores[indice], indice, large) }
      gravar_versao!(agent, versao)
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

  # Conta uma semeadura que voltou `BASE_PARCIAL` para este agente nesta versão.
  def anotar_parcial!(agent_id)
    chave = chave_das_parciais(agent_id)
    Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, VALIDADE_DAS_PARCIAIS.to_i)
  end

  def parciais_esgotadas?(agent_id)
    Redis::Alfred.get(chave_das_parciais(agent_id)).to_i >= TETO_DE_PARCIAIS
  end

  def chave_das_parciais(agent_id)
    "#{PARCIAIS}#{agent_id}:#{VERSAO}"
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
