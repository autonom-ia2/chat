# #2519 (frente 1): quantos comentários de cada anúncio estão com o dono, sem ninguém ter agido. É o contrato com o painel
# de Anúncios (#2521): só leitura, lido do banco (nunca da Meta), sem visibilidade por pessoa (comentário não é
# conversa; quem abre o painel já passou pelo gate dele).
#
# Esperando: o que a IA deixou com o dono nos últimos 7 dias (Registro: reclamação, privado recusado ou incerto, já
# tinha o privado, era o caso mas não sai ali, não cuidou) e o que chegou sem cuidado ligado (`no_care`) e a IA não pegou
# depois. Sai da conta quando a pessoa age no comentário pela plataforma (qualquer ação com actor `user`: responder,
# privado, esconder, apagar — no Instagram, InstagramComments e SeusPosts::ComentariosInstagram gravam as quatro).
#
# Limites, ditos no PR:
# - conta a partir do deploy do #2519 (antes dele, o comentário sem cuidado não deixava registro);
# - só o comentário que trouxe o `ad_id`: no Instagram vem no evento; no Facebook não vem, e sem cuidado nada no banco
#   liga o post ao anúncio. Para o Facebook sem cuidado, o painel mostra o total dos insights;
# - o comentário cujo evento nunca chegou não tem linha: só o "Esperando você" do Painel (que lê a Meta) o mostra;
# - a resposta dada direto no app do Instagram (fora da plataforma) não deixa linha: o comentário segue contado até os
#   7 dias.
module Crm::MetaAds::ComentariosIa::Esperando
  COM_O_DONO = %w[ai_unread kept_for_owner to_you private_reply_failed private_reply_unsure private_reply_already].freeze

  module_function

  # { 'ad_id' => Integer }, com zero para o anúncio sem nada esperando.
  def por_anuncio(account_id, ad_ids)
    ids = Array(ad_ids).map(&:to_s).uniq
    return {} if ids.empty?

    contagem = esperam(account_id, ids).group(:ad_id).distinct.count(:comment_id)
    ids.index_with { |id| contagem.fetch(id, 0) }
  end

  def esperam(account_id, ids)
    da_ia = Crm::MetaAdsCommentAction.where(account_id: account_id, actor: Crm::MetaAds::ComentariosIa::Registro::ACTOR, ad_id: ids)
                                     .where(at: Crm::MetaAds::ComentariosIa::Cuidar::JANELA.ago..)
    sem_cuidado = da_ia.where(action: Crm::MetaAds::ComentariosIa::Registro::SEM_CUIDADO)
                       .where(sem_outra(actor: Crm::MetaAds::ComentariosIa::Registro::ACTOR, action: Crm::MetaAds::ComentariosIa::Registro::LIDO))

    da_ia.where(action: COM_O_DONO).or(sem_cuidado).where(sem_outra(actor: 'user'))
  end

  # NOT EXISTS de outra ação no mesmo comentário (conta, rede e id): o índice idx_crm_meta_ads_comment_actions_lookup.
  def sem_outra(**filtros)
    tabela = Crm::MetaAdsCommentAction.table_name
    outra = Crm::MetaAdsCommentAction.unscoped.from("#{tabela} outra").select('1')
                                     .where("outra.account_id = #{tabela}.account_id AND outra.network = #{tabela}.network " \
                                            "AND outra.comment_id = #{tabela}.comment_id")
    filtros.each { |coluna, valor| outra = outra.where("outra.#{coluna}" => valor) }
    outra.arel.exists.not
  end
end
