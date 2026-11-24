# #3099: os números de cada versão de um passo "mensagem" com duas versões, desde que o teste (re)começou
# (`teste_desde` da VersaoVencedora). Servem ao histórico da automação e à escolha automática (DuasVersoes::Teste).
#
# - Receberam: os envios que saíram (uma pessoa que passa duas vezes pelo passo conta duas);
# - Responderam: o envio depois do qual o contato escreveu em até RESPOSTA_EM_HORAS (as mesmas 72 h da campanha,
#   CampaignJourney::ResultReplies), em qualquer conversa da conta;
# - Compraram: quem fechou uma venda em até 7 dias depois do primeiro envio da versão, pela régua do histórico
#   (Autonomia::Automacao::ComprasDoHistorico, CampaignJourney::ComprasNaJanela). Só com o CRM ligado.
class Autonomia::Automacao::DuasVersoes::Numeros
  RESPOSTA_EM_HORAS = 72
  ENVIOS = 'autonomia_automacao_versoes_envios'.freeze

  def initialize(linha)
    @linha = linha
  end

  def envios
    ::Autonomia::Automacao::VersaoEnvio.do_passo(@linha.automacao_id, @linha.passo).where(created_at: @linha.teste_desde..)
  end

  # { 1 => n, 2 => m }
  def receberam
    @receberam ||= envios.group(:versao).count
  end

  # Quanto falta para a versão mais atrasada chegar ao mínimo (0 = o teste fechou).
  def faltam
    ::Autonomia::Automacao::DuasVersoes::VERSOES.map { |versao| [minimo - receberam[versao].to_i, 0].max }.max
  end

  # A hora em que a versão mais atrasada chegou ao mínimo: o fim do teste. nil enquanto falta gente.
  def fechou_em
    return if faltam.positive?

    ::Autonomia::Automacao::DuasVersoes::VERSOES.map do |versao|
      envios.where(versao: versao).order(:created_at, :id).offset(minimo - 1).pick(:created_at)
    end.max
  end

  # [{ receberam:, responderam:, compraram:, valor: }, { … }] da versão 1 e da versão 2. `pipeline_ids`: nil = todos os
  # funis; `com_valor`: o dinheiro das compras por moeda (nil sem a permissão de ver valor de venda).
  def por_versao(pipeline_ids: nil, com_valor: false)
    ::Autonomia::Automacao::DuasVersoes::VERSOES.map do |versao|
      da_versao = envios.where(versao: versao)
      compras = compras_de(da_versao, pipeline_ids)
      { receberam: receberam[versao].to_i, responderam: da_versao.where(respondeu).count, compraram: compras.pluck(:contato).uniq.size,
        valor: (CampaignJourney::ComprasNaJanela.valor(compras) if com_valor) }
    end
  end

  private

  def minimo = ::Autonomia::Automacao::DuasVersoes::MINIMO_POR_VERSAO

  # O contato escreveu (mensagem recebida) depois do envio, dentro da janela da resposta.
  def respondeu
    [<<~SQL.squish, { contato: 'Contact', recebida: Message.message_types[:incoming] }]
      EXISTS (SELECT 1 FROM messages WHERE messages.account_id = #{ENVIOS}.account_id AND messages.sender_type = :contato
      AND messages.sender_id = #{ENVIOS}.contact_id AND messages.message_type = :recebida
      AND messages.created_at > #{ENVIOS}.created_at AND messages.created_at <= #{ENVIOS}.created_at + interval '#{RESPOSTA_EM_HORAS} hours')
    SQL
  end

  def compras_de(da_versao, pipeline_ids)
    return [] unless Crm::Config.enabled?

    inicios = da_versao.where.not(contact_id: nil).group(:contact_id).minimum(:created_at)
    CampaignJourney::ComprasNaJanela.new(@linha.account, dias: ::Autonomia::Automacao::ComprasDoHistorico::JANELA_DE_COMPRA,
                                                         pipeline_ids: pipeline_ids).de(inicios)
  end
end
