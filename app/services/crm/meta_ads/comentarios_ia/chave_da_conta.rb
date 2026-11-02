# IA cuida dos comentários: a chave de IA é sempre a da própria conta ("Sempre a chave de cada conta. Sempre!", Rodrigo).
# O Crm::Ai::CredentialResolver, que outros recursos usam, cai na chave da instalação quando a conta não tem o hook
# crm_kanban_ai. Aqui não: só a do hook (`source: :hook`). Sem ela, nil, e quem chama não vai ao modelo
# (Classificador: Bloqueado `no_credential`; Rascunho e Foto: `no_credential`).
module Crm::MetaAds::ComentariosIa::ChaveDaConta
  module_function

  def de(account)
    credencial = Crm::Ai::CredentialResolver.new(account: account).resolve
    credencial if credencial.present? && credencial[:source] == :hook
  end
end
