#!/usr/bin/env python3
"""
check_lib_updates.py (AlterEgo)

Verifica se as libs listadas em `externals:` no .pkgmeta têm versão nova
no upstream, comparando com um lockfile local (.pkgmeta-lock.json). Não
baixa nem sobrescreve nada sem confirmação explícita (--apply).

Adaptado do script usado no projeto EllesmereUI, com duas correções
necessárias para o jeito como o .pkgmeta do AlterEgo fixa versões:

1. Libs de SVN (repos.wowace.com) são fixadas numa TAG nomeada
   (ex: "Release-r1377", "1.0"), não na revisão do trunk. A versão
   original comparava a revisão do trunk, o que ignora completamente
   qual tag está fixada e, se aplicado, vendorizaria trunk instável em
   vez de uma tag testada. Agora ele lista o diretório tags/ de verdade
   (svn ls <repo>/tags/) e compara tag com tag.

2. Libs de Git fixadas numa TAG nomeada (ex: LiqUI -> "v1.3.0", que não
   é "latest" nem um commit) caíam no caminho de comparação por commit
   do HEAD, o que nunca bate com o nome da tag. Agora qualquer entrada
   com "tag:" (nomeada ou "latest") é resolvida contra as tags reais do
   repositório; só entradas com "commit:" (sem "tag:") continuam sendo
   comparadas por commit do HEAD, que é o comportamento certo pra esse
   caso (TaintLess e LibDataBroker-1.1 são fixadas assim de propósito).

Uso:
    python3 scripts/check_lib_updates.py                # apenas relatório
    python3 scripts/check_lib_updates.py --apply LiqUI   # baixa e vendoriza a lib "LiqUI"
    python3 scripts/check_lib_updates.py --apply all     # aplica todas as pendentes

Requisitos: git e svn instalados e no PATH.
Lockfile:   .pkgmeta-lock.json (uma única branch neste projeto: new-features)
Cache:      .pkgmeta-cache/<nome-da-lib>/<versao>/  (cópia da última versão
            já vista, usada só para diff no relatório).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

PKGMETA_PATH = ".pkgmeta"
LOCKFILE_PATH = ".pkgmeta-lock.json"
CACHE_DIR = ".pkgmeta-cache"


# --------------------------------------------------------------------------
# Parsing do .pkgmeta
# --------------------------------------------------------------------------

def strip_quotes(value: str) -> str:
    """Remove aspas simples/duplas que envolvem o valor todo (ex: tag: "1.0")."""
    v = value.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        return v[1:-1]
    return v


def parse_externals(pkgmeta_text: str) -> dict:
    """
    Parser simples e tolerante do bloco `externals:` do .pkgmeta. Não é um
    parser YAML completo (o formato do pkgmeta não é YAML estrito), mas
    cobre o padrão usado pelo BigWigsMods packager:

        externals:
            Path/To/Lib:
                url: https://...
                tag: "1.0"
            Path/To/OutraLib:
                url: https://...
                commit: abcdef...
    """
    lines = pkgmeta_text.splitlines()
    externals = {}
    in_externals = False
    current_path = None
    current = {}

    def flush():
        if current_path is not None:
            externals[current_path] = current.copy()

    for raw_line in lines:
        line = raw_line.rstrip()
        if not line.strip():
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        stripped = line.strip()

        if stripped == "externals:":
            in_externals = True
            continue

        if not in_externals:
            continue

        # Uma nova seção de topo (ignore:, move-folders: etc.) encerra o bloco.
        if indent == 0 and stripped.endswith(":") and stripped != "externals:":
            flush()
            in_externals = False
            current_path = None
            current = {}
            continue

        # Uma linha de path de lib: indent baixo, termina em ":", sem valor.
        if indent <= 2 and stripped.endswith(":") and ":" not in stripped[:-1]:
            flush()
            current_path = stripped[:-1]
            current = {}
            continue

        # Linhas de atributo: "url: ...", "tag: ...", etc.
        m = re.match(r"([\w-]+):\s*(.+)", stripped)
        if m and current_path is not None:
            key, value = m.group(1), strip_quotes(m.group(2))
            current[key] = value

    flush()
    return externals


def short_name(path: str) -> str:
    """Nome curto pra usar nos comandos (--apply LiqUI), baseado no último segmento do path."""
    return path.rstrip("/").split("/")[-1]


# --------------------------------------------------------------------------
# Resolução de versão upstream
# --------------------------------------------------------------------------

def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kwargs)


def latest_git_tag(url: str):
    """Retorna a tag mais recente (ordenação por versão) de um repo git remoto."""
    result = run(["git", "ls-remote", "--tags", "--sort=-v:refname", url])
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        parts = line.split("refs/tags/")
        if len(parts) == 2:
            tag = parts[1]
            if tag.endswith("^{}"):
                tag = tag[:-3]
            return tag
    return None


def latest_git_commit(url: str, branch: str = "HEAD"):
    result = run(["git", "ls-remote", url, branch])
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return result.stdout.split()[0]


def version_key(tagname: str):
    """Return a stable release family and numeric version, or None."""
    revision = re.fullmatch(r"(?:Release-)?r(\d+)(?:-release)?", tagname)
    if revision:
        return ("revision", (int(revision.group(1)),))
    version = re.fullmatch(r"v?(\d+(?:\.\d+)*(?:-\d+)?)", tagname)
    if version:
        return ("version", tuple(int(n) for n in re.findall(r"\d+", version.group(1))))
    return None


def split_trunk_url(url: str):
    """https://host/wow/ace3/trunk/AceAddon-3.0 -> ('https://host/wow/ace3', 'AceAddon-3.0')."""
    if "/trunk" not in url:
        return url, ""
    root, _, rest = url.partition("/trunk")
    return root, rest.lstrip("/")


