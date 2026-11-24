# #3101: a segunda mensagem do WhatsApp Oficial é outro modelo aprovado da mesma caixa (fora das 24 horas a Meta só deixa
# mandar modelo). Conferido na criação da primeira, para a campanha nova não ser recusada dias depois:
# - aprovado na caixa e diferente do modelo da primeira;
# - sem cupom, oferta com prazo ou carrossel (pedem dados que a revisão do reenvio não tem);
# - cada variável com de onde vem, pelas colunas do público (CampaignJourney::VariableBindings, a mesma conferência da
#   primeira).
# Guarda { modelo_id, template_params, ligacoes } (CampaignJourney::Reenvio).
class CampaignJourney::Reenvio::Modelo
  Invalido = CampaignJourney::Reenvio::Invalido

  def initialize(campanha)
    @campanha = campanha
  end

  def conferir(dados)
    params = dados['template_params'].to_h.deep_stringify_keys
    modelo = aprovado(params['name'], params['language'])
    raise Invalido, 'reenvio_modelo_nao_aprovado' unless modelo
    raise Invalido, 'reenvio_modelo_igual' if mesmo_da_primeira?(modelo)
    raise Invalido, 'reenvio_modelo_com_oferta' if Whatsapp::Templates::SendableFormat.offer_format?(modelo)

    ligacoes = dados['ligacoes'].to_h.deep_stringify_keys
    conferir_ligacoes!(ligacoes, modelo)
    { 'modelo_id' => dados['modelo_id'].to_s, 'template_params' => params, 'ligacoes' => ligacoes }
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

  def conferir_ligacoes!(ligacoes, modelo)
    publico = CampaignAudienceLink.for_campaign(@campanha)&.campaign_import
    CampaignJourney::VariableBindings.new(ligacoes, {}).validate!(publico, template_keys: CampaignJourney::TemplateVariableKeys.keys(modelo))
  rescue CampaignJourney::VariableBindings::Error => e
    raise Invalido, "reenvio_#{e.message}"
  end
end
