# "Preciso mandar um aviso desta finalidade fora da janela de 24 h: me dê um modelo aprovado" (#1518). Só ESCOLHE ou
# CRIA; o envio continua com quem chama (`template_params` do upstream, pelo `Autonomia::LiteralMessageBuilder`).
#
#   Whatsapp::Templates::Garantir.call(inbox:, finalidade: :cobranca_vencimento, momento: :antes, com_valor: true)
#   # => { status: :pronto, nome:, idioma:, categoria:, campos: { '1' => 'cliente.primeiro_nome', ... } }
#   #  | { status: :em_analise, nome:, idioma: }         criado agora ou ainda em análise na Meta
#   #  | { status: :indisponivel, motivo:, ... }         sem número oficial, Meta fora, recusado...
#
# `campos`: { "<n.º da variável do corpo>" => "<chave do catálogo>" }, só o corpo, na ordem: `processed_params.body`
# sai dele. `idioma: nil` = o do pronto (pt_BR); outro idioma sem pronto volta `idioma_sem_pronto`.
# `botoes` (só quando o pronto tem botões): a posição de cada um no modelo, para montar `processed_params.buttons`
# alinhado, sem índice fixo em quem chama:
#   botoes: [{ 'indice' => 0, 'tipo' => 'url', 'campo' => 'horario.link_codigo' },   # URL com {{1}} no fim: o valor do campo
#            { 'indice' => 1, 'tipo' => 'quick_reply', 'payload' => 'stop_notices' }] # resposta rápida: o payload no envio
# `motivo` de `:indisponivel`: sem_whatsapp_oficial, idioma_sem_pronto, formato (o envio não manda o formato), recusado
# (com `detalhe`, o motivo da Meta), pausado, desativado, situacao_desconhecida, meta_fora, sem_permissao, meta_recusou,
# texto_diferente (modelo com o nome do pronto e outro texto), perfil_invalido (o perfil não pode ser gravado: nada é
# criado).
#
# Regras:
# - o modelo da finalidade é o pronto de `Finalidades` (nome estável), achado na lista da caixa (`message_templates`);
# - aprovado só serve se o envio sabe mandar o formato (`SendableFormat`);
# - em análise, recusado, pausado ou desativado: nunca cria de novo (a Meta não aceita outro com o mesmo nome e idioma);
# - fora da lista: cria pelo `MetaClient` (que não duplica pelo nome), depois da mesma conferência estrutural do `Manager`
#   (`SubmitFormat`), põe na lista pela `ChannelList` e grava o perfil com o dono do sistema e sem quem criou (origem
#   sistema). O dono protege o modelo na tela de Modelos (`SystemTemplates`), onde a situação aparece (recusado com o
#   motivo da Meta).
# Fala com a Meta (até alguns segundos): chamar de job, não de requisição do painel. Nada do texto da Meta vai para o log.
class Whatsapp::Templates::Garantir
  Finalidades = Whatsapp::Templates::Finalidades
  MetaClient = Whatsapp::Templates::MetaClient
  INDISPONIVEIS = { 'REJECTED' => 'recusado', 'PAUSED' => 'pausado', 'DISABLED' => 'desativado' }.freeze
  EM_ANALISE = %w[PENDING IN_APPEAL].freeze
  APROVADO = 'APPROVED'.freeze

  def self.call(inbox:, finalidade:, idioma: nil, **opcoes)
    new(inbox: inbox, pronto: Finalidades.pronto(finalidade, **opcoes), idioma: idioma).call
  end

  def initialize(inbox:, pronto:, idioma:)
    @inbox = inbox
    @pronto = pronto
    @idioma = idioma
  end

  def call
    return indisponivel('sem_whatsapp_oficial') unless MetaClient.supported?(@inbox)
    return indisponivel('idioma_sem_pronto') unless @idioma.nil? || @idioma.to_s.casecmp?(@pronto.idioma)

    template = listed
    return criar unless template

    registrar_perfil(template)
    situacao(template)
  end

  private

  def channel
    @inbox.channel
  end

  # Lida direto do banco: a lista do objeto pode estar velha (outro escritor gravou depois que a caixa foi carregada).
  def listed
    lista = Whatsapp::Templates::ChannelList.entries(channel.class.where(id: channel.id).pick(:message_templates))
    lista.find { |item| item['name'] == @pronto.nome && item['language'].to_s.casecmp?(@pronto.idioma) }
  end

  def situacao(template)
    status = template['status'].to_s.upcase
    return aprovado(template) if status == APROVADO
    return { status: :em_analise, nome: template['name'], idioma: template['language'] } if EM_ANALISE.include?(status)

    motivo = INDISPONIVEIS.fetch(status, 'situacao_desconhecida')
    detalhe = template['rejected_reason'].presence if motivo == 'recusado'
    { status: :indisponivel, motivo: motivo, detalhe: detalhe, nome: template['name'], idioma: template['language'] }.compact
  end

  # Só serve o modelo com o texto do pronto: com o mesmo nome e outro texto (feito à mão no Gerenciador da Meta), os
  # `campos` do catálogo não casariam com as variáveis dele.
  def aprovado(template)
    return indisponivel('formato') unless Whatsapp::Templates::SendableFormat.sendable?(template)
    return indisponivel('texto_diferente') unless corpo_de(template) == @pronto.texto

    resultado = { status: :pronto, nome: template['name'], idioma: template['language'],
                  categoria: template['category'].to_s.upcase.presence || Finalidades::CATEGORIA, campos: @pronto.campos }
    @pronto.botoes.any? ? resultado.merge(botoes: @pronto.botoes_do_envio) : resultado
  end

  def corpo_de(template)
    Whatsapp::Templates::SendableFormat.hashes(template['components']).find { |item| item['type'].to_s.casecmp?('BODY') }&.dig('text')
  end

  # O perfil é conferido ANTES de falar com a Meta (como no `Manager`): perfil inválido não deixa modelo lá sem perfil aqui.
  def criar
    corpo = @pronto.corpo.deep_stringify_keys
    return indisponivel('formato') if Whatsapp::Templates::SubmitFormat.problems(corpo).any?
    return falha('perfil_invalido') unless montar_perfil.valid?

    template = MetaClient.new(inbox: @inbox).create(corpo).template
    Whatsapp::Templates::ChannelList.upsert!(channel, template)
    registrar_perfil(template)
    situacao(template)
  rescue MetaClient::Unreachable
    falha('meta_fora')
  rescue MetaClient::MetaError => e
    falha(e.code == 'permission_denied' ? 'sem_permissao' : 'meta_recusou')
  end

  # O perfil do sistema existe sempre que o modelo está na lista (também quando ele entrou por outro caminho, ou quando
  # uma chamada anterior caiu entre a lista e o perfil). Dois jobs ao mesmo tempo: o segundo acha o do primeiro numa
  # segunda leitura (savepoint próprio: a colisão não derruba a transação de quem chamou). O perfil não decide a
  # resposta: o modelo já está na Meta e na lista, e o selo do sistema também vem do nome (`SystemTemplates`). Falha
  # fica no log.
  def registrar_perfil(template, tentativa: 1)
    perfil = montar_perfil
    perfil.meta_template_id = template['id'].presence || perfil.meta_template_id
    WhatsappTemplateProfile.transaction(requires_new: true) { perfil.save! } if perfil.changed?
  # A colisão chega pelo índice único ou, quando o outro já terminou, pela validação de unicidade.
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    return registrar_perfil(template, tentativa: tentativa + 1) if tentativa == 1

    Rails.logger.warn("[whatsapp][templates][garantir] perfil_nao_gravado inbox_id=#{@inbox.id} template=#{@pronto.nome}")
  end

  def montar_perfil
    perfil = WhatsappTemplateProfile.for_inbox(@inbox).find_by(name: @pronto.nome, language: @pronto.idioma) ||
             WhatsappTemplateProfile.new(account_id: @inbox.account_id, inbox: @inbox, waba_id: channel.waba_id,
                                         name: @pronto.nome, language: @pronto.idioma)
    perfil.assign_attributes(system_owner: @pronto.dono, fields: @pronto.campos,
                             friendly_name: perfil.friendly_name.presence || @pronto.nome_amigavel)
    perfil
  end

  def falha(motivo)
    Rails.logger.warn("[whatsapp][templates][garantir] #{motivo} inbox_id=#{@inbox.id} template=#{@pronto.nome}")
    indisponivel(motivo)
  end

  def indisponivel(motivo)
    { status: :indisponivel, motivo: motivo }
  end
end
