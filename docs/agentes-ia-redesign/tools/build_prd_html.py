"""Gera PRD-agentes.html (página de leitura do PRD) a partir de PRD.md.

Uso (na pasta docs/agentes-ia-redesign):  uv run --with markdown python3 tools/build_prd_html.py
Depois publique PRD-agentes.html no mesmo artifact (ou abra no navegador).
"""
import html
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
src = (ROOT / "PRD.md").read_text()
md = markdown.Markdown(extensions=["tables", "toc", "sane_lists", "fenced_code"],
                       extension_configs={"toc": {"toc_depth": "2-3"}})
body = md.convert(src)
toc = md.toc.replace('<div class="toc">', "").rsplit("</div>", 1)[0]
body = body.replace("<table>", '<div class="tw"><table>').replace("</table>", "</table></div>")
if body.startswith("<h1"):
    body = body[body.index("</h1>") + len("</h1>"):]


def inline(text):
    return markdown.markdown(text).removeprefix("<p>").removesuffix("</p>")


decisions = []
for line in src.split("\n"):
    if not line.startswith("| **D"):
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    if len(cells) >= 4:
        decisions.append((cells[0].replace("*", ""), cells[1], cells[3]))
decisions.sort(key=lambda d: int(d[0][1:]))
cards = "".join(
    f'<li><span class="did">{html.escape(d)}</span><div><div class="dq">{inline(q)}</div>'
    f'<div class="dr">Recomendação: {inline(r)}</div></div></li>'
    for d, q, r in decisions
)
status = next(l for l in src.split("\n") if l.startswith("| **Status** |")).split("|")[2].split("—")[0].strip()
rounds = []
for line in src.split("\n"):
    cells = [c.strip() for c in line.strip("|").split("|")]
    if len(cells) >= 4 and cells[0].endswith("(05/10)") and cells[0].split(" ")[0].isdigit() and " altos" in cells[2]:
        count, rest = cells[2].split(" (", 1)
        rounds.append((cells[0].split(" ")[0], count, rest.split(" ")[0]))
conv = "".join(
    f'<span class="{"z" if a == "0" else ""}">R{r} {n}·{a}</span>' for r, n, a in rounds
)

CSS = (ROOT / "tools" / "prd_page.css").read_text()
page = f"""<title>PRD Agentes de IA</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;700;800&family=Source+Sans+3:ital,wght@0,400;0,600;0,700;1,400&family=JetBrains+Mono:wght@400;500&display=swap">
<style>{CSS}</style>
<header class="cover"><div class="in">
  <div>
    <div class="eyebrow">Chat2You · PRD</div>
    <h1>Agentes de IA — nova experiência</h1>
    <p class="lede">A área de agentes passa a ter o mesmo padrão premium e simples de Automações e Campanhas: lista clara, criação em 4 etapas (Escolha → Conte → Teste → Ligue), teste obrigatório antes de ir ao ar e um painel completo — sem tocar no que a Clara e a Lia fazem hoje em produção.</p>
    <div class="chips"><span class="chip">Status <b>{html.escape(status)}</b></span><span class="chip"><b>{len(decisions)}</b> decisões para o Rodrigo</span><span class="chip"><b>{len(rounds)}</b> rodadas de revisão</span></div>
  </div>
  <div class="todo">
    <div class="card"><h2>1. Veja a jornada</h2><p>O protótipo navegável mostra cada tela e cada estado, com os dados reais da conta Hub2you. <a href="https://claude.ai/artifact/NdjZdAnt8uhTa4P2VziyGM">Abrir o protótipo</a></p></div>
    <div class="card"><h2>2. Decida os D</h2><p>Cada decisão tem uma recomendação. O que não depende dela já pode começar. A lista está logo abaixo.</p></div>
    <div class="card"><h2>3. Revisões</h2><p>Achados · altos por rodada:</p><div class="conv">{conv}</div></div>
  </div>
</div></header>
<div class="wrap">
  <nav class="toc" aria-label="Índice"><div class="t">Índice</div>{toc}</nav>
  <main>
    <details class="tocm"><summary>Índice</summary>{toc}</details>
    <section class="decs" aria-labelledby="dtit"><h2 id="dtit">Decisões que dependem do Rodrigo</h2>
      <p class="sub">Resumo da §4. As opções completas e o que cada uma bloqueia estão na tabela da §4.</p>
      <ol>{cards}</ol></section>
    <article>{body}</article>
  </main>
</div>
"""
(ROOT / "PRD-agentes.html").write_text(page)
print(f"PRD-agentes.html: {len(page)} bytes, {len(decisions)} decisões, {len(rounds)} rodadas")
