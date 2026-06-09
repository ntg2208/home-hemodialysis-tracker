# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
import json
import sys
from datetime import datetime
from pathlib import Path

import httpx

BASE_URL = "https://homehd.web.app/api"
API_KEY = sys.argv[1] if len(sys.argv) > 1 else input("API key: ").strip()

r = httpx.get(
    f"{BASE_URL}/blood-tests",
    headers={"Authorization": f"Bearer {API_KEY}"},
    params={"phase": "admission,in-center-hd,home-hd"},
    timeout=30,
)
r.raise_for_status()
data = r.json()

out = Path(__file__).parent / f"blood_tests_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
out.write_text(json.dumps(data, indent=2))
print(f"Backed up {data['count']} rows → {out}")
