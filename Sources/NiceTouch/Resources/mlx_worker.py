"""Offline JSON-lines MLX adapter. One model load, no shell or network service."""
import os
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
import contextlib
import json
from pathlib import Path
import sys

protocol = sys.stdout

def emit(value):
    protocol.write(json.dumps(value) + "\n")
    protocol.flush()

try:
    folder = Path(sys.argv[1]).expanduser().resolve(strict=True)
    if not folder.is_dir() or not (folder / "config.json").is_file():
        raise ValueError("Choose a complete local MLX model folder containing config.json.")
    with contextlib.redirect_stdout(sys.stderr):
        from mlx_lm import load
        import outlines
        from outlines.types import JsonSchema
        from mlx_lm.sample_utils import make_sampler
        model, tokenizer = load(str(folder), tokenizer_config={"trust_remote_code": False})
        constrained = outlines.from_mlxlm(model, tokenizer)
        schema = json.loads(Path(__file__).with_name("rule.schema.json").read_text())
        schema["properties"]["gesture"].pop("allOf", None)
        output_type = JsonSchema({"anyOf": [
            {"type": "object", "required": ["status", "rule"], "additionalProperties": False,
             "properties": {"status": {"const": "ready"}, "rule": schema}},
            {"type": "object", "required": ["status", "question"], "additionalProperties": False,
             "properties": {"status": {"const": "clarification"}, "question": {"type": "string", "minLength": 1, "maxLength": 300}}}
        ]})
    emit({"ready": True})
except Exception as error:
    emit({"error": str(error)[:1500]})
    sys.exit(1)

for line in sys.stdin:
    try:
        if len(line) > 64000:
            raise ValueError("Request too large")
        request = json.loads(line)
        messages = [{"role": "system", "content": request["system"]}, {"role": "user", "content": request["prompt"]}]
        with contextlib.redirect_stdout(sys.stderr):
            prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
            result = constrained(prompt, output_type=output_type, max_tokens=400, sampler=make_sampler(temp=0))
        envelope = json.loads(result)
        value = envelope["rule"] if envelope["status"] == "ready" else {"error": envelope["question"]}
        emit({"text": json.dumps(value)})
    except Exception as error:
        emit({"error": str(error)[:1500]})
