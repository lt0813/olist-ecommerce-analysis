from __future__ import annotations

import importlib.util
import os
from datetime import datetime
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent
ENV_FILE = PROJECT_ROOT / ".env"
ANALYSIS_SCRIPT = PROJECT_ROOT / "src" / "01_customer_rfm_cohort.py"


def load_local_env(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("\"'")
        if key:
            os.environ[key] = value


def main() -> None:
    load_local_env(ENV_FILE)

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = PROJECT_ROOT / "analysis_outputs" / f"customer_analysis_{run_id}"
    output_dir.mkdir(parents=True, exist_ok=True)

    spec = importlib.util.spec_from_file_location(
        "olist_customer_analysis",
        ANALYSIS_SCRIPT,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load analysis script: {ANALYSIS_SCRIPT}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.OUTPUT_DIR = output_dir
    module.main()


if __name__ == "__main__":
    main()
