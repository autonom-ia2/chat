# Capturas reais — editor #807

Aplicação Rails completa, bundle frontend de teste, conta sintética Hub2You QA · Editor 807. Capturas JPEG nativas do navegador, sem edição, composição ou geração de imagens. A marca e a navegação pertencem ao app real. A imagem de campanha foi disponibilizada apenas no servidor de assets local de QA.

| Captura | Situação |
| --- | --- |
| `01-editor-real.jpg` | Entrada direta, detalhes recolhidos e lista pronta com check. |
| `02-rolagem-real.jpg` | Scroll para baixo: etapas recolhidas, ações e destinatários no cabeçalho. |
| `03-visao-completa-real.jpg` | E-mail inteiro enquadrado, incluindo rodapé. Ampliar e voltar disponíveis. |
| `04-destinatarios-alerta-real.jpg` | Importação falha: etapa âmbar com ícone, sem texto/botão extra “Corrigir lista”. |
| `05-notebook-real.jpg` | 1024 × 768: conteúdo amplo e abas para alternar painéis. |
| `06-celular-real.jpg` | 390 × 844: título e ações em linhas próprias. Menu móvel recolhido. |
| `07-celular-visao-completa-real.jpg` | 390 × 844: corpo inteiro e rodapé enquadrados. |
| `08-html-legado-real.jpg` | Modelo sem MJML: prévia existente apresenta o HTML original. |

Capturas 01–04 e 08 em 1280 × 720. Nesse viewport, o iframe começa em y=239 e oferece 481 px de altura no editor. Com a rolagem, começa em y=178 e oferece 542 px: mais 61 px disponíveis. Em visão completa, o corpo transformado ocupa y=145,02 até y=704,97, dentro da tela de 720 px.

Fluxos conferidos no navegador: abertura direta; popup automático de erro; fechar e reabrir pelo item Destinatários; aplicar modelo; recolher/restaurar etapas; detalhes de assunto/prévia; salvar e reler o texto de prévia; visão completa; ampliar com scroll; ajustar novamente; voltar por botão e Escape com foco nos controles externos; revisão de envio com dois aptos e um protegido. Em notebook, o scroll dos painéis alcançou o último bloco (Rodapé legal) e o último controle (Margem). Os novos textos foram conferidos com bootstrap em português e inglês. Nenhum envio ou agendamento foi confirmado.

Validação funcional, API, limitações e plano de release/rollback: [auditoria](../../audit/2026-10-01-editor-scroll-807.md).
