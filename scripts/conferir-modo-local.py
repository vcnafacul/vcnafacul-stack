#!/usr/bin/env python3
"""Confere que, no modo local, NENHUM app fala com banco ou bucket remoto.

Lê a config final do compose (`docker compose config --format json`, depois
de juntar env_file + environment) pela entrada padrão e falha se algum
endereço de dados não apontar para os containers locais. É a trava contra o
api-vcnafacul/.env real, que aponta para o MySQL de homol.
"""
import json
import re
import sys

# serviço -> {variável: o que o valor tem de conter}
ESPERADO = {
    "api": {"MY_HOST": "mysql", "AWS_ENDPOINT": "http://minio:9000"},
    "api-migrate": {"MY_HOST": "mysql"},
    "ms-simulado": {"MONGODB": "mongo:27017", "AWS_ENDPOINT": "http://minio:9000"},
    "ms-omr": {"AWS_ENDPOINT": "http://minio:9000"},
    "form": {"MONGODB": "mongo:27017"},
}


def sem_senha(valor: str) -> str:
    """Esconde usuário:senha de URIs (mongodb://user:pass@host) na mensagem."""
    return re.sub(r"//[^/@]*@", "//***@", valor)


def main() -> int:
    config = json.load(sys.stdin)
    servicos = config.get("services", {})
    erros = []
    for servico, regras in ESPERADO.items():
        env = (servicos.get(servico) or {}).get("environment") or {}
        for var, trecho in regras.items():
            valor = env.get(var) or ""
            if var == "MY_HOST":
                ok = valor == trecho
            else:
                ok = trecho in valor
            if not ok:
                erros.append(f"  {servico}: {var}={sem_senha(valor) or '(vazio)'} — esperado {trecho}")
    if erros:
        print("❌ modo local apontando para fora dos containers:")
        print("\n".join(erros))
        return 1
    print("✔ modo local: bancos e bucket apontam para os containers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
