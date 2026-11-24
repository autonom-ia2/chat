# #3101: a segunda mensagem do WhatsApp Oficial é outro modelo aprovado da mesma caixa (fora das 24 horas a Meta só deixa
# mandar modelo). Conferido na criação da primeira, para a campanha nova não ser recusada dias depois:
# - aprovado na caixa e diferente do modelo da primeira;
# - sem cupom, oferta com prazo ou carrossel (pedem dados que a revisão do reenvio não tem);
# - o template_params normalizado como o da primeira (topo com arquivo, botões: CampaignJourney::WhatsappCampaignCreator
#   .normalized_template_params), recusado já aqui com reenvio_<código> e guardado normalizado;
# - cada variável com de onde vem, pelas colunas do público (CampaignJourney::VariableBindings, a mesma conferência da
#   primeira), com os textos padrão da primeira para as variáveis de mesmo nome.
# Guarda { modelo_id, template_params, ligacoes } (CampaignJourney::Reenvio).
class CampaignJourney::Reenvio::Modelo
  Invalido = CampaignJourney::Reenvio::Invalido

  def initialize(campanha)
    @campanha = campanha
    @link = CampaignAudienceLink.for_campaign(campanha)
  end

  def conferir(dados)
    params = dados['template_params'].to_h.deep_stringify_keys
    modelo = aprovado(params['name'], params['language'])
    raise Invalido, 'reenvio_modelo_nao_aprovado' unless modelo
    raise Invalido, 'reenvio_modelo_igual' if mesmo_da_primeira?(modelo)
    raise Invalido, 'reenvio_modelo_com_oferta' if Whatsapp::Templates::SendableFormat.offer_format?(modelo)

    ligacoes = dados['ligacoes'].to_h.deep_stringify_keys
    conferir_ligacoes!(ligacoes, modelo)
    { 'modelo_id' => dados['modelo_id'].to_s, 'template_params' => normalizado(params, modelo), 'ligacoes' => ligacoes }
  end

  private

  def aprovado(nome, idioma)
    Array(@campanha.inbox&.channel&.message_templates).find do |modelo|
      modelo['name'] == nome.to_s && modelo['language'].to_s.casecmp?(idioma.to_s) && modelo['status'].to_s.casecmp?('approved')
    end
  end

  def mesmo_da_primeira?(modelo)
    primeira = @campanha.template_params.to_h
    primeira['name'] == modelo['name'] && primeira['language'].to_s.casecmp?(modelo['language'].to_s)
  end

  def normalizado(params, modelo)
    CampaignJourney::WhatsappCampaignCreator.normalized_template_params(params, template: modelo, inbox: @campanha.inbox)
  rescue Whatsapp::Templates::HeaderMedia::Invalid => e
    raise Invalido, "reenvio_#{e.code}"
  end

  def conferir_ligacoes!(ligacoes, modelo)
    padroes = CampaignJourney::Reenvio.padroes_das_chaves(@link, ligacoes.keys)
    CampaignJourney::VariableBindings.new(ligacoes, padroes)
                                     .validate!(@link&.campaign_import, template_keys: CampaignJourney::TemplateVariableKeys.keys(modelo))
  rescue CampaignJourney::VariableBindings::Error => e
    raise Invalido, "reenvio_#{e.message}"
  end
end