def latest_svn_tag(repo_root: str):
    """Compare stable tags numerically; order different families by SVN history."""
    result = run(["svn", "ls", "--xml", f"{repo_root}/tags/"])
    if result.returncode != 0:
        return None
    try:
        entries = ET.fromstring(result.stdout).findall("./list/entry")
        families = {}
        for entry in entries:
            if entry.get("kind") != "dir":
                continue
            name = entry.findtext("name", "")
            key = version_key(name)
            if key is None:
                continue  # Ignore moving Alpha/Beta aliases and prereleases.
            family, numbers = key
            commit = entry.find("commit")
            if commit is None:
                return None
            revision = int(commit.attrib["revision"])
            candidate = (numbers, revision, name)
            if family not in families or candidate > families[family]:
                families[family] = candidate
        if not families:
            return None
        # Revision numbers and semantic versions are not comparable numerically.
        # SVN's tag history establishes which release family is more recent.
        return max(families.values(), key=lambda item: (item[1], item[2]))[2]
    except (ET.ParseError, KeyError, ValueError):
        return None


def resolve_upstream_version(entry: dict):
    """
    Retorna (tipo, versao_encontrada, url_para_baixar) para uma entrada de
    external, ou None se não conseguiu resolver.
    tipo é um de: "git-tag", "git-commit", "svn-tag".
    """
    url = entry.get("url", "")
    tag = entry.get("tag")
    commit = entry.get("commit")

    if "repos.wowace.com" in url:
        repo_root, subpath = split_trunk_url(url)
        latest_tag = latest_svn_tag(repo_root)
        if not latest_tag:
            return None
        export_url = f"{repo_root}/tags/{latest_tag}/{subpath}".rstrip("/")
        return ("svn-tag", latest_tag, export_url)

    # Git. Se está fixada num commit específico (sem "tag:"), acompanha o
    # HEAD do commit — é o caso certo pra libs como TaintLess/LibDataBroker,
    # que o autor fixou deliberadamente num commit, não numa release.
    if commit and not tag:
        c = latest_git_commit(url)
        return ("git-commit", c, url) if c else None

    # Fixada numa tag (nomeada, ex: "v1.3.0", ou o sentinel "latest"):
    # sempre resolve contra as tags reais do repositório.
    t = latest_git_tag(url)
    return ("git-tag", t, url) if t else None


# --------------------------------------------------------------------------
# Lockfile
# --------------------------------------------------------------------------

def load_lockfile() -> dict:
    if os.path.exists(LOCKFILE_PATH):
        with open(LOCKFILE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_lockfile(data: dict) -> None:
    # Replace only a complete file; preserve the previous lock on write failure.
    directory = os.path.dirname(os.path.abspath(LOCKFILE_PATH))
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=directory,
                                         delete=False) as f:
            temporary = f.name
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(temporary, LOCKFILE_PATH)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


# --------------------------------------------------------------------------
# Fluxo principal
# --------------------------------------------------------------------------

def find_orphan_lib_folders(externals: dict, libs_root: str = "Libs") -> list:
    """
    Lista subpastas dentro de Libs/ que existem no disco mas não têm
    entrada correspondente em `externals:` no .pkgmeta. Essas pastas são
    invisíveis para o resto deste script — não são checadas nem
    atualizadas — então é bom sinalizar a existência delas separadamente.
    """
    if not os.path.isdir(libs_root):
        return []

    known = set()
    for path in externals:
        # externals usa paths tipo "Libs/AceAddon-3.0" -> pega só o
        # primeiro nível abaixo de Libs/
        parts = path.split("/")
        if len(parts) >= 2 and parts[0] == libs_root:
            known.add(parts[1])

    on_disk = {
        name for name in os.listdir(libs_root)
        if os.path.isdir(os.path.join(libs_root, name))
    }

    return sorted(on_disk - known)


