# Fork (#3148): o anúncio de novidade vale também fora da nuvem do Chatwoot, então a tela abre no self-hosted.
# Fora da nuvem o formulário só oferece `feature_announcement` (PlatformBannerDashboard), porque a faixa do topo
# (info/warning/error) continua só da nuvem em DashboardController#active_platform_banners.
class SuperAdmin::PlatformBannersController < SuperAdmin::ApplicationController
end
