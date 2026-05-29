from pathlib import Path
import json
import argparse
from jinja2 import Environment, FileSystemLoader, StrictUndefined

BASE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = BASE_DIR / "templates"
CONFIG_DIR = BASE_DIR / "config"
RENDERED_DIR = BASE_DIR / "rendered"


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def merge_dicts(base: dict, extra: dict) -> dict:
    result = dict(base)
    result.update(extra)
    return result


def pssq(value):
    return str(value).replace("'", "''")


def resolve_template_path(template_arg: str) -> Path:
    p = Path(template_arg)
    if p.is_absolute():
        return p
    if p.exists():
        return p.resolve()

    candidate = TEMPLATES_DIR / template_arg
    if candidate.exists():
        return candidate.resolve()

    raise FileNotFoundError(f"No se encuentra la plantilla: {template_arg}")


def resolve_config_path(config_arg: str) -> Path:
    p = Path(config_arg)
    if p.is_absolute():
        return p
    if p.exists():
        return p.resolve()

    candidate = CONFIG_DIR / config_arg
    if candidate.exists():
        return candidate.resolve()

    raise FileNotFoundError(f"No se encuentra el config: {config_arg}")


def resolve_output_path(output_arg: str) -> Path:
    p = Path(output_arg)
    if p.is_absolute():
        return p

    # Si ya incluye rendered\..., respétalo
    if p.parts and p.parts[0].lower() == "rendered":
        return (BASE_DIR / p).resolve()

    return (RENDERED_DIR / p).resolve()


def render_template(template_arg: str, config_args: list[str], output_arg: str) -> Path:
    template_path = resolve_template_path(template_arg)
    config_paths = [resolve_config_path(c) for c in config_args]
    output_path = resolve_output_path(output_arg)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    env = Environment(
        loader=FileSystemLoader(str(template_path.parent)),
        autoescape=False,
        trim_blocks=True,
        lstrip_blocks=True,
        undefined=StrictUndefined,
    )
    env.filters["pssq"] = pssq

    data = {}
    for cfg in config_paths:
        data = merge_dicts(data, load_json(cfg))

    template = env.get_template(template_path.name)
    rendered = template.render(**data)

    output_path.write_text(rendered, encoding="utf-8", newline="\r\n")
    return output_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", required=True)
    parser.add_argument("--config", nargs="+", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    out = render_template(args.template, args.config, args.output)
    print(f"Plantilla renderizada en: {out}")


if __name__ == "__main__":
    main()