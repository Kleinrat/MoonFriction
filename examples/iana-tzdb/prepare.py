"""Write the full zone1970.tab projection to stdout from the pinned IANA archive."""
import csv
import hashlib
import io
from pathlib import Path
import sys
import tarfile

EXPECTED = "11810413345fc7805017e27ea9fa4885fd74cd61b2911711ad038f5d28d71474"
archive = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(archive).hexdigest() != EXPECTED:
    raise SystemExit("Expected the unmodified IANA tzdata2025b.tar.gz")
with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as source:
    lines = source.extractfile("zone1970.tab").read().decode("utf-8").splitlines()

sys.stdout.reconfigure(encoding="utf-8", newline="")
writer = csv.writer(sys.stdout, lineterminator="\n")
writer.writerow(["zone", "country_codes", "coordinates", "comment"])
for line in lines:
    if not line or line.startswith("#"):
        continue
    countries, coordinates, zone, *comments = line.split("\t")
    if len(comments) > 1:
        raise ValueError(f"Unexpected extra columns for {zone}")
    writer.writerow([zone, countries, coordinates, comments[0] if comments else ""])
