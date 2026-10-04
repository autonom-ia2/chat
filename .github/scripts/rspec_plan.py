#!/usr/bin/env python3
"""Divide os arquivos de spec do RSpec entre os nós da CI pelo tempo real de cada arquivo.

Os pesos vêm dos `rspec-results-*/rspec_results.json` da última rodada verde da main (artefatos que o
próprio testes.yml publica). Sem pesos utilizáveis, cai no round-robin de antes. O plano é verificado antes
de sair: toda spec entra em exatamente um nó e nenhum nó fica vazio (fail-closed). Um plano errado
derruba a CI; nunca deixa spec sem rodar.

Uso: rspec_plan.py --shards 8 --specs specs.txt [--tempos DIR] --saida plan.json
"""
import argparse
import json
import statistics
import sys
from pathlib import Path


def carregar_specs(caminho):
    specs = [linha.strip() for linha in Path(caminho).read_text().splitlines() if linha.strip()]
    if not specs:
        raise SystemExit('nenhum arquivo de spec encontrado')
    if len(set(specs)) != len(specs):
        raise SystemExit('lista de specs com arquivo repetido')
    return sorted(specs)


def arquivo_do_exemplo(exemplo):
    # `id` aponta para o arquivo que roda o exemplo; `file_path` aponta para o arquivo do shared example.
    ident = str(exemplo.get('id') or '')
    arquivo = ident.split('[', 1)[0]
    return arquivo[2:] if arquivo.startswith('./') else arquivo


def carregar_pesos(pasta, specs):
    pesos = {}
    if not pasta or not Path(pasta).is_dir():
        return pesos
    conhecidos = set(specs)
    for arquivo in sorted(Path(pasta).rglob('*.json')):
        try:
            dados = json.loads(arquivo.read_text())
        except (OSError, ValueError) as erro:
            print(f'aviso: ignorando {arquivo}: {erro}', file=sys.stderr)
            continue
        for exemplo in dados.get('examples') or []:
            spec = arquivo_do_exemplo(exemplo)
            tempo = exemplo.get('run_time')
            if spec in conhecidos and isinstance(tempo, (int, float)) and tempo >= 0:
                pesos[spec] = pesos.get(spec, 0.0) + float(tempo)
    return pesos


def round_robin(specs, shards):
    nos = [[] for _ in range(shards)]
    for indice, spec in enumerate(specs):
        nos[indice % shards].append(spec)
    return nos, 'round-robin', [0.0] * shards


def dividir(specs, shards, pesos):
    # Sem tempo nenhum (ou todos zero) não há o que equilibrar: volta ao round-robin de antes.
    if not pesos or not any(pesos.values()):
        return round_robin(specs, shards)

    padrao = statistics.median(pesos.values())
    peso = {spec: pesos.get(spec, padrao) for spec in specs}
    nos = [[] for _ in range(shards)]
    carga = [0.0] * shards
    for spec in sorted(specs, key=lambda s: (-peso[s], s)):
        # Empate de carga (specs de tempo zero) vai para o nó com menos arquivos: sem isso elas se
        # empilhariam no primeiro nó e deixariam outros vazios.
        destino = min(range(shards), key=lambda i: (carga[i], len(nos[i]), i))
        nos[destino].append(spec)
        carga[destino] += peso[spec]
    return [sorted(no) for no in nos], 'tempos', carga


def verificar(specs, nos, shards):
    todos = [spec for no in nos for spec in no]
    if len(nos) != shards:
        raise SystemExit(f'plano com {len(nos)} nós, esperado {shards}')
    if len(todos) != len(specs) or set(todos) != set(specs):
        raise SystemExit('plano não cobre todas as specs exatamente uma vez')
    if len(specs) >= shards and any(not no for no in nos):
        raise SystemExit('plano com nó vazio')


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--shards', type=int, required=True)
    parser.add_argument('--specs', required=True)
    parser.add_argument('--tempos')
    parser.add_argument('--saida', required=True)
    args = parser.parse_args(argv)
    if args.shards < 1:
        raise SystemExit('--shards precisa ser positivo')

    specs = carregar_specs(args.specs)
    pesos = carregar_pesos(args.tempos, specs)
    nos, fonte, carga = dividir(specs, args.shards, pesos)
    verificar(specs, nos, args.shards)

    plano = {'fonte': fonte, 'total': args.shards, 'specs': len(specs), 'shards': nos,
             'carga_prevista_s': [round(c, 1) for c in carga]}
    Path(args.saida).write_text(json.dumps(plano, ensure_ascii=False, indent=1) + '\n')
    print(f'fonte={fonte} specs={len(specs)} pesos={len(pesos)} carga_prevista_s={plano["carga_prevista_s"]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
