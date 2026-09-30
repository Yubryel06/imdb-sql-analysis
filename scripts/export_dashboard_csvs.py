"""
Step 6 - Present: export the dashboard views (sql/05_dashboard_views.sql) to CSV files
in data/exports/ for use in Tableau Public.

Uses the `mysql` command-line client, so no extra Python packages are needed.

Usage:
  python scripts/export_dashboard_csvs.py                    # prompts for the root password
  python scripts/export_dashboard_csvs.py --user myuser
  python scripts/export_dashboard_csvs.py --login-path imdb  # saved login (mysql_config_editor)

Information courtesy of IMDb (https://www.imdb.com). Used with permission.
"""

import argparse
import csv
import getpass
import os
import shutil
import subprocess
from pathlib import Path

VIEWS = [
    "dash_movies",
    "dash_movie_genres",
    "dash_director_films",
    "dash_actor_director_pairs",
]

PROJECT_DIR = Path(__file__).resolve().parent.parent
EXPORT_DIR = PROJECT_DIR / "data" / "exports"
DEFAULT_MYSQL = r"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"


def find_mysql():
    return shutil.which("mysql") or DEFAULT_MYSQL


def export_view(mysql_cmd, view, env):
    """Query one view and write it to data/exports/<view>.csv. Returns the row count."""
    result = subprocess.run(
        mysql_cmd + ["--batch", "--raw", "-e", f"SELECT * FROM imdb_movies.{view}"],
        capture_output=True, check=True, env=env,
    )
    lines = result.stdout.decode("utf-8").splitlines()
    target = EXPORT_DIR / f"{view.removeprefix('dash_')}.csv"

    with open(target, "w", encoding="utf-8", newline="") as out:
        writer = csv.writer(out)
        for line in lines:
            # --batch prints SQL NULL as the word NULL; a CSV uses an empty cell
            writer.writerow("" if value == "NULL" else value for value in line.split("\t"))

    rows = len(lines) - 1  # minus header
    print(f"  {target.name}: {rows:,} rows")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--login-path", help="saved mysql_config_editor login to use")
    parser.add_argument("--user", default="root", help="MySQL user (ignored with --login-path)")
    args = parser.parse_args()

    mysql_cmd = [find_mysql()]
    env = os.environ.copy()
    if args.login_path:
        mysql_cmd.append(f"--login-path={args.login_path}")
    else:
        mysql_cmd.append(f"--user={args.user}")
        env["MYSQL_PWD"] = getpass.getpass("MySQL password: ")  # hidden input, kept off the command line
    mysql_cmd.append("--default-character-set=utf8mb4")

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Exporting dashboard views to {EXPORT_DIR}")
    for view in VIEWS:
        export_view(mysql_cmd, view, env)


if __name__ == "__main__":
    main()