def main():
    parser = argparse.ArgumentParser(description="Checa updates das libs do .pkgmeta")
    parser.add_argument(
        "--apply",
        metavar="NOME",
        help="Nome curto da lib a vendorizar (ou 'all' para todas as pendentes). "
             "Sem essa flag, o script só reporta.",
    )
    args = parser.parse_args()

    if not os.path.exists(PKGMETA_PATH):
        print(f"Não encontrei {PKGMETA_PATH} na pasta atual.", file=sys.stderr)
        sys.exit(1)

    with open(PKGMETA_PATH, "r", encoding="utf-8") as f:
        pkgmeta_text = f.read()

    externals = parse_externals(pkgmeta_text)
    lock = load_lockfile()

    pending = {}
    unknown = 0

    for path, entry in externals.items():
        name = short_name(path)
        try:
            resolved = resolve_upstream_version(entry)
        except (OSError, subprocess.SubprocessError) as error:
            raise RuntimeError(f"Version lookup failed for {name}: {error}") from error

        if resolved is None:
            unknown += 1
            print(f"[?] {name} ({path}) — não consegui resolver a versão upstream (url: {entry.get('url')})")
            continue

        kind, upstream_version, export_url = resolved
        locked = lock.get(path, {})
        locked_version = locked.get("value") or entry.get("tag") or entry.get("commit")

        if locked_version == upstream_version:
            continue
        if kind.endswith("-tag") and locked_version:
            current_key = version_key(locked_version)
            upstream_key = version_key(upstream_version)
            if (current_key and upstream_key and current_key[0] == upstream_key[0]
                    and upstream_key[1] <= current_key[1]):
                continue

        pending[path] = {
            "name": name,
            "entry": entry,
            "kind": kind,
            "old": locked_version,
            "new": upstream_version,
            "export_url": export_url,
        }
        old_display = locked_version or entry.get("tag") or entry.get("commit") or "(desconhecida)"
        print(f"[!] {name}: version available (content not compared)")
        print(f"    atual : {old_display}")
        print(f"    nova  : {upstream_version}")

    state = 'pending' if pending else ('unknown' if unknown else 'up_to_date')
    print(f"LIBS={state}")
    print(f"CHECKED={len(externals) - unknown}")
    print(f"UNKNOWN={unknown}")

    orphans = find_orphan_lib_folders(externals)
    if orphans:
        print("\n[ATENÇÃO] Pastas dentro de Libs/ que NÃO estão no .pkgmeta")
        print("(não são checadas nem atualizadas por este script):")
        for name in orphans:
            print(f"  - Libs/{name}")

    if args.apply and unknown:
        raise RuntimeError('Cannot vendor libraries while upstream lookups are unresolved; lockfile unchanged')

    if not pending:
        return 1 if unknown else 0

    if not args.apply:
        print(
            "\nRode de novo com --apply <nome> (ou --apply all) para vendorizar "
            "uma das libs acima."
        )
        return 1 if unknown else 0

    targets = list(pending.keys()) if args.apply == "all" else [
        p for p, info in pending.items() if info["name"] == args.apply
    ]

    if not targets:
        print(f"\nNenhuma lib pendente chamada '{args.apply}'.", file=sys.stderr)
        sys.exit(1)

    for path in targets:
        info = pending[path]
        vendor_lib(path, info)
        lock[path] = {"kind": info["kind"], "value": info["new"]}

    save_lockfile(lock)
    print(f"\n{LOCKFILE_PATH} atualizado. Revise o diff com `git diff` antes de commitar.")
    return 1 if unknown else 0


def vendor_lib(path: str, info: dict) -> None:
    """Baixa a versão nova da lib para dentro de `path`, substituindo o conteúdo atual."""
    kind = info["kind"]
    export_url = info["export_url"]
    name = info["name"]

    print(f"\n--- Vendorizando {name} em {path} ({kind} -> {export_url}) ---")

    with tempfile.TemporaryDirectory() as tmp:
        final = os.path.join(tmp, "final")

        if kind == "svn-tag":
            result = run(["svn", "export", "--force", export_url, final])
            if result.returncode != 0:
                raise RuntimeError(f"SVN export failed for {name}: {result.stderr.strip()}")
        else:
            clone_dir = os.path.join(tmp, "_clone")
            ref_args = ["--branch", info["new"]] if kind == "git-tag" else []
            result = run(["git", "clone", "--depth", "1", *ref_args, export_url, clone_dir])
            if result.returncode != 0:
                # fallback: clone default e faz checkout manual (tag ou commit)
                if os.path.exists(clone_dir):
                    shutil.rmtree(clone_dir)
                result = run(["git", "clone", export_url, clone_dir])
            if result.returncode != 0:
                raise RuntimeError(f"Git clone failed for {name}: {result.stderr.strip()}")
            # Commit pins need checkout even after a successful shallow clone.
            result = run(["git", "checkout", info["new"]], cwd=clone_dir)
            if result.returncode != 0 and kind == "git-commit":
                result = run(["git", "fetch", "--unshallow"], cwd=clone_dir)
                if result.returncode == 0:
                    result = run(["git", "checkout", info["new"]], cwd=clone_dir)
            if result.returncode != 0:
                raise RuntimeError(f"Git checkout failed for {name}: {result.stderr.strip()}")
            shutil.copytree(clone_dir, final, ignore=shutil.ignore_patterns(".git"))

        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        if os.path.exists(path):
            shutil.rmtree(path)
        shutil.copytree(final, path)

    # guarda uma cópia pra diff da próxima vez
    cache_path = os.path.join(CACHE_DIR, name, info["new"])
    if not os.path.exists(cache_path):
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        shutil.copytree(path, cache_path)

    print(f"{name} atualizada para {info['new']} em {path}")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
