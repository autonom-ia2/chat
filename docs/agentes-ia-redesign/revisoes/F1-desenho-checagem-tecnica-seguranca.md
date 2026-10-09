# F1 — checagem limitada técnica e segurança

Alvo: design/F1.md, SHA-256 9190084edc615e4b304eea0f2a230f6f304291bea6c9e9caacc451b3a1ac1fd4. F0 compatível: SHA-256 9c878aff38937afb191f6255ac8a14e3d509096685ccdc7d256ccacaa152613d.

Esta checagem se limita aos dois achados da única revisão normal técnica, após a correção documental do autor e registro das causas. Não é nova revisão geral, prova de código, tela real ou aprovação de release.

- **F1-TEC-01: fechado no desenho.** E2m ramifica antes de BE-05 e aponta para autonomia_agent_panel_legacy/tune. F0 nomeia essa entrada com o componente legado real, guards antigos, conta/agente preservados e disponibilidade independente da flag nova durante o staging. E2m não consulta o leitor manage-only/manual422 nem cria thread. A prova em rotas com flags ON/OFF continua obrigatória na implementação.
- **F1-TEC-02: fechado no desenho.** Pausar/religar usa uma ação própria com PATCH somente status/enabled, sem EDIT/UPSERT da resposta parcial. Só GET bem-sucedido substitui a projeção; GET falho mantém os campos anteriores e avisa dados desatualizados. O desenho também impede atualização otimista e sucesso visual antes da releitura. Teste do corpo mínimo, ausência de mutação parcial e GET falho permanece obrigatório.

**Resultado: sem residual dos dois achados nesta checagem documental.** A implementação F1 permanece dependente de F0, backend B2 validado e BE-05 real. Nenhuma tela foi construída, nenhum cenário real foi aceito e nenhum merge, fila, deploy ou produção foi autorizado.

Validação: leitura dos alvos corrigidos, relatório normal, auditoria de causas e fluxo CRUD existente; nenhuma execução de testes, banco, build ou navegador nesta checagem.
